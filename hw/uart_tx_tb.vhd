--------------------------------------------------------------------------------
-- Testbench for uart_tx (L02).
--
-- Drives one byte, then samples tx at the centre of each bit and checks the 8N1 frame: a low
-- start bit, eight data bits LSB first, and a high stop bit.
--
-- Run, from hw/:
--       ghdl -a --std=93 uart_tx.vhd uart_tx_tb.vhd
--       ghdl -e --std=93 uart_tx_tb
--       ghdl -r --std=93 uart_tx_tb --assert-level=error
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity uart_tx_tb is
end entity uart_tx_tb;

architecture sim of uart_tx_tb is
constant CLOCK_PERIOD_NS: time    := 20 ns;
constant CLOCK_EVENT_NS : time    := CLOCK_PERIOD_NS / 2;
constant CLOCKS_PER_TICK: natural := 4;    -- one baud tick every four clocks
constant TICKS_PER_BIT  : natural := 16;   -- 16 ticks per bit
constant HALF_BIT_TICKS : natural := 8;    -- ticks from a bit edge to its centre

-- How long to wait for the start bit before giving up. A transmitter that never leaves idle
-- would otherwise hang the simulation with no message at all, so the wait below is bounded.
constant START_TIMEOUT  : time    := 2 * TICKS_PER_BIT * CLOCKS_PER_TICK * CLOCK_PERIOD_NS;

-- The byte under test. It must NOT be a bit-reversal palindrome, or the LSB-first check in Case 2
-- has no teeth: 0xA5, 0x3C and 0x5A all read the same backwards, so a transmitter packing its frame
-- most significant first would put exactly the same ten levels on the line and pass. 0x53 reversed
-- is 0xCA, so a reversed frame fails on data bit 0. Sixteen of the 256 bytes are palindromes; avoid
-- all of them here.
constant TXBYTE: std_logic_vector(7 downto 0) := x"53";

signal clock, reset_s2_n: std_logic := '0';
signal baud_tick, start : std_logic := '0';
signal data             : std_logic_vector(7 downto 0) := (others => '0');
signal tx, busy, done   : std_logic;
signal stop             : boolean := false;
begin
    dut: entity work.uart_tx
        port map(clock, reset_s2_n, baud_tick, start, data, tx, busy, done);

    CLOCK_PROCESS: process is
    begin
        if (stop) then
            wait;
        else
            clock <= '0';
            wait for CLOCK_EVENT_NS;
            clock <= '1';
            wait for CLOCK_EVENT_NS;
        end if;
    end process;

    -- One baud tick every four clocks: 16 ticks per bit, 64 clocks per bit.
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

    SIM_PROCESS: process is
        -- Wait for 'n' baud ticks.
        procedure wait_ticks(n: natural) is
        begin
            for k in 1 to n loop
                wait until rising_edge(clock) and baud_tick = '1';
            end loop;
        end procedure;
    begin
        reset_s2_n <= '0';
        wait until rising_edge(clock);
        wait until rising_edge(clock);
        reset_s2_n <= '1';

        -- The line must idle high before anything is sent.
        assert tx = '1'
            report "uart_tx_tb: tx must idle high before start!"
            severity error;

        -- Kick off one transmission of TXBYTE.
        data <= TXBYTE;
        wait until rising_edge(clock);
        start <= '1';
        wait until rising_edge(clock);
        start <= '0';

        -- Case 1: the start bit. Wait for the line to fall, then move to its centre.
        -- Expect tx low.
        wait until tx = '0' for START_TIMEOUT;
        assert tx = '0'
            report "uart_tx_tb: tx never went low after start!"
            severity error;
        wait_ticks(HALF_BIT_TICKS);
        assert tx = '0'
            report "uart_tx_tb: start bit was not low!"
            severity error;

        -- Case 2: the eight data bits, sampled a full bit apart.
        -- Expect each bit, LSB first, to equal TXBYTE(i).
        for i in 0 to 7 loop
            wait_ticks(TICKS_PER_BIT);
            assert tx = TXBYTE(i)
                report "uart_tx_tb: data bit " & natural'image(i) & " mismatch!"
                severity error;
        end loop;

        -- Case 3: the stop bit.
        -- Expect tx high.
        wait_ticks(TICKS_PER_BIT);
        assert tx = '1'
            report "uart_tx_tb: stop bit was not high!"
            severity error;

        report "uart_tx_tb passed!"
        severity note;
        stop <= true;
        wait;
    end process;
end architecture sim;
