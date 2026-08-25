# L10 - Integration & Bring-Up

## Agenda
Everything the course built meets on one bench. The first thing to get straight is that two serial
links run across it, carrying different traffic over different protocols:

* **SPI** (Nano to DE0-CV, through the level shifter) is the **control plane**: the ATmega driving
  the peripheral's registers.
* The peripheral's own **UART** `tx`/`rx` is the **data plane**, running out to a 3.3 V USB-serial
  adapter.

From there the lecture covers:

* **Level shifting**, since the Nano is 5 V and the DE0-CV 3.3 V, together with the four SPI lines
  and the wiring table.
* **The bring-up ladder**, climbed one rung at a time, each rung proving something the previous one
  could not.
* **`app::EchoNode`**, written and host-tested against the L06 UART stub first, and only then run on
  the ATmega over your own VHDL peripheral, with one byte traced end to end.

---

## Objectives
After this lecture, participants should be able to:

* **Write `app::EchoNode`** against the driver interface and host-test it on the L06 UART stub with
  no hardware, then bring it up as the final rung of the ladder.
* **Wire the two-link bench correctly**, level shifter included, and explain what each SPI line and
  each UART line carries.
* **Climb the bring-up ladder methodically** and state what each rung establishes that the previous
  one cannot.
* **Explain what an integration test catches that no host test can**, and where the top of the test
  pyramid sits for this system.

---

## Prerequisites
You need a `uart_top` from L05 that passes the system testbench, synthesized and programmed onto the
DE0-CV in L09 via the board wrapper (`uart_board.vhd`) in the Quartus project, and the ATmega
firmware from L09, flashed, with its host tests passing. You also need the hardware listed in
[`info/README.md`](../../info/README.md): a DE0-CV, a Nano, a level shifter, a 3.3 V USB-serial
adapter, and, recommended but not required, a logic analyzer.

---

## Instructions

### Preparation
Read [Appendix A](./appendix/a_bench.md) for the two links, level shifting and the board wrapper.
Then read [Appendix B](./appendix/b_exercises.md), and write and host-test `app::EchoNode` before
the lecture; that needs no hardware, only the driver interface and the UART stub from L06. Read
[Appendix C](./appendix/c_bringup.md) for the wiring tables and the bench procedure, and build the
wiring table yourself from the [protocol spec](../../protocol/uart_register_protocol.md)'s SPI
parameters and the board pinout. Have it checked before powering anything.

### During the Lecture (bench work)
The FPGA hardware is limited, so the assembly and bring-up are demonstrated live on the provided
DE0-CV and Nano. Follow along, then try it hands-on at the provided bench, per
[Appendix C](./appendix/c_bringup.md).

The work is climbing the **bring-up ladder**, stopping at the first rung that misbehaves. Each rung
adds exactly one layer, so the first rung that breaks names the culprit; the rungs are Appendix C's
Exercise 3. Rung a is a **data-plane pin loopback**: the board wrapper wires its `rx` pin straight
back to its `tx` pin, bypassing the peripheral, so a PC terminal echoes itself and only the adapter,
the levels, the terminal settings and the pin assignment are on trial. Rung b brings up the
**control plane**, writing `BAUD_DIV` over SPI and reading it back. Rung c is **peripheral
loopback**, with `tx` tied to `rx` on the board so the driver can send a byte and read the same byte
back without the outside world. Rung d is the **real data plane**, the same send and receive against
the terminal. Rung e is **EchoNode**, the full application.

The order is forced: the peripheral cannot transmit until `BAUD_DIV` is written, and `BAUD_DIV` is
only reachable over SPI, so the control plane must be proven before any rung that uses the
peripheral.

**The 60 minutes.** Nothing is typed this session. `app::EchoNode` and its test are written and
passing before the lecture, which is what makes the bench possible in an hour: the class arrives
already proven, so the only open questions are wiring and links. The session is the bench itself,
climbing the ladder rung by rung and stopping wherever it first misbehaves.

### After the Lecture
Complete the closing exercise, [Appendix C, Exercise 4](./appendix/c_bringup.md): trace a single byte
through every layer, from the PC terminal through the FPGA's UART RX, the FIFO, the register bank,
the SPI bridge, `AvrSpi`, the driver and `EchoNode`, and back out again, naming each module and the
lecture that built it.

---

## Evaluation
* The real-data-plane rung (d) works but the EchoNode rung (e) does not: which layer is implicated,
  and which layers has the ladder already cleared?
* Rung c loops `tx` back to `rx` on the board and passes, yet rung d fails against the terminal:
  what does that isolate, given that the peripheral's own datapath is common to both?
* What does the control-plane rung (b) prove that a passing `uart_top_tb` in simulation did not?
* If one SPI line is left un-shifted, wired 5 V straight to a 3.3 V pin, what is the likely symptom,
  and which rung exposes it first?

---

## Course Review
The pattern you have just completed, a peripheral in VHDL, a driver in C++, one shared register
contract, integrated across a real chip boundary, is the whole FPGA-meets-MCU method. The same
method scales to far harder protocols, and the SPI transport this course handed you as a black box is
itself built from the wire up two courses later, in SPI: The MCU-FPGA Transport, from the Wire Up.

---

