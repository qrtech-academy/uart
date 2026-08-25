# Appendix A

## The two-link bench
Everything the course built meets on one bench: your VHDL peripheral on the DE0-CV, your C++ driver
on the Nano's ATmega328P, and a PC terminal at the far end. What makes the bench worth understanding
is that **two different serial links** run across it, for two different jobs, and confusing them is
the most common bring-up mistake.

**The control plane is SPI.** The ATmega328P is the CPU, and it configures and drives the peripheral
by reading and writing its registers over SPI, in the 5-byte transactions of
[Part 3 of the spec](../../../protocol/uart_register_protocol.md). This is `AvrSpi` on one end and
the provided `spi_slave` / `spi_reg_bridge` on the other, and it carries *register* traffic, not user
data.

**The data plane is the UART itself.** The peripheral's own `tx`/`rx` pins carry bytes to and from
the outside world, out to a USB-serial adapter and a PC terminal. This is the line the whole
peripheral exists to drive.

So a byte the user types travels **in** on the data plane (UART `rx`), is read by the CPU **over
the control plane** (SPI `RX_DATA`), and, in the echo application, is written back **over the
control plane** (SPI `TX_DATA`) to leave again on the data plane (UART `tx`). Two protocols,
one byte.

---

## Level shifting: 5 V meets 3.3 V
The Nano runs at **5 V**, the DE0-CV at **3.3 V**, and that mismatch is the one electrical hazard
on the bench.

The **four SPI lines cross a level shifter**, a bidirectional BSS138-style board: `SCK`, `MOSI` and
`SS` go from 5 V on the Nano down to 3.3 V at the FPGA, while `MISO` goes 3.3 V up to 5 V. The
shifter's HV side ties to the Nano's 5 V, its LV side to the DE0-CV's 3.3 V, and grounds are common.
The **data-plane UART needs no shifting** at all, because the DE0-CV's `tx`/`rx` are already 3.3 V
and the USB-serial adapter is set to 3.3 V logic, so those two connect directly.

Drive a 3.3 V FPGA input straight from a 5 V pin and, best case, it misbehaves; worst case, you
damage the pin. This is exactly the failure the bring-up ladder's early rungs are designed to
surface before it can do harm.

---

## The board wrapper and Quartus
`uart_top` passed its system testbench in simulation (L05), but a testbench is not a pin assignment.
To run on real silicon, `uart_top` is wrapped by **`uart_board.vhd`**, the Quartus top level that
maps the peripheral's ports (`clock`, `reset_n`, the SPI lines, `rx`, `tx`) onto specific DE0-CV
pins: an onboard 50 MHz clock circuit, a reset button, and GPIO-header pins for SPI and the UART.

That wrapper is board I/O, not peripheral logic, so it lives with the Quartus project rather than
in `hw/`, and it is provided. You already synthesized it and programmed the board in L09, so nothing
about the FPGA toolchain is new here; the only change today is the loopback edit each rung of the
ladder asks for.

---

## Why a ladder, and what integration proves
The peripheral works in simulation and the driver passes its host tests, yet the assembled bench
can still fail, because simulation and host tests cannot see a level shifter, a crossed wire, a
clock that is not really 50 MHz, or SPI and UART timing on real edges. Integration is the top of the
test pyramid: it is the only level that exercises the actual chip boundary.

The **bring-up ladder** climbs that gap one rung at a time, each rung proving something the last
could not, so a failure points at one layer instead of the whole bench. **Data-plane pin loopback**
bypasses your logic entirely and proves only the adapter, the levels, the terminal settings and the
pin assignment. **The control plane** adds the SPI link, the level shifter, `AvrSpi` and the
register bank, checked by writing `BAUD_DIV` and reading it back. **Peripheral loopback** adds the
whole datapath, with `tx` tied to `rx` on the board so the byte never leaves the FPGA. **The real
data plane** adds the outside world, and with it two independently generated baud rates that have to
agree. And **EchoNode** adds the application on top.

The order is forced, not arbitrary. The peripheral cannot transmit until `BAUD_DIV` is written, and
`BAUD_DIV` is only reachable over SPI, so the control plane has to be proven before anything that
uses the peripheral. Any ladder that puts a peripheral rung first is really testing two layers at
once and calling it one.

Climbed in order, the first rung that misbehaves names the layer at fault. That is the point of the
method, and it is what an integration test catches that no host test can.

---

## What's ahead
[Appendix C](./c_bringup.md) is the bench procedure: assemble the provided hardware, program the
FPGA and flash the Nano, climb the ladder, run `app::EchoNode`, and trace one byte through every
layer the course built.

---

