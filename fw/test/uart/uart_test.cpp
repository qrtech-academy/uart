/**
 * @file Host tests for the UART driver over a scripted transport stub.
 */
#include <cstdint>
#include <initializer_list>

#include "qacademy/test/test.hpp"

#if __has_include("driver/uart/register_map.hpp") && __has_include("driver/uart/uart.hpp")
#if __has_include("driver/transport/stub.hpp") && __has_include("driver/uart/blocking.hpp")

#include "driver/transport/stub.hpp"
#include "driver/uart/blocking.hpp"
#include "driver/uart/register_map.hpp"
#include "driver/uart/uart.hpp"

namespace driver::uart::test
{
namespace
{
/** Bytes clocked per register transaction: one command byte, then four data bytes. */
constexpr std::uint16_t transactionLen{5U};

/** STATUS value with every flag clear. */
constexpr std::uint32_t noStatusFlags{0U};

/** STATUS value reporting that the transmitter accepts another byte. */
constexpr std::uint32_t txReadyFlag{1U << status::TX_READY};

/** STATUS value reporting that a received byte is waiting. */
constexpr std::uint32_t rxValidFlag{1U << status::RX_VALID};

/** Value written to RX_POP to drop the byte just read. */
constexpr std::uint8_t popRequest{1U};

/** ASCII representation of H, a recognizable byte value used across the cases below. */
constexpr std::uint8_t letterH{0x48U};

/** ASCII representation of A, a second recognizable byte value, distinct from letterH. */
constexpr std::uint8_t letterA{0x41U};

/** Zero (empty byte). */
constexpr std::uint8_t zero{0U};

/**
 * @brief Command byte for a register read (write bit clear).
 */
[[nodiscard]] constexpr std::uint8_t readCmd(const std::uint8_t index) noexcept { return index; }

/**
 * @brief Command byte for a register write (write bit set).
 */
[[nodiscard]] constexpr std::uint8_t writeCmd(const std::uint8_t index) noexcept
{
    constexpr std::uint8_t writeMask{0x80U};
    return static_cast<std::uint8_t>(writeMask | index);
}

/**
 * @brief Assert the exact bytes the driver put on the wire, starting at an offset.
 *
 * @param[in] stub The transport stub that recorded the transfers.
 * @param[in] offset Index of the first byte to check in the TX record.
 * @param[in] expected The bytes expected from that offset onward.
 */
void expectTxBytes(const transport::Stub& stub, const std::uint16_t offset,
                   const std::initializer_list<std::uint8_t> expected)
{
    auto index = offset;
    for (const auto byte : expected)
    {
        EXPECT_EQ(stub.txByte(index), byte);
        ++index;
    }
}

/**
 * @brief Script one register-read response into the stub.
 *
 * @note A read transaction clocks five bytes, the command byte (whose MISO reply the driver
 *       ignores) and four data bytes (MSB). So the placeholder covers the command phase, and
 *       the value supplies the four data bytes.
 *
 * @param[in,out] stub The stub to script.
 * @param[in] value The 32-bit register value the read should return.
 */
void scriptRead(transport::Stub& stub, const std::uint32_t value)
{
    // Inject command byte.
    constexpr std::uint8_t data{0U};
    stub.injectRxByte(data);

    // Inject the four data bytes, MSB first.
    stub.injectRxWord(value);
}

/**
 * @brief Queue a register value, expect it clocked back most significant byte first.
 */
TEST(TransportStub, InjectRxWordQueuesMsbFirst)
{
    constexpr std::uint8_t wordLen{4U};
    constexpr std::uint32_t value{0x12345678U};
    constexpr std::uint8_t expected[wordLen]{0x12U, 0x34U, 0x56U, 0x78U};

    transport::Stub stub{};
    stub.injectRxWord(value);

    for (const auto byte : expected)
    {
        EXPECT_EQ(stub.transfer(zero), byte);
    }

    // The script is exhausted, so every further transfer reads back zero.
    EXPECT_EQ(stub.transfer(zero), zero);
}

/**
 * @brief Consume a scripted reply, clear it, script another, expect the replay to start over.
 */
TEST(TransportStub, ClearRxDataRestartsTheScript)
{
    transport::Stub stub{};

    stub.injectRxByte(letterH);
    EXPECT_EQ(stub.transfer(zero), letterH);

    stub.clearRxData();
    stub.injectRxByte(letterA);
    EXPECT_EQ(stub.transfer(zero), letterA);
}

/**
 * @brief Record one transferred byte, expect it read back and an index past the end to read zero.
 */
TEST(TransportStub, TxRecordEndsAtTxLen)
{
    constexpr std::uint16_t expectedTxLen{1U};
    constexpr std::uint16_t firstIdx{0U};
    constexpr std::uint16_t pastEndIdx{1U};

    transport::Stub stub{};
    stub.transfer(letterH);

    EXPECT_EQ(stub.txLen(), expectedTxLen);
    EXPECT_EQ(stub.txByte(firstIdx), letterH);
    EXPECT_EQ(stub.txByte(pastEndIdx), zero);
}

/**
 * @brief Frame two transactions unevenly, expect begin() and end() counted separately.
 */
TEST(TransportStub, BeginAndEndAreCountedSeparately)
{
    constexpr std::uint16_t expectedBegins{2U};
    constexpr std::uint16_t expectedEnds{1U};

    transport::Stub stub{};
    stub.begin();
    stub.end();
    stub.begin();

    EXPECT_EQ(stub.beginCalls(), expectedBegins);
    EXPECT_EQ(stub.endCalls(), expectedEnds);
}

/**
 * @brief Configure the UART, expect BAUD_DIV then CTRL (enable) written, each MSB first.
 */
TEST(Uart, ConfigureWritesBaudThenEnable)
{
    constexpr std::uint16_t baudDiv{0x1BU};

    // CTRL value that enables the UART.
    constexpr std::uint8_t ctrlEnable{1U << ctrl::ENABLE};

    // One transaction writes BAUD_DIV, the next writes CTRL.
    constexpr std::uint16_t expectedTransactions{2U};
    constexpr std::uint16_t expectedTxLen{expectedTransactions * transactionLen};
    constexpr std::uint16_t baudDivOffset{0U};
    constexpr std::uint16_t ctrlOffset{transactionLen};

    transport::Stub stub{};
    Uart uart{stub};

    // Set baud rate to 115 200 bps.
    uart.configure(baudDiv);

    EXPECT_EQ(stub.beginCalls(), expectedTransactions);
    EXPECT_EQ(stub.endCalls(), expectedTransactions);
    EXPECT_EQ(stub.txLen(), expectedTxLen);
    expectTxBytes(stub, baudDivOffset, {writeCmd(reg::BAUD_DIV), zero, zero, zero, baudDiv});
    expectTxBytes(stub, ctrlOffset, {writeCmd(reg::CTRL), zero, zero, zero, ctrlEnable});
}

/**
 * @brief Configure the UART with a divider above 0xFF, expect BAUD_DIV written MSB first.
 */
TEST(Uart, ConfigureWritesBaudDivMsbFirst)
{
    // Divider for 9600 bps per the protocol spec, round(50e6 / (16 * 9600)) = 326 = 0x0146,
    // split into the two bytes it occupies on the wire.
    constexpr std::uint16_t baudDiv{0x0146U};
    constexpr std::uint8_t baudDivHigh{0x01U};
    constexpr std::uint8_t baudDivLow{0x46U};
    constexpr std::uint16_t baudDivOffset{0U};

    transport::Stub stub{};
    Uart uart{stub};

    // Set baud rate to 9600 bps.
    uart.configure(baudDiv);
    expectTxBytes(stub, baudDivOffset,
                  {writeCmd(reg::BAUD_DIV), zero, zero, baudDivHigh, baudDivLow});
}

/**
 * @brief Write a byte while TX is ready, expect it pushed to TX_DATA and true returned.
 */
TEST(Uart, WriteWhenReadyPushesTxData)
{
    // The STATUS read, then the TX_DATA write.
    constexpr std::uint16_t expectedTransactions{2U};
    constexpr std::uint16_t expectedTxLen{expectedTransactions * transactionLen};

    // The TX_DATA write is the last transaction.
    constexpr std::uint16_t txDataOffset{expectedTxLen - transactionLen};

    transport::Stub stub{};
    Uart uart{stub};

    // The STATUS poll reports TX ready.
    scriptRead(stub, txReadyFlag);

    EXPECT_TRUE(uart.write(letterH));
    EXPECT_EQ(stub.beginCalls(), expectedTransactions);
    EXPECT_EQ(stub.txLen(), expectedTxLen);
    expectTxBytes(stub, txDataOffset, {writeCmd(reg::TX_DATA), zero, zero, zero, letterH});
}

/**
 * @brief Write a byte while the TX FIFO is full, expect false returned and nothing written.
 */
TEST(Uart, WriteWhenFullReturnsFalseAndWritesNothing)
{
    // Only the STATUS read, since no TX_DATA write follows.
    constexpr std::uint16_t expectedTransactions{1U};
    constexpr std::uint16_t expectedTxLen{expectedTransactions * transactionLen};

    transport::Stub stub{};
    Uart uart{stub};

    // The STATUS poll reports TX_READY clear.
    scriptRead(stub, noStatusFlags);

    EXPECT_FALSE(uart.write(letterH));
    EXPECT_EQ(stub.beginCalls(), expectedTransactions);
    EXPECT_EQ(stub.txLen(), expectedTxLen);
}

/**
 * @brief Read a byte while RX is valid, expect the byte returned and a separate RX_POP issued.
 */
TEST(Uart, ReadWhenValidReturnsByteAndPops)
{
    // The STATUS read, the RX_DATA read, then the RX_POP write.
    constexpr std::uint16_t expectedTransactions{3U};
    constexpr std::uint16_t expectedTxLen{expectedTransactions * transactionLen};

    // The RX_POP write is the last transaction.
    constexpr std::uint16_t rxPopOffset{expectedTxLen - transactionLen};

    transport::Stub stub{};
    Uart uart{stub};

    // The STATUS poll reports RX valid, then RX_DATA = 'A'.
    scriptRead(stub, rxValidFlag);
    scriptRead(stub, letterA);

    std::uint8_t byte{};
    EXPECT_TRUE(uart.read(byte));
    EXPECT_EQ(byte, letterA);
    EXPECT_EQ(stub.beginCalls(), expectedTransactions);
    EXPECT_EQ(stub.txLen(), expectedTxLen);
    expectTxBytes(stub, rxPopOffset, {writeCmd(reg::RX_POP), zero, zero, zero, popRequest});
}

/**
 * @brief Read a byte while RX is empty, expect false returned and no RX_POP issued.
 */
TEST(Uart, ReadWhenEmptyReturnsFalseAndDoesNotPop)
{
    // Only the STATUS read, since no RX_DATA read and no RX_POP write follow.
    constexpr std::uint16_t expectedTransactions{1U};
    constexpr std::uint16_t expectedTxLen{expectedTransactions * transactionLen};

    // Sentinel the driver must leave untouched.
    constexpr std::uint8_t untouched{0xFFU};

    transport::Stub stub{};
    Uart uart{stub};

    // The STATUS poll reports RX_VALID clear.
    scriptRead(stub, noStatusFlags);

    std::uint8_t byte{untouched};
    EXPECT_FALSE(uart.read(byte));
    EXPECT_EQ(stub.beginCalls(), expectedTransactions);
    EXPECT_EQ(stub.txLen(), expectedTxLen);
}

/**
 * @brief Read the status, expect the STATUS register assembled most significant byte first.
 */
TEST(Uart, StatusReadsRegisterMsbFirst)
{
    // Every byte differs, so a swapped byte order shows up.
    constexpr std::uint32_t statusValue{0x12345678U};
    constexpr std::uint16_t statusOffset{0U};

    transport::Stub stub{};
    Uart uart{stub};
    scriptRead(stub, statusValue);
    EXPECT_EQ(uart.status(), statusValue);
    expectTxBytes(stub, statusOffset, {readCmd(reg::STATUS), zero, zero, zero, zero});
}

/**
 * @brief Read the error flags, expect the ERROR_FLAGS register returned.
 */
TEST(Uart, ErrorFlagsReadsRegister)
{
    // ERROR_FLAGS value reporting a single overrun.
    constexpr std::uint32_t overrunFlag{1U << error::OVERRUN};
    constexpr std::uint16_t errorFlagsOffset{0U};

    transport::Stub stub{};
    Uart uart{stub};
    scriptRead(stub, overrunFlag);
    EXPECT_EQ(uart.errorFlags(), overrunFlag);
    expectTxBytes(stub, errorFlagsOffset, {readCmd(reg::ERROR_FLAGS), zero, zero, zero, zero});
}

/**
 * @brief Clear the errors, expect zero written to ERROR_FLAGS.
 */
TEST(Uart, ClearErrorsWritesZero)
{
    // A single ERROR_FLAGS write.
    constexpr std::uint16_t expectedTransactions{1U};
    constexpr std::uint16_t expectedTxLen{expectedTransactions * transactionLen};
    constexpr std::uint16_t errorFlagsOffset{0U};

    transport::Stub stub{};
    Uart uart{stub};
    uart.clearErrors();
    EXPECT_EQ(stub.txLen(), expectedTxLen);
    expectTxBytes(stub, errorFlagsOffset, {writeCmd(reg::ERROR_FLAGS), zero, zero, zero, zero});
}

/**
 * @brief Write a byte with writeBlocking while TX starts not ready, expect it retried until pushed.
 */
TEST(UartBlocking, WriteBlockingSpinsUntilReady)
{
    // Three STATUS reads, then the TX_DATA write.
    constexpr std::uint16_t expectedTransactions{4U};
    constexpr std::uint16_t expectedTxLen{expectedTransactions * transactionLen};

    // The TX_DATA write is the last transaction.
    constexpr std::uint16_t txDataOffset{expectedTxLen - transactionLen};

    transport::Stub stub{};
    Uart uart{stub};

    // The first two STATUS polls report not-ready; the third reports TX ready.
    scriptRead(stub, noStatusFlags);
    scriptRead(stub, noStatusFlags);
    scriptRead(stub, txReadyFlag);

    writeBlocking(uart, letterH);
    EXPECT_EQ(stub.beginCalls(), expectedTransactions);
    EXPECT_EQ(stub.txLen(), expectedTxLen);
    expectTxBytes(stub, txDataOffset, {writeCmd(reg::TX_DATA), zero, zero, zero, letterH});
}

/**
 * @brief Read a byte with readBlocking while RX starts empty, expect it retried until the byte
 *        arrives.
 */
TEST(UartBlocking, ReadBlockingSpinsUntilValid)
{
    // Three STATUS reads, the RX_DATA read, then the RX_POP write.
    constexpr std::uint16_t expectedTransactions{5U};
    constexpr std::uint16_t expectedTxLen{expectedTransactions * transactionLen};

    // The RX_POP write is the last transaction.
    constexpr std::uint16_t rxPopOffset{expectedTxLen - transactionLen};

    transport::Stub stub{};
    Uart uart{stub};

    // The first two STATUS polls report no data; the third reports RX valid, then RX_DATA follows.
    scriptRead(stub, noStatusFlags);
    scriptRead(stub, noStatusFlags);
    scriptRead(stub, rxValidFlag);
    scriptRead(stub, letterA);

    std::uint8_t byte{};
    readBlocking(uart, byte);

    EXPECT_EQ(byte, letterA);
    EXPECT_EQ(stub.beginCalls(), expectedTransactions);
    EXPECT_EQ(stub.txLen(), expectedTxLen);
    expectTxBytes(stub, rxPopOffset, {writeCmd(reg::RX_POP), zero, zero, zero, popRequest});
}
} // namespace
} // namespace driver::uart::test

#endif // __has_include("driver/transport/stub.hpp") && ...
#endif // __has_include("driver/uart/register_map.hpp") && ...

/**
 * @brief Run all test cases.
 *
 * @return 0 on success, or -1 on failure.
 */
int main() { return qacademy::test::runAllTests() ? 0 : -1; }
