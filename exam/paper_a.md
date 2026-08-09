# UART: Hardware, Driver & Integration - Written Examination, Paper A

**Time:** 4 hours. **Closed book.** A basic calculator is permitted. **Total: 100 marks.**

This paper exists to test your own skills and knowledge. It is not a qualification and it gates
nothing. It draws on all eight lectures and on both halves of the system, so **it is meant to be
taken once the course is over**, after L08 and the bring-up ladder.

---

## Rubric

**The protocol specification is the single source of truth.** Where an implementation and the spec
disagree, the implementation is wrong. An answer that argues from the contract beats one that argues
from code.

**Both languages are the subject, so you write both here.** VHDL is VHDL-93 using
`ieee.std_logic_1164`, and `ieee.numeric_std` where a conversion needs it. C++ that would run on the
ATmega328P is written in the course's AVR-portable subset: `<stdint.h>` and the bare types, no
`std::`, nested `namespace` blocks rather than `namespace driver::uart`, no `[[nodiscard]]`, no
`inline` variables. Host-only test code may use full modern C++, and a question says so when it
means it.

**Syntax is not what is being marked. The design is.** A missing semicolon, a forgotten `is` or an
absent `#include` costs nothing. A process that describes a latch where you meant a wire, or a
`readReg` that assembles its four bytes backwards, costs that part in full, because that is a
different system.

**The course's conventions are the ones expected**, and a design that breaks one should say why:

* VHDL ports are declared all inputs first, then all outputs, and every `port map` and `generic map`
  is **positional**.
* An active-low signal is named with an `_n` suffix; a signal that has been through a two-flop
  synchronizer is named with an `_s2` suffix. Every submodule takes `reset_s2_n`; only `uart_top`
  takes the raw `reset_n`. Signals carrying SPI traffic between the two transport blocks take a
  `spi_` prefix.
* Resets are asserted **asynchronously**, so `reset_s2_n` belongs in the sensitivity list.
* C++ uses `camelCase`, a leading capital on type names, `my` on private members and `our` on
  private statics, brace initialization, `noexcept` on driver methods, and copy and move deleted on
  any class holding a reference member or a unique hardware resource.

**Where a question asks what reaches the wire, answer in hardware or in bytes**, not in code. "It
calls `writeReg`" is not an answer to "what does the peripheral do".

**Where a question asks for a stated number of defects**, listing more is not penalised, but only
that many are marked, so put your strongest answers first.

### Supplied constants and formulas

| Quantity                     | Value                                              |
| ---------------------------- | -------------------------------------------------- |
| DE0-CV system clock          | 50 MHz, a 20 ns period                             |
| Arduino Nano clock (f_osc)   | 16 MHz                                             |
| SPI `SCK`                    | f_osc / 16 = 1 MHz, mode 0, MSB first              |
| Receiver oversampling        | 16x                                                |
| Default frame                | 8N1: 1 start, 8 data LSB first, 1 stop             |
| Baud divider                 | `BAUD_DIV = round( 50_000_000 / (16 * baud) )`      |
| SPI transaction              | 5 bytes: 1 command byte, then 4 data bytes MSB first |
| SPI command byte             | bit 7 = W (1 write, 0 read), bits 6-4 = 0, bits 3-0 = register index |

The register map itself is **not** supplied: Question 1 asks for part of it.

### Marks

| Question | 1   | 2   | 3   | 4   | 5   | 6   | 7   | 8   |
| -------- | --- | --- | --- | --- | --- | --- | --- | --- |
| Marks    | 12  | 13  | 14  | 13  | 12  | 13  | 11  | 12  |

---

## Question 1 - The map, the top, and what a clean analysis does not prove (12 marks)

**(a)** A driver reads `STATUS` over SPI and gets back `0x0000000D`.

