# Paper A - Solutions

Marks are shown per part. Method carries them: a correct derivation with a slip in it is worth more
than a correct answer with no working, and later parts consume earlier ones, so an error should be
followed through rather than penalised twice. A candidate who decodes the register map wrongly in
Question 1 and then uses their own map consistently in Questions 4 and 6 loses the marks once.

Where a part asks for VHDL, mark the **hardware described**, not the syntax. Where it asks for C++,
mark the **byte order, the ordering of register accesses, and the qualifiers that carry meaning**,
not the punctuation.

Two questions - 2(d) and 4(d) - ask what a provided testbench *cannot* catch. An answer that treats
a passing bench as proof has missed the point of the question however correct the rest of it is, and
those parts are marked accordingly.

---

## Question 1 - The map, the top, and what a clean analysis does not prove (12 marks)

### (a) 3 marks

`0x0000000D` is `1101` in its low nibble.

| Bit | Constant | Position | Meaning | In `0x0D` |
|---|---|---|---|---|
| 0 | `ST_TX_READY` | 0 | TX FIFO not full | **set** |
| 1 | `ST_RX_VALID` | 1 | RX FIFO not empty | clear |
| 2 | `ST_ERROR` | 2 | one or more `ERROR_FLAGS` bits set | **set** |
| 3 | `ST_TX_IDLE` | 3 | TX FIFO empty **and** the line idle | **set** |

*(1 mark for all four names and positions, correctly read against the value)*

**The state.** The transmitter has nothing to send and nothing in flight - TX-idle implies TX-ready,
which is why both are set - no received byte is waiting, and at least one error has been latched
since the flags were last cleared. In this course's build that error can only be a framing error,
since `ER_FRAMING` is the only flag with a producer.

**What each call does.** *(1 mark)*

* `write(0x41)` reads `STATUS`, finds `TX_READY` set, writes `0x41` to `TX_DATA` and returns `true`.
  Two transactions, ten bytes.
* `read(byte)` reads `STATUS`, finds `RX_VALID` clear, and returns `false`. It performs **no**
  `RX_DATA` read and **no** `RX_POP` write - that omission is the contract, not an optimization, and
  it is what one of the host tests exists to check.

**`ERROR_FLAGS`.** Index **6**, offset **0x18** (the index is the offset divided by four). Command
byte to read it: **`0x06`**. To write it: **`0x86`**, bit 7 being the write bit.
*(1 mark)*

### (b) 3 marks

**`ghdl -a` accepts it.** Both ports are `in std_logic`, so swapping them produces a perfectly legal
entity: the analyzer checks that each formal has a type and a direction, and both still do. There is
nothing here for it to object to. *(1 mark)*

**Elaboration accepts it too.** `uart_top_tb` binds positionally, so it connects its own `sclk`
signal to the entity's third port and its `mosi` signal to the fourth. Names never enter into it.
Every type and direction matches, so elaboration succeeds - and the same is true inside `uart_top`,
where the architecture's positional `port map` into `spi_slave` now hands the SPI clock line to
`mosi` and the data line to `sclk`.

**Where it surfaces.** The first check anywhere in the course that fails is **`uart_top_tb`, at the
end of L04** - the first time the system testbench runs at all. Before that it is *skipped*, not
passed: its datapath blocks do not exist. So a wiring mistake made in L01 sits undetected for three
lectures and then arrives as an SPI transaction that produces nothing.
*(1 mark)*

**The change that would move it forward.** Bind by **name** rather than by position, in the bench
and in every instantiation. With named association the entity's port *order* stops mattering: both
the bench and `uart_top`'s architecture refer to `sclk` by name, so moving it from position three to
position four changes nothing and the transposition becomes a no-op instead of a bug.

The cost is the reason the course did not: named association is verbose, it lets the declared order
drift from the documented one, and it changes what "the contract" means. This course made the
**order and the types** the contract precisely so that a port table in an appendix is a complete
specification of a module - rename every signal and everything still binds. That is a real benefit,
and this failure is its real price. *(1 mark)*

Accept "give the ports distinct subtypes so a swap is a type error" as a second answer, with the
observation that it is impractical for a bus of `std_logic` pins.

### (c) 4 marks

#### (i) 2 marks

**The mechanism is driver resolution.** `std_logic` is a *resolved* type: a signal with more than one
driver takes the value its resolution function computes from all of them, bit by bit. The placeholder
is a concurrent assignment and therefore a driver; `uart_regs`' `reg_rdata` output is a second one.
Resolving `'1'` against `'0'` gives `'X'`; resolving `'0'` against `'0'` gives `'0'`.

For a read-back of `0x00000004`, the low four bits carry:

| Bit | Bank drives | Placeholder drives | Resolved |
|---|---|---|---|
| 3 | `'0'` | `'0'` | `'0'` |
| 2 | `'1'` | `'0'` | **`'X'`** |
| 1 | `'0'` | `'0'` | `'0'` |
| 0 | `'0'` | `'0'` | `'0'` |

*(1 mark)*

**What the bench reports.** The `'X'` propagates out through the bridge and `spi_slave` onto `MISO`
and into the bench's captured word, so `rd(15 downto 0) = x"0004"` is false and the BAUD_DIV
read-back assertion fires. The symptom generalizes: **every bit the bank drives `'1'` comes back
unknown**, so the value looks like the one you wrote with all its ones missing. That is the
signature to recognize, and the fix is to delete the L01 placeholder line, exactly as the L04
exercise instructs. *(1 mark)*

An answer that says "two drivers, so it fails" without naming resolution or without the per-bit
result gets one of the two marks.

#### (ii) 2 marks

**The value and the message.** `to_integer` on an all-`'U'` vector prints

```text
NUMERIC_STD.TO_INTEGER: metavalue detected, returning 0
```

and returns **0**. *(1 mark)*

**Why 0 is worse than wrong.** `baud_gen`'s `div` port is declared `natural range 1 to 65535`, so 0
is not a bad baud rate - it is **outside the port's subtype**, and binding it is a run-time bound
check failure that aborts the simulation. A wrong divider you could at least see on a waveform; this
one stops the run before there is a waveform. And the library chose the value, not the designer,
which is the deeper objection: a warning that silently substitutes a value has made a design
decision on your behalf.

**The guard.** *(1 mark)*

```vhdl
baud_div_int <= 1 when is_x(baud_div) or unsigned(baud_div) = 0
              else to_integer(unsigned(baud_div));
```

* `is_x(baud_div)` covers the **metavalue** case: before L04 nothing drives `baud_div`, so it sits
  at all-`'U'`.
* `unsigned(baud_div) = 0` covers the **legitimate zero** that arrives once `uart_regs` exists:
  `BAUD_DIV` holds whatever the bank reset it to until software writes a divider, and that reset
  value is a real, well-defined `0`.

`1` is chosen because it is the smallest value the port accepts. Nothing useful is transmitted at
either value, so the only thing that matters is that the design elaborates and runs. Worth a
comment rather than a mark: `or` on `BOOLEAN` is short-circuit in VHDL, so the comparison is never
evaluated on the all-`'U'` vector and the metavalue case stays warning-free as well as legal.

### (d) 2 marks

**The port is `sync`'s `reset_s2_n` *input*.** `sync` **consumes** the synchronized reset; a module
that requires a clean reset as an input cannot be the module that manufactures one. Try it and the
dependency is circular: `sync`'s own two flops would need `reset_s2_n` to start from a known state,
and `reset_s2_n` is the thing they were supposed to produce. *(1 mark)*

**What the pattern buys.** *(1 mark)*

* **Assert asynchronously.** The instant `reset_n` falls, every flop clears with no clock edge
  needed. That matters because the clock may not be running, or may be about to start, and a reset
  that requires a clock cannot rescue a design whose clock has not arrived.
* **Release synchronously.** The release is lined up with `clock` by `reset_sync`'s own two flops,
  so every flip flop in the design leaves reset on the same edge.

Released asynchronously, the rising edge of `reset_n` could land inside some flops' setup-and-hold
window and not others'. Those flops would leave reset one cycle later than the rest, so the design
starts **half-reset**: a state machine already in `STATE_IDLE` beside a tick counter that never
cleared, or a FIFO whose `head` reset while its `tail` did not. That is a state the design's own
logic never anticipates, and it happens at a rate that depends on where the button bounced.

