# UART: Hardware, Driver & Integration - Written Examination, Paper B

**Time:** 4 hours. **Closed book.** A basic calculator is permitted. **Total: 100 marks.**

This paper exists to test your own skills and knowledge. It is not a qualification and it gates
nothing. It draws on all ten lectures and on both halves of the system, so **it is meant to be
taken once the course is over**, after L10 and the bring-up ladder.

---

## Rubric

**The protocol specification is the single source of truth.** Where an implementation and the spec
disagree, the implementation is wrong. An answer that argues from the contract beats one that argues
from code.

**Both languages are the subject, so you write both here.** VHDL is VHDL-93 using
`ieee.std_logic_1164`, and `ieee.numeric_std` where a conversion needs it; write the `library` and
`use` clauses out at least once, after which they are assumed. C++ that would run on the ATmega328P
is written in the course's AVR-portable subset: `<stdint.h>` and the bare types, no `std::`, nested
`namespace` blocks rather than `namespace driver::uart`, no `[[nodiscard]]`, no `inline` variables.
Host-only test code may use full modern C++, and a question says so when it means it.

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

**Where a question asks you to review a design**, naming the defect earns half the marks and saying
what it does to the running system earns the other half. "This is wrong" scores nothing.

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

The register map itself is **not** supplied: Question 5 asks you to write it out, and Questions 4 and
6 consume it, which is what the follow-through rule is for.

### Marks

| Question | 1   | 2   | 3   | 4   | 5   | 6   | 7   | 8   |
| -------- | --- | --- | --- | --- | --- | --- | --- | --- |
| Marks    | 12  | 13  | 14  | 13  | 12  | 13  | 11  | 12  |

---

## Question 1 - Building the top before anything it holds (12 marks)

**(a)** Write the complete `uart_top` **entity**, with its `library` and `use` clauses and the
course's banner comment naming the inputs and outputs. Eight ports, all inputs first, in the order
the system testbench binds them.

Then name the `use` clause the file does **not** need in L01 and say why, name the lecture that adds
it and the single expression that needs it, and state why `uart_top` never writes
`use work.uart_def.all` at all. (3 marks)

**(b)** Here are the two provided transport blocks' port lists, in declaration order.

```text
spi_slave        1 clock       2 reset_s2_n  3 sclk        4 mosi     5 ss
                 6 tx_data     7 miso        8 rx_data     9 rx_valid 10 ss_active

spi_reg_bridge   1 clock       2 reset_s2_n  3 ss_active   4 rx_data  5 rx_valid
                 6 reg_rdata   7 tx_data     8 reg_addr    9 reg_wdata 10 reg_write
```

`spi_slave`'s ports 1-5 are `std_logic` inputs, 6 is an 8-bit input vector, 7 is a `std_logic`
output, 8 is an 8-bit output vector, and 9-10 are `std_logic` outputs. `spi_reg_bridge`'s ports 1-3
are `std_logic` inputs, 4 is an 8-bit input vector, 5 is a `std_logic` input, 6 is a 32-bit input
vector, 7 is an 8-bit output vector, 8 is a 4-bit output vector, 9 is a 32-bit output vector, and 10
is a `std_logic` output.

Declare **exactly** the internal signals these two instantiations and the provided `reset_sync`
require, with their types, following the course's naming conventions, and write the three positional
instantiations. Do not declare anything a later lecture will bring.

Then answer two things. `spi_slave` and `spi_reg_bridge` both have a port called `rx_data`: state
why those are not one bus and which way each of your signals runs. And state why `reg_addr` is four
bits wide when there are only seven registers. (5 marks)

**(c)** L01 ends with one placeholder assignment, because the register bank is four lectures away.

Write it. Then state what an SPI **read** transaction returns while it is in place and why that is
harmless until L05, and state what a read would return instead if the placeholder were left out
altogether - being precise about what "returns" means for a signal nobody drives. (2 marks)

**(d)** State what building `uart_top` before any block it instantiates fixes about every block you
write later.

Then: `baud_gen` arrives in L02. State exactly what has to be true of its entity for its
instantiation in `uart_top` to bind correctly without you touching the top again, and name the one
thing about it that the course explicitly says is *not* part of the contract. (2 marks)