Name every `STATUS` bit, give its position, and say whether this value has it set or clear.
Describe the state the peripheral is in, in one sentence. Then state what `Uart::write(0x41)` and
`Uart::read(byte)` would each do if called immediately afterwards, including any register access
each does **not** perform.

Finally, give the register index and the byte offset of `ERROR_FLAGS`, and the two command bytes
that would read it and write it. (3 marks)

**(b)** `uart_top`'s entity declares eight ports in the order `clock`, `reset_n`, `sclk`, `mosi`,
`ss`, `rx`, `miso`, `tx`. A colleague swaps `sclk` and `mosi` in the entity and changes nothing
else.

State whether `ghdl -a` rejects the file, and why. State whether elaborating `uart_top_tb` rejects
it. Name the first check anywhere in the course that fails, and the lecture in which that happens.

Then state the single change to the course's conventions that would have moved this failure forward
to analysis time, and what that change costs. (3 marks)

**(c)** Two things about `reg_rdata` and one about `baud_div`.

**(i)** L01 leaves the placeholder `reg_rdata <= (others => '0');` in `uart_top`, and L04
instantiates `uart_regs`, whose `reg_rdata` output drives the same signal. A candidate forgets to
delete the placeholder. `uart_top_tb` writes `BAUD_DIV` with `0x00000004` and reads it back.

Name the VHDL mechanism that now governs `reg_rdata`, give the value each of the low four bits
carries during the read-back, and state what the bench reports. (2 marks)

**(ii)** Before L04 exists, `baud_div` has no driver at all, and `uart_top` still has to hand
`baud_gen` a `natural range 1 to 65535`. State the value `to_integer(unsigned(baud_div))` returns in
that situation and the message it prints, and state why the value the library picks is worse than
merely wrong here. Then give the guarded expression the course uses, and say which of its two cases
covers this and which covers a legitimate value that arrives once the register bank exists.
(2 marks)

**(d)** `reset_sync` and `sync` are both two flip flops in series, and the course keeps them as
separate modules.

Name the port on `sync` that makes it impossible for `sync` to be the reset synchronizer, and
describe the circular dependency you would create by trying. Then state what "assert
asynchronously, release synchronously" buys in a design of a few hundred flip flops, and what could
go wrong if the release were asynchronous too. (2 marks)

---

## Question 2 - The wire, the divider, and the transmitter (13 marks)

**(a)** The byte `0x53` is sent 8N1 by `uart_tx`, which builds its frame as

```vhdl
frame <= STOP_BIT & data & START_BIT;
```

and then drives `tx <= frame(bit_idx)` with `bit_idx` walking from 0 to 9.

Give `frame` as a 10-bit vector, index 9 down to 0. Then give the ten levels `tx` carries in **time
order**, naming the `frame` index each one comes from and what each bit is (start, data bit *n*, or
stop).

State how many `baud_tick`s the whole frame takes, and how many 50 MHz clock cycles that is at
115200 baud. (4 marks)

**(b)** The peripheral is to run at 57600 baud from the 50 MHz clock.

Give the exact (unrounded) divider, the value written to `BAUD_DIV`, the baud rate actually achieved,
and the error as a percentage with its sign. State why the receiver at the other end tolerates it,
and name precisely what has to still be true, and at which bit of the frame, for the byte to be
received correctly. (3 marks)

**(c)** Here is the state machine of `uart_tx`, unchanged:

```vhdl
process(clock, reset_s2_n) is
begin
    if (reset_s2_n = '0') then
        tx <= '1'; done <= '0'; state <= STATE_IDLE;
        frame <= (others => '0'); bit_idx <= 0; ticks <= 0;
    elsif (rising_edge(clock)) then
        done <= '0';
        case (state) is
            when STATE_IDLE =>
                tx <= '1';
                if (start = '1') then
                    state <= STATE_SEND;
                    tx    <= '0';
                    frame <= STOP_BIT & data & START_BIT;
                end if;
            when STATE_SEND =>
                tx <= frame(bit_idx);
                if (baud_tick = '1') then
                    if (ticks >= MAX_TICKS - 1) then
                        ticks <= 0;
                        if (bit_idx >= FRAME_WIDTH-1) then
                            done <= '1'; state <= STATE_IDLE; bit_idx <= 0;
                        else
                            bit_idx <= bit_idx + 1;
                        end if;
                    else
                        ticks <= ticks + 1;
                    end if;
                end if;
            when others =>
                state <= STATE_IDLE;
        end case;
    end if;
end process;
```

