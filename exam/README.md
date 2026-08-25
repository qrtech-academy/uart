# Written Examinations

Two complete four-hour papers for **UART: Hardware, Driver & Integration**, with worked solutions.

```text
paper_a.md              Paper A, questions only. Hand this out.
paper_a_solutions.md    Paper A, model answers with marks.
paper_b.md              Paper B, questions only.
paper_b_solutions.md    Paper B, model answers with marks.
```

---

## What these are for

The course as written has **no exam and nothing is marked**. Assessment is the exercises after every
lecture, the provided self-checking testbench or host suite that grades each one, and the Evaluation
questions that close every lecture README. Roughly half the code the course produces lives in those
exercises, and the benches in [`hw/`](../hw/README.md) and the suites in
[`fw/`](../fw/README.md) are what say whether it works.

These papers do not replace that. **They are here to test your own skills and knowledge, nothing
more.** They gate nothing, they are not a qualification, and no part of the course requires them.
Nothing in the repository depends on them: no module is built from them, and neither `make build`
nor `make format-check` knows they exist.

What they check is something the benches cannot. Every exercise is done at a keyboard, with the
appendix open in the next tab, GHDL ready to say no and `make test` ready to say no twice. These
papers ask what you can reconstruct with none of that in front of you - which of the rules you have
absorbed, and which you have merely been looking up.

**Take one after the course is over.** Every paper draws on all ten lectures and on both halves of
the system, so sitting one partway through examines material nobody has taught you yet, and the
result says more about how far you have read than about what you have understood. The intended point
is after [L10](../lectures/L10/README.md), with the bench climbed and `app::EchoNode` echoing.

---

## The two papers

Both cover the whole course, L01 to L10, at the same weighting, in **eight questions: four of VHDL,
three of C++, and one with both halves on the bench at once.** Two of the eight span a pair of
lectures rather than one - Question 3 covers the receive side across L03 and L04, and Question 6 the
driver and the suite that grades it across L07 and L08 - which is why ten lectures fit into eight
questions without dropping anything. They share no question. Either can be used alone; use both as a
main sitting and a resit, or in alternate years.

| Question | Topic                                                | Lecture | Side | Marks   |
| -------- | ---------------------------------------------------- | ------- | ---- | ------- |
| 1        | The register map, the peripheral top, and binding     | L01     | VHDL | 12      |
| 2        | Framing, the baud divider, and the transmitter        | L02     | VHDL | 13      |
| 3        | The asynchronous line: synchronizer, oversampling, FIFO | L03-L04 | VHDL | 14      |
| 4        | The register bank: ports become registers             | L05     | VHDL | 13      |
| 5        | The driver's contracts                                | L06     | C++  | 12      |
| 6        | The driver and the five-byte transaction              | L07-L08 | C++  | 13      |
| 7        | The real transport and the freestanding target        | L09     | C++  | 11      |
| 8        | Integration and bring-up                              | L10     | Both | 12      |
|          |                                                       |         |      | **100** |

**Paper A leans towards reading and tracing.** Most of its questions hand you something - a `STATUS`
word, a listing, a recorded byte log, a bench result - and ask what it means: decode a status read
and say what the driver does next, trace a byte through the transmitter's frame vector, work out how
much baud mismatch the receiver's real sampling phase leaves, read five SPI transactions off a stub's
record and name the driver call that produced each.

Five of its parts do ask for code, so that "leans towards" does not mean "never writes any", and
they are chosen so that **no module is written on both papers**: `fifo`'s clocked process and flags,
the concurrent `STATUS` assembly, an AVR-portable header corrected, `env.cpp`'s runtime symbols, and
the `main()` that builds the stack on the target. Paper B writes none of those five.

**Paper B leans towards writing and reviewing.** Most of its questions ask you to produce a
module - `baud_gen` in full, `sync` with its generic, the receiver's stop-bit branch, the two
`Interface` headers, `readReg` and `writeReg`, `AvrSpi`, `app::EchoNode` - or to say what is wrong
with one you are handed.

Both papers include at least one design that passes every check the course ships and is wrong
anyway, because that is the failure mode this subject actually has. Two more questions - one per
paper - are about the limits of the provided benches themselves, worked through a real gap that the
course's testbenches once had and no longer do.

---

## Why the papers ask for both languages

Because **the boundary is the subject**, and a boundary has two sides. A paper that examined the
VHDL and stopped at the register map would be examining Digital Design with VHDL; one that started
at `readReg` would be examining Modern Embedded C++. What this course adds is the thing in between:
one contract, written down once in
[`protocol/uart_register_protocol.md`](../protocol/uart_register_protocol.md), implemented
independently on each side, and proven to agree only at the end.

