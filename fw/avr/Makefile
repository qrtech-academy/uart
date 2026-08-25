# Cross build of the UART firmware for the ATmega328P (Arduino Nano).
#
# This is the target build. The host build lives one directory up in fw/Makefile and shares
# every source under source/; only main.cpp and the runtime stubs in env.cpp are AVR-specific.
#
# Like the rest of the repository, this Makefile is written to sit in place before the code it
# builds exists: with no avr/main.cpp yet, `make build` reports that there is nothing to do rather
# than failing, so CI stays green from L01 through L08 and only starts building in L09.
#
# Usage:
#   make build     compile and link, then report flash and RAM use
#   make flash     build, then program the Nano over its USB bootloader
#   make clean     remove the build products

# Target device. F_CPU is the Nano's 16 MHz crystal, and is read by <util/delay.h> and by the
# UBRR0 divider for the debug USART.
MCU    := atmega328p
F_CPU  := 16000000UL

# Programmer. The Nano's USB bootloader appears as a USB-serial port. PORT and BAUD are overridable
# because they vary by board revision and by machine:
#
#   make flash PORT=/dev/ttyACM0            a Nano that enumerates as ACM rather than USB
#   make flash BAUD=115200                  a newer bootloader (older clones need 57600)
#
# On WSL the port must first be attached from Windows with usbipd, since WSL does not see USB
# devices by default.
PROGRAMMER := arduino
PORT       := /dev/ttyUSB0
BAUD       := 57600

# Toolchain.
CXX     := avr-g++
OBJCOPY := avr-objcopy
SIZE    := avr-size
AVRDUDE := avrdude

# Compiler flags.
#
# The driver is deliberately written to a conservative subset: it compiles unchanged at -std=c++11,
# c++14 and c++17. c++14 is what this build asks for because every avr-gcc in circulation accepts
# it, whereas -std=c++17 is not a recognized option before GCC 8 and so fails outright on the
# toolchain Microchip Studio ships. Nothing here needs a C++17 feature: in particular the register
# map uses plain `constexpr` constants, not C++17 inline variables.
#
# -fno-threadsafe-statics drops the __cxa_guard_* calls a function-local static would otherwise
# emit; env.cpp defines them anyway so the link succeeds either way.
CXXFLAGS := -std=c++14 -mmcu=$(MCU) -DF_CPU=$(F_CPU) -Os -Wall -Wextra -Werror \
            -ffunction-sections -fdata-sections \
            -fno-exceptions -fno-rtti -fno-threadsafe-statics \
            -I../include

# Linker flags. --gc-sections discards the sections the flags above split out, which matters on a
# 32 KB part once virtual dispatch pulls in vtables.
LDFLAGS := -mmcu=$(MCU) -Os -Wl,--gc-sections

# Products.
TARGET := uart_firmware

# Sources. The driver, the transport and the application come from the shared tree; main.cpp and
# env.cpp are the two AVR-only files. source/main.cpp is deliberately excluded: that is the host
# demo's entry point, and this build has its own.
SHARED_SRC := $(shell find ../source -name '*.cpp' ! -name 'main.cpp' 2>/dev/null)
AVR_SRC    := $(wildcard main.cpp) env.cpp
SRC        := $(AVR_SRC) $(SHARED_SRC)

default: build

ifeq ($(wildcard main.cpp),)
build:
	@echo "fw/avr: no main.cpp yet; nothing to build."

flash:
	@echo "fw/avr: no main.cpp yet; nothing to flash."
else
build: $(TARGET).hex

$(TARGET).elf: $(SRC)
	@$(CXX) $(CXXFLAGS) $(SRC) -o $@ $(LDFLAGS)
	@echo "fw/avr: built $@."
	@$(SIZE) --mcu=$(MCU) --format=avr $@

$(TARGET).hex: $(TARGET).elf
	@$(OBJCOPY) -O ihex -R .eeprom $< $@

# Program the part. -D suppresses the chip erase the bootloader performs anyway.
flash: $(TARGET).hex
	$(AVRDUDE) -c $(PROGRAMMER) -p $(MCU) -P $(PORT) -b $(BAUD) -D -U flash:w:$(TARGET).hex:i
endif

clean:
	@rm -f $(TARGET).elf $(TARGET).hex

.PHONY: default build flash clean
