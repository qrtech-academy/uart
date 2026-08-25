# L01 - The Register Package & the Peripheral Top

## Agenda
This lecture starts at the top. Before a single datapath block exists we build the peripheral's
shell, because the shell is what fixes every block's interface: once `uart_top` says how it
instantiates `baud_gen`, the ports `baud_gen` must expose are settled, and the rest of the VHDL
course is filling that shell in. We cover:

* **The provided register map, `uart_def`**: the seven register indices and the `STATUS` / `CTRL` /
  `ERROR_FLAGS` bit positions from [Part 2 of the spec](../../protocol/uart_register_protocol.md),
  mirrored on the C++ side in `register_map.hpp`.
* **`uart_top` itself**: the entity as a positional port contract, the provided `reset_sync` that
  asserts asynchronously and releases synchronously, and the provided SPI transport behind it.
* **Declaring signals as you need them**: each internal signal comes from reading the entity of the
  block it connects to, so the top grows one block's worth of wiring per lecture rather than
  starting with a list of names for modules that do not exist yet.
* **What the shape costs and buys**: what a positional contract cannot catch, and how the top grows
  across L02 through L05 until the system testbench can finally run.

---

## Objectives
After this lecture, participants should be able to:

* **Read the provided register-map package** (`uart_def`) and explain why its `natural`
  bit-**position** constants must match the spec, and why the C++ `register_map.hpp` agrees with it
  value for value wherever a name exists on both sides.
* **Build the `uart_top` skeleton** (the entity, the provided `reset_sync`, the provided transport,
  and the signals those three need) so that it analyzes cleanly with no datapath blocks present.
* **Derive the internal signals from the entities they connect**, rather than from a list, and apply
  the `spi_` prefix and `_s2` suffix conventions the provided modules already use.
* **Explain top-down structural design**: why fixing the top first fixes each block's port contract,
  and why the system testbench is gated, skipped rather than failed, until L05.

---

## Prerequisites
This lecture assumes Digital Design with VHDL: `entity` and `architecture`, structural
instantiation, clocked processes, and analyzing a design with GHDL. Before the lecture, read the
**Register Map** (Part 2) and **SPI Transport** (Part 3) sections of the [protocol
spec](../../protocol/uart_register_protocol.md); you instantiate the transport but do not write it.

---

## Instructions

### Preparation
Read [Appendix A](./appendix/a_uart_def.md) first, for the register map you will wire against, then
[Appendix B](./appendix/b_uart_top.md), which is the reasoning behind `uart_top` and the design you
build from. [Appendix C](./appendix/c_exercises.md) carries the build itself, so skim it as well and
know where its tables are. Do open [`reset_sync.vhd`](../../hw/reset_sync.vhd),
[`spi_slave.vhd`](../../hw/spi_slave.vhd) and [`spi_reg_bridge.vhd`](../../hw/spi_reg_bridge.vhd):
their entities are where the signals you have to declare come from, and reading a port list to work
out what wiring it implies is the habit this lecture is teaching. Appendix C tabulates the same
ports, but as a check on your reading rather than a substitute for it. Finally, read the system
testbench [`uart_top_tb.vhd`](../../hw/uart_top_tb.vhd) to see the contract the top must eventually
satisfy; you will not run it until L05.

### During the Lecture
We walk through the provided `uart_def.vhd`, then start the `uart_top` skeleton. By the end of the
session the file analyzes, though you finish filling it in afterwards. There is no testbench to run
yet:

```bash
cd hw
ghdl -a --std=93 uart_def.vhd reset_sync.vhd spi_slave.vhd spi_reg_bridge.vhd uart_top.vhd
```

Then, from the repository root, run `make build-vhdl` and note that `uart_top_tb` reports
**skipped**: its datapath blocks do not exist yet.

**The 60 minutes.** We type the entity, then `reset_sync` and `spi_slave`, deriving each signal from
the entity of the block being instantiated rather than from a list handed to you. That method is the
session: the entity because it is the contract every later block is measured against, and the two
instantiations because positional binding, and the habit of reading a port list to find out what
signals you need, both have to be seen once. The `spi_reg_bridge` instantiation follows exactly the
same pattern and is left to the exercises, along with the `reg_rdata` placeholder and the check.

### After the Lecture
Work through the [exercises](./appendix/c_exercises.md). Exercise 2 is the build, decomposed into
five steps: the entity, the signals this lecture actually wires, the provided `reset_sync`, the two
transport blocks, and the check. Exercise 1 is the reading: the register map, positions rather than
masks, and when a swapped index would surface. Exercise 3 is the reasoning, about positional
binding, the reset synchronizer, and a register bus that waits four lectures for its bank.

---

## Evaluation
* Why build `uart_top` before any block it instantiates, and what does fixing the top first fix
  about every datapath module you write later?
* The reset is asserted asynchronously but released synchronously: what can go wrong if the release
  is not synchronized, and why can `sync` (L03) not do this job?
* `uart_top_tb` binds `uart_top`'s ports positionally: what class of wiring mistake does that leave
  the analyzer unable to catch, and at which point in the course does it finally surface?

---

## Next Lecture
The datapath begins: `baud_gen` (the shared time base) and `uart_tx` (the transmitter), each verified
against its own testbench and instantiated into the `uart_top` you built here.

---

