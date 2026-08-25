# Paper B - Solutions

Marks are shown per part. Method carries them: a correct derivation with a slip in it is worth more
than a correct answer with no working, and later parts consume earlier ones, so an error should be
followed through rather than penalised twice. A candidate whose register map is wrong in Question 1
and who then uses their own map consistently in Questions 4 and 5 loses the marks once.

Where a part asks for VHDL, mark the **hardware described**, not the syntax: the sensitivity list,
the reset branch, whether a pulse is one clock wide, whether every path assigns its output, and
which way a shift goes. Where it asks for C++, mark the **byte order, the ordering of register
accesses, and the qualifiers that carry meaning** - `const`, `noexcept`, `override`, and what has
been deleted - not the punctuation.

Where a part asks for a review, naming the defect earns half and saying what it does to the running
system earns the other half.

---

## Question 1 - Building the top before anything it holds (12 marks)

### (a) 3 marks

```vhdl
--------------------------------------------------------------------------------
-- UART peripheral top level.
--
-- Inputs:
--    - clock: 50 MHz system clock.
--    - reset_n: Asynchronous active-low reset.
--    - sclk, mosi, ss: SPI from the processor.
--    - rx: UART serial input.
--
-- Outputs:
--    - miso: SPI to the processor.
--    - tx: UART serial output.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity uart_top is
    port(clock, reset_n: in std_logic;
         sclk, mosi, ss: in std_logic;
         rx            : in std_logic;
         miso, tx      : out std_logic);
end entity;
```

*(2 marks: 1 for the eight ports in the right order with the right directions, 1 for inputs-first
grouping, the clauses and the banner)*

**The clause it does not need.** `ieee.numeric_std`. Nothing in the L01 skeleton converts between a
vector and an integer: the top wires bytes and vectors from block to block and never interprets one
as a number.

It is added in **L02**, for the single guarded conversion that turns the register bank's `BAUD_DIV`
vector into the `natural` `baud_gen` expects:

```vhdl
baud_div_int <= 1 when is_x(baud_div) or unsigned(baud_div) = 0
              else to_integer(unsigned(baud_div));
```

`unsigned` and `to_integer` come from `numeric_std`; `is_x` comes from `std_logic_1164`, so it needs
no clause of its own. That expression is the only place in `uart_top` where a `std_logic_vector`
becomes an integer.

**Why never `use work.uart_def.all`.** The top carries the register bus - `reg_addr`, `reg_wdata`,
`reg_write`, `reg_rdata` - from the bridge to the bank without ever **naming** a register or a bit
on it. It is wiring, not interpretation. `uart_regs` is the only synthesizable module that
interprets what is on that bus, so it is the only one that needs the package (the testbenches use it
too, mostly for `to_hex`). *(1 mark)*

### (b) 5 marks

**The signals.** Read each entity and declare, for every port that does not connect straight to a
`uart_top` port, a signal of the same type:

```vhdl
architecture behaviour of uart_top is
signal reset_s2_n   : std_logic;                      -- from reset_sync, to everything
signal spi_rx_data  : std_logic_vector(7 downto 0);   -- slave  -> bridge
signal spi_rx_valid : std_logic;                      -- slave  -> bridge
signal spi_ss_active: std_logic;                      -- slave  -> bridge
signal spi_tx_data  : std_logic_vector(7 downto 0);   -- bridge -> slave
signal reg_addr     : std_logic_vector(3 downto 0);   -- bridge -> uart_regs (L05)
signal reg_wdata    : std_logic_vector(31 downto 0);  -- bridge -> uart_regs (L05)
signal reg_write    : std_logic;                      -- bridge -> uart_regs (L05)
signal reg_rdata    : std_logic_vector(31 downto 0);  -- uart_regs (L05) -> bridge
begin
```

*(2 marks: 1 for the nine signals and their types, 1 for the `spi_` prefix and `_s2` suffix used
correctly and for declaring nothing a later lecture brings)*

**The instantiations.** *(2 marks)*

```vhdl
    reset_sync: entity work.reset_sync
        port map(clock, reset_n, reset_s2_n);

    spi_slave: entity work.spi_slave
        port map(clock, reset_s2_n, sclk, mosi, ss, spi_tx_data,
                 miso, spi_rx_data, spi_rx_valid, spi_ss_active);

    spi_reg_bridge: entity work.spi_reg_bridge
        port map(clock, reset_s2_n, spi_ss_active, spi_rx_data, spi_rx_valid, reg_rdata,
                 spi_tx_data, reg_addr, reg_wdata, reg_write);
```

Note that `miso` connects **straight to the entity port**, so it needs no signal of its own - that is
the reason the list above has nine entries rather than ten, and it is the whole method of the
exercise.

**The two `rx_data` ports.** *(1 mark)* They are not one bus, and they are not even the same
direction. `spi_slave`'s `rx_data` is an **output**: bytes it has finished shifting in from `MOSI`.
The bridge's `rx_data` is an **input**: the bytes it assembles into transactions. So `spi_rx_data`
runs **slave to bridge**. `spi_tx_data` runs the other way, from the bridge's `tx_data` *output*
into the slave's `tx_data` *input*, carrying the bytes to be shifted out on `MISO`. Read them as two
one-directional lanes that happen to share a naming convention, and the wiring falls out.

**Why `reg_addr` is four bits.** The protocol's command byte reserves bits 3-0 for the register
index, so the master can send any value from 0 to 15 and the bus has to be able to carry it. Indices
7-15 are *defined* as reserved - a read returns `0x00000000` and a write is ignored - which is a
rule the bank can only implement if it can see the out-of-range index in the first place. Three bits
would make an illegal address indistinguishable from a legal one.

### (c) 2 marks

```vhdl
    reg_rdata <= (others => '0');
```

*(half a mark - the line is trivial; the marks are in what follows)*

**With it in place**, an SPI read transaction returns **`0x00000000`** for every register index.
That is harmless until L05 because there is no register bank yet: nothing in the design has a value
to return, and no testbench asks for one - `uart_top_tb` is *skipped* until its datapath exists, and
the two transport benches drive the provided blocks directly. *(1 mark)*

**Without it**, `reg_rdata` has **no driver at all**. That is legal VHDL and the file still
analyzes. But an undriven signal of a resolved type sits at the **left-most value of its type**,
which for `std_logic` is `'U'` - *uninitialized*. So "returns" is the wrong word: the bridge latches
all-`'U'`, shifts `'U'` out on `MISO`, and the metavalue propagates into anything that looks at it.
It is not zero and it is not garbage-but-defined; it is the simulator's marker for "nothing has ever
driven this", which is exactly the information the placeholder exists to suppress while the bank is
missing. *(half a mark)*

The other half of the mark is for saying **when it must go**: in L05, in the same edit that
instantiates `uart_regs`. Leave it and the vector has two drivers.

### (d) 2 marks

**What the top fixes.** Every block's **port contract**: the number of ports, their order, their
directions and their types. The moment `uart_top` writes `port map(clock, reset_s2_n, baud_div_int,
baud_tick)`, `baud_gen` has no interface decisions left to make - and neither does its testbench,
which was written against the same contract before either existed. Building top-down means a block
arrives into a shape that is already waiting for it, rather than the top being rewritten around each
block as it lands. *(1 mark)*

**What has to be true of `baud_gen`.** Its entity must declare exactly four ports, in this order and
with these types:

| # | Dir | Type |
|---|---|---|
| 1 | in | `std_logic` |
| 2 | in | `std_logic` |
| 3 | in | `natural range 1 to 65535` |
| 4 | out | `std_logic` |

**What is not part of the contract: the names.** `hw/README.md` says so outright - rename every port
and everything still binds, because nothing in this course associates a port by name. The appendices
keep their names anyway so that the prose and the code talk about the same signals, but that is a
convenience for readers, not a rule the tools enforce. It is also, as Paper A's Question 1 explores,
the reason a transposed pair of same-type ports is invisible until the system testbench runs.
*(1 mark)*

---

## Question 2 - The generator, the divider, and the frame (13 marks)

### (a) 4 marks

