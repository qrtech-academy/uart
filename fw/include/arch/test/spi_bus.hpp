/**
 * @file SPI bus implementation for testing.
 */
#pragma once

#ifdef HOST_TEST

#include <cstdint>

#include "arch/test/regs.hpp"

namespace test
{
/**
 * @brief SPI bus implementation.
 *
 *        This class is non-copyable and non-movable.
 */
class SpiBus final
{
public:
    /**
     * @brief Constructor.
     */
    SpiBus() noexcept
        : myMosiBuf{}
        , myMisoBuf{}
        , myMosiLen{}
        , myMisoLen{}
        , myMisoIdx{}
        , myRx{}
        , myPendingRx{}
        , myTransferPending{}
        , mySpif{}
    {}

    /**
     * @brief Destructor.
     */
    ~SpiBus() noexcept = default;

    /**
     * @brief Get the number of captures MOSI bytes.
     */
    [[nodiscard]] std::uint8_t mosiLen() const noexcept { return myMosiLen; }

    /**
     * @brief Get captured MOSI byte at the given index.
     *
     * @param[in] idx Index of the captures MOSI byte.
     *
     * @return Captured MOSI byte, or 0 if the index is invalid.
     */
    [[nodiscard]] std::uint8_t mosi(const std::uint8_t idx) const noexcept
    {
        return idx < myMosiLen ? myMosiBuf[idx] : 0U;
    }

    /**
     * @brief Get the next SPDR RX byte, and clear SPIF.
     *
     *        Reading SPDR clears SPIF on the real part, so it does here too. The byte returned is
     *        whatever the last *completed* transfer delivered: a transfer that is still in flight
     *        has not written myRx yet, so a driver that skips the poll reads the previous byte.
     *
     * @return Byte the next SPDR read returns.
     */
    [[nodiscard]] std::uint8_t rx() noexcept
    {
        mySpif = false;
        return myRx;
    }

    /**
     * @brief Get the SPSR value, completing any transfer that is in flight.
     *
     *        This models the one property the mock previously threw away: a transfer takes time.
     *        exchange() leaves SPIF clear, and only a read of SPSR - that is, the driver's poll -
     *        completes the transfer and makes the received byte readable. Deleting the poll from
     *        AvrSpi::transfer() therefore fails the tests, which is what the lectures claim.
     *
     * @return Current SPSR value.
     */
    [[nodiscard]] std::uint8_t status() noexcept
    {
        if (myTransferPending)
        {
            myRx              = myPendingRx;
            myTransferPending = false;
            mySpif            = true;
        }
        return mySpif ? static_cast<std::uint8_t>(1U << SPIF) : 0U;
    }

    /**
     * @brief Reset SPI bus.
     */
    void reset() noexcept
    {
        myMosiLen         = 0U;
        myMisoLen         = 0U;
        myMisoIdx         = 0U;
        myRx              = 0U;
        myPendingRx       = 0U;
        myTransferPending = false;
        mySpif            = false;
    }

    /**
     * @brief Queue MISO byte.
     *
     * @param[in] byte Byte to queue.
     */
    void queueMiso(const std::uint8_t byte) noexcept
    {
        if (OurBufLen > myMisoLen) { myMisoBuf[myMisoLen++] = byte; }
    }

    /**
     * @brief Perform full-duplex exchange.
     *
     * @param[in] byte Byte to transmit.
     *
     * @note This operation is triggered by an SPDR write.
     */
    void exchange(const std::uint8_t byte) noexcept
    {
        // Capture MOSI. The MISO byte advances even once the MOSI log is full, so a test that
        // overruns the buffer still sees the queued reply rather than a stale one.
        if (OurBufLen > myMosiLen) { myMosiBuf[myMosiLen++] = byte; }
        myPendingRx = myMisoIdx < myMisoLen ? myMisoBuf[myMisoIdx++] : 0U;

        // The transfer is now in flight, not complete: SPIF stays clear until SPSR is read.
        myTransferPending = true;
    }

    SpiBus(const SpiBus&)            = delete; // No copy constructor.
    SpiBus(SpiBus&&)                 = delete; // No move constructor.
    SpiBus& operator=(const SpiBus&) = delete; // No copy assignment.
    SpiBus& operator=(SpiBus&&)      = delete; // No move assignment.

private:
    /** Buffer length in bytes. */
    static constexpr std::uint16_t OurBufLen{64U};

    /** MOSI buffer. */
    std::uint8_t myMosiBuf[OurBufLen];

    /** MISO buffer. */
    std::uint8_t myMisoBuf[OurBufLen];

    /** MOSI length in bytes. */
    std::uint8_t myMosiLen;

    /** MISO length in bytes. */
    std::uint8_t myMisoLen;

    /** Index of the next MISO byte to pop. */
    std::uint8_t myMisoIdx;

    /** Byte the next SPDR read returns. */
    std::uint8_t myRx;

    /** Byte the in-flight transfer will deliver once SPSR is read. */
    std::uint8_t myPendingRx;

    /** True while a transfer has been started but not yet observed as complete. */
    bool myTransferPending;

    /** State of the SPIF flag. */
    bool mySpif;
};
} // namespace test
#endif /** HOST_TEST */
