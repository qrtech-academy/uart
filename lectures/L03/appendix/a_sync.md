# Appendix A

## Designing `sync.vhd`
The `rx` line arrives from another chip. Nothing in this FPGA has ever governed it, so it can
change at any instant relative to `clock`, including inside a flip flop's setup-and-hold window.
Sample it directly and that flop can go metastable: sit between 0 and 1 for a while before
resolving, and resolve either way. Digital Design with VHDL solved this with two flip flops in
series, and that is all `sync` is, written once, properly, for this design to keep.

It is also the only module in the course with nothing UART-specific in it, which is exactly why it
is reusable. `uart_top` instantiates it on the `rx` pin, producing `rx_s2` for the receiver in
Appendix B, so the asynchronous crossing is handled by the module that owns the pins. The same
two-flop idea also guards the three SPI inputs inside the provided `spi_slave`, though that block,
being provided and self-contained, spells it out inline rather than depending on your module.

---

### Interface

![Module `sync`](./images/sync.png)

| Port / generic | Dir | Type | Meaning |
|---|---|---|---|
| `COUNT`      | generic | `natural range 1 to 15 := 1` | Number of independent bits to synchronize. |
| `clock`      | in  | `std_logic`                          | 50 MHz system clock, the domain being crossed *into*. |
| `reset_s2_n` | in  | `std_logic`                          | Active-low synchronized reset. |
| `async_in`   | in  | `std_logic_vector(COUNT-1 downto 0)` | The asynchronous input(s). |
| `sync_out`   | out | `std_logic_vector(COUNT-1 downto 0)` | The same bits, safe to use in this domain. |

`sync_tb` binds the ports positionally, and the **generic map is positional too**, so `COUNT` must
be the module's only (or first) generic. The testbench instantiates the module twice, at the default
count and at count 4, so both the scalar case and the generic are exercised. `sync` reads no
package, so its analyze line is just the module and its testbench, nothing else.

`uart_top` uses it at `COUNT = 1` for `rx`. The generic earns its place by being exercised and by
staying reusable; a wider instance is a one-line change should a later design want to synchronize a
bus of switches or pins.

---

### Behaviour
Two flip flops per bit, in series, on the rising edge of `clock`. The first may go metastable; the
second gives it a full clock period to settle before anything downstream sees it. So `sync_out`
follows `async_in` after **exactly two** rising edges: not one (one flop is not a synchronizer)
and not three.

Two choices are deliberate. The first is the **reset, and which reset it is**. `sync` clears both
flops on `reset_s2_n`, asserted asynchronously so the chain starts from a known state with no clock
needed, exactly as the rest of the design does. Note carefully *which* reset that is: `reset_s2_n`
is the **already-synchronized** one, produced by the provided `reset_sync` in `uart_top`.

That asymmetry is the point, and it is why `sync` cannot be the reset synchronizer, however alike
the two look. `reset_sync` takes the raw asynchronous `reset_n` and manufactures a clean one; `sync`
**consumes** the clean one it produces. A module that needs `reset_s2_n` as an input cannot be the
module that creates it, so the two stay separate even though both are two flops in series.

The second is **the count generic**, under which each bit crosses independently. That is fine for
independent signals, and it is the reason a plain synchronizer is *not* a general answer for a
multi-bit value whose bits must stay coherent: two bits that change together may land one clock
apart. `rx` is a single bit, so the question does not arise here, but it is worth knowing before
reaching for a wide instance on a counter.

---

### What the testbench pins down
`sync_tb` checks that `sync_out` follows `async_in` after exactly two rising edges, low-to-high
and high-to-low alike; that at `COUNT = 4` all four bits arrive together, two edges after the input
changed; and that a steady input leaves `sync_out` steady, so the output tracks the input rather
than the intermediate flop.

It also checks the reset from both sides. Held low, the outputs stay clear whatever the input does.
Asserted *between* clock edges with a known non-zero output standing, the outputs must clear
**immediately** rather than at the next edge, a check that fails against a synchronous reset and is
how the bench pins down that this one is asynchronous. Released, the chain must re-synchronize and
take the full two edges again.

Deleting one flip flop is the exact bug this testbench exists to catch, and it is a bug no
functional simulation would otherwise reveal, because nothing in a simulator is ever metastable.

---

### Where it fits
In `uart_top`, the `rx` pin goes through `sync` before any logic looks at it, and the receiver in
Appendix B reads only the synchronized copy, `rx_s2`. Because `sync`'s ports are vectors even at
`COUNT = 1`, a scalar `rx` needs a one-element signal on each side; that wiring is part of the L03
exercise that adds the receive path to the top.

---

### What's ahead
[Appendix B](./b_uart_rx.md) builds `uart_rx`, the receiver, which takes the synchronized `rx` and
recovers a byte from it by oversampling.

---

