# Host build of the UART C++ driver and its tests.
#
# Two products: the host application (source/, an optional demo with its own main), and one test
# binary linking the QAcademy Test framework (libs/test, a submodule). Both are guarded so this
# Makefile can sit in place before any C++ exists: `make build` and `make test` report that there
# is nothing to do rather than failing, keeping CI green until the driver arrives.
#
# The AVR port lives in fw/avr with its own avr-gcc Makefile and is not built here.

# Products.
TARGET      := uart_firmware
TEST_TARGET := uart_test

# Host compiler and flags.
CXX      := g++
CXXFLAGS := -Wall -Wextra -Werror -std=c++17 -Iinclude

# QAcademy Test framework (repository submodule at libs/test). Only the test build defines HOST_TEST,
# so the platform header selects the mock register file there and the real <avr/io.h> everywhere
# else. The guard is HOST_TEST, not TEST, because the framework already defines TEST as a macro.
TEST_DIR   := ../libs/test
TEST_FLAGS := $(CXXFLAGS) -DHOST_TEST -I$(TEST_DIR)/include

# Sources (found recursively, so source/driver/uart/*.cpp is picked up). AVR_SRC reaches hardware
# registers through arch/avr/hw_platform.hpp, so it only compiles for the AVR target or, under
# -DHOST_TEST, against the mock; the host app build (g++, no HOST_TEST) skips it, while the test
# build links it. TESTED_SRC is everything the tests link except the application's own main().
AVR_SRC    := source/driver/transport/avr_spi.cpp
ALL_SRC    := $(shell find source -name '*.cpp' 2>/dev/null)
APP_SRC    := $(filter-out $(AVR_SRC),$(ALL_SRC))
TESTED_SRC := $(filter-out source/main.cpp,$(ALL_SRC))
TEST_SRC   := $(shell find test -name '*.cpp' 2>/dev/null)

# Headers the L08 suite needs, and whichever of them are still missing. Each suite already guards
# its own body with #if __has_include(...), so a suite whose code has not been written yet compiles
# to nothing on its own. What that cannot cover is *every* suite being empty: runAllTests() reports
# failure on an empty registry, so a test binary with no cases in it fails the build. The L08 suite
# is the first to have any, so until its headers exist there is no binary worth linking.
UART_TEST_DEPS := include/driver/transport/stub.hpp include/driver/uart/blocking.hpp \
                  include/driver/uart/register_map.hpp include/driver/uart/uart.hpp
MISSING_DEPS   := $(filter-out $(wildcard $(UART_TEST_DEPS)),$(UART_TEST_DEPS))

# Wall-clock ceiling for one run of the suite. Every case finishes in milliseconds, so this only
# fires on a genuine hang, and a hang is the failure this suite is most likely to produce:
# writeBlocking() and readBlocking() spin until the transport reports ready, so a driver or a
# scripted stub that never reports it loops forever, taking the terminal (and CI) with it instead
# of going red. Same guard, and the same reasoning, as the timeout around ghdl -r in
# ci/build_vhdl.sh.
TEST_TIMEOUT_S ?= 60

default: build

# Build the host application, if it has an entry point yet.
#
# The guards below are make conditionals rather than shell `if` blocks inside a single recipe line.
# That matters: a recipe line containing $(MAKE) is executed even under `make -n`, so folding the
# whole test recipe into one continued line made a dry run build and run the suite for real.
ifeq ($(wildcard source/main.cpp),)
build:
	@echo "fw: no source/main.cpp yet; nothing to build."
else
build:
	@$(CXX) $(APP_SRC) -o $(TARGET) $(CXXFLAGS)
	@echo "fw: built $(TARGET)."
endif

# Build and run the host tests, if any exist. Each test binary provides its own main() that calls
# qacademy::test::runAllTests(); the framework library supplies only the registry and assertions.
#
# Two guards, both by file existence: no suites yet, or no code for the first suite to exercise.
# Either way `make test` reports there is nothing to do rather than failing, the same rule
# ci/build_vhdl.sh applies to a testbench whose modules have not been written yet.
ifeq ($(strip $(TEST_SRC)),)
test:
	@echo "fw: no test/*.cpp yet; nothing to test."
else ifneq ($(strip $(MISSING_DEPS)),)
test:
	@echo "fw: no $(MISSING_DEPS) yet; nothing to test."
else
test:
	@$(MAKE) --no-print-directory -C $(TEST_DIR) lib
	@$(CXX) $(TEST_SRC) $(TESTED_SRC) -o $(TEST_TARGET) $(TEST_FLAGS) -L$(TEST_DIR) -lqacademy_test
	@timeout $(TEST_TIMEOUT_S) stdbuf -oL -eL ./$(TEST_TARGET) || { \
	  status=$$?; \
	  if [ $$status -eq 124 ]; then \
	    echo "ERROR: $(TEST_TARGET) did not finish within $(TEST_TIMEOUT_S)s and was killed." >&2; \
	    echo "       A suite that hangs is usually spinning in writeBlocking() or readBlocking()," >&2; \
	    echo "       waiting on a status bit the driver or the transport stub never reports. Each" >&2; \
	    echo "       case is printed once it completes, so the one that hung is the case *after*" >&2; \
	    echo "       the last line printed above." >&2; \
	  fi; \
	  exit $$status; }
endif

# Remove this course's host binaries (the framework cleans its own library).
clean:
	@rm -f $(TARGET) $(TEST_TARGET)

.PHONY: default build test clean
