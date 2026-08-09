--------------------------------------------------------------------------------
-- Testbench for baud_gen (L02).
--
-- Sets div = 4 and asserts that ticks arrive exactly four clocks apart.
--
-- Run, from hw/:
--       ghdl -a --std=93 baud_gen.vhd baud_gen_tb.vhd
--       ghdl -e --std=93 baud_gen_tb
--       ghdl -r --std=93 baud_gen_tb --assert-level=error
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity baud_gen_tb is
end entity baud_gen_tb;

architecture sim of baud_gen_tb is
constant CLOCK_PERIOD_NS: time    := 20 ns;
constant CLOCK_EVENT_NS : time    := CLOCK_PERIOD_NS / 2;
constant DIV_VALUE      : natural := 4;   -- baud divisor under test
constant TICKS_CHECKED  : natural := 3;   -- inter-tick gaps verified

signal clock, reset_s2_n: std_logic := '0';
signal div              : natural range 1 to 65535 := DIV_VALUE;
signal tick             : std_logic;
signal done             : boolean := false;
begin
    dut: entity work.baud_gen
        port map(clock, reset_s2_n, div, tick);

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
        variable cyc: natural;
    begin
        reset_s2_n <= '0';
        wait until rising_edge(clock);
        wait until rising_edge(clock);
        reset_s2_n <= '1';

        -- Advance to the first tick.
        loop
            wait until rising_edge(clock);
            exit when tick = '1';
        end loop;

        -- Case 1: run the generator with div = 4.
        -- Expect each of the next three ticks exactly 4 clocks after the previous.
        for n in 1 to TICKS_CHECKED loop
            cyc := 0;
            loop
                wait until rising_edge(clock);
                cyc := cyc + 1;
                exit when tick = '1';
            end loop;
            assert cyc = DIV_VALUE
                report "baud_gen_tb: expected a tick every 4 clocks, got " & natural'image(cyc) & "!"
                severity error;
        end loop;

        report "baud_gen_tb passed!"
        severity note;
        done <= true;
        wait;
    end process;
end architecture sim;
