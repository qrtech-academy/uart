/**
 * @file Host tests for app::EchoNode over a UART stub driver.
 *
 *       The UART stub driver sets the shared stop flag once its input is exhausted, so run()
 *       echoes every queued byte and then returns.
 */
#include <cstdint>

#include "qacademy/test/test.hpp"

// EchoNode is written in L10 over the UART stub from L06, so this suite compiles to nothing until
// both exist. Guarding on app/echo_node.hpp is also what keeps the link honest: the header and
// source/app/echo_node.cpp arrive together, so a present header means the definitions exist too.
#if __has_include("app/echo_node.hpp") && __has_include("driver/uart/stub.hpp")

#include "app/echo_node.hpp"
#include "driver/uart/stub.hpp"

using namespace driver;

namespace app
{
namespace
{
/**
 * @brief Queue several bytes, run the node.
 *
 *        Expect every byte echoed back in order before it stops.
 */
TEST(EchoNode, EchoesQueuedBytesThenStops)
{
    constexpr uint8_t rxLen{3U};
    constexpr uint8_t rxBuf[rxLen]{0x00U, 0x41U, 0xFFU};

    bool stop{false};
    uart::Stub uart{stop};
    EchoNode node{uart};

    for (const auto byte : rxBuf)
    {
        uart.injectRxByte(byte);
    }
    // Stop flag will be set by the UART stub.
    node.run(stop);

    EXPECT_EQ(uart.txLen(), rxLen);

    for (std::uint8_t i{}; (i < rxLen) && (i < uart.txLen()); ++i)
    {
        EXPECT_EQ(uart.txBuf()[i], rxBuf[i]);
    }
}
} // namespace
} // namespace app

#endif // __has_include(...)