---

## Question 2 - The generator, the divider, and the frame (13 marks)

**(a)** Write `baud_gen.vhd` complete: the `library` and `use` clauses, the entity with its four
ports in order and their exact types, and the architecture. It produces a registered, one-clock-wide
`tick` every `div` clocks, and its reset is the course's.

Then justify your comparison. State what `counter >= div - 1` and `counter = div - 1` each do when
`div` is `1`, and what each does if `div` could ever be `0`, and say which keeps the counter inside
its declared range. (4 marks)

**(b)** The peripheral is to run at 9600 baud.

Give the exact (unrounded) divider, the value written to `BAUD_DIV`, the baud rate achieved, and the
error as a percentage with its sign.

Then state why the division is by `16 * baud` rather than by `baud`, name the module that spends the
sixteen ticks and say what it spends them on, and state what the transmitter does with the same tick
stream. (3 marks)

**(c)** `uart_tx` produces 8N1 only. Extend it with `parity_en` and `parity_odd` inputs.

Give the new frame vector expression and its index range, say which index the parity bit occupies
and which the stop bit now does, and give the expression that computes the parity bit from `data`
for even parity and for odd.

Then a `two_stop` input is added as well. Name the only field of the frame whose length now varies,
give the three possible frame lengths in bits, and state what the longest frame costs in transmitted
bytes per second at 115200 baud compared with 8N1. (3 marks)

**(d)** A candidate's transmitter passes `uart_tx_tb`. Their `busy` is not the course's concurrent
line but a registered flag, set inside the clocked process on the edge *after* the state becomes
`STATE_SEND`, so it rises one clock late.

State what `uart_tx_tb` checks about `busy` and what it does not. Then state what `uart_top`'s TX
feeder does during that one clock, what `uart_tx` does with what the feeder sends, and what happens
to the byte involved. Give the one-line fix and say which lecture's testbench is the first that
could have caught it. (3 marks)

---

## Question 3 - The asynchronous line, written out (14 marks)

**(a)** Write `sync.vhd` complete: the `library` and `use` clauses, the entity with its generic and
its four ports in order, and the architecture. Two flip flops per bit, the course's reset, and the
output taken from the right one.

Then answer two things. State how many rising edges `sync_out` takes to follow `async_in`, and why
neither one fewer nor one more is correct. And state what a `COUNT = 8` instance does **not**
guarantee about eight bits that change on the same edge, why that is not a defect in `sync`, and one
kind of signal you must therefore never put through a wide instance. (4 marks)

**(b)** Write the `STATE_IDLE` and `STATE_START` branches of `uart_rx`'s state machine as the course
specifies them, including the one flip flop of history, where in the process it is updated, and why
that position matters. Assume the surrounding `if baud_tick = '1'` and the tick counter are already
written.

Then a candidate replaces the falling-edge test with a level test, `if rx_s2 = '0' then`. State what
this does during a **break** - the line held low for longer than one frame - and then state
precisely what happens to the frame that is still in flight at the moment the break *ends*. Name the
testbench case that catches it and say what its message tells you. (4 marks)

**(c)** Write the `STATE_STOP` branch, and the output defaults at the top of the clocked process
that go with it.

State what makes `valid` and `frame_err` exactly one clock wide, why the byte is dropped on a
framing error rather than delivered alongside a flag, and what the register bank does with each of
the two pulses. (3 marks)

**(d)** An earlier revision of `uart_rx_tb` sent `0xA5` in its clean-frame case and `0x3C` elsewhere,
while `uart_top_tb` sent `0x5A` through a `tx`-to-`rx` loopback.

Show that a receiver which stores its data bits in the wrong order passed all three. Name the
property `0xA5`, `0x3C` and `0x5A` share, state how many of the 256 bytes have it, and give the
**second**, independent reason `uart_top_tb` could not have caught a bit-order convention shared by
`uart_tx` and `uart_rx`, however good its constant was.

`uart_rx_tb`'s clean-frame case sends `0x53` today. State the value `data_out` carries under the
faulty receiver, and hence what the bench now reports. Then state which single kind of bit-order
mistake remains beyond the reach of every bench in `hw/`, and why. (3 marks)