So both papers cross the wire more than once. A question about the register bank's `STATUS` bits
ends up in the driver's `write()`; a question about byte order in `writeReg` ends up in what
`baud_gen` divides by. That is deliberate, and it is where the marks are.

What a written paper cannot do is run GHDL or `make test`, and it should not pretend to. The rubric
says outright that syntax is not what is being marked: a missing semicolon costs nothing, and a
process that describes a latch where the candidate meant a wire, or a `readReg` that assembles its
bytes backwards, costs that part in full.

---

## Conventions the papers assume

Both papers state these in their own rubric, so a candidate never has to have read this file.

* **The protocol spec is the single source of truth.** Where an implementation and the spec
  disagree, the implementation is wrong, and an answer that cites the spec beats one that cites
  code.
* **VHDL-93**, with `ieee.std_logic_1164`, and `ieee.numeric_std` where a conversion needs it.
* **The VHDL conventions are the course's**: ports declared all inputs first then all outputs; every
  `port map` and `generic map` positional; an active-low signal named `_n`; a two-flop synchronized
  signal named `_s2`; every submodule taking `reset_s2_n` while `uart_top` alone takes `reset_n`;
  SPI traffic between the two transport blocks prefixed `spi_`.
* **C++ is written in the course's AVR-portable subset** wherever it would run on the target:
  `<stdint.h>` and the bare types, no `std::`, nested `namespace` blocks rather than `namespace
  driver::uart`, no `[[nodiscard]]`, no `inline` variables. Host-only code - the test suites - may
  use full modern C++, and the papers say which is which.
* **The C++ house style is expected**: `camelCase`, a leading capital on type names, `my` on private
  members and `our` on private statics, brace initialization, `noexcept` on driver methods, and copy
  and move deleted on anything holding a reference member or a unique hardware resource.
* **The numbers are fixed**: the DE0-CV runs at 50 MHz (a 20 ns period), the Nano at 16 MHz, `SCK`
  at f_osc/16 = 1 MHz, the receiver oversamples 16x, and the default frame is 8N1.
* **Hardware answers, not code answers**, where a question asks what a design does. "It assigns `x`"
  is not an answer to "what reaches the wire".

### Supplied in each paper

Each paper supplies the clock rates, the `BAUD_DIV` formula, and the SPI command-byte layout. It does
**not** supply the register map: Question 1 of both papers asks for part of it, so it cannot be
printed on the front page. Later questions consume it, which is what the follow-through rule below
is for.

---

## Marking

Every solution is written to be marked by somebody who has read the appendices and does not
otherwise write VHDL or freestanding C++ daily, so each carries the reasoning rather than the answer
alone. Marks are shown per part.

Four conventions worth agreeing before a paper is marked:

* **Method carries the marks.** A correct derivation with a slip in it is worth more than a correct
  answer with no working, and both papers are built so that later parts consume earlier ones. Follow
  through an error rather than penalising it twice: a driver that faithfully polls the wrong bit of
  a `STATUS` word the candidate decoded wrongly in Question 1 loses nothing in Question 6.
* **Mark the design, not the punctuation.** Where a VHDL listing is asked for, the marks are in the
  sensitivity list, the reset branch, the direction of the shift, whether the pulse is one clock
  wide, and whether every path assigns its output. Where C++ is asked for, they are in the byte
  order, the `const` and `noexcept` qualifiers that carry meaning, the ordering of the three
  register accesses, and whether the seam is respected.
* **The named traps are worth full marks on their own.** Several parts exist entirely to see whether
  a candidate avoids one specific mistake: a bit *position* used as a mask, a `readReg` that
  assembles least significant byte first, a `RX_DATA` read that pops, a TX feeder that pops without
  watching `busy`, a `transfer()` with no `SPIF` poll, a receiver that leaves idle on a level rather
  than an edge, and a `run()` loop that blocks and can never be stopped. Where a solution flags one
  of these, a candidate who walks into it loses those marks and no others.
* **"State the consequence" means the consequence.** Naming a defect earns half the marks; saying
  what it does to the running system - which byte is lost, which poll never returns, what appears in
  the terminal - earns the other half.

There is a fifth, particular to this course. Several questions ask what a design does in
**simulation or on the host** and what it does **on the bench**, and the answer is that they differ.
Two questions go further and ask what a provided testbench *cannot* catch. An answer that treats a
green bench as proof has missed the point of the question, however correct the rest of it is.
