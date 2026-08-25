# Lectures
Ten lectures in two parts, in the rhythm five VHDL, four C++, one both. Each `L<nn>/README.md` has
the agenda, objectives, prerequisites, in-lecture work, and after-lecture exercises for that
lecture.

## Part 1 - The FPGA Peripheral (VHDL)

| Lecture | Side | Topic |
|---------|------|-------|
| [L01](./L01/README.md) | VHDL | The register package & the peripheral top |
| [L02](./L02/README.md) | VHDL | UART framing & the transmitter |
| [L03](./L03/README.md) | VHDL | The synchronizer & the receiver |
| [L04](./L04/README.md) | VHDL | The FIFO & the receive path |
| [L05](./L05/README.md) | VHDL | The register bank |

## Part 2 - The Driver & Integration (C++)

| Lecture | Side | Topic |
|---------|------|-------|
| [L06](./L06/README.md) | C++  | The driver's contracts |
| [L07](./L07/README.md) | C++  | The driver, built |
| [L08](./L08/README.md) | C++  | The driver, tested |
| [L09](./L09/README.md) | C++  | The real transport, and both toolchains |
| [L10](./L10/README.md) | Both | Integration & bring-up |

The VHDL the lectures produce lives in [`hw/`](../hw/README.md); the C++ in
[`fw/`](../fw/README.md). The contract both halves implement is the
[UART register protocol](../protocol/uart_register_protocol.md).

---
