--------------------------------------------------------------------------------
-- SPI transaction to register bus.
--
-- Inputs:
--    - clock     : 50 MHz system clock.
--    - reset_s2_n: Active-low synchronized reset.
--    - ss_active : '1' when the SPI Chip Select is active.
--    - rx_data   : Incoming byte.
--    - rx_valid  : '1' if incoming byte is fresh.
--    - reg_rdata : Incoming register data.
-- Outputs:
--    - tx_data  : Next byte to shift to output.
--    - reg_addr : Register address.
--    - reg_wdata: Outgoing register data.
--    - reg_write: Write enablement signal.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity spi_reg_bridge is
    port(clock, reset_s2_n: in std_logic;
         ss_active        : in std_logic;
         rx_data          : in std_logic_vector(7 downto 0);
         rx_valid         : in std_logic;
         reg_rdata        : in std_logic_vector(31 downto 0);
         tx_data          : out std_logic_vector(7 downto 0);
         reg_addr         : out std_logic_vector(3 downto 0);
         reg_wdata        : out std_logic_vector(31 downto 0);
         reg_write        : out std_logic);
end entity;

architecture behaviour of spi_reg_bridge is
-- Byte index (0 = command, 1-4 = data, 5 = done).
signal byte_idx: natural range 0 to 5;

-- Indicator signals.
signal is_write, need_latch: std_logic;

-- Command address.
signal cmd_addr: std_logic_vector(3 downto 0);

-- Write and read values.
signal wr_value, rd_value: std_logic_vector(31 downto 0);

begin
    reg_addr <= cmd_addr;

    -- Shift the latched read value out, MSB byte first.
    process(rd_value, byte_idx) is
    begin
        case (byte_idx) is
            when 1 =>
                tx_data <= rd_value(31 downto 24);
            when 2 =>
                tx_data <= rd_value(23 downto 16);
            when 3 =>
                tx_data <= rd_value(15 downto 8);
            when 4 =>
                tx_data <= rd_value(7 downto 0);
            when others =>
                tx_data <= (others => '0');
        end case;
    end process;

    -- Implement SPI register bridge logic.
    process(clock, reset_s2_n) is
    begin
        if (reset_s2_n = '0') then
            byte_idx   <= 0;
            is_write   <= '0';
            cmd_addr   <= (others => '0');
            wr_value   <= (others => '0');
            rd_value   <= (others => '0');
            need_latch <= '0';
            reg_write  <= '0';
            reg_wdata  <= (others => '0');
        elsif (rising_edge(clock)) then
            reg_write <= '0';

            -- Check SS state, reset for the transfer if deselected.
            if (ss_active = '0') then
                byte_idx   <= 0;
                need_latch <= '0';
            end if;

            -- One cycle after a read command decodes, cmd_addr has settled and reg_rdata
            -- reflects the addressed register, so latch it for the read shift-out.
            if (need_latch = '1') then
                rd_value   <= reg_rdata;
                need_latch <= '0';
            end if;

            -- Extract data from incoming bytes.
            if (rx_valid = '1') then
               case (byte_idx) is
                   -- Byte index = 0: extract write bit + command address.
                   when 0 =>
                       is_write <= rx_data(7);
                       cmd_addr <= rx_data(3 downto 0);
                       byte_idx <= 1;
                       -- On a read (write bit clear), fetch the register value next cycle.
                       if (rx_data(7) = '0') then
                           need_latch <= '1';
                       end if;
                   -- Byte index = 1-3: shift in incoming byte.
                   when 1 | 2 | 3  =>
                       wr_value <= wr_value(23 downto 0) & rx_data;
                       byte_idx <= byte_idx + 1;
                   -- Byte index = 4: signal write operation if selected.
                   when 4 =>
                       if (is_write = '1') then
                           reg_wdata <= wr_value(23 downto 0) & rx_data;
                           reg_write <= '1';
                       end if;
                       byte_idx <= 5;
                   -- Byte index >= 5: ignore until SPI Chip Select rises.
                   when others =>
                       null;
               end case;
            end if;
        end if;
    end process;
end architecture;
