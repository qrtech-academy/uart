# UART Register Protocol

This is the contract at the centre of the course. The FPGA side (L01-L05) implements it as a
peripheral behind the provided SPI transport; the MCU side (L06-L09) implements it as a master;
and L10 proves the two agree. Both halves are written against this document, not against each
other's code; if an implementation and this document disagree, the implementation is wrong.

There are two layers here, and they are independent:

1. **The UART line protocol** - how the peripheral's `tx`/`rx` pins carry bytes to the outside world
   (the *data plane*).
2. **The register map and its SPI access** - how the ATmega328P reaches the peripheral's registers
   across the chip boundary (the *control plane*).

---

# Part 1 - The UART Line Protocol (data plane)

The peripheral's own asynchronous serial line, on `tx`/`rx`.

| Parameter | Value |
|---|---|
| Frame | 1 start bit (low), then data bits, then optional parity, then stop bit(s) (high). |
| Data bits | 8, **LSB first**. |
| Idle | Line idles **high**. |
| Parity | None / even / odd, selected by `CTRL`. Default none. |
| Stop bits | 1 or 2, selected by `CTRL`. Default 1. |
| Default frame | **8N1** (8 data, no parity, 1 stop). |
| Voltage | 3.3 V logic (the DE0-CV). The data-plane peer must be 3.3 V, e.g. a CP2102/FT232 set to 3.3 V. |

### Baud rate
The system clock is **50 MHz**. The receiver oversamples the line at **16x** the baud rate, so
the internal tick rate is `16 * baud`. `BAUD_DIV` holds the divider from the 50 MHz clock to that
tick:

```text
BAUD_DIV = round( 50_000_000 / (16 * baud) )
```

| Baud | BAUD_DIV |
|---|---|
| 9600 | 326 |
| 19200 | 163 |
| 57600 | 54 |
| 115200 | 27 |

The transmitter emits one bit per 16 ticks; the receiver samples each bit at tick 8 (mid-bit)
after detecting a start edge. `BAUD_DIV` is 16 bits, so with the 16x oversampling factor the lowest
representable rate is `50_000_000 / (16 * 65535)`, or about 48 baud.

Because `BAUD_DIV` is an integer, the achieved rate is only as close as the rounding allows. At
115200 the exact divider is 27.126, so `BAUD_DIV = 27` gives 115740.7 baud, about +0.47% fast; at
9600 the error is -0.15%. Both are comfortably inside what an 8-bit frame tolerates, since the
receiver resynchronizes on every start bit and only has to still be inside the stop bit nine bit
periods later, which allows a few percent of combined error between the two ends.

---

# Part 2 - The Register Map (control plane)

Seven 32-bit registers, reached over the provided SPI transport (Part 3). Only the low bits of
each register are meaningful; upper bits read back as zero and are ignored on write.

| Index | Register | Offset | Access | Description |
|---|---|---|---|---|
| 0 | `STATUS` | 0x00 | R | Bit 0: TX ready (TX FIFO not full). Bit 1: RX valid (RX FIFO not empty). Bit 2: Error (any `ERROR_FLAGS` bit set). Bit 3: TX idle (FIFO empty and line idle). |
| 1 | `CTRL` | 0x04 | R/W | Bit 0: enable. Bits 2-1: parity (00 none, 01 even, 10 odd; 11 reserved). Bit 3: stop bits (0 = 1, 1 = 2). Bit 4: RX-valid IRQ mask. Bit 5: TX-ready IRQ mask. **Reserved in this course: see the note below.** |
| 2 | `BAUD_DIV` | 0x08 | R/W | Baud divider (bits 15-0), per Part 1. |
| 3 | `TX_DATA` | 0x0C | W | Bits 7-0: push one byte into the TX FIFO. |
| 4 | `RX_DATA` | 0x10 | R | Bits 7-0: the byte at the front of the RX FIFO (does **not** pop). |
| 5 | `RX_POP` | 0x14 | W | Any write discards the front RX byte and advances the FIFO; the value is ignored. Write `0x1` by convention. |
| 6 | `ERROR_FLAGS` | 0x18 | R/W | Bit 0: framing error. Bit 1: parity error. Bit 2: overrun. Write `0x0` to clear all. |

Indices 7-15 are reserved: a read returns `0x00000000`, a write is ignored.

### What this course implements, and what it reserves
The map above is the full contract. The peripheral built in L01-L05 implements the part of it that
carries data, and stores but does not act on the rest. Specifically:

* **`CTRL` is stored and read back, but gates nothing.** The register bank has no `ctrl` output, so
  `CT_ENABLE`, the parity select, the stop-bit select and the two IRQ masks reach no logic. The
  peripheral is always enabled and always 8N1. The driver's `configure()` still writes the enable
  bit, so the two halves agree on the wire; the write simply has no effect on the hardware yet.
* **There is no interrupt line.** `uart_top` has eight ports and none of them is an IRQ output, so
  the two IRQ mask bits mask nothing. The system is poll-only, end to end.
* **Only the framing error flag has a producer.** The receiver emits `frame_err` and nothing else,
  so `ER_PARITY` and `ER_OVERRUN` are defined positions that always read zero. Parity detection and
  overrun detection are the natural extensions of L03 and L05 respectively.

