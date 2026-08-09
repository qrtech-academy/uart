# Appendix D

## Exercises
Exercise 1 reinforces [Appendix A](./a_sync.md), Exercise 2 [Appendix B](./b_uart_rx.md), and
Exercise 3 [Appendix C](./c_fifo.md). Exercise 4 is the reasoning that links the receiver to the
register bank you build next. Design each module from the specification in its own appendix and
check it with the provided testbench, run from `hw/` (see [`hw/README.md`](../../../hw/README.md)).

---

## Exercise 1 - `sync`
**a)** Write your own `sync.vhd` from Appendix A's specification and run its testbench:

```bash
cd hw
ghdl -a --std=93 sync.vhd sync_tb.vhd
ghdl -e --std=93 sync_tb
ghdl -r --std=93 sync_tb --assert-level=error
```

Note that no package appears in that first line: `sync` reads none, which is part of what makes it
reusable.

**b)** Delete one of the two flip flops, leaving a single register, and re-run. Which check fails,
and what does its message tell you? Put it back. Why would this bug pass every *other* simulation
in the course if this one testbench did not exist?

**c)** `sync` clears on `reset_s2_n`, and the testbench asserts it *between* two clock edges and
requires the output to clear before the next one. Change your reset to a synchronous one, tested
inside `if rising_edge(clock)`, and re-run. Which check fails, and what is the message? Put it back,
then say why the assertion has to be asynchronous while the *release* does not need to be, given
where `reset_s2_n` comes from.

**d)** `sync` takes `reset_s2_n`, the already-synchronized reset, as an input. Explain why that one
fact makes it impossible for `sync` to be the module that produces `reset_s2_n`, and why
`reset_sync` therefore exists as a separate provided block even though both are two flops in
series.

**e)** `uart_top` uses `sync` at `COUNT = 1`. Two bits of a `COUNT = 8` instance change on the same
edge; explain why `sync_out` may show one bit's new value and the other's old one for a clock, why
that is not a bug in `sync`, and why it would matter if those eight bits were a counter read across
clock domains rather than eight unrelated pins.

---

## Exercise 2 - `uart_rx`
**a)** Write your own `uart_rx.vhd` from Appendix B's specification and run its testbench:

```bash
cd hw
ghdl -a --std=93 uart_def.vhd uart_rx.vhd uart_rx_tb.vhd
ghdl -e --std=93 uart_rx_tb
ghdl -r --std=93 uart_rx_tb --assert-level=error
```

`uart_def.vhd` comes first because `uart_rx_tb` names bits through the package. `sync.vhd` is not on
that line at all: `uart_rx` reads `rx_s2`, the already-synchronized line, and instantiates nothing.
The crossing belongs one level up, in `uart_top`, which is where part e) puts it.

**b)** The receiver samples each bit at tick 8 of 16. Suppose the transmitter's baud rate is a few
percent faster than the receiver's, so the receiver's ticks are slightly long. Which end of the
byte drifts furthest from the bit centre, the first data bit or the stop bit, and why? Roughly how
much faster could the transmitter run before the stop-bit sample landed outside its bit?

**c)** The `STATE_START` state re-checks `rx_s2` at tick 8 before committing to a frame. Remove
that check (go straight from the falling edge to `STATE_DATA`) and describe what a single-tick
glitch on an idle line would now produce. Which real-world condition makes this more than a
theoretical worry?

**d)** Trace the store `frame(bit_idx) <= rx_s2` for the byte `0x53` (`0101_0011`) sent least
significant first. Write the eight received bits in the order they arrive, name the index each one
lands in, and show that after eight bits `frame` holds `0x53`. Then: what would `data_out` read if
`bit_idx` counted **down** from 7 instead of up from 0, and what is the relationship between that
byte and the one that was sent?

**e)** Add the receive path to the `uart_top` skeleton, which this time is two instantiations rather
than one: `sync` on the `rx` pin, then `uart_rx` behind it, reading `rx_s2` rather than `rx`. The
signals this lecture adds:

| Signal | Type | Driven by | Read by |
|---|---|---|---|
| `rx_vec`    | `std_logic_vector(0 downto 0)` | the `rx` pin, in the adapter below | `sync` |
| `rx_vec_s2` | `std_logic_vector(0 downto 0)` | `sync` | the adapter below |
| `rx_s2`     | `std_logic`                    | the adapter below | `uart_rx` |
| `rx_byte`   | `std_logic_vector(7 downto 0)` | `uart_rx` | `uart_regs` (L04) |
| `rx_push`   | `std_logic`                    | `uart_rx`'s `valid` | `uart_regs` (L04) |
| `frame_err` | `std_logic`                    | `uart_rx` | `uart_regs` (L04) |

![Module `sync`](./images/sync.png)

`COUNT` defaults to 1, so this instance needs no generic map - but it does work on vectors, which
is why the two one-element vectors above exist.