```vhdl
--------------------------------------------------------------------------------
-- Baud rate generator.
--
-- Inputs:
--    - clock: 50 MHz system clock.
--    - reset_s2_n: Active-low synchronized reset.
--    - div: Baud rate divider. Must be greater than 0.
--
-- Outputs:
--    - tick: Baud rate tick.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity baud_gen is
    port(clock, reset_s2_n: in std_logic;
         div              : in natural range 1 to 65535;
         tick             : out std_logic);
end entity;

architecture behaviour of baud_gen is
signal counter: natural;
begin
    process(clock, reset_s2_n) is
    begin
        if (reset_s2_n = '0') then
            tick    <= '0';
            counter <= 0;
        elsif (rising_edge(clock)) then
            if (counter >= div - 1) then
                tick    <= '1';
                counter <= 0;
            else
                tick    <= '0';
                counter <= counter + 1;
            end if;
        end if;
    end process;
end architecture;
```

*(3 marks: 1 for the entity with `div` as a `natural` and the four ports in order; 1 for the
asynchronous reset with `reset_s2_n` in the sensitivity list and both outputs cleared; 1 for a
**registered**, one-clock-wide `tick` with the counter reloading to zero)*

Deduct for a `tick` driven combinationally, for a synchronous reset, or for a counter that reloads to
`1`.

**The comparison.** *(1 mark)*

At `div = 1`, `div - 1` is `0` and the counter is always `0` when the test runs, so both forms fire
on **every** clock. They are indistinguishable, and the same is true for any stable `div`: the
counter reloads the instant it reaches the threshold and never passes it.

At `div = 0` they diverge completely. `div - 1` evaluates to `-1`:

* `counter >= -1` is **always true**, so the block ticks every cycle and the counter never leaves
  zero. Useless output, but the design keeps running and stays inside its declared range.
* `counter = -1` is **never true**, so the counter is incremented on every edge for ever. `counter`
  is a `natural`, so this ends in a **run-time bound check failure** that aborts the simulation, and
  in synthesis it is a counter that free-runs and wraps.

So `>=` is the one that keeps the counter inside its declared range. It also corrects a `div`
changed mid-count on the next edge rather than after a wrap. One character of typing for both.

Worth noting for a candidate who raises it: `div` is declared `natural range 1 to 65535`, so `0`
cannot legally be *bound* to it. The `>=` is defensive against the case the subtype is supposed to
rule out, which is exactly when defensiveness is cheap and worth having.

### (b) 3 marks

```text
exact divider = 50_000_000 / (16 x 9600) = 50_000_000 / 153_600 = 325.52
BAUD_DIV       = round(325.52) = 326

tick rate = 50_000_000 / 326 = 153_374.2 Hz
baud rate = 153_374.2 / 16   = 9585.9 baud
error     = (9585.9 - 9600) / 9600 = -0.15%   (slow)
```

*(2 marks: 1 for the divider, 1 for the achieved rate and a correctly signed error)*

**Why `16 x baud`.** *(1 mark)* The receiver cannot see where a bit begins - there is no clock on the
wire, only the line itself. So it **oversamples**: it watches `rx` sixteen times per bit, finds the
falling edge that starts a frame, and then aims for the middle of each bit rather than its edge. For
the transmitter and the receiver to share **one** time base rather than each keeping its own, that
base has to tick at the finer rate.

**`uart_rx` spends the sixteen.** It uses them for resolution: one to notice the start edge, eight to
reach the middle of the start bit for the re-check that rejects a glitch, and then one sample every
sixteen thereafter, at each bit's centre.

**`uart_tx` does not need them** and simply counts: sixteen ticks to a bit, changing the line only on
bit boundaries. It shares the generator not because it needs the resolution but so that both halves
are paced by the same divider from the same clock, with no handshake between them.

### (c) 3 marks

**The frame.** *(1 mark)*

```vhdl
frame <= STOP_BIT & parity_bit & data & START_BIT;   -- frame(10 downto 0)
```

| index | 0 | 1 .. 8 | 9 | 10 |
|---|---|---|---|---|
| carries | start | `data(0)` .. `data(7)` | **parity** | stop |

`FRAME_WIDTH` becomes 11 and `bit_idx` is declared `natural range 0 to 10`, so the terminal test
`bit_idx >= FRAME_WIDTH-1` still reads correctly. The parity bit goes **between the last data bit and
the stop bit**, which is where the line protocol puts it, and the stop bit moves from index 9 to
index 10.

**The parity bit.** *(1 mark)*

```vhdl
even_parity <= data(0) xor data(1) xor data(2) xor data(3)
           xor data(4) xor data(5) xor data(6) xor data(7);

parity_bit  <= '0'          when parity_en  = '0' else
               even_parity  when parity_odd = '0' else
               not even_parity;
```

Even parity makes the total number of ones - data plus parity - **even**, and the XOR of the data
bits is exactly the bit that achieves it. Odd parity is its complement. (With `parity_en` clear the
bit is not sent at all; a design that keeps the eleventh position and drives it `'0'` is *wrong*,
because that is a frame with a permanently-zero parity bit rather than an 8N1 frame.)

**The variable field, and the cost.** *(1 mark)* With a `two_stop` input, the **stop field** is the
only field whose length varies - 1 or 2 bits. Parity is a different matter: it adds a field rather
than lengthening one.

Frame lengths: **10** bits (8N1), **11** (either parity or a second stop bit), **12** (both).

At 115200 baud, throughput is `baud / bits-per-frame`:

```text
10 bits: 115_200 / 10 = 11_520 bytes/s
12 bits: 115_200 / 12 =  9_600 bytes/s
```

so the longest frame costs **1920 bytes/s**, a drop of **16.7%**, for the same line rate. The wire
runs at exactly the same speed; you are simply spending a third of it on framing (4 bits in 12)
rather than data, where 8N1 spent a fifth (2 bits in 10).

### (d) 3 marks

**What the bench checks about `busy`.** *(1 mark)* Nothing. `uart_tx_tb` **binds** `busy` and `done`
but never asserts on either - the appendix says so in as many words. What it does check is that `tx`
idles high, goes low within two bit periods of `start`, that the start bit is low at its centre, that
the eight data bits match least significant first, and that the stop bit is high. A `busy` that rises
one clock late is entirely invisible to it.

**What the feeder does.** *(1 mark)* The feeder is

```vhdl
tx_load <= (not tx_empty) and (not tx_busy);
tx_pop  <= tx_load;
```

On the edge that loads a byte, the FIFO is popped and the transmitter enters `STATE_SEND`. On the
**next** clock, `tx_busy` is still low - it rises a clock late - and `tx_empty` is still low if any
byte remains queued. So `tx_load` is high for a **second** clock, producing a second `start` pulse
and a second `tx_pop`.

**What happens to the byte.** `uart_tx` ignores `start` outside `STATE_IDLE`, so the second start
does nothing - the candidate is right about that, and it is what makes the bug survive review. But
`tx_pop` is not ignored: the FIFO honours it and **discards its front byte**. So the byte behind the
one in flight is popped and never transmitted, once per frame.

Note the edge case that hides it: with exactly one byte queued, the FIFO is already empty after the
first pop, so `tx_empty` is high on the second clock and `tx_load` is low. The bug only appears from
the second queued byte onward.

**The fix and the first bench that could catch it.** *(1 mark)*

```vhdl
busy <= '1' when state = STATE_SEND else '0';
```

A concurrent decode of the state, so `busy` is high in the same simulation cycle as the state change
rather than a clock later.

The first testbench that **could** have caught it is `uart_top_tb`, in **L05** - the first bench in
which the feeder, the FIFO and the transmitter exist at the same time. Be honest about the rest: as
written it writes exactly **one** byte to `TX_DATA`, so it lands squarely in the edge case above and
does **not** catch it. Catching it needs a bench that queues two bytes and checks that both leave.
Full marks for the honest answer; half for "L05's `uart_top_tb`" without the caveat.

---

## Question 3 - The asynchronous line, written out (14 marks)

### (a) 4 marks

```vhdl
--------------------------------------------------------------------------------
-- Generic double-flop synchronizer.
--
-- Generics:
--    - COUNT: Number of inputs to synchronize. Must be greater than 0.
--
-- Inputs:
--    - clock: 50 MHz system clock.
--    - reset_s2_n: Active-low synchronized reset.
--    - async_in: Inputs to synchronize.
--
-- Outputs:
--    - sync_out: Synchronized signals.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity sync is
    generic(COUNT: natural range 1 to 15 := 1);
    port(clock, reset_s2_n: in std_logic;
         async_in         : in std_logic_vector(COUNT-1 downto 0);
         sync_out         : out std_logic_vector(COUNT-1 downto 0));
end entity;

architecture behaviour of sync is
signal sync_s1, sync_s2: std_logic_vector(COUNT-1 downto 0);
begin
    sync_out <= sync_s2;

    process(clock, reset_s2_n) is
    begin
        if (reset_s2_n = '0') then
            sync_s1 <= (others => '0');
            sync_s2 <= (others => '0');
        elsif (rising_edge(clock)) then
            sync_s1 <= async_in;
            sync_s2 <= sync_s1;
        end if;
    end process;
end architecture;
```

