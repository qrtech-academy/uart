--------------------------------------------------------------------------------
-- Self-checking testbench for spi_slave: a modeled SPI master (mode 0).
--
-- Drives sclk/mosi/ss as a mode-0 master (SCK idles low; MOSI set while low,
-- sampled by the slave on the rising edge; MISO shifted by the slave on the
-- falling edge and sampled by the master on the rising). Clocks known bytes in
-- and reads bytes back, checking rx_data / rx_valid and the MISO bytes.
--
-- Run, from hw/:
--       ghdl -a --std=93 uart_def.vhd spi_slave.vhd spi_slave_tb.vhd
--       ghdl -e --std=93 spi_slave_tb
--       ghdl -r --std=93 spi_slave_tb --assert-level=error
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

use work.uart_def.all;   -- to_hex, for the failure messages

entity spi_slave_tb is
end entity;

architecture sim of spi_slave_tb is
constant CLOCK_PERIOD_NS: time := 20 ns;
constant CLOCK_EVENT_NS : time := CLOCK_PERIOD_NS / 2;
constant SCK_EVENT_NS   : time := 200 ns;

signal clock, reset_s2_n: std_logic := '0';
signal sclk, mosi, ss   : std_logic := '0';
signal tx_data, rx_data : std_logic_vector(7 downto 0) := (others => '0');
signal miso, ss_active  : std_logic := '0';
signal rx_valid         : std_logic := '0';
signal captured_rx      : std_logic_vector(7 downto 0) := (others => '0');
signal valid_count      : natural := 0;
signal done             : boolean := false;

begin

    dut: entity work.spi_slave
        port map(clock, reset_s2_n, sclk, mosi, ss, tx_data,
                 miso, rx_data, rx_valid, ss_active);

    CLK_PROCESS: process is
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

    MONITOR_PROCESS: process(clock) is
    begin
        if (rising_edge(clock)) then
            if (rx_valid = '1') then
                captured_rx <= rx_data;
                valid_count <= valid_count + 1;
            end if;
        end if;
    end process;

    SIM_PROCESS: process is
        -- One mode-0 byte exchange: send tx on MOSI (MSB first), capture MISO into rx.
        procedure spi_exchange(constant tx : in  std_logic_vector(7 downto 0);
                               variable rx : out std_logic_vector(7 downto 0)) is
        begin
            for i in 7 downto 0 loop
                -- Set MOSI while SCK is low.
                mosi <= tx(i);
                wait for SCK_EVENT_NS;
                -- Rising edge: slave samples MOSI.
                sclk <= '1';
                 -- Master samples MISO mid-high.
                wait for SCK_EVENT_NS / 2;
                rx(i) := miso;
                wait for SCK_EVENT_NS / 2;
                -- Falling edge: slave shifts MISO.
                sclk <= '0';
                wait for SCK_EVENT_NS;
            end loop;
        end procedure;

    constant tx1: std_logic_vector(7 downto 0) := x"3C";
    constant tx2: std_logic_vector(7 downto 0) := x"A5";
    constant tx3: std_logic_vector(7 downto 0) := x"69";
    variable got: std_logic_vector(7 downto 0) := (others => '0');
    begin
        -- Idle and reset: SS high, SCK low.
        ss         <= '1';
        sclk       <= '0';
        reset_s2_n <= '0';
        wait for 5 * CLOCK_PERIOD_NS;
        reset_s2_n <= '1';
        wait for 5 * CLOCK_PERIOD_NS;
        assert ss_active = '0'
            report "ss_active should be low while deselected!"
            severity error;

        -- Select, and present the byte the slave will send.
        tx_data <= tx1;
        ss      <= '0';
        wait for 10 * CLOCK_PERIOD_NS;       -- let the synchronizer see SS and load tx_sh
        assert ss_active = '1'
            report "ss_active should be high once selected!"
            severity error;

        -- Byte 1: master sends 0xA5, expects 0x3C back; slave should receive 0xA5.
        spi_exchange(tx2, got);
        wait for 5 * CLOCK_PERIOD_NS;
        assert got = tx1
            report "MISO byte 1 wrong: expected 0x3C, got 0x" & to_hex(got) & "!"
            severity error;
        assert captured_rx = tx2
            report "rx_data byte 1 wrong: expected 0xA5, got 0x" & to_hex(captured_rx) & "!"
            severity error;
        assert valid_count = 1
            report "rx_valid should have pulsed exactly once after byte 1!"
            severity error;

        -- Byte 2 (still selected): master sends 0x69, expects 0x3C back (reloaded); rx = 0x69.
        spi_exchange(tx3, got);
        wait for 5 * CLOCK_PERIOD_NS;
        assert got = tx1
            report "MISO byte 2 wrong: expected 0x3C (reload), got 0x" & to_hex(got) & "!"
            severity error;
        assert captured_rx = tx3
            report "rx_data byte 2 wrong: expected 0x69, got 0x" & to_hex(captured_rx) & "!"
            severity error;
        assert valid_count = 2
            report "rx_valid should have pulsed twice after byte 2!"
            severity error;

        -- Deselect.
        ss <= '1';
        wait for 10 * CLOCK_PERIOD_NS;
        assert ss_active = '0'
            report "ss_active should be low after deselect!"
            severity error;

        report "spi_slave_tb: all checks passed!"
        severity note;
        done <= true;
        wait;
    end process;
end architecture;
