/**
 * @file SPSR proxy implementation for testing.
 */
#pragma once

#ifdef HOST_TEST

#include <cstdint>

#include "arch/test/spi_bus.hpp"

namespace test
{
/**
 * @brief SPSR (SPI Status Register) proxy implementation.
 *
 *        SPSR is a proxy rather than a plain byte so that reading it can have an effect, the way
 *        it does on real hardware. A write to SPDR starts a transfer; the transfer is not finished
 *        until the driver polls SPIF. Modelling that is what makes the poll in
 *        AvrSpi::transfer() load-bearing: remove the poll and the driver reads SPDR before the
 *        byte has arrived, so the tests fail.
 *
 *        This class is non-copyable and non-movable.
 */
class SpsrProxy final
{
public:
    /**
     * @brief Constructor.
     *
     * @param[in] spiBus Associated SPI bus instance.
     */
    explicit SpsrProxy(SpiBus& spiBus) noexcept
        : mySpiBus{spiBus}
    {}

    /**
     * @brief Destructor.
     */
    ~SpsrProxy() noexcept = default;

    /**
     * @brief Reset the status register.
     *
     * @param[in] value Value to write. Only 0 is meaningful; SPIF is not writable on the part.
     */
    SpsrProxy& operator=(const std::uint8_t value) noexcept
    {
        if (0U == value) { mySpiBus.reset(); }
        return *this;
    }

    /**
     * @brief Read the status register, completing any transfer that is in flight.
     *
     * @return Current SPSR value.
     */
    operator std::uint8_t() const noexcept { return mySpiBus.status(); }

    SpsrProxy()                            = delete; // No default constructor.
    SpsrProxy(const SpsrProxy&)            = delete; // No copy constructor.
    SpsrProxy(SpsrProxy&&)                 = delete; // No move constructor.
    SpsrProxy& operator=(const SpsrProxy&) = delete; // No copy assignment.
    SpsrProxy& operator=(SpsrProxy&&)      = delete; // No move assignment.

private:
    /** Associated SPI bus instance. */
    SpiBus& mySpiBus;
};
} // namespace test
#endif /** HOST_TEST */
