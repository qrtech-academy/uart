# Appendix C

## Bringing up the bench
This is the bench work that ends the course: the DE0-CV, the Nano, a level shifter, and a USB-serial
adapter, wired into one working node. The **DE0-CV is provided**, one per bench; the Nano, the level
shifter and the 3.3 V USB-serial adapter are on the shopping list in
[`info/README.md`](../../../info/README.md). Because the FPGA hardware is limited, the assembly and
bring-up are **demonstrated live**; follow along here, and try it hands-on at the provided bench.

Read [Appendix A](./a_bench.md) first: it explains the two links, the level shifting, and why the
bring-up ladder climbs one rung at a time.

---

## Exercise 1 - Assemble the bench
Wire it with everything **powered off**, and have the wiring checked before applying power. A single
5 V line into a 3.3 V FPGA pin can damage it.

**The control plane (SPI), through the level shifter.** The Nano's SPI pins are fixed; the DE0-CV
signals are the GPIO-header pins assigned in `uart_board.vhd`.

| Signal | Nano | Level shifter | DE0-CV |
|---|---|---|---|
| `SCK`   | D13 (PB5) | HV to LV | `sclk` |
| `MOSI`  | D11 (PB3) | HV to LV | `mosi` |
| `MISO`  | D12 (PB4) | LV to HV | `miso` |
| `SS` / CS | D10 (PB2) | HV to LV | `ss` |
| 5 V reference | 5V | HV | - |
| 3.3 V reference | - | LV | 3.3 V |
| GND | GND | GND (both sides) | GND |

**The data plane (UART), 3.3 V direct** (no shifter; the adapter is set to 3.3 V logic). The
`tx`/`rx` crossover is the usual one.

| Signal | DE0-CV | USB-serial adapter |
|---|---|---|
| peripheral `tx` | `tx` | RX |
| peripheral `rx` | `rx` | TX |
| GND | GND | GND |

The adapter's USB goes to the PC, where a terminal at 115200 8N1 is the far end of the data plane.

---

## Exercise 2 - Program the FPGA and flash the Nano
Two chips, two toolchains, both of which you have already used. For the **DE0-CV**, re-synthesize
`uart_board.vhd`, the provided Quartus top level wrapping your `uart_top`, and program the FPGA over
USB-Blaster exactly as in L09; confirm the design fits and that the pin assignments match the wiring
table above. For the **Nano**, flash the ATmega firmware:

```bash
make -C fw/avr flash        # avr-gcc + avrdude; see fw/README.md
```

With both programmed and the bench wired, you are ready to climb the ladder.

---

## Exercise 3 - Climb the bring-up ladder
Climb one rung at a time and **stop at the first that misbehaves**; that rung names the layer at
fault (Appendix A explains why).

**a) Data-plane pin loopback.** In `uart_board.vhd`, temporarily wire the board's UART receive pin
straight back out to its transmit pin, bypassing `uart_top` altogether, and re-synthesize. Type in
the PC terminal; every character should come straight back. None of your logic is in this path, and
that is the point: it proves the USB-serial adapter, its 3.3 V logic levels, the terminal's baud and
frame settings, the two data-plane wires, and the FPGA pin assignment, and it proves nothing else,
because nothing else is in the circuit yet. Fix any problem here before going further, since every
later rung depends on this one.

**b) The control plane.** Restore the wrapper. Flash a bring-up `main()` that does nothing but write
`BAUD_DIV` over SPI and read it straight back, comparing the two values. A matching read-back is the
first evidence that the whole control plane works: the level shifter on all four SPI lines,
`AvrSpi`'s register setup, the provided `spi_slave` and `spi_reg_bridge`, and your register bank's
read path. This rung has to come before any rung that uses the peripheral, because until `BAUD_DIV`
is written the divider reads zero and `uart_top` substitutes 1, so the line runs at 50 MHz / 16 =
3.125 Mbaud - transmitting, but at a rate nothing on the bench can decode - and the only route to a
usable `BAUD_DIV` is SPI. A crossed, unshifted or floating SPI line surfaces here and nowhere
earlier.

**c) The peripheral, looped back on itself.** Wire the peripheral's own `tx` to its own `rx` in the
wrapper, exactly as `uart_top_tb` does in simulation, and re-synthesize. Have the bring-up `main()`
configure the peripheral, write a byte to `TX_DATA`, then poll `STATUS` and read `RX_DATA` back. The
same byte coming back proves the entire datapath on real silicon: `baud_gen`, `uart_tx`, `uart_rx`,
both FIFOs and the register bank, running at an actual 50 MHz rather than a simulated one. The PC
terminal is not involved at all, so a failure here is the FPGA and not the link.

**d) The real data plane.** Undo the loopback and wire `tx` and `rx` to the USB-serial adapter.
Repeat the send and the receive from rung c, but against the terminal this time: a byte the driver
writes should appear in the terminal, and a character you type should come back through `RX_DATA`.
This adds the one thing rung c could not, which is the peripheral talking to a *different* device,
with two independently generated baud rates that now have to agree with each other.

**e) `app::EchoNode`.** Flash the echo application you wrote and host-tested in [Appendix
B](./b_exercises.md): `main()` constructs a `Uart` over `AvrSpi`, `configure()`s it for 115200 8N1,
and calls `node.run(stop)`. What you type in the terminal is received by the driver over SPI and
echoed back out the peripheral's `tx`, one byte crossing every layer. Because the class was already
proven on the host, anything that fails at this rung is the wiring or the link, not the echo logic.

---

## Exercise 4 - Trace a byte
The closing exercise, and the course's summary. Take a single character typed in the terminal and
trace it through **every** layer, out and back, naming each module and the lecture that built it.

It travels in on the data plane, from the PC terminal to the USB-serial adapter to the DE0-CV's `rx`
pin, into `uart_rx` (L03), then the RX FIFO (`fifo`, L04) inside `uart_regs` (L05). It then crosses
the control plane, out through `spi_reg_bridge` and `spi_slave` (provided) to `AvrSpi` (L09), up
through `readReg` and `Uart` (L07), and into `EchoNode` (L10). Finally it goes back out, from
`Uart::write()` to `writeReg()` to `AvrSpi`, into `uart_regs` and the TX FIFO, through `uart_tx`
(L02) to the DE0-CV's `tx` pin, and back via the adapter to the terminal.

Name the one place the byte changes representation (a UART frame on the wire, a register field over
SPI, a `uint8_t` in the driver), and you have described the whole FPGA-meets-MCU stack the course
built.

---

