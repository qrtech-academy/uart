# Appendix A

## `uart_def.vhd` (provided)
`uart_def` is the register map in VHDL form: one package of named constants for the seven register
indices and the meaning of each `STATUS`, `CTRL` and `ERROR_FLAGS` bit, from [Part 2 of the protocol
spec](../../../protocol/uart_register_protocol.md). Like the SPI transport, **it is given to you**;
you write every module in this course, but not the map. It exists so the register bank (`uart_regs`,
L05) and the testbenches can name registers and bits instead of writing bare numbers, and so the two
sides of the wire cannot drift apart.

The C++ driver carries the same map in `register_map.hpp`, transcribed once on each side of the wire.
Both store **bit positions**, not masks, so `STATUS` bit 1 is the constant `1` in both languages. The
C++ side declares only the subset the driver actually uses, under the `reg::`, `status::`, `ctrl::`
and `error::` namespaces; where a name exists on both sides, the value is identical. You do not edit
`uart_def`, but read it closely: a module that indexes the wrong bit is a bug you would only find on
the bench.

---

### The constants
Everything is a `natural` in `package uart_def`. The register indices are the offset divided by 4;
the bit constants are positions into a 32-bit register word.

| Group | Constant | Value | Meaning |
|---|---|---|---|
| Register index | `REG_STATUS` | 0 | Status register. |
| | `REG_CTRL` | 1 | Control register. |
| | `REG_BAUD_DIV` | 2 | Baud divider. |
| | `REG_TX_DATA` | 3 | Push a byte into the TX FIFO. |
| | `REG_RX_DATA` | 4 | Front byte of the RX FIFO (pure read). |
| | `REG_RX_POP` | 5 | Advance the RX FIFO. |
| | `REG_ERR_FLAGS` | 6 | Error flag register. |
| `STATUS` bit | `ST_TX_READY` | 0 | TX FIFO not full. |
| | `ST_RX_VALID` | 1 | RX FIFO not empty. |
| | `ST_ERROR` | 2 | One or more error flags set. |
| | `ST_TX_IDLE` | 3 | TX FIFO empty and line idle. |
| `CTRL` bit | `CT_ENABLE` | 0 | Enable the peripheral. |
| | `CT_PARITY_LO` | 1 | Parity select, low bit. |
| | `CT_PARITY_HI` | 2 | Parity select, high bit (00 none, 01 even, 10 odd). |
| | `CT_STOP` | 3 | 0 = 1 stop bit, 1 = 2 stop bits. |
| | `CT_RX_IRQ` | 4 | RX-valid IRQ mask. |
| | `CT_TX_IRQ` | 5 | TX-ready IRQ mask. |
| `ERROR_FLAGS` bit | `ER_FRAMING` | 0 | Framing error. |
| | `ER_PARITY` | 1 | Parity error. |
| | `ER_OVERRUN` | 2 | Overrun. |

Because they are positions, you index a `std_logic_vector` with them directly, for example
`status(ST_RX_VALID)` for the RX-valid bit, exactly as `1U << status::RX_VALID` forms the same mask
on the C++ side. Laid out as words, the three flag registers are:

![Bit fields of `STATUS`, `CTRL` and `ERROR_FLAGS`](./images/reg_fields.png)

`CTRL` is the only one with bits this course does not act on, and `ERROR_FLAGS` the only one where
two of the three have no producer yet; both are noted where they are built, in
[L05 Appendix A](../../L05/appendix/a_uart_regs.md).

---

### The `to_hex` helper
The package also carries one small convenience for the testbenches: `to_hex`, which renders a
`std_logic_vector` as an uppercase, zero-padded hex string. It pads to whole nibbles taken from the
argument's own length, so `x"A5"` becomes `"A5"` and a 12-bit bus becomes three digits. It lets a
bench name the offending value in a failure message,

```vhdl
report "rx_data byte 1 wrong: expected 0xA5, got 0x" & to_hex(captured_rx) & "!"
    severity error;
```

rather than a bare "mismatch". It is the one piece of behaviour in an otherwise pure constants
package: declared in the package, defined in the package body, and called only by benches. No
synthesizable module uses it.

---

### Where it fits
`uart_def` sits underneath everything that speaks in registers. `uart_regs` (L05) is the module that
actually reads and writes these bits; the package only names them. `uart_top` never uses it at all,
because the top wires the register bus without interpreting anything carried on it. Six testbenches
analyze against the package, most of them only for `to_hex`.

On the far side of the SPI wire the driver you build in L06 reaches the same registers through the
same positions. That is the point of transcribing the map twice rather than inventing it twice: the
spec is the single source, and each language is checked against it rather than against the other.

---

### What's ahead
[Appendix B](./b_uart_top.md) is the peripheral top, `uart_top`, the structural skeleton built
against this package. The [exercises](./c_exercises.md) read `uart_def`, then build `uart_top` from
the ground up. The datapath and register modules the top composes arrive in L02 through L05, and are
instantiated into `uart_top` as each one lands.

---