---

## Question 2 - The wire, the divider, and the transmitter (13 marks)

### (a) 4 marks

`0x53` is `0101 0011`, so `data(7 downto 0) = "01010011"`.

**The frame.** Concatenation puts the leftmost item in the highest bits, so
`frame <= STOP_BIT & data & START_BIT` gives

```text
frame(9 downto 0) = '1' & "01010011" & '0' = "1010100110"
```

| index | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|---|---|
| value | 1 | 0 | 1 | 0 | 1 | 0 | 0 | 1 | 1 | 0 |
| is | stop | `data(7)` | `data(6)` | `data(5)` | `data(4)` | `data(3)` | `data(2)` | `data(1)` | `data(0)` | start |

*(1 mark)*

**The wire order.** `bit_idx` walks 0 upward, so the line carries `frame(0)` first:

| time order | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|---|
| `frame` index | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
| level | 0 | 1 | 1 | 0 | 0 | 1 | 0 | 1 | 0 | 1 |
| is | start | `data(0)` | `data(1)` | `data(2)` | `data(3)` | `data(4)` | `data(5)` | `data(6)` | `data(7)` | stop |

*(2 marks: 1 for the order, 1 for the levels)*

That is the whole point of building the frame as a vector: read it from index 0 upward and it *is*
the wire order, start bit first and data least significant first, so the transmitter never thinks
about bit order again.

**The timing.** Ten bits at sixteen ticks each is **160 `baud_tick`s**. At 115200 baud
`BAUD_DIV = 27`, so that is `160 x 27 =` **4320 clock cycles**, or 4320 x 20 ns = **86.4 us**.
*(1 mark)*

### (b) 3 marks

```text
exact divider = 50_000_000 / (16 x 57_600) = 50_000_000 / 921_600 = 54.2535
BAUD_DIV      = round(54.2535) = 54
```

*(1 mark)*

```text
tick rate  = 50_000_000 / 54 = 925_925.9 Hz
baud rate  = 925_925.9 / 16  = 57_870.4 baud
error      = (57_870.4 - 57_600) / 57_600 = +0.47%   (fast)
```

*(1 mark)*

**Why it is tolerated, and what has to be true.** *(1 mark)*

The receiver does not run free: it hunts for the falling edge of every start bit and restarts its
own tick counter there. So the error does not accumulate across a stream of bytes - only across the
ten bit periods of a single frame.

The condition is therefore specific: the **stop-bit sample must still land inside the stop bit**,
nine bit periods after the edge that started the frame. That is the last and worst-placed sample in
the frame, so it is the one that decides. Question 3 puts the budget at roughly plus or minus five
percent combined for an ideally centred sample; 0.47% at this end leaves the peer almost all of it.

An answer that says only "it resynchronizes each frame" earns half; the mark is for naming the stop
bit as the condition.

### (c) 3 marks

**When `tx` goes low.** `start` is looked at only in `STATE_IDLE`, and `tx <= '0'` is scheduled in
the same clocked process at the same rising edge, so `tx` is low from just after **the very edge on
which `start` was seen**. Nothing waits for a `baud_tick`. The start bit therefore begins on a
*clock* edge, at whatever phase `baud_gen`'s internal counter happens to be sitting.
*(1 mark)*

**How long the start bit lasts.** The bit ends on the sixteenth `baud_tick` after entry to
`STATE_SEND`: tick 1 finds `ticks = 0` and increments, ..., tick 15 finds `ticks = 14` and
increments to 15, tick 16 finds `ticks = 15`, satisfies `ticks >= MAX_TICKS - 1`, and advances
`bit_idx`.

The **first** of those sixteen ticks arrives between 1 and `div` clocks after entry, because the
divider's counter was already partway through a window. Every tick after it is exactly `div` clocks
apart. So, for `k` in `1 .. div`:

```text
start bit length = k + 15 x div  clocks
                 = 15 x div + 1   at shortest
                 = 16 x div       at longest
```

*(1 mark)*

A nominal bit is `16 x div` clocks, so the worst case is `div - 1` clocks short: just under one tick
period, that is just under **one sixteenth of a bit**.

**Why nothing else inherits it.** *(1 mark)*

`ticks` is cleared *on* the tick that ends the bit, and that tick is itself a tick boundary. So every
bit after the first begins on a tick and lasts exactly sixteen tick periods. The error is confined
to the start bit and does not accumulate down the frame.

And the receiver does not care: it triggers on the falling edge that opens the start bit and samples
the start bit half a bit later. A start bit up to one sixteenth short is still comfortably low at
its own midpoint, and every bit the receiver actually reads a value out of is full length.

### (d) 3 marks

**The two orderings.** `0xA5 = 1010 0101`, so `d7 = 1, d6 = 0, d5 = 1, d4 = 0, d3 = 0, d2 = 1,
d1 = 0, d0 = 1`.

| order | 1st | 2nd | 3rd | 4th | 5th | 6th | 7th | 8th |
|---|---|---|---|---|---|---|---|---|
| least significant first (`d0..d7`) | 1 | 0 | 1 | 0 | 0 | 1 | 0 | 1 |
| most significant first (`d7..d0`)  | 1 | 0 | 1 | 0 | 0 | 1 | 0 | 1 |

**They are identical.** A transmitter that packed its frame most significant first would put exactly
the same eight levels on the line, in exactly the same order, and `uart_tx_tb` would have passed.
*(1 mark)*

**The property.** `0xA5` is a **bit-reversal palindrome**: reverse its eight bits and you get `0xA5`
again. The constant chosen was one of the few bytes that cannot possibly distinguish the two
orderings.

**How many bytes share it.** A palindrome is determined entirely by its top four bits - `b7` fixes
`b0`, `b6` fixes `b1`, `b5` fixes `b2`, `b4` fixes `b3` - so there are `2^4 =` **16** of them out of
256. Pick a byte at random and you have a 15-in-16 chance of catching the bug; the earlier bench had
     picked one of the 16. *(1 mark)*

**The constant the bench uses today.** `0x53 = 0101 0011`, and its reverse is `0xCA`:

| order | 1st | 2nd | 3rd | 4th | 5th | 6th | 7th | 8th |
|---|---|---|---|---|---|---|---|---|
| least significant first (`d0..d7`) | 1 | 1 | 0 | 0 | 1 | 0 | 1 | 0 |
| most significant first (`d7..d0`)  | 0 | 1 | 0 | 1 | 0 | 0 | 1 | 1 |

They differ at the **first** data bit, so the bench fails immediately and reports **data bit 0**
mismatched. Any non-palindromic byte would do - `0x01`, `0x0F`, `0x48`, `0xB2` - and the mark is for
seeing that asymmetry is the property required, not for naming this particular byte.

**The lesson.** *(1 mark)*

A green bench proves the cases it contains, not the property you believed you were checking. The
check itself was always real - the levels must match `TXBYTE` bit for bit in the order expected -
but with a symmetric constant it had no power to distinguish an ordering at all, so a genuine check
had been quietly turned into a decoration by its own test data.

Worth saying out loud, because the same reasoning applies to the other benches: `uart_rx_tb` used
`0xA5` and `0x3C`, and `uart_top_tb` used `0x5A`. All three were palindromes, so at that revision
**no bench in `hw/` pinned down bit order at all**. All four constants are non-palindromic today.
One case survives even so: `uart_top_tb` loops `tx` back to `rx`, so a transmitter and a receiver
that are reversed **together** cancel exactly and pass whatever constant it sends. Only the two unit
benches can catch that pair, which is exactly why a system-level loopback is not a substitute for
them.

Full marks for reaching that conclusion by any route. A candidate who writes out the two orderings,
sees they match and says so has done the hard part.

---

## Question 3 - The asynchronous line (14 marks)

### (a) 3 marks

**What can happen.** `rx` is governed by another chip, so it can change at any instant relative to
`clock`, including inside a flip flop's **setup-and-hold window**. A flop clocked in that window can
go **metastable**: its output sits between the two logic levels for an unbounded time before
resolving, and resolves either way.