---

## Question 4 - The bank, written out (13 marks)

**(a)** Write the `ERROR_FLAGS` latch for the framing bit: its reset value, the condition that sets
it, the condition that clears it, and what happens when both occur on the same clock. Use
`uart_def`'s constants rather than numbers.

Then state why a single-cycle error pulse cannot be polled by software at all, and say what would
actually be observed if `STATUS` bit 2 were wired straight to the receiver's `frame_err` output and
a driver polled `STATUS` once per SPI transaction. (4 marks)

**(b)** Write the bank's read path: the combinational decode that drives `reg_rdata` from
`reg_addr`, covering all seven registers and the reserved indices, using `uart_def`'s constants.
Then write the two write **actions**, for `TX_DATA` and for `RX_POP`, as they appear in the clocked
process.

State why the read is combinational rather than registered, what the `when others` branch must
produce and why leaving it out would be a different kind of mistake here than in a purely
combinational decoder, and what the bank relies on the provided bridge to guarantee about
`reg_write`. (4 marks)

**(c)** Overrun is reserved in this course but not implemented. Design it.

Give the condition that detects an overrun, in terms of signals `uart_regs` already has. Give the
`ERROR_FLAGS` bit it sets and its position, and the clear path it shares. State the one piece of
information `uart_rx` would have to be given for it to detect the overrun itself instead, and why
handing it that information is a worse design.

Then give a physical cause for an overrun and a different physical cause for a framing error.
(3 marks)

**(d)** A candidate's bank stores `STATUS` in a 32-bit register, updated in the clocked process
whenever `rx_push`, `tx_pop` or `frame_err` asserts. It passes a test they wrote themselves.

Give two distinct ways it disagrees with `uart_regs_tb`, and state the general rule the course draws
from it in one sentence. (2 marks)

---

## Question 5 - Writing the contracts (12 marks)

**(a)** Write `include/driver/transport/interface.hpp` and `include/driver/uart/interface.hpp` in
full, in the course's AVR-portable style: the include guard or `#pragma`, the includes, the
namespaces, the destructors, and every pure virtual method with its exact signature, parameters,
return type and qualifiers.

`driver::transport::Interface` has three operations. `driver::uart::Interface` has six. (5 marks)

**(b)** Write the `reg` and `status` nested namespaces of `include/driver/uart/register_map.hpp`,
with the correct names and values, in the course's style.

Then state why the constants are declared plain `constexpr` rather than `inline constexpr`, and what
"internal linkage at namespace scope" costs here. And state why the map stores bit **positions**
rather than masks, naming the file on the other side of the wire that this decision keeps identical
and the one-line idiom that forms a mask at the use site. (3 marks)

**(c)** `driver::uart::Stub` holds `bool& myStop` as a member.

State what that reference is for and who owns the flag it refers to. State what `read()` does with it
when the scripted RX buffer runs out, and why that behaviour exists at all given that a stub has no
reason to care how a caller's loop terminates.

Then state what holding a reference member forces about the class's copy constructor, move
constructor and default constructor, and why. (2 marks)

**(d)** `driver::uart::Stub`'s `status()` returns `0`, its `errorFlags()` returns `0` and its
`clearErrors()` does nothing, even though a real UART's `STATUS` is the register the whole driver is
built around.

State the general rule about what a test double must be faithful about and what it may ignore, and
apply it here: say what would have to change about the stub before it could be used to test
something new, and give an example of such a thing. (2 marks)

---

## Question 6 - Writing the protocol (13 marks)

**(a)** Write `Uart::readReg(uint8_t addr) const` and `Uart::writeReg(uint8_t addr, uint32_t value)`
in full, in the course's style, using only `myTransport`.

Both perform one five-byte transaction. Get the command byte, the framing and the byte order right,
and say in one line each what `readReg` does with the reply to the command byte and what
`writeReg` does with all four of its replies.

Then state what marking `readReg` `const` buys the class, and name the two public methods that
depend on it. (5 marks)

**(b)** Write `Uart::read(uint8_t& byte)`.

