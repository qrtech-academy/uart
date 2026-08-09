/**
 * @file AVR register definitions for testing.
 */
#pragma once

#ifdef HOST_TEST

#include <cstdint>

namespace test
{
/**
 * @brief Mock register structure for testing.
 */
struct MockRegs
{
    /** Length of the register buffer in bytes. */
    static constexpr std::uint16_t BufLen{20U};

    /**
     * @brief Register buffer.
     *
     *        Declared volatile to match the real hardware registers these stand in for. Without
     *        it the busy-wait in AvrSpi::transfer() is a loop over an ordinary object the
     *        compiler is free to hoist, so the mock would not exercise the very property the
     *        driver relies on.
     */
    volatile std::uint8_t buf[BufLen]{};
};

/** AVR mock register instance. */
inline MockRegs regs{};

} // namespace test

/** Mapping of AVR registers. */
#define DDRB test::regs.buf[0U]
#define PORTB test::regs.buf[1U]
#define PINB test::regs.buf[2U]
#define DDRC test::regs.buf[3U]
#define PORTC test::regs.buf[4U]
#define PINC test::regs.buf[5U]
#define DDRD test::regs.buf[6U]
#define PORTD test::regs.buf[7U]
#define PIND test::regs.buf[8U]
#define SPCR test::regs.buf[9U]
/** SPSR is not a plain byte here: see arch/test/spsr_proxy.hpp for why reading it has an effect. */

/** Bit-position macros. */
#define SPE 6U
#define MSTR 4U
#define SPR1 1U
#define SPR0 0U
#define DORD 5U
#define CPOL 3U
#define CPHA 2U
#define SPIF 7U
#define SPI2X 0U

#endif /** HOST_TEST */