State at which clock edge `tx` first goes low relative to the edge on which `start` was seen, and
say what that means for when the start bit begins relative to `baud_gen`'s tick.

Then, for a divider `div`, give the **shortest** and the **longest** the start bit can be, in clock
cycles, and explain where the variation comes from. Express the worst case as a fraction of a
nominal bit period, and state why neither the data bits nor the stop bit inherit it. (3 marks)

**(d)** `uart_tx_tb` checks the eight data bits least significant first, and L02 describes this as the
check that catches a transmitter sending most significant first. An earlier revision of the bench
sent `TXBYTE = x"A5"`; it sends `x"53"` today.

Write out the eight data-bit levels the line would carry under each of the two orderings for `0xA5`,
and use them to show that the bench could not have caught that bug at all. Name the property of
`0xA5` responsible, and state how many of the 256 possible bytes share it.

Then repeat the exercise for `0x53`, state which data bit the bench reports as wrong first, and say
what the episode tells you about reading a passing test as proof. (3 marks)

---

## Question 3 - The asynchronous line (14 marks)

**(a)** The `rx` pin arrives from another chip.

State what can happen to a flip flop that samples it directly, and be precise about what the failure
actually is: getting either level back from a mid-transition sample is *not* it. State why two flip
flops in series fix it and why one does not.

Then state which module in this design instantiates the synchronizer, which module deliberately does
**not**, and what the receiver's port name for the line tells a reader about that decision.
(3 marks)

**(b)** A correctly built `uart_rx` receives `0x53`, sent 8N1 least significant first, and stores
each sampled bit with `frame(bit_idx) <= rx_s2`, walking `bit_idx` from 0 upward.

Give the eight data-bit levels in the order they arrive on the line, and the `bit_idx` each lands
in. Show `frame` after the eighth, and confirm `data_out` carries `0x53`.

Then a colleague counts `bit_idx` **down** from 7 instead. Give the byte `data_out` would carry for
this same frame, in hex, and state the general relationship between what was sent and what is
delivered. (3 marks)

**(c)** The receiver aims to sample each bit at tick 8 of 16. It does not quite. Three things each
cost one tick: the falling edge is only noticed at the next `baud_tick`; `ticks` is compared before
it is incremented; and every `ticks <= 0` on a state change spends one more. The result, as built,
is that the start-bit re-check arrives **nine** ticks after the detected edge rather than eight, the
first data sample **seventeen** ticks after that re-check, the stop-bit sample **seventeen** after
the last data bit, and data bit to data bit exactly **sixteen**.

**(i)** State how far past the centre of its own bit each of the start-bit re-check, a data bit and
the stop bit is sampled, in ticks. State why the offset is fixed rather than accumulating across the
byte. (1 mark)

**(ii)** Take an **ideal** receiver first, sampling every bit exactly at its centre. Working in
ticks measured from the start-bit edge, give the tick at which the stop bit is sampled and the two
ticks at which the stop bit begins and ends. Hence derive the combined baud mismatch, as a
percentage, at which the stop-bit sample first falls outside the stop bit. (2 marks)

**(iii)** Now do the same arithmetic for the receiver as built. Give the two limits, state which
side of the ideal figure has been eaten into and by how much, and say in one sentence which physical
situation that lost margin makes more dangerous. (2 marks)

**(d)** Both FIFOs in the finished peripheral are `WIDTH = 8, DEPTH = 8`.

