--------------------------------------------------------------------------------
-- Testbench for fifo (L03).
--
-- Fills a depth-4 FIFO, checks full asserts and a further write is dropped, then drains it and
-- checks the bytes come back in order and empty asserts. Finally pushes and pops on the same edge
-- and checks the depth is unchanged.
--
-- Run, from hw/:
--       ghdl -a --std=93 uart_def.vhd fifo.vhd fifo_tb.vhd
--       ghdl -e --std=93 fifo_tb
--       ghdl -r --std=93 fifo_tb --assert-level=error
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

use work.uart_def.all;   -- to_hex, for the failure messages

entity fifo_tb is
end entity fifo_tb;

architecture sim of fifo_tb is
constant CLOCK_PERIOD_NS: time    := 20 ns;
constant CLOCK_EVENT_NS : time    := CLOCK_PERIOD_NS / 2;
constant DATA_WIDTH     : natural := 8;
constant FIFO_DEPTH     : natural := 4;

-- The four bytes pushed and drained, plus one extra offered while full.
constant B0     : std_logic_vector(7 downto 0) := x"11";
constant B1     : std_logic_vector(7 downto 0) := x"22";
constant B2     : std_logic_vector(7 downto 0) := x"33";
constant B3     : std_logic_vector(7 downto 0) := x"44";
constant DROPPED: std_logic_vector(7 downto 0) := x"99";

signal clock, reset_s2_n: std_logic := '0';
signal wdata            : std_logic_vector(7 downto 0) := (others => '0');
signal wr               : std_logic := '0';
signal rd               : std_logic := '0';
signal rdata            : std_logic_vector(7 downto 0);
signal empty            : std_logic;
signal full             : std_logic;
signal done             : boolean := false;
begin
    dut: entity work.fifo
        generic map(DATA_WIDTH, FIFO_DEPTH)
        port map(clock, reset_s2_n, wdata, wr, rd, rdata, empty, full);

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

    SIM_PROCESS: process is
        procedure push(b: std_logic_vector(7 downto 0)) is
        begin
            wdata <= b;
            wr    <= '1';
            wait until rising_edge(clock);
            wr    <= '0';
            wait until rising_edge(clock);
        end procedure;

        procedure pop is
        begin
            rd <= '1';
            wait until rising_edge(clock);
            rd <= '0';
            wait until rising_edge(clock);
        end procedure;

        -- Both strobes high for one cycle: a push and a pop at the same rising edge.
        procedure push_and_pop(b: std_logic_vector(7 downto 0)) is
        begin
            wdata <= b;
            wr    <= '1';
            rd    <= '1';
            wait until rising_edge(clock);
            wr    <= '0';
            rd    <= '0';
            wait until rising_edge(clock);
        end procedure;
    begin
        reset_s2_n <= '0';
        wait until rising_edge(clock);
        wait until rising_edge(clock);
        reset_s2_n <= '1';
        wait until rising_edge(clock);

        -- Case 1: just out of reset.
        -- Expect the FIFO empty and not full.
        assert empty = '1'
            report "fifo_tb: should be empty after reset!"
            severity error;
        assert full = '0'
            report "fifo_tb: should not be full after reset!"
            severity error;

        -- Case 2: push four bytes into the depth-4 FIFO.
        -- Expect full to assert.
        push(B0);
        push(B1);
        push(B2);
        push(B3);
        assert full = '1'
            report "fifo_tb: should be full after four pushes!"
            severity error;

        -- Case 3: offer a fifth byte while full.
        -- Expect it to be dropped, not overwrite, and full to stay asserted.
        push(DROPPED);
        assert full = '1'
            report "fifo_tb: still full after a dropped write!"
            severity error;

        -- Case 4: drain the FIFO.
        -- Expect the four bytes back in push order, then empty to assert.
        assert rdata = B0
            report "fifo_tb: front should be 0x11, got 0x" & to_hex(rdata) & "!"
            severity error;
        pop;
        assert rdata = B1
            report "fifo_tb: front should be 0x22, got 0x" & to_hex(rdata) & "!"
            severity error;
        pop;
        assert rdata = B2
            report "fifo_tb: front should be 0x33, got 0x" & to_hex(rdata) & "!"
            severity error;
        pop;
        assert rdata = B3
            report "fifo_tb: front should be 0x44, got 0x" & to_hex(rdata) & "!"
            severity error;
        pop;
        assert empty = '1'
            report "fifo_tb: should be empty after draining!"
            severity error;

        -- Case 5: with two entries queued, push and pop on the same rising edge.
        -- Expect one entry in and one out, so the depth is unchanged and the order still holds.
        push(B0);
        push(B1);
        push_and_pop(B2);
        assert empty = '0'
            report "fifo_tb: a push and a pop on one edge should leave the depth unchanged!"
            severity error;
        assert rdata = B1
            report "fifo_tb: front should be 0x22 after the push+pop, got 0x" & to_hex(rdata) & "!"
            severity error;
        pop;
        assert empty = '0'
            report "fifo_tb: the byte pushed alongside the pop should still be queued!"
            severity error;
        assert rdata = B2
            report "fifo_tb: front should be 0x33, got 0x" & to_hex(rdata) & "!"
            severity error;
        pop;
        assert empty = '1'
            report "fifo_tb: should be empty after draining the push+pop case!"
            severity error;

        report "fifo_tb passed!"
        severity note;
        done <= true;
        wait;
    end process;
end architecture sim;
