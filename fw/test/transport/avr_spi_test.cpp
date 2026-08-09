/**
 * @file Host tests for the AvrSpi transport over the mocked AVR register file.
 */
#include <cstddef>
#include <cstdint>

#include "qacademy/test/test.hpp"

#if __has_include("driver/transport/avr_spi.hpp") && __has_include("driver/uart/uart.hpp")

#include "arch/avr/hw_platform.hpp"
#include "driver/transport/avr_spi.hpp"
#include "driver/uart/uart.hpp"

namespace driver::transport
{
namespace
{
using driver::transport::AvrSpi;

/** Zero (empty byte). */
constexpr std::uint8_t zero{0U};

/**
 * @brief Clear the SPI registers and the scripted bus so each test starts from a known state.
 */
void resetHardware() noexcept
{
    DDRB  = zero;
    PORTB = zero;
    SPCR  = zero;
    SPSR  = zero;
    test::spiBus.reset();
}

/**
 * @brief Construct an AvrSpi, expect the master configured: SPCR, DDRB directions, CS idle high.
 */
TEST(AvrSpi, ConfiguresMasterOnConstruction)
{
    resetHardware();
    AvrSpi spi{};

    constexpr std::uint8_t spcr{(1U << SPE) | (1U << MSTR) | (1U << SPR0)};
    constexpr std::uint8_t ddrb{(1U << SCK) | (1U << MOSI) | (1U << SS)};

    // Enable, master, mode 0 (CPOL/CPHA clear), MSB first (DORD clear), f_osc/16 (SPR0 only).
    EXPECT_EQ(SPCR, spcr);

    // SCK, MOSI, SS are outputs; MISO stays an input.
    EXPECT_EQ(DDRB, ddrb);

    EXPECT_EQ(DDRB & (1U << MISO), zero);

    // Chip select idles high.
    EXPECT_NE(PORTB & (1U << SS), zero);
}

/**
 * @brief Call begin(), expect the chip select driven low.
 */
TEST(AvrSpi, BeginDrivesChipSelectLow)
{
    resetHardware();
    AvrSpi spi{};

    spi.begin();
    EXPECT_EQ(PORTB & (1U << SS), zero);
}

/**
 * @brief Call end() after begin(), expect the chip select released high.
 */
TEST(AvrSpi, EndReleasesChipSelectHigh)
{
    resetHardware();
    AvrSpi spi{};

    spi.begin();
    spi.end();
    EXPECT_NE(PORTB & (1U << SS), zero);
}

/**
 * @brief Transfer a byte, expect it recorded on MOSI and the scripted MISO byte returned.
 */
TEST(AvrSpi, TransferExchangesByte)
{
    constexpr std::uint8_t miso{0xCDU};
    constexpr std::uint8_t mosi{0x12U};
    constexpr std::uint8_t mosiLen{static_cast<std::uint8_t>(sizeof(mosi))};
    constexpr std::uint8_t mosiIdx{zero};

    resetHardware();
    AvrSpi spi{};
    test::spiBus.queueMiso(miso);
    const auto rx = spi.transfer(mosi);

    EXPECT_EQ(rx, miso);
    EXPECT_EQ(test::spiBus.mosiLen(), mosiLen);
    EXPECT_EQ(test::spiBus.mosi(mosiIdx), mosi);
}

/**
 * @brief Transfer two bytes, expect both recorded on MOSI and both MISO bytes returned in order.
 */
TEST(AvrSpi, TransferIsFullDuplexInOrder)
{
    constexpr std::uint8_t bufLen{2U};
    constexpr std::uint8_t miso[bufLen]{0xAAU, 0xBBU};
    constexpr std::uint8_t mosi[bufLen]{0x11U, 0x22U};

    resetHardware();
    AvrSpi spi{};

    for (std::uint8_t i{}; i < bufLen; ++i)
    {
        test::spiBus.queueMiso(miso[i]);
    }
    for (std::uint8_t i{}; i < bufLen; ++i)
    {
        EXPECT_EQ(spi.transfer(mosi[i]), miso[i]);
    }
    EXPECT_EQ(test::spiBus.mosiLen(), bufLen);

    for (std::uint8_t i{}; i < bufLen; ++i)
    {
        EXPECT_EQ(test::spiBus.mosi(i), mosi[i]);
    }
}

/**
 * @brief Read the status through a Uart over an AvrSpi, expect the scripted register value
 *        to be returned.
 */
TEST(AvrSpi, DrivesTheDriverEndToEnd)
{
    resetHardware();
    AvrSpi spi{};
    driver::uart::Uart uart{spi};

    constexpr std::uint8_t dummyCmd{zero};
    constexpr std::uint32_t data{0x12345678U};
    constexpr std::size_t size{sizeof(data)};

    // A status read sends one command byte followed by four data bytes, so queue a dummy.
    test::spiBus.queueMiso(dummyCmd);

    for (std::size_t i{}; i < size; ++i)
    {
        constexpr std::size_t last{size - 1U};
        constexpr std::uint32_t bits{8U};

        const auto shift = static_cast<std::uint32_t>(last - i) * bits;
        const auto byte  = static_cast<std::uint8_t>(data >> shift);
        test::spiBus.queueMiso(byte);
    }
    EXPECT_EQ(uart.status(), data);
}
} // namespace
} // namespace driver::transport

#endif // __has_include(...)