Write `fifo`'s clocked process, and the concurrent assignments that go with it for `rdata`, `empty`
and `full`. Assume the declarations `entries`, `head`, `tail`, `count` and a helper that advances a
pointer with wraparound; write everything else. Guard both directions - a write to a full FIFO and a
read from an empty one must each do nothing - and be careful that a push and a pop landing on the
same edge leave `count` where it was.

Then software stops reading while frames keep arriving. State how many back-to-back frames the RX
path absorbs before anything is lost, what happens to the next one, and which line of what you just
wrote decides it. Name the `ERROR_FLAGS` bit reserved for that loss, and state what it reads in this
course's build and why that is a reservation rather than an omission. (3 marks)

---

## Question 4 - Ports become registers (13 marks)

**(a)** `STATUS` is computed, never stored.

Write the concurrent assignments that build the whole 32-bit `status_reg` in `uart_regs`: all four
defined bits, indexed by their `uart_def` names, in terms of the signals the bank actually has, and
the reserved bits above them. Then say in a few words, for each defined bit, why it could not be a
stored register that the datapath writes.

Then: `STATUS` is read at a moment when the TX FIFO holds two of its eight bytes, the transmitter is
mid-frame, the RX FIFO is empty and no error has been latched. Give the 32-bit value the bank
presents on `reg_rdata`. (3 marks)

**(b)** A candidate makes `RX_DATA` advance the FIFO as a side effect of being read, so that the
driver needs no `RX_POP`.

Name the check in `uart_regs_tb` that fails and state what it asserts. Then, in terms of the SPI
transport's abort rule, state why a read with a side effect is genuinely harder to get right than a
pure read plus a separate write, and name the thing the bridge would have to tell the bank that it
currently has no way to say.

Finally trace the driver side, with the popping read in place and the driver's own `RX_POP` write
still present. The RX FIFO holds `0x41` then `0x42`, and nothing more arrives. Give what
`Uart::read()` hands back on the first call and on the second, and say what became of `0x42`.
(4 marks)

**(c)** A candidate gates the TX FIFO push on `CTRL` bit 0, reasoning that a disabled peripheral
should not transmit. The design analyzes and elaborates.

State what `uart_regs_tb` reports and why. State what `uart_top_tb` reports and why, and say why
that second failure message is the less useful of the two.

Then name the fact about `uart_regs`' port list that settles, on its own, whether any `CTRL` bit may
gate anything at all, and say why the bits exist in `uart_def` regardless. (3 marks)

**(d)** The TX feeder in `uart_top` is two concurrent lines:

```vhdl
tx_load <= (not tx_empty) and (not tx_busy);
tx_pop  <= tx_load;
```

State why this loads exactly one byte each time the transmitter goes idle with a non-empty FIFO,
never zero and never two, naming what holds `tx_load` low for the rest of the frame.

Then a colleague simplifies it to `tx_load <= not tx_empty;`, keeping `tx_pop <= tx_load;`, arguing
that `uart_tx` ignores `start` while it is sending anyway. They are right about `start`. Say what
happens to a TX FIFO holding four bytes, how many of them reach the wire, and how long the rest
survive. State whether `uart_top_tb` catches it, and why. (3 marks)

---

## Question 5 - The driver's contracts (12 marks)

**(a)** Both sides of the wire store bit **positions**, not masks.

Give the C++ expression that tests RX-valid in a `uint32_t status`, and the VHDL expression that
indexes the same bit of a `std_logic_vector`.

Then three one-line changes. For each, name the defect and state what the running system does - not
merely that it is wrong.

* `if (status & status::RX_VALID) { ... }`
* `writeReg(reg::CTRL, ctrl::ENABLE);`
* `register_map.hpp` declares `constexpr uint8_t RX_VALID{1U << 1};` while `uart_def.vhd` keeps
  `ST_RX_VALID : natural := 1;`