*(2 marks: 1 for the generic with its default and the vector ports sized from it; 1 for two flops in
series with the **asynchronous** reset and `sync_out` taken from the **second**)*

The commonest error worth deducting for is `sync_out <= sync_s1`, which throws away the entire point:
the output must come from the flop that has had a full clock period to settle.

**Two edges.** *(1 mark)* `sync_out` follows `async_in` after **exactly two** rising edges.

* **One is not a synchronizer.** A single register gives a metastable output no settling time at
  all: whatever it is doing at the next edge is what the design consumes. It looks identical in
  simulation - nothing in a simulator is ever metastable - which is precisely why `sync_tb`'s
  "exactly two edges" check exists and why deleting a flop is the bug that testbench is *for*.
* **Three is not wrong, it is unspecified.** An extra stage buys more settling time and would be
  right at a much higher clock or for a far more hostile input, but here it adds a clock of latency,
  fails `sync_tb`, and changes the receiver's edge-detection timing. The contract is two, so the
  module delivers two.

**A `COUNT = 8` instance.** *(1 mark)* Each bit crosses **independently**, through its own pair of
flops. Two bits that change on the same source edge can therefore resolve on different clocks, so
`sync_out` may show one bit's new value beside another's old one for a cycle.

That is **not a defect in `sync`**: each bit individually is correctly synchronized, which is
everything a synchronizer promises. The promise was never coherence across bits.

So the kind of signal you must never put through a wide instance is a **multi-bit value whose bits
must stay coherent** - a counter, an address, any encoded number crossing clock domains. The
receiving side can read a value the source never held: a counter going from `0111` to `1000` can be
sampled as anything from `0000` to `1111`. Use a Gray code (only one bit changes per step, so the
worst case is the old value or the new one), a request/acknowledge handshake, or an asynchronous
FIFO. `rx` is a single bit, so the question does not arise here - but it arises the first time
somebody reaches for a wide instance.

### (b) 4 marks

```vhdl
when STATE_IDLE =>
    -- Leave idle only on a high-to-low transition, never on a level.
    if ((rx_s2 = START_BIT) and (rx_prev = STOP_BIT)) then
        state <= STATE_START;
        ticks <= 0;              -- restart the count from this edge
    end if;

when STATE_START =>
    -- Half a bit on from the edge, check the line is still low.
    if (sample_start_bit = '1') then
        if (rx_s2 = '0') then
            state <= STATE_DATA;
            ticks <= 0;
        else
            state <= STATE_IDLE; -- a glitch, not a start bit
        end if;
    end if;
```

and, **last on the tick**, after the `case` and inside the `if baud_tick = '1'`:

```vhdl
rx_prev <= rx_s2;
```

*(2 marks: 1 for the edge test and the glitch re-check with both outcomes; 1 for the history flop and
its placement)*

**Why the placement matters.** Updating `rx_prev` **after** the state machine has read it is what
makes the comparison "this tick against the previous tick". Move it before the `case` and `rx_prev`
already equals `rx_s2`, so `rx_s2 = START_BIT and rx_prev = STOP_BIT` can never both hold - the
receiver never leaves idle and never receives anything. Worth noting alongside: the `ticks <= 0` in
the idle branch overrides the tick-counter block above it, because that block comes first in the
process and VHDL gives the **last** assignment in a process the final say.

**The level test and the break.** *(2 marks)*

With `if rx_s2 = '0' then`, the receiver re-arms the moment the previous frame's stop bit has been
judged. During a break - the line held low for longer than a frame, which is what a transmitter
losing power or a cable coming loose looks like - it marches through back-to-back **all-zero
frames**. Each of those ends on a low stop bit and is correctly rejected as a framing error, and
that part is fine.

The failure is the frame still **in flight when the break ends**. Its stop bit is sampled after the
line has returned high, so as far as the receiver can tell it is a well-formed frame: `valid` pulses
and a byte assembled out of nothing - the tail of the break plus the returning idle - is pushed into
the RX FIFO as real data. Software receives a byte nobody sent.

With an edge test there is no second falling edge until the line has gone high again, so no frame is
ever in flight across that boundary. One flip flop, and it is the difference between a receiver that
works on clean data and one that survives a cable being unplugged.

**The testbench case** is `uart_rx_tb`'s break case: it holds the line low for longer than one frame
and then idles long enough for a frame in flight to complete. Its message names the fix outright -
"a break produced a byte - leave `STATE_IDLE` on a falling edge" - and a second check requires the
break to be reported as at least one framing error, so a receiver that goes silent instead of wrong
does not pass either.

### (c) 3 marks

```vhdl
    elsif (rising_edge(clock)) then
        -- Defaults first: any pulse from the previous cycle lasts exactly one clock.
        data_out  <= (others => '0');
        valid     <= '0';
        frame_err <= '0';
        ...
            when STATE_STOP =>
                if (sample_data = '1') then
                    if (rx_s2 = '1') then
                        data_out <= frame;      -- the stop bit is where it should be
                        valid    <= '1';
                    else
                        frame_err <= '1';       -- framing is broken
                        frame     <= (others => '0');
                    end if;
                    state <= STATE_IDLE;        -- either way
                end if;
```

*(2 marks: 1 for both outcomes and the unconditional return to idle, 1 for the defaults)*

**What makes the pulses one clock wide.** The defaults are written **first on every clock edge**, and
only the specific case overrides them. So a `valid` set at one edge is cleared at the next, with no
extra counter, no extra state and nothing to get out of step. Writing the default first and letting
the specific case override it is the course's idiom for a single-cycle strobe, and it is the same
one `uart_tx` uses for `done`.

**Why the byte is dropped.** *(1 mark)* A framing error means the receiver's idea of *where the bits
were* is wrong: the stop bit was not high where it should have been, so the eight bits it sampled
were sampled at times it cannot vouch for. Delivering them alongside a flag would put a byte into the
RX FIFO that software cannot distinguish from good data once it has popped past it - `ERROR_FLAGS`
is **global and sticky**, not attached to a FIFO entry, so there is no way to say "this byte in
particular is suspect". Dropping it preserves the invariant that every byte in the RX FIFO is a byte
the receiver believes in, and the sticky flag still tells software that something went wrong.

**What the bank does with each pulse.** `valid` becomes `uart_regs`' `rx_push`, so the byte enters
the RX FIFO and `STATUS` bit 1 (RX-valid) goes high, where software can poll it. `frame_err` is
latched into `ERROR_FLAGS` bit 0, which stays set until software writes zero to clear it, and
`STATUS` bit 2 is the OR of the error flags. Both pulses are one clock wide and neither could be
polled directly - turning them into levels is the register bank's entire job.

### (d) 3 marks

**All three passed.** *(1 mark)*

| Byte | Binary | Reversed | Same? |
|---|---|---|---|
| `0xA5` | `1010 0101` | `1010 0101` | yes |
| `0x3C` | `0011 1100` | `0011 1100` | yes |
| `0x5A` | `0101 1010` | `0101 1010` | yes |

A receiver that stores its data bits in the reverse order delivers, for each of these, **exactly the
byte that was sent**. Every check comparing the received byte with the expected one passed, and no
other check in any of the three benches looks at bit order at all - so at that revision the whole of
`hw/` was blind to it.

**The property and the count.** They are **bit-reversal palindromes**. A palindrome is determined by
its top four bits - `b7` fixes `b0`, `b6` fixes `b1`, and so on - so there are `2^4 = 16` of them out
of 256. All three constants happen to be among the sixteen.

**The second, independent reason for `uart_top_tb`.** *(1 mark)* It **loops `tx` back to `rx`**. A
design built by one person from one set of appendices will get the order the same way in both halves,
and a matched pair of reversals **cancels exactly**: the transmitter puts the byte on the wire
backwards and the receiver reads it backwards, so the byte read back over SPI is the byte written,
whatever the constant. Changing `0x5A` to something asymmetric would let the bench catch a *one-sided*
flip - a receiver reversed while the transmitter is not - but it structurally cannot catch the
matched pair, which is the likelier bug.

