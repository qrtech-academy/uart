--------------------------------------------------------------------------------
-- Byte-level SPI slave.
--
-- Inputs:
--    - clock     : 50 MHz system clock.
--    - reset_s2_n: Active-low synchronized reset.
--    - sclk      : SPI clock.
--    - mosi      : Master Out Slave In.
--    - ss        : SPI Chip Select.
--    - tx_data   : Next byte to shift output.
-- Outputs:
--    - miso     : Master In Slave Out.
--    - rx_data  : Incoming byte.
--    - rx_valid : '1' if incoming byte is fresh.
--    - ss_active: '1' while selected (ss low).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity spi_slave is
    port(clock, reset_s2_n  : in std_logic;
         sclk, mosi, ss     : in std_logic;
         tx_data            : in std_logic_vector(7 downto 0);
         miso               : out std_logic;
         rx_data            : out std_logic_vector(7 downto 0);
         rx_valid, ss_active: out std_logic);
end entity;

architecture behaviour of spi_slave is

-- Record of synchronized signals.
type sync_t is record
    s1: std_logic; -- First sync stage.
    s2: std_logic; -- Second sync stage (current value).
    s3: std_logic; -- Third sync state (previous value).
end record;

-- Synchronized SPI signals.
signal sclk_s, ss_s, mosi_s: sync_t;

-- Bit counter.
signal bit_counter: natural range 0 to 7;

-- Shift registers.
signal rx_sh, tx_sh: std_logic_vector(7 downto 0);

begin
    ss_active <= not ss_s.s2;
    miso      <= tx_sh(7) when ss_s.s2 = '0' else '0';

    -- Synchronize SPI inputs.
    process(clock, reset_s2_n) is
    begin
        if (reset_s2_n = '0') then
            sclk_s <= ('0', '0', '0');
            ss_s   <= ('1', '1', '1');   -- ss is active low and idles high: reset to deselected.
            mosi_s <= ('0', '0', '0');
        elsif (rising_edge(clock)) then
            sclk_s.s1 <= sclk;
            sclk_s.s2 <= sclk_s.s1;
            sclk_s.s3 <= sclk_s.s2;
            ss_s.s1   <= ss;
            ss_s.s2   <= ss_s.s1;
            ss_s.s3   <= ss_s.s2;
            mosi_s.s1 <= mosi;
            mosi_s.s2 <= mosi_s.s1;
        end if;
    end process;

    -- Run SPI slave logic.
    process(clock, reset_s2_n) is
    variable sclk_rising, sclk_falling, ss_falling: std_logic := '0';
    begin
        if (reset_s2_n = '0') then
            bit_counter  <= 0;
            rx_sh        <= (others => '0');
            tx_sh        <= (others => '0');
            rx_valid     <= '0';
        elsif (rising_edge(clock)) then
            rx_valid <= '0';

            -- Detect edges on sclk and ss.
            sclk_rising  := sclk_s.s2 and (not sclk_s.s3);
            sclk_falling := (not sclk_s.s2) and (sclk_s.s3);
            ss_falling   := (not ss_s.s2) and ss_s.s3;

            -- Check ss. Everything below only happens while selected, so sclk toggling on a
            -- deselected slave can neither shift rx_sh nor advance bit_counter.
            if (ss_s.s2 = '1') then
                bit_counter <= 0;
            else
                -- If SS fell, load the first byte to send.
                if (ss_falling = '1') then
                    bit_counter <= 0;
                    tx_sh       <= tx_data;
                end if;

                -- Sample MOSI, MSB first on rising SCLK edge.
                if (sclk_rising = '1') then
                    if (bit_counter = 7) then
                        rx_data     <= rx_sh(6 downto 0) & mosi_s.s2;
                        rx_valid    <= '1';
                        bit_counter <= 0;
                    else
                        rx_sh       <= rx_sh(6 downto 0) & mosi_s.s2;
                        bit_counter <= bit_counter + 1;
                    end if;
                end if;

                -- Present the next MISO bit on falling edge.
                if (sclk_falling = '1') then
                    if (bit_counter = 0) then
                        tx_sh <= tx_data;
                    else
                        tx_sh <= tx_sh(6 downto 0) & '0';
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture;
