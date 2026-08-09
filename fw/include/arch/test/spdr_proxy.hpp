/**
 * @file SPDR proxy implementation for testing.
 */
#pragma once

#ifdef HOST_TEST

#include <cstdint>

#include "arch/test/spi_bus.hpp"

namespace test
{
/**
 * @brief SPDR (SPI Data Register) proxy implementation.
 *
 *        This class is non-copyable and non-movable.
 */
class SpdrProxy final
{
public:
    /**
     * @brief Constructor.
     *
     * @param[in] spiBus Associated SPI bus instance.
     */
    explicit SpdrProxy(SpiBus& spiBus) noexcept
        : mySpiBus{spiBus}
    {}

    /**
     * @brief Destructor.
     */
    ~SpdrProxy() noexcept = default;

    /**
     * @brief Perform full-duplex exchange.
     *
     * @param[in] byte Byte to transmit.
     *
     * @note This operation is triggered by an SPDR write.
     */
    SpdrProxy& operator=(const std::uint8_t byte) noexcept
    {
        mySpiBus.exchange(byte);
        return *this;
    }

    /**
     * @brief Get the next SPDR RX byte.
     *
     * @return Byte the next SPDR read returns.
     *
     * @note Reading SPDR clears SPIF, mirroring the ATmega328P, where SPIF is cleared by reading
     *       SPSR while it is set and then accessing SPDR. Without this the flag would latch high
     *       after the first exchange and stay high forever, so every later poll would pass on a
     *       stale flag rather than on the transfer it is actually waiting for.
     */
    operator std::uint8_t() const noexcept { return mySpiBus.rx(); }

    SpdrProxy()                            = delete; // No default constructor.
    SpdrProxy(const SpdrProxy&)            = delete; // No copy constructor.
    SpdrProxy(SpdrProxy&&)                 = delete; // No move constructor.
    SpdrProxy& operator=(const SpdrProxy&) = delete; // No copy assignment.
    SpdrProxy& operator=(SpdrProxy&&)      = delete; // No move assignment.

private:
    /** Associated SPI bus instance. */
    SpiBus& mySpiBus;
};
} // namespace test
#endif /** HOST_TEST */