**What the bench reports today.** *(1 mark)* `0x53` is `0101 0011` and its reverse is `1100 1010`, so
with the reversed-order receiver in place `data_out` carries **`0xCA`**. `uart_rx_tb`'s clean-frame
case then fails and names both values, since its message already prints the expected and the
received byte through `to_hex`:

```text
uart_rx_tb: received byte mismatch, expected 0x53, got 0xCA!
```

The fix that got it there was one constant per bench - `TXBYTE` in `uart_tx_tb`, `BYTE_A` and
`BYTE_B` in `uart_rx_tb`, and the transmitted byte in `uart_top_tb` - which is worth noting in its
own right: the gap was three lines wide and had nothing to do with the checks themselves.

**What is still out of reach.** A transmitter and a receiver that are reversed **together**.
`uart_tx_tb` and `uart_rx_tb` each catch their own half, so the pair cannot survive both unit
benches - but `uart_top_tb` alone never could, for the structural reason above, and a candidate who
says "the loopback is fixed now" has missed it. No constant makes a loopback able to test a
convention that both ends of it share.

Full marks for reaching the conclusion by any route. The key insight, worth the bulk of the marks, is
that a loopback bench cannot test a property that both halves get wrong together, and that a
symmetric constant cannot test an ordering.

---

## Question 4 - The bank, written out (13 marks)

### (a) 4 marks

```vhdl
process(clock, reset_s2_n) is
    variable addr: natural range 0 to 15;
begin
    if (reset_s2_n = '0') then
        err_flags <= (others => '0');
    elsif (rising_edge(clock)) then
        addr := to_integer(unsigned(reg_addr));

        -- Software clear: a write of zero to ERROR_FLAGS clears every flag.
        if ((reg_write = '1') and (addr = REG_ERR_FLAGS) and (unsigned(reg_wdata) = 0)) then
            err_flags <= (others => '0');
        end if;

        -- The receiver's pulse sets the framing bit. Written last, so it wins a tie.
        if (frame_err = '1') then
            err_flags(ER_FRAMING) <= '1';
        end if;
    end if;
end process;
```

