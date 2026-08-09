--------------------------------------------------------------------------------
-- Testbench for sync (L03).
--
-- Two instances are driven at once, one at the default COUNT and one at COUNT = 4, so the generic
-- is exercised rather than merely declared. Checks the two-clock latency (old level after one
-- edge, new level after two), that a steady input holds the output steady, and that reset_s2_n
-- clears the chain asynchronously and that it re-synchronizes cleanly once released.
--
-- Run, from hw/:
--       ghdl -a --std=93 sync.vhd sync_tb.vhd
--       ghdl -e --std=93 sync_tb
--       ghdl -r --std=93 sync_tb --assert-level=error
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity sync_tb is
end entity sync_tb;

architecture sim of sync_tb is
constant CLOCK_PERIOD_NS: time    := 20 ns;   -- 50 MHz
constant CLOCK_EVENT_NS : time    := CLOCK_PERIOD_NS / 2;
constant SYNC_UPDATE_NS : time    := 1 ns;
constant WIDE           : natural := 4;
constant STEADY_CYCLES  : natural := 6;   -- edges a steady input is held for in case 4
constant MID_CYCLE_NS   : time    := CLOCK_EVENT_NS / 2;   -- a point away from any clock edge

signal clock, reset_s2_n  : std_logic := '0';
signal async_bit, sync_bit: std_logic_vector(0 downto 0) := "0";
signal async_vec, sync_vec: std_logic_vector(WIDE - 1 downto 0) := (others => '0');
signal done               : boolean := false;
begin
    dut_bit: entity work.sync
        port map(clock, reset_s2_n, async_bit, sync_bit);

    dut_vec: entity work.sync
        generic map(WIDE)
        port map(clock, reset_s2_n, async_vec, sync_vec);

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
    begin
        -- Case 0: reset. Hold reset_s2_n low with a non-zero input applied.
        -- Expect the outputs to stay clear for as long as reset is asserted.
        reset_s2_n <= '0';
        async_bit  <= "1";
        async_vec  <= "1111";
        wait until rising_edge(clock);
        wait until rising_edge(clock);
        wait for SYNC_UPDATE_NS;
        assert sync_bit = "0" and sync_vec = "0000"
            report "sync: output left reset while reset_s2_n was low!"
            severity error;

        -- Release reset with the inputs back at zero, and let the cleared level settle.
        async_bit  <= "0";
        async_vec  <= (others => '0');
        wait until rising_edge(clock);
        reset_s2_n <= '1';
        wait until rising_edge(clock);
        wait until rising_edge(clock);

        -- Case 1: drive one bit low to high.
        -- Expect the old level after one edge, and the new level after two.
        async_bit <= "1";
        wait until rising_edge(clock);
        wait for SYNC_UPDATE_NS;
        assert sync_bit = "0"
            report "sync: output changed after only one clock edge!"
            severity error;
        wait until rising_edge(clock);
        wait for SYNC_UPDATE_NS;
        assert sync_bit = "1"
            report "sync: output did not follow the input after two edges!"
            severity error;

        -- Case 2: drive the same bit high to low.
        -- Expect the symmetric two-edge latency the other way.
        async_bit <= "0";
        wait until rising_edge(clock);
        wait for SYNC_UPDATE_NS;
        assert sync_bit = "1"
            report "sync: output changed after one edge (high to low)!"
            severity error;
        wait until rising_edge(clock);
        wait for SYNC_UPDATE_NS;
        assert sync_bit = "0"
            report "sync: output did not follow a high-to-low change!"
            severity error;

        -- Case 3: drive the COUNT = 4 instance.
        -- Expect all four bits to arrive together, two edges after the change.
        async_vec <= "1011";
        wait until rising_edge(clock);
        wait for SYNC_UPDATE_NS;
        assert sync_vec = "0000"
            report "sync: COUNT=4 output changed after only one edge!"
            severity error;
        wait until rising_edge(clock);
        wait for SYNC_UPDATE_NS;
        assert sync_vec = "1011"
            report "sync: COUNT=4 output did not follow after two edges!"
            severity error;

        -- Case 4: hold both inputs steady.
        -- Expect both outputs to hold too.
        for i in 1 to STEADY_CYCLES loop
            wait until rising_edge(clock);
            wait for SYNC_UPDATE_NS;
            assert sync_vec = "1011" and sync_bit = "0"
                report "sync: output moved while the input was steady!"
                severity error;
        end loop;

        -- Case 5: assert reset away from a clock edge, with a known non-zero output standing.
        -- Expect the output to clear immediately, without waiting for an edge: the reset is
        -- asserted asynchronously, which is the whole reason it is not a plain synchronous load.
        wait until rising_edge(clock);
        wait for MID_CYCLE_NS;
        reset_s2_n <= '0';
        wait for SYNC_UPDATE_NS;
        assert sync_vec = "0000" and sync_bit = "0"
            report "sync: reset_s2_n did not clear the output asynchronously!"
            severity error;

        -- Case 6: release reset with the input still driven.
        -- Expect the chain to re-synchronize, so the input reappears two edges later.
        wait until rising_edge(clock);
        reset_s2_n <= '1';
        wait until rising_edge(clock);
        wait for SYNC_UPDATE_NS;
        assert sync_vec = "0000"
            report "sync: output appeared only one edge after reset release!"
            severity error;
        wait until rising_edge(clock);
        wait for SYNC_UPDATE_NS;
        assert sync_vec = "1011"
            report "sync: chain did not re-synchronize after reset release!"
            severity error;

        report "sync_tb passed!"
        severity note;
        done <= true;
        wait;
    end process;
end architecture sim;
