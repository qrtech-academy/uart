# Appendix C

## Exercises
Exercise 1 reinforces [Appendix A](./a_uart_def.md); Exercises 2 and 3 go with
[Appendix B](./b_uart_top.md). `uart_def` is **provided** and only needs reading. `uart_top` is
yours, and Exercise 2 is self-contained: everything needed to type `hw/uart_top.vhd`, from the entity
down to the last internal signal, is below. Appendix B is where the reasoning behind it lives, and
Exercise 3 asks for that reasoning back.

Neither module has a testbench of its own in L01. `uart_def` is a package of constants, and
`uart_top`'s system testbench (`uart_top_tb`) stays skipped until its datapath exists in L04. So the
check here is that `uart_top` **analyzes cleanly** against the transport it instantiates. Run GHDL
from `hw/` (see [`hw/README.md`](../../../hw/README.md) for the full flow and what
`--assert-level=error` does).

---

## Exercise 1 - `uart_def`
**a)** `uart_def.vhd` is provided. Read it against Appendix A, then, without looking, name the seven
register indices and the `STATUS` / `CTRL` / `ERROR_FLAGS` bit positions. Analyze it so the names are
in your `work` library for everything that follows:

```bash
cd hw
ghdl -a --std=93 uart_def.vhd
```

There is nothing to elaborate or run; a clean analysis means the package compiles and its names are
available to every module that later writes `use work.uart_def.all`.

**b)** These are bit **positions**, not masks: `ST_RX_VALID` is `1`, not `2`. Show how you would test
the RX-valid bit of a status vector `status` using the constant, and contrast it with how the C++
driver forms the same test (`1U << status::RX_VALID`). Why does storing positions keep both sides
identical to the spec's "bit N" wording?

**c)** A teammate swaps two index values, setting `REG_RX_POP` to 6 and `REG_ERR_FLAGS` to 5.
Nothing in L01 notices. At what point in the course, and in which testbench, would the swap first
surface as a failure, and why not before?

---

## Exercise 2 - `uart_top`
Build the skeleton in the order the file is written: entity, declarations, then the three
instantiations and the one placeholder assignment. Each part below carries what that step needs.
Do not instantiate `baud_gen`, `uart_tx`, `sync`, `uart_rx` or `uart_regs` yet, and do not declare
their signals: those blocks arrive in L02 through L04, and each brings its own wiring with it.

**a) The entity.** Declare the eight ports in exactly this order. `uart_top_tb` binds them by
position, so the numbers are the contract; the names are yours.

| # | Port | Dir | Type |
|---|---|---|---|
| 1 | `clock`   | in  | `std_logic` |
| 2 | `reset_n` | in  | `std_logic` |
| 3 | `sclk`    | in  | `std_logic` |
| 4 | `mosi`    | in  | `std_logic` |
| 5 | `ss`      | in  | `std_logic` |
| 6 | `rx`      | in  | `std_logic` |
| 7 | `miso`    | out | `std_logic` |
| 8 | `tx`      | out | `std_logic` |

The file needs `ieee.std_logic_1164` for `std_logic`. It does not need `ieee.numeric_std` yet, since
nothing here converts a vector to an integer, and it does **not** need `use work.uart_def.all`: the
top wires the register bus but never names a bit on it, and `uart_regs` (L04) is the only module
that does. Follow the provided files' house style, a banner comment listing the inputs and outputs,
then `architecture behaviour of uart_top is`.

**b) The internal signals.** Declare only the signals **this** lecture wires. The method matters more
than the list: open the entity of every module you are about to instantiate, and for each port that
does not connect straight to a `uart_top` port, declare a signal of the same type to carry it. In
L01 that means `reset_sync`, `spi_slave` and `spi_reg_bridge`, and nothing else. Each later lecture
adds its own signals the same way, when it adds the block that needs them.

Two naming conventions run through the whole design, and both are worth adopting now. Signals that
carry SPI traffic between the two transport blocks take a **`spi_` prefix**. Signals that have been
through a two-flop synchronizer take an **`_s2` suffix**, which is why the provided modules all
expect `reset_s2_n` rather than `reset_n`.

| Signal | Type | Driven by | Read by |
|---|---|---|---|
| `reset_s2_n`   | `std_logic`                     | `reset_sync` in c) | every submodule |
| `spi_rx_data`  | `std_logic_vector(7 downto 0)`  | `spi_slave` | `spi_reg_bridge` |
| `spi_rx_valid` | `std_logic`                     | `spi_slave` | `spi_reg_bridge` |
| `spi_ss_active`| `std_logic`                     | `spi_slave` | `spi_reg_bridge` |
| `spi_tx_data`  | `std_logic_vector(7 downto 0)`  | `spi_reg_bridge` | `spi_slave` |
| `reg_addr`     | `std_logic_vector(3 downto 0)`  | `spi_reg_bridge` | `uart_regs` (L04) |
| `reg_wdata`    | `std_logic_vector(31 downto 0)` | `spi_reg_bridge` | `uart_regs` (L04) |
| `reg_write`    | `std_logic`                     | `spi_reg_bridge` | `uart_regs` (L04) |
| `reg_rdata`    | `std_logic_vector(31 downto 0)` | zeros in e), then `uart_regs` (L04) | `spi_reg_bridge` |

The four register-bus signals are here even though the block that answers on them is three lectures
away, because `spi_reg_bridge` has ports for them and an instantiation must connect every port. That
is the register bus existing with nothing behind it, which is the shape this lecture is really about.

`reg_addr` is four bits, not three, even though there are only seven registers: the protocol's
command byte reserves bits 3 to 0 for the index.

