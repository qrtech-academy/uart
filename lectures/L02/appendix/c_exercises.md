# Appendix C

## Exercises
Exercise 1 reinforces [Appendix A](./a_baud_gen.md); Exercises 2 and 3 reinforce
[Appendix B](./b_uart_tx.md). Design each module from the specification in its own appendix; the
provided testbenches are the check that they behave correctly. Run them from `hw/` with the three
GHDL steps (see [`hw/README.md`](../../../hw/README.md) for the full flow and what
`--assert-level=error` does).

---

## Exercise 1 - `baud_gen`
**a)** Write your own `baud_gen.vhd` from Appendix A's specification and run its testbench:

```bash
cd hw
ghdl -a --std=93 baud_gen.vhd baud_gen_tb.vhd
ghdl -e --std=93 baud_gen_tb
ghdl -r --std=93 baud_gen_tb --assert-level=error
```

**b)** The testbench uses `div = 4`. Work out on paper what `div` produces 115200 baud from the
50 MHz clock, and confirm it matches Appendix A. Why is the divide by `16 * baud` and not by
`baud`? Which later module spends those sixteen ticks, and on what?

**c)** Change the comparison in your design from `counter >= div - 1` to `counter = div - 1` and
re-run. The testbench still passes; explain why the two are indistinguishable for `div = 4`. Then
say what each version does if `div` is ever 0, and which of the two keeps the counter inside its
declared range.

**d)** `tick` is a registered output, one clock wide. Suppose you drove it combinationally instead
(asserting it whenever `counter = div - 1`). Nothing in this testbench would notice; name a
downstream consumer (L02 or L03) that counts ticks, and argue whether a glitchy or wider `tick`
would break it.

---

## Exercise 2 - `uart_tx`
**a)** Write your own `uart_tx.vhd` from Appendix B's specification and run its testbench:

```bash
cd hw
ghdl -a --std=93 uart_tx.vhd uart_tx_tb.vhd
ghdl -e --std=93 uart_tx_tb
ghdl -r --std=93 uart_tx_tb --assert-level=error
```

**b)** The testbench sends `0x53` and checks the data bits **least significant first**. Change your
frame packing so it sends most significant first and re-run. Which bit does the testbench report
first as wrong, and does that match `0x53 = 0101_0011` shifted the other way? Put it back.

**c)** Now the reason that constant is what it is. Leave your frame packed most significant first,
change `TXBYTE` in `uart_tx_tb` to `x"A5"`, and re-run: the bench **passes**, with the transmitter
still wrong. Write out the eight data-bit levels under both packings and explain why. What property
must a byte have for this check to be able to fail at all, and how many of the 256 bytes lack it?

Then look at `uart_rx_tb` and `uart_top_tb` with the same question in mind, and say why a loopback
bench could never catch `uart_tx` and `uart_rx` being reversed **together**, however good its
constant was, while each unit bench catches its own half. Put both files back.

**d)** `busy` and `done` carry different information. Give one job each does that the other cannot:
what would go wrong in `uart_top`'s feeder if it watched `done` instead of `busy` to decide when
to load the next byte?

**e)** The frame is captured on `start` into a 10-bit vector. Show, by writing out the bits, that
reading `'1' & data & '0'` from index 0 upward gives start, then `data(0)` .. `data(7)`, then stop.
Then explain why the caller is free to change `data` on the very next cycle.

**f)** Instantiate `baud_gen` and `uart_tx` into the `uart_top` skeleton from L01, positionally, and
declare the signals they need as you go. Read each entity and let it tell you what to add:
`baud_gen` takes a `natural` divider and drives `baud_tick`; `uart_tx` takes `baud_tick`, a byte and
a `start` pulse, and drives `tx`, `busy` and `done`. So `uart_top` gains these signals, and no more
than that:

| Signal | Type | Driven by | Read by |
|---|---|---|---|
| `baud_div`     | `std_logic_vector(15 downto 0)` | `uart_regs` (L04) | the conversion below |
| `baud_div_int` | `natural range 1 to 65535`      | the conversion below | `baud_gen` |
| `baud_tick`    | `std_logic`                     | `baud_gen` | `uart_tx`, and `uart_rx` (L03) |
| `tx_byte`      | `std_logic_vector(7 downto 0)`  | `uart_regs` (L04) | `uart_tx` |
| `tx_load`      | `std_logic`                     | the feeder (L04) | `uart_tx`, and `tx_pop` (L04) |
| `tx_busy`      | `std_logic`                     | `uart_tx` | the feeder (L04), `uart_regs` (L04) |
| `tx_done`      | `std_logic`                     | `uart_tx` | nothing, in this build |

![Module `baud_gen`](./images/baud_gen.png)

| # | `baud_gen` port | Dir | Type | Connect to |
|---|---|---|---|---|
| 1 | `clock`      | in  | `std_logic`                | `clock` |
| 2 | `reset_s2_n` | in  | `std_logic`                | `reset_s2_n` |
| 3 | `div`        | in  | `natural range 1 to 65535` | `baud_div_int` |
| 4 | `tick`       | out | `std_logic`                | `baud_tick` |