*(2 marks: 1 for a reset value of zero with a defined set and a defined clear, 1 for using
`uart_def`'s constants and for a clear that is a write of zero to the right index)*

**Both on the same clock.** The set is written **after** the clear in the same process, and VHDL
gives the last assignment the final say, so **the set wins**: an error arriving in the same cycle as
a clear is not lost. That is the right way round. Losing an error because software happened to clear
in the same 20 ns window is a silent data-integrity hole that would be essentially impossible to
reproduce; a flag that survives one extra clear merely makes software clear twice, which it was
polling anyway. A candidate who orders it the other way should say why - the honest reason would be
"so a clear always leaves the register readable as zero", and it is not a good enough one.

**Why a pulse cannot be polled.** *(1 mark)* `frame_err` is high for **one clock**: 20 ns. Software
polls over SPI, and one five-byte transaction at 1 MHz `SCK` takes at least **40 us** - two thousand
times longer than the pulse, before any inter-byte overhead. The probability that a `STATUS` read
lands on precisely the clock the pulse is high is effectively zero, and even then the pulse would
have to coincide with the exact cycle in which the bridge latches the read value. A pollable bit has
to be a **level that persists until acknowledged**, and manufacturing that level from a pulse is
what the latch is for.

**Wired straight through.** *(1 mark)* `STATUS` bit 2 would read `0` on **every single poll, for
ever**, no matter how many framing errors occurred. The system would appear to have no errors at all.

Worse, it would appear so *consistently*: a driver would never see the bit flicker, never see it
disagree with `ERROR_FLAGS`, and have nothing at all to suggest the mechanism was broken. A flag that
is always wrong in the same direction is far harder to notice than one that is sometimes wrong, and
the first evidence would be a bench full of corrupted bytes and a peripheral cheerfully reporting
itself healthy.

### (b) 4 marks

**The read decode.** *(1 mark)*

```vhdl
with to_integer(unsigned(reg_addr)) select reg_rdata <=
    status_reg                           when REG_STATUS,
    ctrl_reg                             when REG_CTRL,
    x"0000" & baud_div_reg               when REG_BAUD_DIV,
    (others => '0')                      when REG_TX_DATA,     -- write-only
    x"000000" & rx_front                 when REG_RX_DATA,
    (others => '0')                      when REG_RX_POP,      -- write-only
    x"0000000" & '0' & err_flags         when REG_ERR_FLAGS,
    (others => '0')                      when others;          -- reserved: 7-15
```

An equivalent `case` inside a combinational process with `reg_addr` and every source register in the
sensitivity list is just as good; mark the decode, not the form. What must be right is that the two
write-only registers and every reserved index read **zero**, and that every path assigns.

**The write actions.** *(1 mark)*

```vhdl
        -- Defaults, so each FIFO strobe is exactly one clock wide.
        tx_wr <= '0';
        rx_rd <= '0';

        if (reg_write = '1') then
            case addr is
                ...
                when REG_TX_DATA =>
                    tx_wdata <= reg_wdata(7 downto 0);
                    tx_wr    <= '1';       -- push one byte into the TX FIFO
                when REG_RX_POP =>
                    rx_rd    <= '1';       -- advance the RX FIFO past its front byte
                ...
                when others => null;       -- reserved indices: ignored
            end case;
        end if;
```

Both are **edge events**: one write, one action, never a held level. That is what makes them safe to
be one-cycle strobes into the FIFOs.

**Why the read is combinational.** *(1 mark)* The transport contract says the bridge **latches the
addressed register's value once**, at the end of the command byte, and then shifts those four bytes
out while the master sends dummies. For that latch to capture the right value, `reg_rdata` must
already reflect `reg_addr` in the same cycle the address becomes known. A registered read would
present its value one clock late, so the bridge would latch the answer to the *previous* question -
every read would return the previous read's register, which is a bug that looks like a random
off-by-one until somebody notices the pattern.

**`when others`, and why it is a different mistake here.** It must produce `(others => '0')` on the
read side and `null` on the write side, because the protocol **defines** indices 7-15 as reserved: a
read returns `0x00000000` and a write is ignored.

In an ordinary combinational decoder, omitting `when others` is a *synthesis* mistake - it infers a
latch, because the tool has no value for the uncovered case and must therefore hold. That is true
here too. But here it is also a **protocol violation**: a driver is entitled to probe an
unimplemented register and get zero, and a bank that returned something else - or held the previous
value - would be non-compliant even if it inferred no latch at all. Two independent reasons for the
same line.

**What the bank relies on.** *(1 mark)* That `spi_reg_bridge` asserts `reg_write` **only on a
completed, non-aborted write transaction** (protocol spec, Part 3). A strobe the bank sees is
therefore always a real commit. That single guarantee is what lets `TX_DATA` and `RX_POP` be simple
one-cycle actions with no commit-and-abort machinery of their own - the bank never has to think about
`SS` at all. If a half-finished transaction could reach it as a `reg_write`, every write action in
the bank would need to be held pending and rolled back, and the read/pop split would stop being an
elegance and start being a necessity.

### (c) 3 marks

**The condition.** *(1 mark)*

```vhdl
overrun <= rx_push and rx_full;
```

The receiver delivered a byte while the RX FIFO had no room, so `fifo`'s `not full` guard dropped it.
Both signals are already inside `uart_regs` - `rx_push` is the receiver's `valid` and `rx_full` is
the FIFO's own flag - so the detection is one AND gate. It sets the flag through the same latch as
`frame_err`.

**The bit and the clear path.** `ER_OVERRUN`, **`ERROR_FLAGS` bit 2**, cleared by the same write of
`0x00000000` to `ERROR_FLAGS` that clears the other two, and visible through `STATUS` bit 2 (the OR
of the flags) so that a polling driver sees it without an extra register read.

**What `uart_rx` would need, and why it is worse.** *(1 mark)* It would have to be told **whether the
previous byte has been consumed** - in practice the RX FIFO's `full` flag, or a "byte still unread"
level, as a new input port.

That is a worse design because it inverts the dependency. `uart_rx`'s job is to recover bytes from a
wire; it is a purely serial, purely synchronous module with no knowledge of buffering and no reason
to acquire any. Giving it a port that reports the state of a buffer it does not own couples it to the
register bank's internal storage, and means `uart_rx_tb` would have to model a FIFO in order to test
a receiver. The bank already holds both facts, one clock apart, in one module.

**The two physical causes.** *(1 mark)*

* **Overrun** - the wire is fine and the *software* is late. A host busy elsewhere, a poll loop that
  stalled, or simply a line faster than the loop can drain: at 115200 a byte arrives every 86.8 us,
  and a single five-byte SPI poll costs at least 40 us, so two transactions per byte is already most
  of the budget. It is a timing failure above the peripheral.
* **Framing error** - the *wire* is not fine. A baud mismatch large enough to move the stop-bit
  sample out of its bit, a break from a transmitter that lost power or a cable that came loose,
  noise or a reflection on a long unterminated run, or a level-shifting problem. It is an electrical
  or configuration failure below the peripheral.

One is caused by the reader, the other by the sender or the medium, which is exactly why they are
separate bits rather than one "something went wrong" flag.

### (d) 2 marks

**Two disagreements with `uart_regs_tb`.** *(1 mark each, any two of the following)*

1. **After reset.** The bench checks that `STATUS` immediately after reset shows **TX-ready and
   TX-idle set** with RX-valid and Error clear. A register updated only when `rx_push`, `tx_pop` or
   `frame_err` asserts has seen none of those, so unless its reset value is hand-written to `0b1001`
   it reads zero and the check fails - and a hand-written reset value is a second copy of the truth
   to keep in step with the FIFOs for ever.
2. **`RX_POP`.** Popping the RX FIFO empties it and must clear RX-valid, and the bench checks
   exactly that. But `RX_POP` is a **register write**, not one of the three events listed, so
   RX-valid stays set after the FIFO is empty. A driver would then poll, see RX-valid, read
   `RX_DATA` from an empty FIFO and pop it, for ever.
3. **`TX_DATA`.** A write pushes a byte and must clear TX-idle; a push is also not in the list, so
   the bench's "a `TX_DATA` write must clear TX-idle" check fails for the same reason.
4. **`tx_busy`.** It changes with no event at all - the transmitter simply enters and leaves a state
   - so TX-idle goes stale whenever the datapath moves without the bank being told.

**The rule.** Derive a status bit from **the state it reports**, never from the events that changed
that state. A register written by events is wrong whenever an event is missed, whenever two coincide,
whenever something changes without an event, and immediately after reset.

---

## Question 5 - Writing the contracts (12 marks)

### (a) 5 marks

```cpp
/**
 * @file Byte transport interface.
 */
#pragma once

#include <stdint.h>

namespace driver
{
namespace transport
{
/**
 * @brief Byte-level SPI transport interface.
 */
class Interface
{
public:
    /** @brief Destructor. */
    virtual ~Interface() noexcept = default;

    /** @brief Start a transaction by pulling SS low. */
    virtual void begin() noexcept = 0;

    /**
     * @brief Exchange a single byte in full duplex.
     *
     * @param[in] byte Byte to send.
     * @return The byte received at the same time.
     */
    virtual uint8_t transfer(uint8_t byte) noexcept = 0;

    /** @brief End the transaction by releasing SS. */
    virtual void end() noexcept = 0;
};
} // namespace transport
} // namespace driver
```

*(2 marks: 1 for the three pure virtuals with correct signatures, 1 for the **virtual**, `noexcept`,
`= default` destructor and the nested-block namespaces)*

```cpp
/**
 * @file UART driver interface.
 */
#pragma once

#include <stdint.h>

namespace driver
{
namespace uart
{
/**
 * @brief UART driver interface.
 */
class Interface
{
public:
    /** @brief Destructor. */
    virtual ~Interface() noexcept = default;

    /** @brief Configure the peripheral: set the baud divider and enable it. */
    virtual void configure(uint16_t baudDiv) noexcept = 0;

    /** @brief Send one byte. @return True if accepted, false if the TX FIFO was full. */
    virtual bool write(uint8_t byte) noexcept = 0;

    /** @brief Receive one byte. @return True if a byte was retrieved, false otherwise. */
    virtual bool read(uint8_t& byte) noexcept = 0;

    /** @brief Read the raw STATUS register. */
    virtual uint32_t status() const noexcept = 0;

    /** @brief Read the raw ERROR_FLAGS register. */
    virtual uint32_t errorFlags() const noexcept = 0;

    /** @brief Clear the error flags. */
    virtual void clearErrors() noexcept = 0;
};
} // namespace uart
} // namespace driver
```

*(3 marks: 1 for `configure`, `write` and `read` with the right parameter and return types - note
`read` takes a **reference** out-parameter and returns `bool`; 1 for the three status methods with
`status()` and `errorFlags()` **`const`** and `clearErrors()` not; 1 for `noexcept` throughout and
for the AVR-portable style - `<stdint.h>`, bare types, nested blocks, no `[[nodiscard]]`)*

Deduct for `std::uint8_t`, for `namespace driver::uart`, for `[[nodiscard]]`, for a non-virtual
destructor, and for `read` returning the byte instead of a `bool`.

### (b) 3 marks

```cpp
namespace reg
{
/** UART status register. */
constexpr uint8_t STATUS{0U};

/** UART control register. */
constexpr uint8_t CTRL{1U};

/** UART baud rate divider register. */
constexpr uint8_t BAUD_DIV{2U};

/** UART TX data register. */
constexpr uint8_t TX_DATA{3U};

/** UART RX data register. */
constexpr uint8_t RX_DATA{4U};

/** UART RX pop register. */
constexpr uint8_t RX_POP{5U};

/** UART error flag register. */
constexpr uint8_t ERROR_FLAGS{6U};
} // namespace reg

namespace status
{
/** Transmitter is ready for another byte. */
constexpr uint8_t TX_READY{0U};

/** An RX byte is available. */
constexpr uint8_t RX_VALID{1U};

/** UART is in an error state. */
constexpr uint8_t ERROR{2U};

/** Transmitter is idle. */
constexpr uint8_t TX_IDLE{3U};
} // namespace status
```

*(1 mark for the seven indices, 1 for the four status positions - both sets in the right order with
the right values)*

**Why plain `constexpr`.** *(1 mark, shared with the next point)* `inline` **variables** are a C++17
feature, and the AVR toolchain the course targets does not have them - it does not accept
`-std=c++17` at all. Plain `constexpr` compiles everywhere the course needs it to.

**What internal linkage costs here: nothing.** At namespace scope `constexpr` already implies
internal linkage, so each translation unit gets its own copy of a **compile-time** constant. That
copy is folded into the instruction stream at every use site and occupies no storage, so there is no
duplication to pay for and no one-definition-rule problem, because there is no object to define
twice.

**Positions rather than masks.** It keeps the C++ **identical to `uart_def.vhd`**, which stores
`natural` bit positions because that is what indexes a `std_logic_vector`, and identical to the
spec's own "bit N" wording. The two sides are then each checked against the specification rather than
against each other, which is the only arrangement in which a disagreement is findable. The mask is
formed at the use site:

```cpp
if (status & (1U << status::RX_VALID)) { /* a byte is waiting */ }
```

which is explicit about which bit is meant and cannot be mistaken for a value.

### (c) 2 marks

**What it is for, and who owns it.** *(1 mark)* `myStop` refers to a flag the **caller** owns - the
very flag the application's `run(const bool& stop)` is watching. The stub sets it `true` the moment
its scripted RX buffer is exhausted, so a single-threaded test can end an application loop that would
otherwise never return.

`read()` therefore does two things when the buffer runs out: it sets `myStop` to `true` and returns
`false`. Both matter - the `false` says "no byte this pass", the flag says "and there will not be
another".

**Why a stub should care at all.** Because the thing it doubles for is a **UART**, and a real UART
never runs out of input; it merely has none *yet*. There is no in-band way to say "that was all the
input there will ever be", so the double supplies an out-of-band one. It is the double being faithful
about the test's needs rather than about the hardware, which is exactly what a double is for.

**What the reference member forces.** *(1 mark)* A reference cannot be rebound after construction, so
copy assignment and move assignment have no sensible definition and are **deleted**; the copy and
move constructors are deleted with them, because a class that cannot be assigned but can be copied is
a trap. And the **default constructor** is deleted because a reference member must be bound at
construction - there is no way to build a `Stub` without a flag to point at. `Uart` and `EchoNode`
delete the same five for the same reason.

### (d) 2 marks

**The rule.** *(1 mark)* A test double must be faithful about **everything the code under test
depends on**, and may ignore everything else. It is a fixture, not a model of the hardware: fidelity
it is not asked for is fidelity nobody checks, and unchecked behaviour in a double is a liability the
day it disagrees with the real thing.

**Applied here.** The only application tested against `driver::uart::Stub` is `app::EchoNode`, which
drives the UART entirely through `read()` and `write()`. It never calls `status()`, `errorFlags()` or
`clearErrors()`. So returning `0` and doing nothing is not laziness - it is the correct amount of
fidelity, and inventing a status word would mean shipping behaviour with nothing to check it against.

**What would have to change.** *(1 mark)* The moment an application makes a **decision** from the
status word, the stub needs a scriptable one: a settable `uint32_t`, a helper such as
`setStatus(uint32_t)` and `setErrorFlags(uint32_t)`, and a `clearErrors()` that actually zeroes what
`errorFlags()` returns so that the clear-then-recheck path can be exercised.

Examples of such a thing: a node that stops or reports when `STATUS` bit 2 goes high; one that waits
for TX-idle before letting the MCU sleep; one that counts framing errors and resets the link after a
threshold. Each of those is a decision the current stub cannot script, and each is a good reason to
extend it - but only when it exists.

---

## Question 6 - Writing the protocol (13 marks)

### (a) 5 marks

```cpp
// -----------------------------------------------------------------------------
uint32_t Uart::readReg(const uint8_t addr) const noexcept
{
    constexpr uint8_t dummy{0x00U};
    constexpr uint32_t shift{8U};
    constexpr uint32_t size{static_cast<uint32_t>(sizeof(uint32_t))};
    constexpr uint32_t last{size - 1U};

    uint32_t value{};
    auto& transport = const_cast<transport::Interface&>(myTransport);

    transport.begin();
    transport.transfer(addr);              // bit 7 clear => read. Reply ignored.

    for (uint8_t i{}; i < size; ++i)
    {
        const auto idx = last - i;         // 3, 2, 1, 0 => most significant byte first
        const uint8_t response{transport.transfer(dummy)};
        value |= static_cast<uint32_t>(response) << (shift * idx);
    }
    transport.end();
    return value;
}

// -----------------------------------------------------------------------------
void Uart::writeReg(const uint8_t addr, const uint32_t value) noexcept
{
    constexpr uint8_t writeMask{0x80U};
    constexpr uint32_t shift{8U};
    constexpr uint32_t size{static_cast<uint32_t>(sizeof(uint32_t))};
    constexpr uint32_t last{size - 1U};

    myTransport.begin();
    myTransport.transfer(static_cast<uint8_t>(addr | writeMask));   // bit 7 set => write

    for (uint32_t i{}; i < size; ++i)
    {
        const auto idx = last - i;         // most significant byte first
        myTransport.transfer(static_cast<uint8_t>(value >> (shift * idx)));
    }
    myTransport.end();
}
```

*(4 marks: 1 for the command bytes - the raw index for a read, `index | 0x80` for a write; 1 for the
`begin()` / five transfers / `end()` framing in both; 1 for **most significant byte first** in the
read assembly; 1 for **most significant byte first** in the write split)*

Byte order is the part to be strict about. Reverse either loop and the same four bytes cross the wire
carrying a different 32-bit value, and neither the compiler nor a round trip through a
symmetrically-wrong stub will say a word.

**The replies.** `readReg` **discards** the reply to the command byte: the slave was shifting that
out before it knew which register was being asked for, so it is meaningless by construction.
`writeReg` discards **all four** of its replies as well - on a write the master has nothing to learn
from `MISO`, and the transfers happen only because SPI is duplex and a byte out costs a byte in.
*(half a mark)*

**What `const` buys.** *(half a mark)* It lets `status()` and `errorFlags()` - the two public methods
that are pure observations - be `const` too. Those are the two that depend on it. Without it, a
caller holding a `const Uart&` could not read the peripheral's status at all, which would be an odd
thing for a `const` handle to forbid.

### (b) 4 marks

```cpp
// -----------------------------------------------------------------------------
bool Uart::read(uint8_t& byte) noexcept
{
    const auto status  = readReg(reg::STATUS);
    const auto rxValid = static_cast<bool>(status & (1U << status::RX_VALID));

    if (rxValid)
    {
        constexpr uint32_t popCount{1U};
        byte = readReg(reg::RX_DATA);        // pure read: does not pop
        writeReg(reg::RX_POP, popCount);     // separate write: advances the FIFO
    }
    return rxValid;
}
```

*(1 mark: poll, then read, then pop, in that order, with nothing issued when `RX_VALID` is clear)*

**The recorded bytes.** *(1 mark)*

```text
transaction 1  STATUS read    : 00 00 00 00 00
transaction 2  RX_DATA read   : 04 00 00 00 00
transaction 3  RX_POP write   : 85 00 00 00 01
```

`beginCalls() == 3`, `endCalls() == 3`, and `txLen() == 15`.

**The scripting.** *(1 mark)*

```cpp
stub.injectRxByte(0x00U);                    // command-phase placeholder
stub.injectRxWord(1U << status::RX_VALID);   // STATUS = 0x00000002
stub.injectRxByte(0x00U);                    // command-phase placeholder
stub.injectRxWord(0x00000041U);              // RX_DATA = 0x41
```

**Ten bytes** in total, for **two** register values. *(1 mark)*

**The discrepancy.** The stub is a **byte pipe**: it returns the next queued byte on *every*
`transfer()` call, and a five-byte read transaction makes five of them. The reply the driver actually
uses is only four bytes long, because the reply to the command byte is discarded - but it is still
*consumed*. So each read costs one placeholder plus the four data bytes.

The third transaction needs nothing queued: it is a write, the driver ignores all five replies, and
the stub returns `0x00` once its buffer is exhausted anyway.

Getting this wrong is spectacular and confusing: queue only the four data bytes and every read is
shifted by one, so `readReg` assembles the top three bytes of the value together with the *next*
transaction's command reply, and the failure appears in a test two calls later. This is precisely why
the provided suite wraps it in a `scriptRead(stub, value)` helper rather than leaving it at each call
site.

### (c) 2 marks

```cpp
inline void writeBlocking(Interface& uart, const uint8_t byte) noexcept
{
    while (!uart.write(byte)) {}
}

inline void readBlocking(Interface& uart, uint8_t& data) noexcept
{
    while (!uart.read(data)) {}
}
```

*(1 mark for both, `inline` and `noexcept`, in the `driver::uart` namespace)*

**Why `inline`.** *(1 mark, shared)* They are **defined in a header**, so every translation unit that
includes it emits a definition. Without `inline` that is a one-definition-rule violation and a
duplicate-symbol error at link time the moment two files include the header.

**Why `Interface&` and not `Uart&`.** So they work over **any** implementation - the concrete `Uart`,
the L06 `driver::uart::Stub`, any future driver - dispatching virtually at run time. Taking the
concrete type would tie a convenience function to one implementation for no reason.

**Why free functions in a separate header.** They add **no state and no new contract**: they are a
spin loop over an operation the interface already provides. Putting them in the interface would
oblige every implementation, including every stub, to reimplement that loop, and would push the
decision to block *below* the seam - so a test could no longer opt out of it. The core stays
deterministic and testable, and the spinning lives where a caller chooses it.

### (d) 2 marks

**The call sequence.** *(1 mark)*

```text
status()  ->  readReg(STATUS)  ->  write(cmd)  ->  readReg(STATUS)  ->  write(cmd)  ->  ...
```

`Uart::write` polls `STATUS` before it sends anything, and `readReg` is what polls. So a `readReg`
implemented in terms of `write()` calls the very method that calls it, with **no base case**:
infinite mutual recursion, entered the first time anything reads a register - which is the first
line of `configure()`'s successor and every single `read()` and `write()` thereafter.

**What the ATmega328P exhibits.** *(1 mark)* Each level pushes a stack frame. The ATmega328P has
**2 KB of SRAM**, the stack grows down from the top of it toward the statically allocated data, and
there is no MMU, no stack guard, no exception and no fault handler. So the stack simply runs into
`.data`/`.bss` and starts overwriting live variables, then keeps going.

The symptom is not a clean crash: it is **memory corruption followed by a jump to a garbage address**,
which typically presents as a device that appears to reset in a loop the moment the driver is first
used, or that behaves erratically before it does. On the host the same bug is a segmentation fault,
which is the kinder outcome and the reason the host suite finds it first - one more argument for
building the driver on the host before it ever reaches a chip.

**The rule.** `transfer()` moves a **byte on the wire**; `write()` sends a **byte over the UART**.
They are two different layers that happen to have the same shape, and the private register core may
only ever touch `myTransport`.

---

## Question 7 - Writing the transport (11 marks)

### (a) 5 marks

```cpp
// -----------------------------------------------------------------------------
AvrSpi::AvrSpi() noexcept
{
    DDRB |= (1U << SCK) | (1U << MOSI) | (1U << SS);   // SCK, MOSI, SS out; MISO stays in.
    PORTB |= (1U << SS);                               // Idle the chip select high.
    SPCR = (1U << SPE) | (1U << MSTR) | (1U << SPR0);  // Enable, master, mode 0, MSB, f_osc/16.
}

// -----------------------------------------------------------------------------
AvrSpi::~AvrSpi() noexcept
{
    DDRB &= ~((1U << SCK) | (1U << MOSI) | (1U << SS));
    PORTB &= ~(1U << SS);
    SPCR = 0U;
}

// -----------------------------------------------------------------------------
void AvrSpi::begin() noexcept { PORTB &= ~(1U << SS); }

// -----------------------------------------------------------------------------
uint8_t AvrSpi::transfer(const uint8_t byte) noexcept
{
    SPDR = byte;
    while (0U == (SPSR & (1U << SPIF))) {}   // Spin until the transfer completes.
    return SPDR;                             // Now SPDR holds the received byte.
}

// -----------------------------------------------------------------------------
void AvrSpi::end() noexcept { PORTB |= (1U << SS); }
```

*(3 marks: 1 for the constructor's three statements with `SS` idled high and `MISO` untouched; 1 for
`begin()` low / `end()` high; 1 for `transfer()` with the `SPIF` spin between the write and the read)*

`SPR0` set with `SPR1` clear and `SPI2X` clear gives f_osc/16 = 1 MHz. `DORD`, `CPOL` and `CPHA` are
all clear, which is MSB-first, mode 0 - so the contract is met by bits that are *absent* as much as
by bits that are present.

**The destructor.** *(1 mark)* It must clear **exactly what the constructor set and nothing else**:

* the three `DDRB` direction bits for `SCK`, `MOSI` and `SS`, putting those pins back to inputs;
* the `SS` bit in `PORTB`, which was the chip-select drive;
* all of `SPCR`, written to `0`, which disables the peripheral.

It must **leave alone**: `MISO`, because the constructor never touched it - it is an input at reset
and stays one, and returning something you did not take is not RAII, it is trespass. Also `SPSR`,
which is status rather than configuration, and every other bit of `DDRB` and `PORTB`, which belong to
whatever else is using port B. The `&=` and `|=` forms are what confine the edits to those bits.

**Why `SPCR = ...` and not `SPCR |= ...`.** *(1 mark)* The plain assignment **guarantees** that every
bit the design relies on being clear is clear: `DORD`, `CPOL`, `CPHA`, `SPIE` and `SPR1`. With `|=`,
whatever was in `SPCR` beforehand survives - a bootloader, an Arduino core's `SPI.begin()`, or a
previous `AvrSpi` that was never destroyed could have left `DORD` set (LSB first) or `SPR1` set (a
different prescaler), and the transport would silently run at the wrong bit order or the wrong rate
with no line in the source to blame it on.

The general rule, worth stating: a register you **own** is *set*; a register you **share** is
*merged*. `SPCR` is entirely this class's, so it is assigned. `DDRB` and `PORTB` are shared with
every other pin on port B, so they are read-modify-written.

### (b) 3 marks

**The principle.** *(1 mark)* **RAII**: what the constructor acquires, the destructor releases. This
class acquires the SPI hardware and three port pins, and a defaulted destructor gives none of them
back. The `Interface` declares a **virtual** destructor precisely so that destroying an `AvrSpi`
through an `Interface&` runs the derived one; providing that mechanism and then making it do nothing
throws away the thing the base class went to the trouble of arranging.

**What is never given back.** PB5, PB3 and PB2 are left as **outputs** in `DDRB`; PB2 is left
**driven high** in `PORTB`; and `SPCR` still has `SPE` and `MSTR` set, so the peripheral is still
enabled and still owns those three pins.

**Concrete harm.** *(1 mark)* Any code that runs afterwards and wants PB2, PB3 or PB5 as a
general-purpose **input** finds them driven as outputs and reads its own drive rather than the world.
Any code that wants the SPI peripheral in a different configuration - as a slave, at a different
prescaler, LSB first - inherits a half-configured master rather than the reset state, and a transport
that uses `|=` on `SPCR` (see (a)) would inherit `MSTR` and never notice. And with `SPE` still set the
peripheral keeps driving `SCK` and `MOSI`, so anything else trying to use those pins fights the
hardware for them.

**Why "never destroyed" is unsafe here in particular.** *(1 mark)* Because this codebase builds its
objects as **automatic variables and injects them by reference**, and the **host test suite** does
exactly that: it constructs an `AvrSpi` inside a scope, exercises it over the mocked register file,
lets it go out of scope, and constructs another for the next case. With a do-nothing destructor the
peripheral it configured outlives it, so a defaulted destructor is observably wrong even on the host.
The suite defends itself today by calling `resetHardware()` at the top of every case; without that
defence the cases would become **order-dependent** and the configuration assertions could pass for
the wrong reason - the bits right because the last test set them, not because this constructor did.
The point is that a class should not need its tests to clean up after it.

### (c) 3 marks

**What sets each.** *(1 mark)*

* **`SCK`** is set by the SPI **prescaler**, a hardware divider off the CPU clock selected by
  `SPR1:SPR0` and `SPI2X`: f_osc/4, /16, /64, /128 and the doubled variants. It divides whatever the
  chip is *actually* running at, and no software constant takes part - which is exactly why `AvrSpi`
  needs no `F_CPU`.
* **The USART's baud** is set by **`UBRR0`, a number the software computes**: `UBRR0 = F_CPU / (16 *
  baud) - 1`. The compiler substitutes `F_CPU` at compile time, so the number is only right if the
  macro matches reality. The logging path needs `F_CPU` because it does arithmetic with it; the
  transport does not because it does none.

**At 8 MHz with `F_CPU` still 16000000.** *(2 marks)*

* **`SCK`** becomes `8 MHz / 16 = ` **500 kHz** instead of 1 MHz. The link **still works**: the FPGA
  synchronizes and edge-detects `sclk` into its own 50 MHz domain, so it keeps up with far more than
  1 MHz and there is no minimum rate. Everything is simply twice as slow - a five-byte transaction
  goes from 40 us to 80 us.
* **The USART** computes `UBRR0` for a 16 MHz clock while the hardware divides a real 8 MHz one, so
  the actual baud is **half** the intended: 57600 where 115200 was asked for. A terminal set to
  115200 sees framing errors and garbage, with the occasional plausible character by luck.

**Which you notice first, and why that is unfortunate.** The **terminal**, immediately and
unmistakably - garbage on a console is impossible to miss, while a `readReg` that takes 80 us instead
of 40 us looks exactly like one that takes 40 us unless you are measuring.

That is unfortunate because the loud symptom points at the **logging**, the one part of the system
that does not matter, and hides the fact that the SPI link is also running at half speed - which is
precisely what the L09 exercise asks you to measure against the 1 MHz budget. A candidate who
"fixes" it by halving the log baud has made the symptom go away and left the wrong clock in place,
and every timing figure they take afterwards is out by a factor of two. The fix is to `F_CPU` (and to
the fuses, if 16 MHz was what was wanted).

---

## Question 8 - The application, and the plan (12 marks)

### (a) 4 marks

```cpp
/**
 * @file Echo node implementation.
 */