**c) The reset synchronizer.** `reset_n` arrives from off-chip, so it must assert asynchronously and
release synchronously, two flip flops later. That job is done by the provided `reset_sync`, which you
instantiate rather than write; its two internal flops are its own business, so the only signal it
adds to your top is `reset_s2_n`. Everything inside `uart_top` takes `reset_s2_n`, and nothing but
this instance sees `reset_n` directly.

![Module `reset_sync`](./images/reset_sync.png)

| # | `reset_sync` port | Dir | Connect to |
|---|---|---|---|
| 1 | `clock`      | in  | `clock` |
| 2 | `reset_n`    | in  | `reset_n` |
| 3 | `reset_s2_n` | out | `reset_s2_n` |

```
reset_sync: entity work.reset_sync
    port map(clock, reset_n, reset_s2_n);
```

**d) The transport.** Instantiate `spi_slave` and `spi_reg_bridge`, both positionally. The last
column names a signal from part b) or a port from part a).

![Module `spi_slave`](./images/spi_slave.png)

| # | `spi_slave` port | Dir | Type | Connect to |
|---|---|---|---|---|
| 1  | `clock`      | in  | `std_logic`                    | `clock` |
| 2  | `reset_s2_n` | in  | `std_logic`                    | `reset_s2_n` |
| 3  | `sclk`       | in  | `std_logic`                    | `sclk` |
| 4  | `mosi`       | in  | `std_logic`                    | `mosi` |
| 5  | `ss`         | in  | `std_logic`                    | `ss` |
| 6  | `tx_data`    | in  | `std_logic_vector(7 downto 0)` | `spi_tx_data` |
| 7  | `miso`       | out | `std_logic`                    | `miso` |
| 8  | `rx_data`    | out | `std_logic_vector(7 downto 0)` | `spi_rx_data` |
| 9  | `rx_valid`   | out | `std_logic`                    | `spi_rx_valid` |
| 10 | `ss_active`  | out | `std_logic`                    | `spi_ss_active` |

![Module `spi_reg_bridge`](./images/spi_reg_bridge.png)

| # | `spi_reg_bridge` port | Dir | Type | Connect to |
|---|---|---|---|---|
| 1  | `clock`      | in  | `std_logic`                     | `clock` |
| 2  | `reset_s2_n` | in  | `std_logic`                     | `reset_s2_n` |
| 3  | `ss_active`  | in  | `std_logic`                     | `spi_ss_active` |
| 4  | `rx_data`    | in  | `std_logic_vector(7 downto 0)`  | `spi_rx_data` |
| 5  | `rx_valid`   | in  | `std_logic`                     | `spi_rx_valid` |
| 6  | `reg_rdata`  | in  | `std_logic_vector(31 downto 0)` | `reg_rdata` |
| 7  | `tx_data`    | out | `std_logic_vector(7 downto 0)`  | `spi_tx_data` |
| 8  | `reg_addr`   | out | `std_logic_vector(3 downto 0)`  | `reg_addr` |
| 9  | `reg_wdata`  | out | `std_logic_vector(31 downto 0)` | `reg_wdata` |
| 10 | `reg_write`  | out | `std_logic`                     | `reg_write` |

The names that look shared are not one bus. `spi_slave`'s `rx_data` is an output and the bridge's
`rx_data` is an input, so `spi_rx_data` runs slave to bridge; `spi_tx_data` runs the other way, from
the bridge's `tx_data` output into the slave's `tx_data` input. Read them as two one-directional
lanes and the wiring falls out.

Nothing drives `reg_rdata` yet, so give it a value:

```
reg_rdata <= (others => '0');
```

The file would analyze without this; an undriven signal is legal. It is here so the bridge reads a
defined value instead of `'U'` while the bank is missing. **Delete this line in L04**, when
`uart_regs` starts driving `reg_rdata`. Leave it in and the vector has two drivers: every `'1'` from
the bank resolves against the `'0'` here to `'X'`, and the system testbench fails on a read-back
caused by a line you wrote three lectures earlier.

**e) The check.** Analyze the skeleton against the package and the transport it instantiates:

```bash
cd hw
ghdl -a --std=93 uart_def.vhd reset_sync.vhd spi_slave.vhd spi_reg_bridge.vhd uart_top.vhd
```

Then run `make build-vhdl` from the repository root. Confirm `uart_def` and `uart_top` both analyze
cleanly, that the two transport testbenches pass (they are the only ones that can run this early,
since they check provided modules), and that `uart_top_tb` reports **skipped**. Which modules does
the skip message name as missing, and which lecture (L02, L03, L04) builds each? One of the six is
never instantiated by `uart_top` at all; find it, and say why the build needs it anyway.

---

## Exercise 3 - What a clean analysis does not prove
`uart_top` analyzes, and almost nothing about it is proven. That gap is the lesson of L01.

**a)** Swap two same-type ports in your entity, say `sclk` and `mosi`, and re-analyze. Does `ghdl -a`
catch it? If not, at which point in the course does the mistake finally show up, and what does that
tell you about the cost of a positional contract?

**b)** `reg_rdata` is tied to zeros and no register bank answers on the bus. What does an SPI read
transaction return with that placeholder in place, and why is that harmless until L04? What would it
return instead if you left the placeholder out altogether?

**c)** The provided `reset_sync` asserts asynchronously but releases synchronously. Suppose it
released asynchronously too, wiring `reset_n` straight to every block. Describe the failure that a
near-edge release could cause. Then explain why `sync` (L03) cannot do this job, given that it is
also two flip flops in series: look at its port list and say what it would need that only
`reset_sync` can give it.

**d)** Why does building `uart_top` before any block it instantiates fix each block's port list in
advance? What has to be true about `baud_gen`'s ports in L02 for its instantiation here to bind
without you touching the top again?

---

