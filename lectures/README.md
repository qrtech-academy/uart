# Lectures
Eight lectures, in the rhythm four VHDL, three C++, one both. Each `L0x/README.md` has the agenda,
objectives, prerequisites, in-lecture work, and after-lecture exercises for that lecture.

| Lecture | Side | Topic |
|---------|------|-------|
| [L01](./L01/README.md) | VHDL | The register package & the peripheral top |
| [L02](./L02/README.md) | VHDL | UART framing & the transmitter |
| [L03](./L03/README.md) | VHDL | The receiver & the FIFO |
| [L04](./L04/README.md) | VHDL | The register bank |
| [L05](./L05/README.md) | C++  | The driver's contracts |
| [L06](./L06/README.md) | C++  | The driver, built and tested |
| [L07](./L07/README.md) | C++  | The real transport, and both toolchains |
| [L08](./L08/README.md) | Both | Integration & bring-up |

The VHDL the lectures produce lives in [`hw/`](../hw/README.md); the C++ in
[`fw/`](../fw/README.md). The contract both halves implement is the
[UART register protocol](../protocol/uart_register_protocol.md).

---