(4 marks)

**(b)** `driver::transport::Interface` has three methods and knows nothing about registers.

Name the three, and name the two things the seam deliberately does not know. State what putting the
seam at the **byte** level buys that a seam exposing `readReg` and `writeReg` would not, then name
the two concrete implementations the course puts under it and state exactly what changes above the
seam when they swap. (3 marks)

**(c)** This header compiles on the host and fails on the AVR toolchain the course targets:

```cpp
#include <cstdint>

namespace driver::uart
{
inline constexpr std::uint8_t TxReady{0U};

class Interface
{
public:
    virtual ~Interface() noexcept = default;
    [[nodiscard]] virtual std::uint32_t status() const noexcept = 0;
};
} // namespace driver::uart
```

Name **four** things in it that the AVR build rejects, and in each case say what the toolchain is
actually missing rather than merely that it is old.

Then write the header out corrected, as the course would have it: the include, the namespaces, the
constant and the class, with nothing left in it the AVR build cannot take. (3 marks)

**(d)** `write()` and `read()` are non-blocking and each returns a `bool`.

State what each `bool` means. Name the `STATUS` bit that makes each answer possible, and the L04
mechanism behind that bit. Then state where the blocking versions live, why they are free functions
taking `Interface&` rather than methods, and what would be lost if the interface itself blocked.
(2 marks)

---

## Question 6 - The five-byte transaction (13 marks)

**(a)** A host test constructs a `driver::transport::Stub`, constructs a real `Uart` over it, and
runs some driver calls. Afterwards the stub's recorded MOSI bytes are, in order:

```text
82 00 00 00 1B
81 00 00 00 01
00 00 00 00 00
04 00 00 00 00
85 00 00 00 01
```

with `beginCalls()` and `endCalls()` both `5`.

Decode every command byte: direction and register. Name the driver call that produced each
transaction, and say which transactions belong together as one call.

State what the driver did with the bytes that came back during the third transaction and during the
fourth, being specific about the order in which it assembled them.

Then state what `beginCalls()` and `endCalls()` prove that the byte log on its own does not, and
describe the wrong behaviour that a byte log alone would fail to distinguish from this one.
(4 marks)

**(b)** A candidate sends the four data bytes least significant first in `writeReg`, and assembles
the four returned bytes least significant first in `readReg`. The two are consistent with each
other, so a stub round trip through this driver still agrees with itself.

**(i)** Give the five bytes that `configure(27)`'s first transaction now puts on the wire, and the
32-bit value the peripheral commits to `BAUD_DIV`. State the 16-bit value `baud_div` therefore
carries, what `uart_top`'s guarded conversion does with it, and the baud rate the line actually
runs at. (2 marks)

**(ii)** The peripheral presents a `STATUS` of `0x0000000B`. Give the `uint32_t` this driver ends up
holding, and state what `write()` returns from then on and what `writeBlocking()` therefore does.
(1 mark)

**(c)** The receive path is poll `STATUS`, read `RX_DATA`, write `RX_POP`.

State what happens if the `RX_POP` write is left out, and what `app::EchoNode` does on the bench as
a result. State what happens if the pop is issued **before** the `RX_DATA` read.

Then name the host test that catches a driver which pops even when RX-valid is clear, state what
that pop actually does to this peripheral, and say why the answer "nothing bad" is not a defence.
(3 marks)

**(d)** `readReg` is a `const` member, and `status()` and `errorFlags()` are `const` because of it.
The transport's `begin()`, `transfer()` and `end()` are not `const`.

State why those three are not `const`. State what `const_cast<transport::Interface&>(myTransport)`
does, and why the compiler would in fact accept the calls without it as the class is written today.
Name the change to `Uart` that would make the cast genuinely necessary.

Then state the one circumstance under which casting away `const` is undefined behaviour, and say why
this is not it. (3 marks)

---