These are reservations, not omissions: the positions are fixed so that an implementation which
adds them later stays compatible with both halves as written.

### The driver flow this map implies
* **Transmit:** poll `STATUS` bit 0 (TX ready); when set, write a byte to `TX_DATA`.
* **Receive:** poll `STATUS` bit 1 (RX valid); when set, read `RX_DATA`, then write `RX_POP` to
  advance to the next byte.

This mirrors the poll-status / read-data / acknowledge shape of a typical hardware FIFO.

---

## Register Semantics (what the register bank must implement)
The TX and RX cores expose single-cycle pulses and levels (L02-L03); the register map promises
sticky, poll-able bits and FIFO-backed data. Bridging the two is the register bank's whole job
(L05):

* **`STATUS` bit 0 (TX ready)**: a level - the TX FIFO is not full. A `TX_DATA` write while it is
  clear is dropped (there is no room), which is why the driver must poll it first.
* **`STATUS` bit 1 (RX valid)**: a level - the RX FIFO is not empty. Set by the receiver pushing a
  byte; cleared when `RX_POP` empties the FIFO.
* **`STATUS` bit 2 (Error) / `ERROR_FLAGS`**: the bank latches the receiver's framing, parity, and
  overrun pulses into the three `ERROR_FLAGS` bits; bit 2 of `STATUS` is their OR. An `ERROR_FLAGS`
  write of `0x0` clears the latches.
* **`TX_DATA`**: a write pushes exactly one byte into the TX FIFO. It is an **edge event** - one
  write, one byte - never a held level. On a transaction abort (Part 3), no byte is pushed.
* **`RX_DATA` vs `RX_POP`**: `RX_DATA` is a *pure read* - it returns the front byte and has no side
  effect, so it obeys the same latch-once rule as `STATUS`. Popping the FIFO is a *separate write*
  (`RX_POP`), so that the side effect is a committed, abort-safe action and never a by-product of
  reading. This split is the point of L05: **a read that popped a FIFO would need write-like
  commit-and-abort discipline; keeping the read pure and the pop explicit avoids that entirely.**
* **`BAUD_DIV` / `CTRL`**: plain read/write registers; the cores sample them continuously, so a
  change takes effect on the next frame. Reconfiguring mid-frame is the driver's problem, not the
  bank's.

---

# Part 3 - The SPI Transport (provided)
The register map above is reached over SPI by the provided `spi_slave` + `spi_reg_bridge`. This
section documents that transport fully; it is a black box in *this* course (you use it, you do
not write it), but it is not magic.

| Parameter | Value |
|---|---|
| Roles | MCU is the SPI master, FPGA the slave. |
| Mode | SPI mode 0 (CPOL = 0, CPHA = 0): SCK idles low, both sides sample on the rising edge. |
| Bit order | MSB first, in every byte. |
| SCK frequency | <= 1 MHz (the Nano uses f_osc/16 = 1 MHz). |
| SS | Active low; one transaction per low period. |
| Voltage | The Nano is 5 V, the DE0-CV 3.3 V; every SPI line crosses a level shifter (L10). |

### Transactions
Every transaction is exactly **5 bytes**: one command byte, then four data bytes. `SS` falls
before the command byte and rises after the fifth byte, staying low for the whole transaction.

The command byte:

```text
Bit:      7    6    5    4    3    2    1    0
        +----+----+----+----+----+----+----+----+
        | W  | 0  | 0  | 0  |   register index  |
        +----+----+----+----+----+----+----+----+
```

* **Bit 7 (`W`)**: `1` = write, `0` = read.
* **Bits 6-4**: reserved, must be `0`.
* **Bits 3-0**: register index (`offset / 4`, 0-6 above).

* **Write (`W = 1`)**: the master sends the 32-bit value in the four data bytes, MSB first. The
  slave commits it to the addressed register only when the fifth byte completes.
* **Read (`W = 0`)**: at the end of the command byte the slave **latches the addressed register's
  value once**; the four data bytes clock it out on `MISO`, MSB first, while the master sends dummy
  `0x00`. The latch-once rule is part of the contract - the four bytes are one coherent sample.
* **Abort**: if `SS` rises before the fifth byte, the transaction is abandoned with **no side
  effects** - nothing commits, no `TX_DATA` push, no `RX_POP`. This is what makes the peripheral
  self-recovering.

---

## Worked Example
Configuring 115200 8N1, sending `'H'` (0x48), then polling and reading one received byte:

```text
Write BAUD_DIV : 82 00 00 00 1B   (0x1B = 27)
Write CTRL    : 81 00 00 00 01   (enable, 8N1)
Read  STATUS  : 00 xx xx xx xx   -> ...01 means TX ready
Write TX_DATA : 83 00 00 00 48   ('H' pushed into TX FIFO)
Read  STATUS  : 00 xx xx xx xx   -> ...02 means RX valid
Read  RX_DATA : 04 00 00 00 XX   -> XX is the received byte
Write RX_POP  : 85 00 00 00 01   (advance the RX FIFO)
```

---