**What the failure actually is.** *(1 mark)* Sampling a signal mid-transition and getting either
level back is **not** the failure. Either answer is legitimate for a signal that genuinely was
changing, and one clock later you would have got the other one anyway. The failure is that for a
while the output is **not a level at all**. Two gates reading the same flop can resolve it
differently in the same cycle, so a state machine can take two branches at once and land in an
encoding that does not exist, and a counter can advance by something other than one. It is a
*late* answer, not a wrong one, and lateness is what breaks a synchronous design.

**Why two flops.** *(1 mark)* The first flop is the one exposed to the asynchronous edge and may go
metastable. The second gives it a **full clock period** to settle before anything downstream sees
it, and the probability of a metastable state surviving that long falls exponentially with the time
allowed - which is what the mean-time-between-failures expression describes. One flop gives it no
settling time whatever: whatever it is doing at the next edge is what the design consumes, so a
single register is not a synchronizer at all, however much it looks like one in simulation. Nothing
in a simulator is ever metastable, which is why `sync_tb`'s "exactly two edges" check exists.

**Where it lives.** *(1 mark)* `uart_top` instantiates `sync` on the `rx` pin. `uart_rx`
deliberately does **not** contain one: its input port is named **`rx_s2`**, and the `_s2` suffix is
the announcement - this signal has already been through a two-flop synchronizer, so treat it as an
ordinary synchronous input and sample it directly.

The principle is that the module which owns the pins owns the crossing. `uart_top` owns the pins, so
it owns the crossing; `uart_rx` is then a purely synchronous design, which is easier to reason about
and easier to test.

### (b) 3 marks

`0x53 = 0101 0011`, so `d0 = 1, d1 = 1, d2 = 0, d3 = 0, d4 = 1, d5 = 0, d6 = 1, d7 = 0`.

Sent least significant first, that is the arrival order, and `frame(bit_idx) <= rx_s2` with
`bit_idx` counting up stores each where it belongs:

| arrival | 1st | 2nd | 3rd | 4th | 5th | 6th | 7th | 8th |
|---|---|---|---|---|---|---|---|---|
| level | 1 | 1 | 0 | 0 | 1 | 0 | 1 | 0 |
| `bit_idx` | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |

*(1 mark)*

After the eighth, `frame(7 downto 0) = "01010011"`, and on a good stop bit that is what `data_out`
carries: **`0x53`**, the byte that was sent. *(1 mark)*

**Counting down.** With `bit_idx` walking 7 down to 0, the first-arriving bit lands in index 7 and
the last in index 0:

```text
frame = d0 d1 d2 d3 d4 d5 d6 d7 = 1 1 0 0 1 0 1 0 = "11001010" = 0xCA
```

The delivered byte is the **bit reversal** of the byte sent. Note that it is not garbage and not
noise: it is a well-formed byte, every frame arrives cleanly, `valid` pulses, no `frame_err` is
raised, and everything downstream works perfectly on data that is silently wrong.
*(1 mark)*

### (c) 5 marks

#### (i) 1 mark

The centre of bit *n* is 8 + 16*n* ticks after the true falling edge. Against that:

| Sample | Ticks after the true edge | Ideal | Past centre |
|---|---|---|---|
| start-bit re-check | 1 (notice) + 9 = 10 | 8 | **2 ticks** |
| first data bit | 10 + 17 = 27 | 24 | **3 ticks** |
| every later data bit | previous + 16 | +16 | **3 ticks** |
| stop bit | last data + 17 = 156 | 152 | **4 ticks** |

The offset is **fixed rather than accumulating** because data bit to data bit is exactly sixteen
ticks. The extra ticks are spent once at each *state change* - idle to start, start to data, data to
stop - not once per bit. So the phase error is paid twice in the whole frame and then held constant.

#### (ii) 2 marks

The stop bit is the tenth bit of an 8N1 frame, so `n = 9`.

```text
ideal sample tick   = 8 + 16 x 9 = 152
stop bit begins at  = 16 x 9     = 144
stop bit ends at    = 16 x 10    = 160
```

*(1 mark)*

Write `T_r` for the receiver's tick period and `T_t` for the transmitter's. The receiver samples 152
of *its own* ticks after the edge; the transmitter's bit boundaries are 144 and 160 of *its own*.
The sample stays inside the stop bit when

```text
144 x T_t  <  152 x T_r  <  160 x T_t

144/152  <  T_r / T_t  <  160/152
0.9474   <  T_r / T_t  <  1.0526
```

so the combined mismatch budget is **plus or minus 5.26%**, symmetric, about five percent either
way. *(1 mark)*

#### (iii) 2 marks

As built, the stop bit is sampled four ticks late, at **156**:

```text
144 x T_t  <  156 x T_r  <  160 x T_t

144/156  <  T_r / T_t  <  160/156
0.9231   <  T_r / T_t  <  1.0256
```

so **-7.69% / +2.56%**. *(1 mark)*

**Which side was eaten into.** `T_r / T_t > 1` means the receiver's ticks are *longer* than the
transmitter's - the receiver is slow, or equivalently **the transmitter is fast**. That limit falls
from 5.26% to 2.56%, a little under half. The other side gains: a transmitter running slow now has
7.69% instead of 5.26%, which is no use to anybody, because a real link is limited by its worst
direction.

**When it bites.** *(1 mark)* A peer that runs fast. This is not hypothetical: both ends round their
own integer divider, and this peripheral at 115200 with `BAUD_DIV = 27` is itself **+0.47% fast**. Two
ends that both round up eat the small budget from both sides at once, and it is the smaller budget
that is left. The margin is still ample for a well-configured link - the point is that the design
started with half the trailing margin the ideal tick-8 sample would have had, for three tick-sized
implementation details nobody chose deliberately.

Accept a candidate who works in "percent baud error" rather than tick-period ratios, provided the
asymmetry and the roughly-halved fast-side figure come out.

### (d) 3 marks

**The FIFO.** *(2 marks)*

```vhdl
    rdata <= entries(tail);
    empty <= empty_s;
    full  <= full_s;

    full_s  <= '1' when count = DEPTH else '0';
    empty_s <= '1' when count = 0 else '0';

    process(clock, reset_s2_n) is
    variable push, pop: std_logic;
    begin
        if (reset_s2_n = '0') then
            head  <= 0;
            tail  <= 0;
            count <= 0;
        elsif (rising_edge(clock)) then
            push := wr and (not full_s);
            pop  := rd and (not empty_s);
            if (push = '1') then
                entries(head) <= wdata;
                advance_ptr(head);
            end if;
            if (pop = '1') then
                advance_ptr(tail);
            end if;
            if ((push = '1') and (pop = '0')) then
                count <= count + 1;
            elsif ((push = '0') and (pop = '1')) then
                count <= count - 1;
            end if;
        end if;
    end process;
```

Four things carry the marks, and each is a place a plausible answer goes wrong:

* **The guards are folded into `push` and `pop` once**, as variables, rather than repeated at each
  use. Everything downstream then tests the *guarded* event, so a write to a full FIFO cannot move
  `head` and a read from an empty one cannot move `tail`.
* **`count` is adjusted only when the two disagree.** A simultaneous push and pop leaves it exactly
  where it was; incrementing in one branch and decrementing in another, unconditionally, is the
  classic bug here and it desynchronizes the flags from the contents within one cycle.
* **`rdata` is a concurrent assignment from `tail`, not something the process writes.** That is the
  look-then-advance contract L04 depends on: the front byte is visible with no `rd` at all, and `rd`
  only advances.
* **Both flags come from `count`**, not from comparing `head` with `tail` - which cannot tell full
  from empty in a ring buffer without a spare slot or an extra bit.

Accept a registered `rdata`, or `full`/`empty` derived from pointers plus a wrap bit, only if the
candidate says what they have paid for it. Accept `advance_ptr` written out inline.

**How many frames.** `DEPTH = 8`, so the RX path absorbs **eight** whole frames. The ninth
`valid` pulse arrives with `full_s` set, so `push` is `'0'` and the byte is **simply dropped** -
silently: no flag, no pulse, nothing on the wire. The line that decides it is
`push := wr and (not full_s)`. The FIFO's contract is to preserve order and keep its flags honest,
not to tell anybody it threw something away, which is why the caller must watch the flags.