#pragma once

#include "app/interface.hpp"

// clang-format off
namespace driver
{
/** UART driver interface. */
namespace uart { class Interface; }
} // namespace driver
// clang-format on

namespace app
{
/**
 * @brief Echo node implementation.
 *
 *        This class is non-copyable and non-movable.
 */
class EchoNode final : public Interface
{
public:
    /** @brief Constructor. @param[in] uart UART driver instance. */
    explicit EchoNode(driver::uart::Interface& uart) noexcept;

    /** @brief Destructor. */
    ~EchoNode() noexcept override = default;

    /** @brief Run application. @param[in] stop Set true to stop the application. */
    void run(const bool& stop) noexcept override;

    EchoNode()                           = delete;
    EchoNode(const EchoNode&)            = delete;
    EchoNode(EchoNode&&)                 = delete;
    EchoNode& operator=(const EchoNode&) = delete;
    EchoNode& operator=(EchoNode&&)      = delete;

private:
    /** UART driver instance. */
    driver::uart::Interface& myUart;
};
} // namespace app
```

```cpp
/**
 * @file Echo node implementation details.
 */
#include "app/echo_node.hpp"
#include "driver/uart/blocking.hpp"
#include "driver/uart/interface.hpp"

namespace app
{
// -----------------------------------------------------------------------------
EchoNode::EchoNode(driver::uart::Interface& uart) noexcept
    : myUart{uart}
{}

// -----------------------------------------------------------------------------
void EchoNode::run(const bool& stop) noexcept
{
    while (!stop)
    {
        uint8_t rxByte{};

        if (myUart.read(rxByte)) { driver::uart::writeBlocking(myUart, rxByte); }
    }
}
} // namespace app
```

*(3 marks: 1 for the reference member to the **interface** with the five deleted operations; 1 for
the `explicit`, `noexcept` constructor that does no I/O and the `override` on `run`; 1 for a loop
that re-checks `stop` every pass and echoes only on a successful `read`)*

**Why non-blocking read, blocking write.** *(1 mark)* A blocking read would spin inside
`Interface::read()` until a byte arrived and would never return to the top of the loop, so `stop`
would never be read again - the application could not be stopped by anybody, including its own test,
which would hang. Polling `read()` returns every pass, which is the only thing that gives the flag a
chance to be seen.

The echo write may block because the byte is **already in hand**: there is no decision left to make,
nothing else the loop could usefully do, and no deadlock available, since the TX FIFO is drained by
hardware whether software cooperates or not. Poll where you might have to give up; block where you
have already committed.

**Why a plain `bool` by `const` reference.** Freestanding avr-libc ships no `<atomic>`, so
`std::atomic<bool>` is not available - and on the single-core ATmega328P a byte read is already
indivisible, so it would not buy anything. It is passed **by reference** and re-read every pass so
that the owner can set it at any moment; a return value would only be examined when `run()` returned,
which is exactly what it will not do until the flag is set. And it is `const` because the application
only ever **reads** it: setting it is the caller's business.

### (b) 3 marks

**The test.** *(2 marks)*

It runs over the L06 **`driver::uart::Stub`** - the UART-level double, not the transport stub, since
`EchoNode` sits above the driver and knows nothing of SPI. Host test code may use full modern C++.

```cpp
bool stop{false};
driver::uart::Stub stub{stop};
app::EchoNode node{stub};

