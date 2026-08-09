--------------------------------------------------------------------------------
-- Testbench for uart_regs (L04).
--
-- Drives the register bus directly (standing in for the SPI bridge) and models the datapath with
-- plain signals, checking config read-back, the STATUS bits, the TX and RX FIFO paths, the
-- framing-error latch and its clear, CTRL's stored bits and its reserved upper bits, and a
-- reserved register index.
--
-- Run, from hw/:
--       ghdl -a --std=93 uart_def.vhd fifo.vhd uart_regs.vhd uart_regs_tb.vhd
--       ghdl -e --std=93 uart_regs_tb
--       ghdl -r --std=93 uart_regs_tb --assert-level=error
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.uart_def.all;

entity uart_regs_tb is
end entity uart_regs_tb;

architecture sim of uart_regs_tb is
constant CLOCK_PERIOD_NS: time := 20 ns;
constant CLOCK_EVENT_NS : time := CLOCK_PERIOD_NS / 2;
constant SETTLE_NS      : time := 1 ns;   -- let a combinational read-back settle
constant RESERVED_IDX   : natural := 7;   -- the first index past the seven the map defines

signal clock, reset_s2_n: std_logic := '0';
signal reg_addr         : std_logic_vector(3 downto 0)  := (others => '0');
signal reg_wdata        : std_logic_vector(31 downto 0) := (others => '0');
signal reg_write        : std_logic := '0';
signal reg_rdata        : std_logic_vector(31 downto 0);
signal baud_div         : std_logic_vector(15 downto 0);
signal tx_byte          : std_logic_vector(7 downto 0);
signal tx_empty         : std_logic;
signal tx_pop           : std_logic := '0';
signal rx_byte          : std_logic_vector(7 downto 0) := (others => '0');
signal rx_push          : std_logic := '0';
signal rx_full          : std_logic;
signal tx_busy          : std_logic := '0';
signal frame_err        : std_logic := '0';
signal done             : boolean := false;
begin
    dut: entity work.uart_regs
        port map(clock, reset_s2_n, reg_addr, reg_wdata, reg_write, tx_pop, rx_byte, rx_push,
                 tx_busy, frame_err, reg_rdata, baud_div, tx_byte, tx_empty, rx_full);

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
        procedure bus_write(addr: natural; data: std_logic_vector(31 downto 0)) is
        begin
            reg_addr  <= std_logic_vector(to_unsigned(addr, 4));
            reg_wdata <= data;
            reg_write <= '1';
            wait until rising_edge(clock);
            reg_write <= '0';
            wait until rising_edge(clock);
        end procedure;

        procedure bus_set_addr(addr: natural) is
        begin
            reg_addr <= std_logic_vector(to_unsigned(addr, 4));
            wait until rising_edge(clock);
            wait for SETTLE_NS;
        end procedure;

        procedure pulse(signal s: out std_logic) is
        begin
            s <= '1';
            wait until rising_edge(clock);
            s <= '0';
            wait until rising_edge(clock);
        end procedure;
    begin
        reset_s2_n <= '0';
        wait until rising_edge(clock);
        wait until rising_edge(clock);
        reset_s2_n <= '1';
        wait until rising_edge(clock);

        -- Case 1: write the BAUD_DIV config register, then read it back.
        -- Expect the read-back and the baud_div output to reflect the written value.
        bus_write(REG_BAUD_DIV, x"000000AA");
        bus_set_addr(REG_BAUD_DIV);
        assert reg_rdata = x"000000AA"
            report "uart_regs_tb: BAUD_DIV read-back mismatch, got 0x" & to_hex(reg_rdata) & "!"
            severity error;
        assert baud_div = x"00AA"
            report "uart_regs_tb: baud_div output mismatch, got 0x" & to_hex(baud_div) & "!"
            severity error;

        -- Case 2: read STATUS straight out of reset.
        -- Expect TX ready and TX idle set, RX valid and Error clear.
        bus_set_addr(REG_STATUS);
        assert reg_rdata(ST_TX_READY) = '1'
            report "uart_regs_tb: TX ready should be set!"
            severity error;
        assert reg_rdata(ST_TX_IDLE) = '1'
            report "uart_regs_tb: TX idle should be set!"
            severity error;
        assert reg_rdata(ST_RX_VALID) = '0'
            report "uart_regs_tb: RX valid should be clear!"
            severity error;
        assert reg_rdata(ST_ERROR) = '0'
            report "uart_regs_tb: Error should be clear!"
            severity error;

        -- Case 3: push a TX byte through the register bus.
        -- Expect it at the TX FIFO front, the FIFO non-empty, and TX idle cleared.
        bus_write(REG_TX_DATA, x"0000005A");
        wait for SETTLE_NS;
        assert tx_byte = x"5A"
            report "uart_regs_tb: TX FIFO front should be 0x5A, got 0x" & to_hex(tx_byte) & "!"
            severity error;
        assert tx_empty = '0'
            report "uart_regs_tb: TX FIFO should be non-empty!"
            severity error;
        bus_set_addr(REG_STATUS);
        assert reg_rdata(ST_TX_IDLE) = '0'
            report "uart_regs_tb: TX idle should clear with data queued!"
            severity error;

        -- Case 4: the transmit engine pops the byte as it loads it.
        -- Expect the TX FIFO empty again.
        pulse(tx_pop);
        wait for SETTLE_NS;
        assert tx_empty = '1'
            report "uart_regs_tb: TX FIFO should be empty after pop!"
            severity error;

        -- Case 5: an RX byte arrives from the receive engine.
        -- Expect RX valid set and RX_DATA to read back the byte.
        rx_byte <= x"3C";
        pulse(rx_push);
        bus_set_addr(REG_STATUS);
        assert reg_rdata(ST_RX_VALID) = '1'
            report "uart_regs_tb: RX valid should be set!"
            severity error;
        bus_set_addr(REG_RX_DATA);
        assert reg_rdata(7 downto 0) = x"3C"
            report "uart_regs_tb: RX_DATA mismatch, got 0x" & to_hex(reg_rdata(7 downto 0)) & "!"
            severity error;

        -- Case 6: a pure RX_DATA read, then an explicit RX_POP.
        -- Expect the read not to consume, and RX_POP to clear RX valid.
        bus_set_addr(REG_STATUS);
        assert reg_rdata(ST_RX_VALID) = '1'
            report "uart_regs_tb: RX_DATA read must not pop!"
            severity error;
        bus_write(REG_RX_POP, x"00000001");
        bus_set_addr(REG_STATUS);
        assert reg_rdata(ST_RX_VALID) = '0'
            report "uart_regs_tb: RX valid should clear after RX_POP!"
            severity error;

        -- Case 7: a framing error pulse, then clear it by writing zero.
        -- Expect it to latch into STATUS and ERROR_FLAGS, and clear on the write.
        pulse(frame_err);
        bus_set_addr(REG_STATUS);
        assert reg_rdata(ST_ERROR) = '1'
            report "uart_regs_tb: Error should latch!"
            severity error;
        bus_set_addr(REG_ERR_FLAGS);
        assert reg_rdata(ER_FRAMING) = '1'
            report "uart_regs_tb: framing flag should be set!"
            severity error;
        bus_write(REG_ERR_FLAGS, x"00000000");
        bus_set_addr(REG_STATUS);
        assert reg_rdata(ST_ERROR) = '0'
            report "uart_regs_tb: Error should clear!"
            severity error;

        -- Case 8: CTRL is stored and read back, but only its defined bits.
        -- Expect bits 5-0 to survive and the reserved bits 31-6 to read back as zero, per the
        -- protocol spec's rule that every register's upper bits read zero. CTRL gates nothing in
        -- this course, so this read-back is the only thing that proves the bank stores it at all.
        bus_write(REG_CTRL, x"FFFFFFFF");
        bus_set_addr(REG_CTRL);
        assert reg_rdata = x"0000003F"
            report "uart_regs_tb: CTRL read-back mismatch, expected 0x0000003F, got 0x"
                   & to_hex(reg_rdata) & "!"
            severity error;

        -- Case 9: a reserved register index.
        -- Expect a write to be ignored and a read to return zero, per the protocol spec.
        bus_write(RESERVED_IDX, x"FFFFFFFF");
        bus_set_addr(RESERVED_IDX);
        assert reg_rdata = x"00000000"
            report "uart_regs_tb: reserved index should read zero, got 0x"
                   & to_hex(reg_rdata) & "!"
            severity error;

        report "uart_regs_tb passed!"
        severity note;
        done <= true;
        wait;
    end process;
end architecture sim;