**The reserved bit.** `ER_OVERRUN`, **`ERROR_FLAGS` bit 2**. In this course's build it always reads
`0`, because only `frame_err` has a producer - `ER_PARITY` (bit 1) is in the same position.

That is a **reservation, not an omission**: the positions are fixed in the spec, in `uart_def.vhd`
and in `register_map.hpp` (`error::OVERRUN = 2` on both sides), so an implementation that adds
overrun detection later drops straight in without renumbering anything or breaking a driver that was
already written against the map. A map that only defined the bits it currently implements would
force exactly that renumbering, and every existing driver with it.
*(1 mark)*

---

## Question 4 - Ports become registers (13 marks)

### (a) 3 marks

**The assignments.** *(1 mark)*

```vhdl
    status_reg(31 downto 4) <= (others => '0');
    status_reg(ST_TX_READY) <= not tx_full_s;
    status_reg(ST_RX_VALID) <= not rx_empty_s;
    status_reg(ST_ERROR)    <= is_error(err_flags);
    status_reg(ST_TX_IDLE)  <= tx_empty_s and (not tx_busy);
```

Five concurrent assignments, not a process: there is no state here to clock. Accept
`err_flags(0) or err_flags(1) or err_flags(2)` written out in place of a helper for `ST_ERROR`, and
accept any spelling of the FIFO flag signals, but **the bits must be indexed by their `uart_def`
names**, not by literals - that is the whole point of the package, and a candidate who writes
`status_reg(1)` has thrown away the protection the shared map exists to give. The reserved line is
worth having: without it bits 31-4 are undriven, and a read returns `'U'` in simulation rather than
the zeros Part 2 promises.

| Bit | Constant | Expression | Why it cannot be stored |
|---|---|---|---|
| 0 | `ST_TX_READY` | `not tx_full` | It is a property of the FIFO's own count, changing on every push *and* every pop; a stored copy is wrong the moment one update is missed. |
| 1 | `ST_RX_VALID` | `not rx_empty` | Same - and note it cannot be the receiver's `valid`, which is one clock wide and long gone before software polls. |
| 2 | `ST_ERROR` | OR of the `ERROR_FLAGS` latches | It is a *view* of other state, not a fact of its own; storing it means two places to keep in step. |
| 3 | `ST_TX_IDLE` | `tx_empty and (not tx_busy)` | It combines a FIFO flag with a datapath level, and no single writer knows both. |

*(1 mark for reasoning that generalizes)*

The general statement is worth the second mark on its own: each bit reports a **state**, while the
things that change that state are **pulses and edges**. A register written by events is a register
that is wrong whenever an event is missed, whenever two arrive together, and immediately after reset
unless its reset value is hand-maintained. Deriving the bit from the state it reports removes all
three failure modes by construction.

**The value.** TX FIFO holds 2 of 8, so `tx_full = '0'` and bit 0 is **1**. RX FIFO empty, so bit 1
is **0**. No error latched, so bit 2 is **0**. `tx_empty` is false (two bytes waiting) *and*
`tx_busy` is true, so bit 3 is **0**. Everything above bit 3 reads zero.

```text
STATUS = 0x00000001
```

*(1 mark)*

### (b) 4 marks

**The failing check.** `uart_regs_tb`'s "a bare `RX_DATA` read must **not** pop" case: it pushes a
byte, reads `RX_DATA`, and then checks that `STATUS`'s RX-valid is *still* set. With a popping read,
RX-valid clears on a plain read and the check fires. It is the check that pins the whole split down;
without it the two designs are indistinguishable. *(1 mark)*

**Why a read with a side effect is harder.** *(2 marks)*

The transport's abort rule says that if `SS` rises before the fifth byte the transaction is
abandoned with **no side effects**. Writes get that for free: `spi_reg_bridge` asserts `reg_write`
only when a write transaction completes, so a `reg_write` the bank sees is always a real commit -
which is precisely what lets `TX_DATA` and `RX_POP` be one-cycle actions with no state machine of
their own.

A read has no such strobe. `reg_rdata` is **combinational**: the bank presents a value for whatever
`reg_addr` currently carries, and the bridge latches it once at the end of the command byte and then
shifts it out. The bank therefore cannot distinguish a read that completed from one abandoned after
the address byte - and it cannot even tell how many times the same address was presented.

So the thing the bridge would have to tell the bank, and currently has no way to say, is **"this
read transaction completed"** - a read-side commit strobe, the mirror of `reg_write`. The bank would
then have to hold the pop pending until that strobe arrived and drop it on an abort. That is the
entire write-side machinery, duplicated, to make a read do something a separate write already does
for free. Splitting `RX_DATA` from `RX_POP` sidesteps the question rather than solving it, which is
why the appendix calls it the single most important idea in the module.

**The driver trace.** *(1 mark)* RX FIFO holds `0x41` then `0x42`.

| Call | `STATUS` poll | `RX_DATA` read | `RX_POP` write | Returns | FIFO after |
|---|---|---|---|---|---|
| 1 | RX-valid set | returns `0x41`, **and advances to `0x42`** | advances again, discarding `0x42` | `0x41`, `true` | empty |
| 2 | RX-valid clear | not issued | not issued | `false` | empty |

`0x42` was **popped without ever being read**. The FIFO advanced twice for one delivered byte, so
every second byte is lost - and lost invisibly, since nothing anywhere reports a discarded entry.
A bench that sends one byte at a time never sees it.

### (c) 3 marks

**`uart_regs_tb`.** It never writes `CTRL`, so the enable bit holds the bank's reset value, `0`. The
`TX_DATA` write is therefore swallowed, the TX FIFO stays empty, and the case that checks the FIFO
front reports "TX FIFO front should be 0x5A" with whatever it actually saw. The message names the
right register, so the cause is findable. *(1 mark)*

**`uart_top_tb`.** It never writes `CTRL` either. The byte never enters the TX FIFO, so nothing is
transmitted, nothing loops back, nothing arrives in the RX FIFO, and the bench polls `STATUS` for
RX-valid up to its poll limit and gives up.

That message is the **less useful** of the two because it is a timeout: it says the byte never came
back and nothing about why. It is equally consistent with a broken transmitter, a broken receiver, a
broken FIFO, a wrong `BAUD_DIV`, a missing feeder, or a bank waiting to be enabled. Exactly the
failure the appendix warns about: "a timeout that says nothing about the cause".
*(1 mark)*

**The fact that settles it.** `uart_regs` has **no `ctrl` output**. Read the port list: there is no
port by which `CT_ENABLE`, the parity select, the stop-bit select or either IRQ mask could reach
`uart_tx`, `uart_rx` or `baud_gen`. If no wire leaves the module carrying `CTRL`, then nothing in
this build may be gated on it, and the question is closed by the interface rather than by taste.
*(1 mark)*

**Why the bits exist anyway.** The register map is the **shared contract** with `register_map.hpp`
and with the protocol spec, and its positions are fixed so that an implementation which wires them
later stays compatible with both halves as already written. The driver's `configure()` writes the
enable bit for the same reason: the two sides agree on the wire, and the write simply has no effect
on the hardware yet.

### (d) 3 marks

**Why exactly one byte.** `busy` is a concurrent decode of the state:

```vhdl
busy <= '1' when state = STATE_SEND else '0';
```

so it is high in the same simulation cycle as the state change the load caused. The moment the
transmitter accepts the byte it is in `STATE_SEND`, `tx_busy` is high, and `tx_load` has already
gone low - one clock of `tx_load`, one `start` pulse, one `tx_pop`.

It stays low for the rest of the frame because `tx_busy` stays high for the rest of the frame; that
is what holds it. And it cannot be **zero** loads, because the instant the transmitter returns to
`STATE_IDLE` with a non-empty FIFO both terms are true again and the next byte goes.
*(1 mark)*

**The simplification.** They are right that `uart_tx` ignores `start` outside `STATE_IDLE`, so the
transmitter is safe. The bug is in the *other* line: `tx_pop` is the same signal.

