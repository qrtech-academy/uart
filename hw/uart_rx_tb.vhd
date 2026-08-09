--------------------------------------------------------------------------------
-- Testbench for uart_rx (L03).
--
-- Drives framed bytes onto rx_s2, the already-synchronized line, and checks the receiver recovers
-- them: a clean byte arrives on data_out with valid and no error, and a byte with a low stop bit
-- raises frame_err and yields no valid byte. uart_top synchronizes the pin; uart_rx does not.
--
-- Run, from hw/:
--       ghdl -a --std=93 uart_def.vhd uart_rx.vhd uart_rx_tb.vhd
--       ghdl -e --std=93 uart_rx_tb
--       ghdl -r --std=93 uart_rx_tb --assert-level=error
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

use work.uart_def.all;   -- to_hex, for the failure messages

entity uart_rx_tb is
end entity uart_rx_tb;

architecture sim of uart_rx_tb is
constant CLOCK_PERIOD_NS: time    := 20 ns;
constant CLOCK_EVENT_NS : time    := CLOCK_PERIOD_NS / 2;
constant CLOCKS_PER_TICK: natural := 4;    -- one baud tick every four clocks
constant TICKS_PER_BIT  : natural := 16;   -- 16 ticks per bit
constant SETTLE_TICKS   : natural := 8;    -- idle held before a frame and between frames
constant POST_FRAME_TICKS: natural := 4;   -- settle after a frame before checking
constant BREAK_BITS      : natural := 12;  -- break held longer than one 10-bit frame
constant RECOVER_BITS    : natural := 14;  -- idle after it, long enough for a frame in flight

-- The bytes sent. Neither may be a bit-reversal palindrome, or Case 1 cannot pin down the
-- least-significant-first shift: 0xA5, 0x3C and 0x5A all read the same backwards, so a receiver
-- storing its data bits in the wrong order would deliver exactly the byte that was sent and pass.
-- 0x53 reversed is 0xCA and 0x2D reversed is 0xB4, so the order is genuinely checked.
constant BYTE_A: std_logic_vector(7 downto 0) := x"53";
constant BYTE_B: std_logic_vector(7 downto 0) := x"2D";

signal clock, reset_s2_n: std_logic := '0';
signal baud_tick        : std_logic := '0';
signal rx_s2            : std_logic := '1';   -- idle high (already synchronized)
signal data_out         : std_logic_vector(7 downto 0);
signal valid            : std_logic;
signal frame_err        : std_logic;
signal done             : boolean := false;

