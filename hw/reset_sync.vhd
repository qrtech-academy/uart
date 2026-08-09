--------------------------------------------------------------------------------
-- Double-flop synchronizes an asynchronous reset.
--
-- Inputs:
--    - clock: 50 MHz system clock.
--    - reset_n: Active-low asynchronous reset.
--
-- Outputs:
--    - reset_s2_n: Active-low synchronized reset.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity reset_sync is
    port(clock, reset_n: in std_logic;
         reset_s2_n    : out std_logic);
end entity;

architecture behaviour of reset_sync is
signal reset_s1_n: std_logic;
begin
    process(clock, reset_n) is
    begin
        if (reset_n = '0') then
            reset_s1_n <= '0';
            reset_s2_n <= '0';
        elsif (rising_edge(clock)) then
            reset_s1_n <= '1';
            reset_s2_n <= reset_s1_n;
        end if;
    end process;
end architecture;