With `tx_load <= not tx_empty`, `tx_load` is high **continuously** for as long as the FIFO has
anything in it. So the FIFO is popped **once per 50 MHz clock cycle**. A FIFO holding four bytes
empties in four consecutive clocks, about 80 ns, while the first byte's start bit is still on the
wire and has roughly 8.6 us left to run.

**One** of the four bytes reaches the wire. The other three survive about 60 ns and are discarded
unsent, with no flag and nothing to see. *(1 mark)*

**Does `uart_top_tb` catch it?** *(1 mark)* **No.** The bench writes exactly one byte to `TX_DATA`,
so the FIFO empties after a single pop either way and the two designs behave identically. It would
take a bench that queues two bytes to see the difference - which is the same lesson as Question 2(d)
in different clothes: a passing testbench proves the cases it contains.

Worth noting for a candidate who spots it: this is also why the feeder could not be written before
L04. `tx_empty` comes from the register bank and `tx_busy` from the transmitter, so it needs a block
from L02 and a block from L04 to exist at the same time.

---

## Question 5 - The driver's contracts (12 marks)

### (a) 4 marks

```cpp
if (status & (1U << status::RX_VALID)) { /* a byte is waiting */ }
```

```vhdl
if (status(ST_RX_VALID) = '1') then -- the same bit, indexed by position
```

*(1 mark for both)*

**`if (status & status::RX_VALID)`.** `status::RX_VALID` is `1`, so the mask is `0x1` - which is
**`TX_READY`'s** bit. The position has been used where a mask was meant, and it happens to be a
legal mask for the wrong bit.

Consequence: `read()` returns `true` whenever the transmitter has room, which after reset it always
does. It reads `RX_DATA` from an empty FIFO, so the bank hands back whatever the ring buffer holds
at `tail` - reset data or a stale entry - and the driver returns that byte to the caller as if it
had arrived on the wire. It then issues an `RX_POP` that the FIFO's `not empty` guard silently
drops. `app::EchoNode` over this driver emits a stream of garbage bytes at the speed of its poll
loop, having received nothing at all. *(1 mark)*

**`writeReg(reg::CTRL, ctrl::ENABLE);`.** `ctrl::ENABLE` is `0`, so this writes `0x00000000` to
`CTRL` - clearing the register rather than setting bit 0. The correct form is
`writeReg(reg::CTRL, 1U << ctrl::ENABLE)`.

Consequence, and this is the interesting part: **in this course's build, nothing happens.** `CTRL`
gates nothing, so the peripheral transmits and receives exactly as before and every test and every
bench passes. The bug is a time bomb: it becomes a peripheral that never enables on the first day
somebody wires `CT_ENABLE` to something real, in a driver that has looked correct for months.
*(1 mark)*

**A mask stored where the map stores a position.** `RX_VALID` is now `2`, so `1U << status::RX_VALID`
shifts by two and tests **bit 2**, the `ERROR` bit. `read()` returns `true` when an error is latched
and `false` otherwise, so it never delivers a byte and does deliver on a framing error.

Worse than the behaviour is where the bug lives: the two sides of the wire now **disagree about the
map**, since `uart_def.vhd` still has `ST_RX_VALID = 1`. Nothing on the host can find it, because
the host tests script the stub with values produced from this same header - the driver and its tests
are wrong together and agree perfectly. It is a bench-only bug, and "both sides store positions,
transcribed from the spec rather than from each other" is the rule that exists to prevent exactly
it. *(1 mark)*

### (b) 3 marks

**The three methods.** `begin()`, `transfer(uint8_t) -> uint8_t`, and `end()`. Select, exchange one
byte in full duplex, deselect - the framing of Part 3 of the spec and nothing more.
*(1 mark)*

**What it does not know.** It knows nothing about **registers** - no indices, no command byte, no
five-byte shape, no byte order - and nothing about the **UART** - no baud, no FIFOs, no status bits.
It is a dumb byte pipe.

**What the byte level buys.** *(1 mark)* All the protocol knowledge stays in one place, the driver,
so there is exactly one implementation of the transaction shape to get right and exactly one to
test. And the layer below becomes something a stub can imitate **perfectly**, because "return a byte
for a byte" has no behaviour to model - there is nothing for a fake to get subtly wrong.

A seam at `readReg`/`writeReg` would push the command byte and the byte order *below* the line. The
stub would then have to reimplement them, and a test asserting that the driver produced the right
transaction would really be asserting that the stub and the driver made the same mistake. The
byte-level seam is what makes the test meaningful, not merely possible.

**The two implementations, and what changes.** *(1 mark)* `driver::transport::Stub` (L06, host,
scripted) and `driver::transport::AvrSpi` (L07, target, real). What changes above the seam when they
swap: **nothing at all.** The register map, `Uart`, the blocking helpers and `EchoNode` are
recompiled, not rewritten - which is the entire return on the design work done in L05.

### (c) 3 marks

1. **`#include <cstdint>` and `std::uint8_t` / `std::uint32_t`.** The AVR target is *freestanding*
   and avr-libc ships **no C++ standard library at all**, so there is no `<cstdint>` and no `std`
   namespace to qualify anything with. Replace with `<stdint.h>` and the bare `uint8_t` /
   `uint32_t`.
2. **`namespace driver::uart { ... }`.** The compact nested-namespace definition is C++17, and the
   reference toolchain does not accept `-std=c++17` as an option at all. Replace with nested blocks:
   `namespace driver { namespace uart { ... } }`.
3. **`inline constexpr` at namespace scope.** `inline` *variables* are also C++17. Plain `constexpr`
   is the replacement and costs nothing: at namespace scope it already has internal linkage, so each
   translation unit gets its own compile-time copy of a constant that never occupies storage.
4. **`[[nodiscard]]`.** Rejected by that toolchain, so it is omitted from everything that has to
   cross-compile. The host-only test suites keep it, because they never build for the target.

The point in each case is that the toolchain is missing a **language level and a library**, not
merely being conservative. The reference is the AVR/GNU C++ compiler bundled with Microchip Studio,
several GCC releases behind a desktop g++, so "it compiled on my Linux avr-g++" is not evidence that
it will build for the target the course names.

*(2 marks: 1 for the four rejections, 1 for reasons that name the missing language level or library
rather than "it is old")*

**The corrected header.** *(1 mark)*

```cpp
#pragma once

#include <stdint.h>

namespace driver
{
namespace uart
{
constexpr uint8_t TxReady{0U};

class Interface
{
public:
    virtual ~Interface() noexcept = default;

    virtual uint32_t status() const noexcept = 0;
};
} // namespace uart
} // namespace driver
```

`#pragma once` is not in the original listing and is not one of the four defects, but a header
without an include guard is a defect of its own and the course's headers all carry it; award the
mark without it, and note it. `virtual` and `= 0` survive untouched, as do `noexcept`, `override`,
`final` and `= default` - the subset is narrower than modern C++, not a different language.

### (d) 2 marks

**What each `bool` means.** `write(byte)` returns `true` if the byte was accepted into the TX FIFO
and `false` if the FIFO was full, in which case **nothing was written** - the driver does not queue,
retry or buffer. `read(byte&)` returns `true` if a byte was placed in the out-parameter, and `false`
if none was waiting, in which case no `RX_DATA` read and no `RX_POP` were issued.
*(1 mark)*

**The bits behind them.** `STATUS` bit 0 `TX_READY` (`not tx_full`) makes the write answer possible;
bit 1 `RX_VALID` (`not rx_empty`) makes the read answer possible. The L04 mechanism behind both is
that `STATUS` is **computed from the FIFO flags**, so each is a level that stays true until the
condition changes - a pollable fact rather than an event that has to be caught.

**The blocking versions.** *(1 mark)* Free functions `writeBlocking` and `readBlocking` in
`driver/uart/blocking.hpp`, taking `Interface&` so they work over any implementation and dispatch to
the concrete driver at run time. They are free functions rather than methods because they add no
state and no new contract - putting them in the interface would oblige every implementation,
including every stub, to reimplement a one-line spin loop.

If the interface itself blocked, two things would be lost. Every operation would become
non-deterministic to test: a test would have to arrange for the stub to *eventually* succeed, and a
mistake would hang rather than fail. And an application could no longer poll - `EchoNode` could not
re-check its `stop` flag between reads, which is the exact property its test depends on.