## Question 7 - The real transport, and the real toolchain (11 marks)

**(a)** `AvrSpi`'s constructor is three statements:

```cpp
DDRB  |= (1U << SCK) | (1U << MOSI) | (1U << SS);
PORTB |= (1U << SS);
SPCR   = (1U << SPE) | (1U << MSTR) | (1U << SPR0);
```

State what each statement achieves. The transport contract asks for mode 0, MSB first, and `SCK` at
1 MHz from a 16 MHz clock: state how this `SPCR` value delivers all three, naming the bits that are
**not** set and what each one's absence means.

State why `MISO` appears in none of the three statements. Then state what would be on the `SS` line
without the middle statement, and what the FPGA's bridge would make of the first transaction.
(4 marks)

**(b)** A colleague writes:

```cpp
uint8_t AvrSpi::transfer(const uint8_t byte) noexcept
{
    SPDR = byte;
    return SPDR;
}
```

State the byte this returns and where it came from. State how many `SCK` periods must pass before
`SPDR` holds the byte that arrived on `MISO`, and how long that is at this bench's `SCK` rate.

State what the correct spin waits on, and name the side effect that reading `SPSR` and then `SPDR`
has. Then say what the driver above would see, on a `readReg(STATUS)`, with this `transfer` in
place. (3 marks)

**(c)** `SS`/PB2 is configured as an output even though the transport drives the chip select
itself.

State what the SPI peripheral does if `SS` is left an input and something pulls it low mid
transaction, naming the `SPCR` bit the hardware changes. State what `transfer()`'s spin does in that
moment, and give the symptom a bench would show from then on. (2 marks)

**(d)** Name two constructs used freely in the host build that do not survive the freestanding
avr-gcc build, and what replaces each.

Then write out `avr/env.cpp`'s definitions: every symbol the file has to supply for this course's
code to link on the ATmega, with the right signatures and `extern "C"` where it belongs, and for
each name the ordinary C++ construct that emits the reference. Finally state why the file lives in
`avr/` rather than `source/`. (2 marks)

---

## Question 8 - The bench (12 marks)

**(a)** A user types `A` (`0x41`) into the PC terminal, and `app::EchoNode` echoes it.

Name, in order, every module the byte passes through from the USB-serial adapter until it reaches
the terminal again. For each, name the lecture that built it (or mark it as provided), and say which
of the two planes - control or data - it is on at that moment.

Then name the three representations the byte takes across that journey, and the two places where it
changes from one to the next. (4 marks)

**(b)** A bench climbs the ladder. Rungs a, b and c pass. Rung d fails: bytes the driver writes
appear in the terminal as wrong characters, and characters typed produce framing errors rather than
bytes.

State what the ladder has already cleared, rung by rung, and name what is left that rung d is the
first to exercise.

Name the most likely cause, and justify it by saying what rung c does that hides it. Then give the
arithmetic that would confirm or exonerate `BAUD_DIV = 27` as the culprit, and say what magnitude of
error you would have to see before the divider itself is to blame. (3 marks)

**(c)** Write the `main()` that runs on the ATmega328P on bring-up day, in `fw/avr/`: the includes it
needs from this course's headers, the objects it constructs and in what order, the `configure()` call
for 115200 8N1, the flag it passes, and the call that starts the application. It allocates nothing
and it never returns.

Then state why the flag this `main` passes is left `false` where the host test's is not, and why
`EchoNode::run()` must poll the non-blocking `read()` rather than call `readBlocking()` - connecting
that to how the host test manages to end the loop at all. (3 marks)

**(d)** One of the four SPI lines is wired 5 V straight to a 3.3 V FPGA pin, with no level shifter.

State the likely symptom and the risk. Name the first rung of the ladder that exposes it and state
why the rung before it cannot.

Then name the one SPI line for which the omission is electrically safe, say which direction it
travels and why, and state what could still go wrong with it. (2 marks)

---
