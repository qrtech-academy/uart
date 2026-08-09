--------------------------------------------------------------------------------
-- uart_def: the register map in VHDL form (L01, provided).
--
-- Named constants for the seven register indices and the meaning of each STATUS,
-- CTRL, and ERROR_FLAGS bit, from Part 2 of the protocol spec. The C++ side's
-- register_map.hpp carries the same map, transcribed once on each side of the
-- wire; it declares only the subset the driver uses, and where a name exists in
-- both, the value is identical. Indices are the byte offset divided by 4; the
-- bit constants are positions into a 32-bit register word.
--
-- This package is given to you. You write every module that uses it (uart_regs,
-- uart_top, and the datapath), but the map itself is fixed so the two sides of
-- the wire cannot drift.
--
-- It also carries one testbench helper, to_hex, so the benches can print a bus
-- value in a failure message.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

package uart_def is
    -- Register indices (byte offset / 4).
    constant REG_STATUS   : natural := 0;   -- Status register.
    constant REG_CTRL     : natural := 1;   -- Control register.
    constant REG_BAUD_DIV : natural := 2;   -- Baud divider.
    constant REG_TX_DATA  : natural := 3;   -- Push a byte into the TX FIFO.
    constant REG_RX_DATA  : natural := 4;   -- Front byte of the RX FIFO (pure read).
    constant REG_RX_POP   : natural := 5;   -- Advance the RX FIFO.
    constant REG_ERR_FLAGS: natural := 6;   -- Error flag register.

    -- STATUS bits.
    constant ST_TX_READY: natural := 0;   -- TX FIFO not full.
    constant ST_RX_VALID: natural := 1;   -- RX FIFO not empty.
    constant ST_ERROR   : natural := 2;   -- One or more error flags set.
    constant ST_TX_IDLE : natural := 3;   -- TX FIFO empty and line idle.

    -- CTRL bits.
    constant CT_ENABLE   : natural := 0;   -- Enable the peripheral.
    constant CT_PARITY_LO: natural := 1;   -- Parity select, low bit.
    constant CT_PARITY_HI: natural := 2;   -- Parity select, high bit (00 none, 01 even, 10 odd).
    constant CT_STOP     : natural := 3;   -- 0 = 1 stop bit, 1 = 2 stop bits.
    constant CT_RX_IRQ   : natural := 4;   -- RX-valid IRQ mask.
    constant CT_TX_IRQ   : natural := 5;   -- TX-ready IRQ mask.

    -- ERROR_FLAGS bits.
    constant ER_FRAMING: natural := 0;   -- Framing error.
    constant ER_PARITY : natural := 1;   -- Parity error.
    constant ER_OVERRUN: natural := 2;   -- Overrun.

    -- Testbench helper: render a std_logic_vector as an uppercase hex string,
    -- zero-padded to whole nibbles (e.g. x"A5" -> "A5", a 12-bit bus -> three digits).
    function to_hex(slv: std_logic_vector) return string;
end package;

library ieee;
use ieee.std_logic_1164.all;

package body uart_def is
    function to_hex(slv: std_logic_vector) return string is
        constant DIGITS : string(1 to 16) := "0123456789ABCDEF";
        constant NIBBLES: natural := (slv'length + 3) / 4;
        variable v  : std_logic_vector(NIBBLES * 4 - 1 downto 0) := (others => '0');
        variable d  : natural;
        variable res: string(1 to NIBBLES);
    begin
        v(slv'length - 1 downto 0) := slv;
        for i in 0 to NIBBLES - 1 loop
            -- Fold the four bits of nibble 'i' into its value, most significant first.
            d := 0;
            for b in 3 downto 0 loop
                d := d * 2;
                if (v(i * 4 + b) = '1') then
                    d := d + 1;
                end if;
            end loop;
            res(NIBBLES - i) := DIGITS(d + 1);
        end loop;
        return res;
    end function;
end package body;