-- Captured by the monitor process below.
signal captured : std_logic_vector(7 downto 0) := (others => '0');
signal valid_cnt: natural := 0;
signal ferr_cnt : natural := 0;
begin
    dut: entity work.uart_rx
        port map(clock, reset_s2_n, baud_tick, rx_s2, data_out, valid, frame_err);

    CLOCK_PROCESS: process is
    begin
        if (done) then
            wait;
        else
            clock <= '0';
            wait for CLOCK_EVENT_NS;
            clock <= '1';
            wait for CLOCK_EVENT_NS;
        end if;
    end process;

    -- One baud tick every four clocks: 16 ticks per bit.
    TICKGEN_PROCESS: process(clock) is
        variable c: natural range 0 to CLOCKS_PER_TICK - 1 := 0;
    begin
        if (rising_edge(clock)) then
            if (c = CLOCKS_PER_TICK - 1) then
                c         := 0;
                baud_tick <= '1';
            else
                c         := c + 1;
                baud_tick <= '0';
            end if;
        end if;
    end process;

    -- Count valid/error pulses and latch the received byte, so the stimulus can check after the
    -- fact rather than racing the one-cycle pulses.
    MONITOR_PROCESS: process(clock) is
    begin
        if (rising_edge(clock)) then
            if (valid = '1') then
                captured  <= data_out;
                valid_cnt <= valid_cnt + 1;
            end if;
            if (frame_err = '1') then
                ferr_cnt <= ferr_cnt + 1;
            end if;
        end if;
    end process;

    SIM_PROCESS: process is
        -- Wait for 'n' baud ticks.
        procedure wait_ticks(n: natural) is
        begin
            for k in 1 to n loop
                wait until rising_edge(clock) and baud_tick = '1';
            end loop;
        end procedure;

        -- Drive one 8N1 frame: start bit, eight data bits LSB first, then a stop bit at
        -- 'stop_level'. Each bit is held for a full 16 ticks; the line returns to idle after.
        procedure send_frame(b: std_logic_vector(7 downto 0); stop_level: std_logic) is
        begin
            rx_s2 <= '0';
            wait_ticks(TICKS_PER_BIT);
            for i in 0 to 7 loop
                rx_s2 <= b(i);
                wait_ticks(TICKS_PER_BIT);
            end loop;
            rx_s2 <= stop_level;
            wait_ticks(TICKS_PER_BIT);
            rx_s2 <= '1';
        end procedure;

        -- Framing-error count captured before the break case, so that case measures its own effect.
        variable ferr_before: natural := 0;
    begin
        reset_s2_n <= '0';
        wait until rising_edge(clock);
        wait until rising_edge(clock);
        reset_s2_n <= '1';
        wait_ticks(SETTLE_TICKS);        -- settle, line idle high

        -- Case 1: send a clean byte (valid stop bit).
        -- Expect exactly one valid byte, equal to BYTE_A, with no frame error.
        send_frame(BYTE_A, '1');
        wait_ticks(POST_FRAME_TICKS);
        assert valid_cnt = 1
            report "uart_rx_tb: expected exactly one valid byte!"
            severity error;
        assert captured = BYTE_A
            report "uart_rx_tb: received byte mismatch, expected 0x" & to_hex(BYTE_A)
                 & ", got 0x" & to_hex(captured) & "!"
            severity error;
        assert ferr_cnt = 0
            report "uart_rx_tb: unexpected frame error!"
            severity error;

        wait_ticks(SETTLE_TICKS);        -- idle gap between frames

        -- Case 2: send a byte with a low (bad) stop bit.
        -- Expect frame_err to raise, and no new valid byte.
        send_frame(BYTE_B, '0');
        wait_ticks(POST_FRAME_TICKS);
        assert ferr_cnt = 1
            report "uart_rx_tb: expected a frame error!"
            severity error;
        assert valid_cnt = 1
            report "uart_rx_tb: frame error must not produce a valid byte!"
            severity error;

        wait_ticks(SETTLE_TICKS);        -- idle gap after the bad frame

        -- Case 3: a break. The line is held low far longer than a frame, which is what a
        -- transmitter losing power or a cable coming loose looks like, and then returns to idle.
        -- Expect no new valid byte, during the break or after it.
        --
        -- Frames the receiver thinks it sees inside the break all end on a low stop bit and are
        -- correctly rejected. The one that matters is the frame still in flight when the break
        -- *ends*: its stop bit is sampled after the line has recovered, so it looks well-formed,
        -- and a byte assembled out of nothing would be handed over as data.
        --
        -- This is the only case here that requires STATE_IDLE to leave on a falling edge on
        -- rx_s2 rather than on a low level. A level test re-arms the instant the previous frame
        -- is judged, so it marches through back-to-back all-zero frames for the whole break and
        -- produces exactly that spurious byte on recovery. Every other case in this file passes
        -- either way.
        -- Take the framing-error count from before the break, so this check measures what the
        -- break itself produced rather than the running total. Asserting on the total would make
        -- the case silently depend on the previous one having contributed exactly one.
        ferr_before := ferr_cnt;
        rx_s2 <= '0';
        wait_ticks(BREAK_BITS * TICKS_PER_BIT);
        rx_s2 <= '1';
        wait_ticks(RECOVER_BITS * TICKS_PER_BIT);
        assert valid_cnt = 1
            report "uart_rx_tb: a break produced a byte - leave STATE_IDLE on a falling edge on "
                 & "rx_s2, not on a low level!"
            severity error;
        assert ferr_cnt > ferr_before
            report "uart_rx_tb: a break should be reported as at least one framing error!"
            severity error;

        report "uart_rx_tb passed!"
        severity note;
        done <= true;
        wait;
    end process;
end architecture sim;
