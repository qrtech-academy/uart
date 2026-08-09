/**
 * @file Hardware platform for AVR devices.
 */
#pragma once

#ifndef HOST_TEST
#include <avr/io.h>

/** When compiling for the test suite, include test hardware platform header instead. */
#else
#include "arch/test/hw_platform.hpp"
#endif /** HOST_TEST */

/** SPI bit positions (on I/O port B). */
#ifndef SCK
#define SCK 5U // SPI clock.
#endif

#ifndef MOSI
#define MOSI 3U // Master Out Slave In.
#endif

#ifndef MISO
#define MISO 4U // Master In Slave Out.
#endif

#ifndef SS
#define SS 2U // SPI Chip Select.
#endif