Then, for one successful call on a peripheral whose RX FIFO front byte is `0x41`, write out the
exact bytes a `driver::transport::Stub` would record, transaction by transaction, and give
`beginCalls()` and `endCalls()`.

Finally, write the scripting the test must perform before the call. The stub's helpers are
`injectRxByte(uint8_t)` and `injectRxWord(uint32_t)`, the latter queuing four bytes most significant
first. State how many bytes in total have to be queued for this one call and explain the discrepancy
between that number and the number of register values involved. (4 marks)

**(c)** Write `writeBlocking()` and `readBlocking()` from `driver/uart/blocking.hpp`.

State why each is `inline`, why each takes `Interface&` rather than `Uart&`, and why they are free
functions in a separate header rather than methods on the interface. (2 marks)

**(d)** A candidate implements `readReg` by calling the driver's own `write()` to send each byte,
reasoning that `write()` is "the method that sends a byte".

State what happens when `status()` is called on this driver, in terms of the call sequence, and name
the failure the ATmega328P actually exhibits. Then state the one-sentence rule that keeps the two
apart. (2 marks)

---

## Question 7 - Writing the transport (11 marks)

**(a)** Write `driver::transport::AvrSpi` in full: the constructor, the destructor and the three seam
methods, in the course's style, reaching the registers through the platform header's `SCK`, `MOSI`,
`MISO` and `SS` bit positions and the `DDRB`, `PORTB`, `SPCR`, `SPSR` and `SPDR` registers.

The class configures the ATmega328P as an SPI master at f_osc/16, mode 0, MSB first.

Then state exactly what the destructor must clear, what it must leave alone and why, and state why
the constructor writes `SPCR = ...` rather than `SPCR |= ...`. (5 marks)

**(b)** A candidate ships `~AvrSpi() noexcept override = default;`, on the grounds that the class has
no members to release and the program never destroys it anyway.

Name the principle broken and list what the constructor took that is now never given back. Then give
one concrete way this harms code that runs afterwards, and one reason "the program never destroys
it" is not a safe assumption in this codebase in particular. (3 marks)

**(c)** The SPI transport needs no `F_CPU`; the debug logging over the ATmega's own USART does.

State what sets the SPI `SCK` rate and what sets the USART's baud rate, and use that to explain the
difference.

Then: the Nano's fuses actually run it at 8 MHz, but the build still defines `F_CPU=16000000UL`.
State what happens to `SCK`, in figures, and whether the SPI link still works. State what happens to
the debug USART, in figures, and what appears in the terminal. Say which of the two failures you
would notice first and why that is unfortunate. (3 marks)

---

## Question 8 - The application, and the plan (12 marks)

**(a)** Write `app::EchoNode` in full - `include/app/echo_node.hpp` and
`source/app/echo_node.cpp` - in the course's AVR-portable style. It implements `app::Interface`,
whose single operation is `void run(const bool& stop) noexcept`.

Include the member, the constructor, the deleted operations and the loop body. State why the
receive is the non-blocking `read()` while the echo is `writeBlocking()`, and why `stop` is a plain
`bool` passed by `const` reference rather than an atomic or a return value. (4 marks)

**(b)** Describe the host test for it precisely enough to write: which stub it runs over, what it
queues, how the loop is made to terminate, and what it asserts and in what order. Host test code may
use full modern C++.

Then state what an additional case that queues **nothing** proves, and name the implementation
mistake it is the only case that catches. (3 marks)

**(c)** Give the five rungs of the bring-up ladder, in order, and for each name the single layer it
adds that the previous rung did not exercise.

State why the order is forced rather than a matter of taste, naming the register that settles it and
the reason it can only be reached one way.

Then a colleague proposes flashing `app::EchoNode` first: "if it echoes, everything works, and if it
does not we start debugging." Give two reasons this is a worse plan **even when it succeeds**.
(3 marks)

**(d)** A candidate writes `EchoNode` to hold `driver::uart::Uart& myUart` rather than
`driver::uart::Interface& myUart`. Everything compiles, the bench works, and the class is otherwise
identical.

State what is now impossible, what has to be built before the class can be tested at all, and give
the one-line fix. Then name the L06 design decision this makes concrete. (2 marks)

---