```vhdl
-- Generate the 16x oversample tick from the divider the register bank will hold.
baud_generator: entity work.baud_gen
    port map(clock, reset_s2_n, baud_div_int, baud_tick);
```

![Module `uart_tx`](./images/uart_tx.png)

| # | `uart_tx` port | Dir | Type | Connect to |
|---|---|---|---|---|
| 1 | `clock`      | in  | `std_logic`                    | `clock` |
| 2 | `reset_s2_n` | in  | `std_logic`                    | `reset_s2_n` |
| 3 | `baud_tick`  | in  | `std_logic`                    | `baud_tick` |
| 4 | `start`      | in  | `std_logic`                    | `tx_load` |
| 5 | `data`       | in  | `std_logic_vector(7 downto 0)` | `tx_byte` |
| 6 | `tx`         | out | `std_logic`                    | `tx` - the **top-level port** |
| 7 | `busy`       | out | `std_logic`                    | `tx_busy` |
| 8 | `done`       | out | `std_logic`                    | `tx_done` |

```vhdl
-- Drive the serial line. Port 6 is the transmitter's own tx output, so it binds to the
-- top-level tx pin, not to a signal.
uart_transmitter: entity work.uart_tx
    port map(clock, reset_s2_n, baud_tick, tx_load, tx_byte, tx, tx_busy, tx_done);
```

Position 6 is the one to check twice. Every port here is a `std_logic` except `data`, so binding
a signal there instead of the `tx` pin analyzes cleanly, elaborates cleanly, and leaves the pin
undriven - the loopback in `uart_top_tb` then feeds `'U'` back into `rx` and the system test fails
two lectures later with nothing pointing at this line.

Two signals need a word. `tx_byte` has no driver yet, because the FIFO that will fill it arrives
with `uart_regs` in L04, and neither does `tx_load`, whose feeder you write in the same lecture: an
undriven signal analyzes and elaborates without complaint, and the transmitter simply sits idle.
`baud_div` is the other, and it needs the **guarded conversion** that turns the register bank's
vector into the `natural` `baud_gen` expects:

```vhdl
-- baud_gen's div starts at 1, so substitute a legal value rather than hand it a zero or a
-- metavalue: baud_div has no driver until uart_regs arrives in L04.
baud_div_int <= 1 when Is_X(baud_div) or unsigned(baud_div) = 0
                else to_integer(unsigned(baud_div));
```

`Is_X` comes from `std_logic_1164`, and `to_integer` and `unsigned` from `numeric_std`, so add that
second `use` clause now. The guard covers two cases, and both of them would otherwise land on `0`,
which `baud_gen` does not accept: its `div` port is a `natural range 1 to 65535`, so a `0` reaching
it is a bound check failure at run time, not a warning you can ignore.

The first case is a **metavalue**. `baud_div` has no driver until L04 either, so it sits at
all-`'U'`, and `to_integer` on an all-`'U'` vector prints `NUMERIC_STD.TO_INTEGER: metavalue
detected, returning 0` and carries on. The library quietly picks a value you did not choose, and the
value it picks is out of range.

The second is a **real zero**, which arrives with `uart_regs` in L04: `BAUD_DIV` holds whatever the
bank resets it to until software writes a divider, and that reset value is a legitimate `0`. The
substitute is `1` because it is the smallest value the port accepts; nothing useful is transmitted
at either value, so the only thing that matters is that the design elaborates and runs.

VHDL's `or` on booleans is short-circuit, so the comparison is never evaluated on the all-`'U'`
vector, and the metavalue case stays warning-free.

```bash
cd hw
ghdl -a --std=93 uart_def.vhd reset_sync.vhd baud_gen.vhd uart_tx.vhd spi_slave.vhd \
     spi_reg_bridge.vhd uart_top.vhd
```

The top now drives `tx`, but the system testbench stays skipped: the receiver and register bank are
still missing. Do the extension in Exercise 3 on a copy, or after this step, since adding ports to
`uart_tx` changes the positional contract `uart_top` binds against.

---

## Exercise 3 - Parity and a second stop bit
8N1 is the only framing `uart_tx` produces. Real UARTs let software pick even/odd parity and one or
two stop bits; in this peripheral those live in the `CTRL` register (L04), but the transmitter is
where the extra bits would be sent.

**a)** Extend your `uart_tx` with two inputs, `parity_en` and `parity_odd`, and insert a parity bit
between the last data bit and the stop bit. Even parity makes the total number of 1s (data plus
parity) even; odd parity makes it odd. Widen your frame vector and index range to match.

**b)** Add a `two_stop` input that appends a second high stop bit. What is the only field of the
frame whose length now varies, and what does that do to the total frame time at a fixed baud rate?

**c)** `uart_tx_tb` checks 8N1 only, so it will still pass with your additions as long as the new
inputs default to off. Confirm that. Then describe, in words, the extra testbench case you would
add to pin down even parity: what byte would you send, and what would you expect on the parity bit?

---