---

## Question 6 - The five-byte transaction (13 marks)

### (a) 4 marks

**The command bytes.** *(1 mark)*

| Bytes | Bit 7 | Index | Register | Direction |
|---|---|---|---|---|
| `82 00 00 00 1B` | 1 | 2 | `BAUD_DIV` | write `0x0000001B` = 27 |
| `81 00 00 00 01` | 1 | 1 | `CTRL` | write `0x00000001` = `1U << ctrl::ENABLE` |
| `00 00 00 00 00` | 0 | 0 | `STATUS` | read, four dummy bytes |
| `04 00 00 00 00` | 0 | 4 | `RX_DATA` | read, four dummy bytes |
| `85 00 00 00 01` | 1 | 5 | `RX_POP` | write `1` |

**Which belong together.** *(1 mark)*

* Transactions 1 and 2 are one **`configure(27)`**: the baud divider first, the enable afterwards,
  in that order, because the peripheral should know its rate before it is switched on.
* Transactions 3, 4 and 5 are one successful **`read(byte)`**: poll `STATUS`, pure read of
  `RX_DATA`, separate `RX_POP` write. Three register accesses, in that order, which is the L04
  contract showing up on the other side of the wire.

**What the driver did with the returned bytes.** *(1 mark)* In both reads, the reply that came back
during the *command* byte is discarded - it is meaningless, since the slave does not yet know which
register is being asked for. The four bytes returned during the four dummy exchanges are assembled
**most significant byte first**: the first into bits 31-24, then 23-16, then 15-8, the last into
bits 7-0. In transaction 3 the driver then tested bit 1 (`RX_VALID`) of the assembled word; in
transaction 4 it kept the low byte and copied it into the caller's out-parameter.

**What the call counts prove.** *(1 mark)* They prove each transaction was **framed exactly once**,
and that the two counts being equal means every `SS` that fell also rose - five complete, balanced
transactions rather than one long one.

The byte log alone cannot distinguish this from a driver that called `begin()` once, pushed all
twenty-five bytes, and called `end()` at the very end. On a stub that is invisible: the same bytes
in the same order. On real hardware it is fatal - `spi_reg_bridge` would see `ss_active` assert
once, decode the first five bytes as one `BAUD_DIV` write, and treat the remaining twenty as a
continuation of a transaction that was already over, so nothing after the first would be decoded at
all. Framing is not visible in a list of MOSI bytes, so it has to be counted separately, which is
why the suite asserts on `beginCalls()` and `endCalls()` in eight different cases.

### (b) 3 marks

#### (i) 2 marks

**The bytes.** Least significant first, `configure(27)`'s first transaction puts

```text
82 1B 00 00 00
```

on the wire. *(1 mark)*

**What the peripheral commits.** The peripheral is not consulted about byte order - the spec says
the first data byte is bits 31-24. So it assembles `0x1B000000` and commits that to `BAUD_DIV`.

`BAUD_DIV` is bits 15-0, so `baud_div` carries `x"0000"`.

`uart_top`'s guarded conversion then hits its **second** case, `unsigned(baud_div) = 0`, and
substitutes `1`. `baud_gen` divides the 50 MHz clock by one, so it ticks every clock:

```text
tick rate = 50_000_000 Hz
baud rate = 50_000_000 / 16 = 3_125_000 baud
```

**3.125 Mbaud**, about 27 times the intended rate. The line runs, `tx` toggles, `uart_tx_tb` and
`uart_regs_tb` are unaffected because neither involves the driver - and nothing at the far end can
read a byte. *(1 mark)*

#### (ii) 1 mark

The peripheral shifts `0x0000000B` out most significant first, so the four bytes returned are
`00 00 00 0B`. Assembled least significant first, the first goes to bits 7-0 and the last to bits
31-24:

```text
driver holds 0x0B000000
```

`status & (1U << status::TX_READY)` is then `0`. `write()` returns `false` on every call for ever,
and `writeBlocking()` - a bare `while (!uart.write(byte)) {}` - spins for ever. The firmware hangs
on the first byte it tries to send, with the peripheral perfectly healthy and reporting itself
ready.

### (c) 3 marks

**No `RX_POP`.** *(1 mark)* `RX_DATA` is a pure read, so the front byte is never discarded. RX-valid
stays set, and every subsequent `read()` polls, finds it set, re-reads the same front byte and
hands it back. `app::EchoNode` echoes the **first character it ever receives**, over and over, as
fast as the poll loop runs - the terminal fills with a single repeated character and nothing typed
afterwards has any effect. It is a very recognizable bench symptom, which is a small mercy.

**Pop before read.** *(1 mark)* The front byte is discarded before it is looked at, so the `RX_DATA`
read returns whatever the FIFO shows *afterwards*: the next byte if one has already arrived, or
stale/empty-FIFO data if not. Every byte is either skipped outright or delivered one position late,
and the stream is silently corrupted rather than stalled - which is harder to diagnose than the
first mistake, not easier.

**The pop on empty.** *(1 mark)* The test is **"`read()`, on no data, must report failure and issue
no `RX_POP`"**. What the stray pop actually does to *this* peripheral: `fifo` guards `rd` on
`not empty`, so it is dropped and no queued byte is lost.

"Nothing bad happens" is not a defence, for three reasons:

* The guard is an implementation detail of `fifo`, **not a promise the register map makes**. The
  spec says `RX_POP` discards the front byte; it does not say what happens when there is not one.
* It costs a five-byte SPI transaction on every idle poll, which on a poll loop with an empty FIFO
  is most of the bus traffic and most of the latency.
* A driver that depends on an unspecified guard breaks against the first compliant peripheral that
  does not have one, and it will break on the bench rather than on the host.

### (d) 3 marks

**Why the three are not `const`.** `begin()`, `transfer()` and `end()` drive `SS` and shift real
bytes through real hardware. They are **actions with side effects**, not observations, and marking
them `const` would be a lie about what calling them does - to the reader first and to the optimizer
second. *(1 mark)*

**What the cast does, and why it is not needed here.** *(1 mark)*
`const_cast<transport::Interface&>(myTransport)` yields a non-`const` reference the three methods can
be called on - but it strips nothing, because the enclosing `const` never reached the transport.

The compiler would accept the calls **without** it as `Uart` is written today, because `myTransport`
is a **reference member**: `const` does not propagate through a reference, so inside a `const`
method `myTransport` still names a `transport::Interface&`. The cast is documentation of intent
rather than a requirement.

It becomes genuinely required the moment the transport is held differently - by value, or behind a
`const`-propagating handle - because then the object's `const` reaches the member and the calls stop
compiling. Writing it now means that change is a one-word edit rather than a redesign.

**The undefined case.** *(1 mark)* Casting away `const` is undefined behaviour when the object being
cast is **actually `const`** - declared `const`, or a temporary bound to a `const` reference - and is
then modified through the resulting reference. That is not what happens here: `myTransport` refers
to a real, non-`const` transport that the caller constructed and owns (a `Stub` on the host, an
`AvrSpi` on the target), so driving it is defined. The one hard rule is to cast away `const` only on
an object that is not genuinely `const`, and this obeys it.

---

## Question 7 - The real transport, and the real toolchain (11 marks)

### (a) 4 marks

**What each statement achieves.** *(1 mark)*

* `DDRB |= ...` makes `SCK` (PB5), `MOSI` (PB3) and `SS` (PB2) **outputs**.
* `PORTB |= (1U << SS)` idles the chip select **high**, that is deasserted, before any transaction.
* `SPCR = ...` enables the peripheral, selects master, and sets the prescaler.

**How `SPCR` delivers the contract, and the bits left clear.** *(2 marks)*

| Bit | State | What it gives |
|---|---|---|
| `SPE` | set | SPI peripheral enabled. |
| `MSTR` | set | Master. The ATmega generates `SCK`; the FPGA is the slave. |
| `SPR0` | set | With `SPR1` clear and `SPI2X` clear, the prescaler is 16: 16 MHz / 16 = **1 MHz**. |
| `DORD` | **clear** | **MSB first**, in every byte, as the protocol requires. |
| `CPOL` | **clear** | `SCK` **idles low**. |
| `CPHA` | **clear** | Sample on the **leading** edge. With `CPOL` clear that is the rising edge. |
| `SPIE` | **clear** | No SPI interrupt. The transport polls, which is why it needs neither `<avr/interrupt.h>` nor any ISR. |
| `SPR1` | **clear** | Half of the prescaler selection above. |