stub.injectRxByte(0x00U);
stub.injectRxByte(0x41U);
stub.injectRxByte(0xFFU);

node.run(stop);

EXPECT_EQ(stub.txLen(), 3U);
EXPECT_EQ(stub.txBuf()[0], 0x00U);
EXPECT_EQ(stub.txBuf()[1], 0x41U);
EXPECT_EQ(stub.txBuf()[2], 0xFFU);
```

* **What it queues:** the scripted RX bytes, `0x00`, `0x41` and `0xFF`. The two extremes are chosen
  deliberately - they are the values most likely to expose a truncation, a sign-extension or a
  "treat zero as no data" mistake.
* **How the loop terminates:** the stub sets `stop` to `true` when `read()` finds its RX buffer
  exhausted, and `run()` sees it on the next pass. That is also a **check on the implementation**:
  because termination depends on `run()` polling and re-checking, a `run()` that blocked in
  `readBlocking()` would hang the test rather than fail it - the test telling you the loop is not
  actually stoppable.
* **What it asserts:** the recorded TX length equals the number queued, and each recorded byte
  equals the queued byte at the same position - equality **in order**, because a UART is a byte
  stream and order is half the contract.

**The empty case.** *(1 mark)* Queue nothing, call `run(stop)`, and assert that it returns and that
`txLen()` is `0`.

It proves two things: that the loop's exit does **not** depend on having echoed anything, and that
the first thing the loop does before any I/O is test `stop` - so a caller who sets the flag before
`run()` is even entered gets an immediate return.

The implementation mistake it isolates is a `run()` that **ignores `read()`'s return value** and
echoes `rxByte` regardless. With input queued that bug is nearly invisible, since every read succeeds
and every echo is correct; with nothing queued it sends one spurious `0x00` where it should send
none. (A non-empty case can catch it too, but only if it asserts the exact `txLen()` rather than just
the first *n* bytes - which is a good argument for asserting the length as well as the contents.)

### (c) 3 marks

**The five rungs, and what each adds.** *(1 mark)*

| Rung | What it is | The one layer it adds |
|---|---|---|
| a | Data-plane **pin loopback**: the wrapper wires `rx` straight back to `tx`, bypassing `uart_top` | The USB-serial adapter, its 3.3 V levels, the terminal's baud and frame settings, the two data-plane wires and their crossover, and the FPGA pin assignment. **None of your logic.** |
| b | **The control plane**: write `BAUD_DIV` over SPI and read it back | The four SPI lines and the level shifter, `AvrSpi`, the provided `spi_slave` and `spi_reg_bridge`, and the register bank's write and read paths. |
| c | **Peripheral loopback**: `tx` tied to `rx` on the board | The whole datapath on real silicon at a real 50 MHz - `baud_gen`, `uart_tx`, `uart_rx`, both FIFOs and the TX feeder. |
| d | **The real data plane**: against the terminal | A **second device** with an **independently generated baud rate** that must now agree with the peripheral's own. |
| e | **`app::EchoNode`** | The application. |

**Why the order is forced.** *(1 mark)* **`BAUD_DIV`.** The peripheral cannot transmit or receive
anything until a divider has been written to it - `baud_gen` has no default and the guarded
conversion substitutes `1`, which is 3.125 Mbaud and useless. And the **only** route to `BAUD_DIV` is
an SPI transaction: it is not reachable from the data plane, not from a pin, not from a strap, not
from a reset value anybody can choose.

So the control plane must be proven before **any** rung that uses the peripheral. Any ladder that
puts a peripheral rung first is exercising two layers at once and calling it one, and its first
failure names both.

**Two reasons EchoNode-first is worse even when it succeeds.** *(1 mark)*

1. **A pass produces no record.** It tells you the whole stack works right now; it does not tell you
   which layers you may trust tomorrow. The next change - a re-synthesis, a different adapter, a
   wire moved, a new bench - puts you back to a single binary result with no cleared layers to fall
   back on. The ladder's product is not the final pass, it is the sequence of things each rung ruled
   out, and one end-to-end test produces none of them.
2. **It hides marginal failures.** The rungs are designed to stress *different* things: rung a
   exercises the levels and the terminal settings with none of your logic in the path, rung c
   removes the second baud source entirely, rung d puts it back. A stack that echoes correctly today
   may still be running with a 0.3 V `MISO` margin, an unshifted line that happens to work at this
   temperature, or a baud error that is inside tolerance now and outside it later. Each rung would
   have failed on exactly one of those; a passing end-to-end test reports none.

(The usual argument - that it is also worse when it *fails*, because nothing is localized - is
correct but was not what the question asked.)

### (d) 2 marks

**What is now impossible.** *(1 mark)* **Host-testing `EchoNode` without a transport.** A `Uart` can
only be constructed over a `driver::transport::Interface&`, so the test must build a
`driver::transport::Stub`, then a `Uart` over it, then script **every SPI transaction the echo
produces**: for each byte received, a `STATUS` read, an `RX_DATA` read and an `RX_POP` write; for
each byte echoed, a `STATUS` read and a `TX_DATA` write - five bytes each, and each read needing its
command-phase placeholder plus four data bytes queued. Testing three bytes of echo becomes scripting
about fifty bytes of SPI, and the test is then re-testing the register protocol rather than the echo
logic.

It is also impossible to run `EchoNode` over anything **else** - the L06 `driver::uart::Stub`, a
loopback double, a future driver variant, a driver over a different transport - because the type is
nailed down at compile time.

**What has to be built first:** the whole L08 test harness, one layer too low, before a single line
of application logic can be checked.

**The fix.** One word:

```cpp
driver::uart::Interface& myUart;
```

**The L06 decision it makes concrete.** *(1 mark)* That `driver::uart::Interface` is **abstract so
that the application codes against a promise rather than against a driver**. The interface exists for
exactly this: the application and its tests are written against the contract, so the same object runs
unchanged over the stub in a host test and over the real `Uart` on the bench, and arrives at the
bench already proven. Depending on the concrete class throws the abstraction away while still paying
for it - the vtable, the indirection and the extra header are all still there, buying nothing.

---