| # | `sync` port | Dir | Type | Connect to |
|---|---|---|---|---|
| 1 | `clock`      | in  | `std_logic`                        | `clock` |
| 2 | `reset_s2_n` | in  | `std_logic`                        | `reset_s2_n` |
| 3 | `async_in`   | in  | `std_logic_vector(COUNT-1 downto 0)` | `rx_vec` |
| 4 | `sync_out`   | out | `std_logic_vector(COUNT-1 downto 0)` | `rx_vec_s2` |

```vhdl
-- Cross the rx pin into the clock domain, once, in the module that owns the pin.
sync: entity work.sync
    port map(clock, reset_s2_n, rx_vec, rx_vec_s2);

-- sync works on vectors, so the single rx bit goes in and comes back out through one.
rx_vec(0) <= rx;
rx_s2     <= rx_vec_s2(0);
```

![Module `uart_rx`](./images/uart_rx.png)

| # | `uart_rx` port | Dir | Type | Connect to |
|---|---|---|---|---|
| 1 | `clock`      | in  | `std_logic`                    | `clock` |
| 2 | `reset_s2_n` | in  | `std_logic`                    | `reset_s2_n` |
| 3 | `baud_tick`  | in  | `std_logic`                    | `baud_tick` - the same tick `uart_tx` uses |
| 4 | `rx_s2`      | in  | `std_logic`                    | `rx_s2`, **not** the `rx` pin |
| 5 | `data_out`   | out | `std_logic_vector(7 downto 0)` | `rx_byte` |
| 6 | `valid`      | out | `std_logic`                    | `rx_push` |
| 7 | `frame_err`  | out | `std_logic`                    | `frame_err` |

```vhdl
-- Recover bytes from the synchronized line. Its valid output is the RX FIFO's push strobe, so
-- it binds straight to rx_push: that side needs no feeder, unlike the transmit side in L04.
uart_receiver: entity work.uart_rx
    port map(clock, reset_s2_n, baud_tick, rx_s2, rx_byte, rx_push, frame_err);
```

The order matters and is the point of the exercise: the pin crosses into the clock domain once, in
the module that owns the pin, and everything downstream of that is ordinary synchronous logic.
Binding `rx` straight to port 4 would analyze - both are `std_logic` - and would sample an
asynchronous pin directly, which is the metastability bug this whole lecture exists to prevent.

Both `rx_byte` and `rx_push` are read by nothing until L04, so nothing yet consumes what the
receiver produces. That is expected: an output with no reader analyzes and elaborates fine.

```bash
cd hw
ghdl -a --std=93 uart_def.vhd reset_sync.vhd baud_gen.vhd sync.vhd uart_tx.vhd uart_rx.vhd \
     spi_slave.vhd spi_reg_bridge.vhd uart_top.vhd
```

The top still analyzes and the system testbench is still skipped; only `uart_regs` is missing now.

---

## Exercise 3 - `fifo`
**a)** Write your own `fifo.vhd` from [Appendix C](./c_fifo.md)'s specification and run its
testbench:

```bash
cd hw
ghdl -a --std=93 uart_def.vhd fifo.vhd fifo_tb.vhd
ghdl -e --std=93 fifo_tb
ghdl -r --std=93 fifo_tb --assert-level=error
```

**b)** The testbench pushes a fifth byte into a full depth-4 FIFO and checks it is dropped. Remove
the `not full` guard on writes and re-run. What does the run report, and what has your FIFO done to
`count` and to the `head`/`tail` pointers to cause it? Note that the answer depends on how you
declared `count`: constrained as `natural range 0 to DEPTH`, the fifth push drives it out of range
and GHDL stops on a bound check before any assertion runs; left as an unconstrained `natural`, the
count simply passes `DEPTH` and it is the testbench's own check that fires. Both are failures, but
only one of them is the testbench talking. Put the guard back.

**c)** `rdata` shows the front entry with no `rd`; `rd` only advances. Explain why the RX path you
will build in L04 needs exactly this "look, then advance" split rather than a single
"read-and-pop" operation.

**d)** Both FIFOs in the finished peripheral are depth 8. Suppose software is slow and the receiver
delivers bytes faster than software reads them. At depth 8, how many back-to-back frames can arrive
before a byte is lost, and what flag would tell software it happened?

---

## Exercise 4 - Overrun belongs to the register bank
`uart_rx` reports a *framing* error but never an *overrun*: a second byte arriving before the first
was read.

**a)** Explain why `uart_rx`, on its own, cannot detect an overrun. What single piece of
information does it lack?

**b)** In L04 the RX FIFO's `full` flag is what makes overrun visible: a `valid` byte arriving while
the FIFO is full is dropped. Sketch, in words, the extra flag you would add so software could tell
that a byte was lost, and say which register it would live in (see the
[protocol spec](../../../protocol/uart_register_protocol.md)'s `ERROR_FLAGS`).

**c)** A framing error and an overrun have different causes. Give a physical cause for each: what on
the wire, or in the software's timing, produces one but not the other?

---