`CPOL = 0` together with `CPHA = 0` **is** SPI mode 0, which is what Part 3 of the spec asks for. So
all three requirements - mode, order and rate - are met by bits that are *not* set, which is exactly
why an answer that lists only the three bits present is incomplete.

**Why `MISO` appears nowhere.** *(half of the last mark)* It is an input at reset and must stay one,
so the constructor has nothing to do to it. The course's rule is that the constructor touches only
what it must, so that the destructor can put back exactly that and nothing else - `MISO` was never
taken, so it is never given back.

**Without the middle statement.** *(half of the last mark)* `PORTB` resets to zero, so the instant
`DDRB` makes PB2 an output the pin is actively driven **low**. The FPGA therefore sees `ss` asserted
from construction onward: `spi_slave` reports `ss_active` before any command byte, and
`spi_reg_bridge` begins counting a transaction from whatever byte happens to arrive first.
`begin()`'s further drive low is a no-op, `SS` never rises between transactions, and the bridge
never sees a transaction boundary - the first five bytes are decoded as one transaction and
everything after is treated as a continuation of it. Nothing works, and nothing in a MOSI byte log
looks wrong, which ties back to 6(a).

### (b) 3 marks

**What it returns.** The byte left in `SPDR` from the **previous** exchange. The receive buffer still
holds the last completed transfer's result, because the transfer just started has not shifted a
single bit yet - the write to `SPDR` starts the shift, it does not perform it.
*(1 mark)*

**How long it takes.** Eight `SCK` periods, one per bit. At 1 MHz that is **8 us**, which at
16 MHz is about **128 ATmega instruction cycles** - an eternity in instructions, and the reason the
omission is both easy to make and impossible to get away with.
*(1 mark)*

**What the spin waits on, and the side effect.** The spin waits on **`SPIF`** in `SPSR`:

```cpp
SPDR = byte;
while (0U == (SPSR & (1U << SPIF))) {}
return SPDR;
```

Reading `SPSR` while `SPIF` is set and *then* reading `SPDR` **clears `SPIF`**, arming the next
transfer. That is not incidental: without it the flag would still be set at the top of the next
`transfer()` and the spin would fall straight through, so the correct code owes its correctness to
the clearing sequence as much as to the wait.

**What the driver sees.** *(1 mark)* Every returned byte is one exchange stale. The reply to the
command byte is discarded anyway, so `readReg` assembles the byte that belonged to the command
exchange together with the first three data exchanges - a `STATUS` word built from the tail of the
previous transaction and the head of this one. The driver reads values the peripheral never
presented, and the poll loops behave differently depending on what was read last, which is the worst
kind of bug to meet first on a bench.

### (c) 2 marks

**What the hardware does.** It clears **`MSTR`** in `SPCR` and sets `SPIF`. The ATmega demotes itself
to a **slave** on the spot, stops driving `SCK`, and abandons the transfer in flight. This is why
`SS`/PB2 must be an output in master mode even when something else is being used as the chip select
- and here PB2 *is* the chip select, so driving it is the transport's job anyway. *(1 mark)*

**What the spin does, and the symptom.** *(1 mark)* The spin ends **immediately**, because the
demotion set `SPIF`, and `transfer()` returns a byte that was never clocked in. So the failure does
not hang - it succeeds, wrongly, which is worse.

From then on: `SCK` stops moving on the analyzer, every `readReg` returns a constant (typically all
ones or all zeros, depending on the idle level of `MISO`), `write()` and `read()` disagree with the
peripheral for ever, and nothing recovers - the transport configured `SPCR` once in its constructor
and never revisits it, so `MSTR` stays clear until the chip is reset.

### (d) 2 marks

**Two host constructs that do not survive.** *(1 mark)* Any two of:

* **Anything from the standard library, `std::cout` above all.** There are no iostreams, so debug
  output goes out the ATmega's **own** hardware USART: set `UBRR0` from `F_CPU` and the target baud,
  enable the transmitter in `UCSR0B`, then poll `UCSR0A & (1U << UDRE0)` and write `UDR0`. (Not to
  be confused with the FPGA peripheral this course builds.)
* **Dynamic allocation**, `new` or `std::make_unique`. There is no `operator new`, so everything is
  static or automatic storage - which is why every seam in this course is a reference injected into
  an object living in `main`'s frame.
* **Exceptions and RTTI.** No `throw`, no `dynamic_cast`, no `typeid`; errors become return values,
  which is what `write()` returning `false` on a full FIFO already is.

**`env.cpp`.** *(1 mark)*

```cpp
void operator delete(void*) noexcept {}
void operator delete(void*, unsigned int) noexcept {}

extern "C" void __cxa_pure_virtual() {}

extern "C" int  __cxa_guard_acquire(volatile void* g) { return !*(char*)g; }
extern "C" void __cxa_guard_release(volatile void* g) { *(char*)g = 1; }
extern "C" void __cxa_guard_abort(volatile void*) {}
```

What emits each reference:

* **`operator delete`** - a class with a **virtual destructor** names the deleting `operator delete`
  in its vtable, even though this code never deletes through a base pointer. Every `Interface` in
  the course has one. **Both** forms are needed: from C++14 the compiler calls the sized form but
  requires the unsized one to exist beside it, and only the unsized one is emitted under
  `-fno-sized-deallocation`. On AVR `size_t` is `unsigned int`, so that is the second parameter's
  type; `std::size_t` is not available to name it.
* **`__cxa_pure_virtual`** - named by every **abstract class's** vtable, so `driver::uart::Interface`
  alone is enough to require it. It is called only if a pure virtual is somehow invoked, so an empty
  body is honest: there is nothing useful to do and nowhere to report it.
* **`__cxa_guard_acquire` / `_release` / `_abort`** - the guard around a **function-local
  `static`**'s one-time initialization. Single-threaded definitions are all a bare-metal target
  needs.

The `extern "C"` on the three `__cxa_*` groups is not decoration: the compiler emits calls to them
by their C names, and C++ mangling would leave the linker with unresolved symbols. `operator delete`
is a C++ operator and must **not** be `extern "C"`. A candidate who writes empty bodies but mangles
the names has not linked anything.

Accept a subset with a note if the candidate says which construct in *their* design each is for; the
mark is for knowing that these are compiler-emitted references with no library behind them, not for
reciting all six.

**Why it lives in `avr/`.** So that the **host** link keeps libstdc++'s versions. Replacing the
host's thread-safe static guards and its `operator delete` with these single-threaded, hand-written
ones would change the behaviour of the build the tests actually run on, for no benefit whatever. The
file exists to satisfy a linker that has no C++ runtime, and the host has one.

---

## Question 8 - The bench (12 marks)

### (a) 4 marks

*(2 marks for the order and completeness of the chain, 1 for the lectures and planes, 1 for the
representations)*

| # | Module | Built in | Plane |
|---|---|---|---|
| 1 | USB-serial adapter to the DE0-CV `rx` pin | provided hardware | data |
| 2 | `sync` on the `rx` pin | L03 | data |
| 3 | `uart_rx` | L03 | data |
| 4 | the RX `fifo` | L03, instantiated L04 | data |
| 5 | `uart_regs` | L04 | the boundary between the two |
| 6 | `spi_reg_bridge`, then `spi_slave` | provided | control |
| 7 | `AvrSpi` | L07 | control |
| 8 | `Uart::readReg`, then `Uart::read` | L06 | control |
| 9 | `app::EchoNode::run` | L08 | neither - it is the application |
| 10 | `Uart::write`, then `Uart::writeReg` | L06 | control |
| 11 | `AvrSpi`, then `spi_slave` and `spi_reg_bridge` | L07 / provided | control |
| 12 | `uart_regs` and the TX `fifo` | L04 / L03 | the boundary again |
| 13 | the TX feeder in `uart_top` | L04 | data |
| 14 | `uart_tx` | L02 | data |
| 15 | the DE0-CV `tx` pin, adapter, terminal | provided hardware | data |

