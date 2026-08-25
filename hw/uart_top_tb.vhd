--------------------------------------------------------------------------------
-- System testbench for uart_top (built in L01, runs from L05).
--
-- Drives the peripheral entirely over SPI, as the ATmega328P would, and loops tx back into rx. A
-- single SPI-written byte is transmitted, received through the loopback, and read back over SPI:
-- an end-to-end check of the whole FPGA half. The stimulus is a mode-0 SPI master at 1 MHz.
--
-- Run, from hw/:
--       ghdl -a --std=93 uart_def.vhd reset_sync.vhd fifo.vhd baud_gen.vhd sync.vhd uart_tx.vhd uart_rx.vhd \
--                        uart_regs.vhd spi_slave.vhd spi_reg_bridge.vhd uart_top.vhd uart_top_tb.vhd
--       ghdl -e --std=93 uart_top_tb
--       ghdl -r --std=93 uart_top_tb --assert-level=error
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.uart_def.all;

entity uart_top_tb is
end entity uart_top_tb;

architecture sim of uart_top_tb is
constant CLOCK_PERIOD_NS : time    := 20 ns;
constant CLOCK_EVENT_NS  : time    := CLOCK_PERIOD_NS / 2;
constant SCK_HALF_NS     : time    := 500 ns;   -- half an SCK period => 1 MHz
constant SETTLE_NS       : time    := 1 ns;      -- master samples MISO just after the edge
constant RESET_SETTLE_NS : time    := 200 ns;    -- settle after reset before driving SPI
constant POLL_LIMIT      : natural := 40;        -- STATUS polls before giving up on RX valid

signal clock, reset_n: std_logic := '0';
signal sclk          : std_logic := '0';
signal mosi          : std_logic := '0';
signal ss            : std_logic := '1';
signal miso          : std_logic;
signal rx            : std_logic;
signal tx            : std_logic;
signal done          : boolean := false;
begin
    dut: entity work.uart_top
        port map(clock, reset_n, sclk, mosi, ss, rx, miso, tx);

    rx <= tx;   -- loopback: what the peripheral sends, it receives

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
        -- Clock one SPI byte: drive txb on MOSI (MSB first) and capture MISO into rxb.
        procedure spi_byte(txb: std_logic_vector(7 downto 0);
                           rxb: out std_logic_vector(7 downto 0)) is
        begin
            for i in 7 downto 0 loop
                mosi <= txb(i);
                wait for SCK_HALF_NS;
                sclk <= '1';                     -- rising edge: slave samples MOSI, master samples MISO
                wait for SETTLE_NS;
                rxb(i) := miso;
                wait for SCK_HALF_NS - SETTLE_NS;
                sclk <= '0';                     -- falling edge: slave presents the next MISO bit
            end loop;
        end procedure;

        -- One 5-byte transaction: command byte, then four data bytes.
        procedure spi_txn(is_wr: boolean; addr: natural;
                          wdata: std_logic_vector(31 downto 0);
                          rdata: out std_logic_vector(31 downto 0)) is
            variable cmd: std_logic_vector(7 downto 0) := (others => '0');
            variable ob : std_logic_vector(7 downto 0);
            variable ib : std_logic_vector(7 downto 0);
            variable rd : std_logic_vector(31 downto 0) := (others => '0');
        begin
            cmd := (others => '0');
            if is_wr then cmd(7) := '1'; end if;
            cmd(3 downto 0) := std_logic_vector(to_unsigned(addr, 4));

            ss <= '0';
            wait for SCK_HALF_NS;
            spi_byte(cmd, ib);                   -- command byte; MISO ignored
            for k in 0 to 3 loop
                if is_wr then
                    case k is
                        when 0      => ob := wdata(31 downto 24);
                        when 1      => ob := wdata(23 downto 16);
                        when 2      => ob := wdata(15 downto 8);
                        when others => ob := wdata(7 downto 0);
                    end case;
                else
                    ob := (others => '0');
                end if;
                spi_byte(ob, ib);
                rd := rd(23 downto 0) & ib;      -- collect MISO, MSB byte first
            end loop;
            wait for SCK_HALF_NS;
            ss <= '1';
            wait for SCK_HALF_NS;
            rdata := rd;
        end procedure;

        variable rd   : std_logic_vector(31 downto 0);
        variable tries: natural;
    begin
        reset_n <= '0'; ss <= '1'; sclk <= '0'; mosi <= '0';
        wait until rising_edge(clock);
        wait until rising_edge(clock);
        reset_n <= '1';
        wait for RESET_SETTLE_NS;

        -- Case 1: speed up the UART for simulation (BAUD_DIV = 4), then read it back.
        -- Expect the read-back to be 4.
        spi_txn(true, REG_BAUD_DIV, x"00000004", rd);
        spi_txn(false, REG_BAUD_DIV, (others => '0'), rd);
        assert rd(15 downto 0) = x"0004"
            report "uart_top_tb: BAUD_DIV read-back mismatch, got 0x" & to_hex(rd(15 downto 0)) & "!"
            severity error;

        -- Case 2: read STATUS out of reset.
        -- Expect TX ready to be set.
        spi_txn(false, REG_STATUS, (others => '0'), rd);
        assert rd(ST_TX_READY) = '1'
            report "uart_top_tb: TX ready should be set!"
            severity error;

        -- Case 3: transmit 0x53; it loops tx -> rx and should be received.
        -- Expect no immediate check here; the RX side is polled next.
        --
        -- 0x53 rather than a bit-reversal palindrome such as 0x5A, so that a bit-order mistake in
        -- one half alone is caught here. Note the limit of a loopback, though: it can never catch
        -- uart_tx and uart_rx being reversed *together*, because the two cancel exactly. That pair
        -- is what uart_tx_tb and uart_rx_tb pin down individually, and why their own constants are
        -- non-palindromic too.
        spi_txn(true, REG_TX_DATA, x"00000053", rd);

        -- Case 4: poll STATUS until RX valid, then read the received byte back over SPI.
        -- Expect the received byte to be 0x53.
        tries := 0;
        loop
            spi_txn(false, REG_STATUS, (others => '0'), rd);
            exit when rd(ST_RX_VALID) = '1';
            tries := tries + 1;
            assert tries < POLL_LIMIT
                report "uart_top_tb: timed out waiting for RX valid!"
                severity error;
            exit when tries >= POLL_LIMIT;
        end loop;

        spi_txn(false, REG_RX_DATA, (others => '0'), rd);
        assert rd(7 downto 0) = x"53"
            report "uart_top_tb: received byte mismatch, expected 0x53, got 0x" & to_hex(rd(7 downto 0)) & "!"
            severity error;

        report "uart_top_tb passed!"
        severity note;
        done <= true;
        wait;
    end process;
end architecture sim;
