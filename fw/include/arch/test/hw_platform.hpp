/**
 * @file Test hardware platform for AVR devices.
 */
#pragma once

#ifdef HOST_TEST

#include <cstdint>

#include "arch/test/regs.hpp"
#include "arch/test/spdr_proxy.hpp"
#include "arch/test/spi_bus.hpp"
#include "arch/test/spsr_proxy.hpp"

namespace test
{
/** SPI bus instance. */
inline SpiBus spiBus{};

/** SPDR proxy instance. */
inline SpdrProxy spdr{spiBus};

/** SPSR proxy instance. */
inline SpsrProxy spsr{spiBus};

} // namespace test

/** Data bytes. */
#define SPDR (test::spdr)

/** Status register. Reading it completes an in-flight transfer; see spsr_proxy.hpp. */
#define SPSR (test::spsr)

#endif /** HOST_TEST */