`baud_gen` (L02) paces both 3 and 14 and is on the data plane throughout; `reset_sync` (provided) is
on neither and is in every clock domain. `uart_top` (L01) is the file that holds all of it together
and is not itself a step.

**The three representations.**

1. A **UART frame on the wire**: a low start bit, eight bits least significant first, a high stop
   bit, timed by the baud rate.
2. A **register field over SPI**: the low eight bits of a 32-bit word, carried most significant byte
   first inside a five-byte transaction.
3. A **`uint8_t`** in the driver and the application.

It changes at **`uart_regs`**, where a frame that has become a FIFO entry becomes a register field,
and again at **`Uart::readReg`**, where four SPI bytes become a `uint32_t` and then a `uint8_t`. On
the way out it changes back at the same two places, in the reverse order. Naming those two places is
the point of the exercise: everything else on the list is transport.

### (b) 3 marks

**What the ladder has cleared.** *(1 mark)*

* **Rung a**, data-plane pin loopback: the USB-serial adapter, its 3.3 V logic levels, the
  terminal's baud and frame settings, the two data-plane wires and their crossover, and the FPGA pin
  assignment. None of the candidate's logic is in that path, which is what makes it a clean result.
* **Rung b**, the control plane: the level shifter on all four SPI lines, `AvrSpi`'s configuration,
  `spi_slave` and `spi_reg_bridge`, and the bank's write and read paths - proven by a `BAUD_DIV`
  write and read-back.
* **Rung c**, peripheral loopback: the whole datapath on real silicon at a real 50 MHz - `baud_gen`,
  `uart_tx`, `uart_rx`, both FIFOs, the TX feeder and the register bank.

**What is left.** The peripheral talking to a **different device**, with a **second, independently
generated baud rate** that now has to agree with the peripheral's own. Rung d is the first rung at
which any absolute timing requirement exists at all.

**The likely cause, and why rung c hides it.** *(1 mark)* A **baud mismatch**. In loopback the
transmitter and receiver are driven by the *same* `baud_gen`, from the *same* 50 MHz clock, with the
*same* `BAUD_DIV`. Any divider whatsoever passes rung c - including a wildly wrong one - because both
ends are wrong by exactly the same amount and the frame is still sixteen ticks per bit at both ends.
Rung d is the first time the number has to be right in absolute terms.

The two symptoms together point the same way: corruption in both directions is a *timing*
disagreement. A broken, uncrossed or floating data-plane wire gives silence, not wrong characters.

**The arithmetic.** *(1 mark)*

```text
tick rate = 50_000_000 / 27      = 1_851_851.9 Hz
baud      = 1_851_851.9 / 16     = 115_740.7
error     = (115_740.7 - 115_200) / 115_200 = +0.47%
```

Question 3 puts this receiver's combined tolerance at roughly **+2.5% / -7.7%**, so 0.47% is nowhere
near the edge and `BAUD_DIV = 27` is **exonerated**. To blame the divider you would need a
percent-scale error: a terminal set to 57600 or 9600 rather than 115200; a `BAUD_DIV` of **26**,
which gives 120 192 baud, +4.3% against the terminal's 115 200 and so outside the +2.5% fast-side
limit outright; or a board clock that is not actually 50 MHz, which would move both halves of the
peripheral together and so would also have been invisible at rung c. Note that `BAUD_DIV = 28` is
*not* on that list: 111 607 baud is -3.1%, comfortably inside the -7.7% slow side, so it would only
bite if the terminal were also slow. Those are the places to look, in that order.

### (c) 3 marks

**The `main`.** *(2 marks)*

```cpp
/**
 * @brief Application entry point for the ATmega328P.
 */
#include <stdint.h>

#include "app/echo_node.hpp"
#include "driver/transport/avr_spi.hpp"
#include "driver/uart/uart.hpp"

int main()
{
    constexpr uint16_t baudDiv{27U};

    driver::transport::AvrSpi transport{};
    driver::uart::Uart        uart{transport};
    uart.configure(baudDiv);

    app::EchoNode node{uart};

    const bool stop{false};
    node.run(stop);

    return 0;
}
```

The marks are in the **order and the ownership**, not the punctuation:

* **Bottom-up construction.** Each layer is built before the one that references it, and each is
  handed up by reference: transport into `Uart`, `Uart` into `EchoNode`. A candidate who constructs
  `EchoNode` first has nothing to give it.
* **`configure()` before `run()`**, and `27` for 115200 - the one number on this page that comes
  from Part 1's formula rather than from a header. Configure after starting the loop and the first
  bytes go out at whatever the reset divider produces.
* **Nothing is allocated.** Three plain locals in `main`'s frame, living until the program ends,
  which on this target is never. This is the freestanding constraint paying off rather than biting:
  the design was reference-injected from L05, so the target needs no `operator new` and none is
  available. A candidate reaching for `new` here has not understood what L07 removed.
* **`main` is the only file that names concrete types.** `EchoNode` sees an interface, `Uart` sees an
  interface; swapping the transport for the L06 stub is an edit to these three lines and nothing
  else.

`return 0` is unreachable and that is fine - `run()` never returns with `stop` held `false`. Accept
an infinite loop after `run()` instead, or `for(;;)` in place of the return; do not accept a `main`
that falls off the end into avr-libc's exit path with the peripheral still live.

**Why the flag is `false` here.** *(1 mark)* On the bench there is nobody to stop it: the node should
echo for as long as the board has power, so `stop` is a `const bool` that is never written and
`run()` is an infinite loop by construction. In the host test the very same parameter is what *ends*
the run - the L05 UART stub sets the caller's flag `true` the moment its scripted RX buffer runs out.
One `bool&`, read every pass, serves both: production runs forever because nothing sets it, and the
test terminates because something does. That is why it is a reference rather than a return value or
a one-time check.

**Why not `readBlocking()`.** It would spin inside `Interface::read()` until a byte
arrived, and would therefore never return to the top of the loop - so `stop` would never be read
again. The application could not be stopped by anybody, including its own test.

That connects directly to how the host test ends: the L05 UART stub sets the caller's `stop` flag
`true` the moment its scripted RX buffer runs out, and `run()` sees it on the **next pass**. With a
blocking read there is no next pass; the test hangs instead of finishing, which is the test telling
you the loop is not actually stoppable.

Worth crediting if a candidate volunteers it: the *write* is allowed to block, and the asymmetry is
deliberate. The byte is already in hand, there is nothing else the loop could usefully do with it,
and waiting cannot deadlock because the TX FIFO is drained by hardware whether software cooperates
or not. Poll where you might have to give up; block where you have already committed.

### (d) 2 marks

**Symptom and risk.** *(1 mark)* The FPGA input is being driven above its own 3.3 V supply. At best
the pin misbehaves and the control plane is unreliable - a `BAUD_DIV` write that reads back wrong, or
intermittently right, which is the worse of the two because it looks like a software problem. At
worst the pin's protection diode conducts into the 3.3 V rail and the pin, or the I/O bank, is
damaged. This is the one genuine electrical hazard on the bench, which is why the wiring is checked
before power is applied.

**The first rung that exposes it.** **Rung b**, the control plane. Rung a cannot: the data-plane pin
loopback has no SPI in it at all, running entirely between the adapter and the FPGA, both at 3.3 V,
with the shifter not in the circuit. That is precisely the property that makes **rung a** a useful
rung - it clears the things it clears and nothing else.

**The safe line.** *(1 mark)* **`MISO`**. It is the only one of the four that travels FPGA to Nano,
3.3 V *up* to 5 V, so nothing over-drives a 3.3 V input. It usually works unshifted because the
ATmega's input-high threshold at Vcc = 5 V is 0.6 x Vcc = 3.0 V, and 3.3 V clears it.

What can still go wrong: the margin is **0.3 V**. A loaded or slow edge, a long breadboard wire, a
supply that has sagged under the FPGA's draw, or a warm room can drop a `1` below the threshold -
producing an intermittent, wiring-and-temperature-dependent read failure. That is considerably worse
to debug than a line that never works at all, and it is why "it mostly works" is not an acceptable
state for this line either.

---
