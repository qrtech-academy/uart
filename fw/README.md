# Firmware (C++)
The software half of the course. Host-testable code is developed and verified on your machine
first (L05-L06); only the thin transport at the bottom is AVR-specific (L07). The unit- and
component-testing approach uses QAcademy Test: a scripted transport stub and dependency
injection.

## Planned layout

```text
include/driver/uart/        The register map, driver::uart::Interface (L05), and this course's
                            driver::uart::Uart (L06).
include/driver/transport/   The transport seam driver::transport::Interface (L05), the scripted
                            driver::transport::Stub used by the host tests (L06), and the real
                            driver::transport::AvrSpi (L07); AvrSpi's source is in
                            source/driver/transport/.
include/app/                The application seam app::Interface, and app::EchoNode (L08).
include/arch/               Hardware access: arch/avr/hw_platform.hpp for the target, and arch/test/
                            for the mocked AVR register file the host tests run against.
source/                     Implementations: the driver::uart::Uart protocol layer (readReg/writeReg
                            as 5-byte SPI transactions), app::EchoNode (L08), and a provided demo
                            main (L06), plus the driver::transport::AvrSpi source (L07) - the
                            AVR-register code the host app build skips, compiled for the target
                            and, against the mock, for the tests.
test/                       Host tests (QAcademy Test) exercising the driver over the stub, with no
                            hardware (L06-L08). Each suite is the executable specification of the
                            register protocol.
avr/                        The ATmega328P port: the freestanding C++ runtime stubs (env.cpp), the
                            avr-gcc Makefile, and the main for the EchoNode demo (L07-L08).
                            AVR-only; the host build never compiles this directory.
```

Each directory with a Makefile is built by CI's `build-cpp` and, if it defines a `test` target,
tested. The build stays green through the early lectures by file existence rather than by
conditional compilation: `make build` reports there is nothing to do until `source/main.cpp` exists,
and `make test` does the same until both a suite and the headers it exercises are present. The
suites themselves are provided from the start, so the gate that actually holds the early lectures
open is the second one: `test` reports there is nothing to do until the L06 driver headers
(`driver/uart/uart.hpp`, `blocking.hpp`, `register_map.hpp`, `driver/transport/stub.hpp`) exist. Add
the files a lecture asks for and the corresponding target starts doing real work.

Host builds use g++ and run in CI. The `avr/` build cross-compiles with avr-gcc and is flashed
with avrdude (see [`info/README.md`](../info/README.md)); it is excluded from host CI.

Three things worth knowing before L07:
* The AVR target is **freestanding**: no C++ standard library at all, no exceptions, no RTTI, no
  iostreams, and no `operator new`/`operator delete`. `Interface`, `Stub`, and `Uart` carry over
  untouched because they were written to that subset from L05; everything is reference-injected into
  static storage, so nothing needs reworking for the target.
* avr-libc ships no C++ runtime, so `avr/env.cpp` hand-defines the few symbols the compiler emits
  for ordinary C++: both the sized and unsized `operator delete`, `__cxa_pure_virtual` (named by
  every abstract class's vtable), and the `__cxa_guard_*` trio that guards function-local statics.
  It lives in `avr/`, not `source/`, precisely so the host build keeps libstdc++'s (thread-safe)
  versions instead of these.
* The AVR's own SPI registers (`SPCR`/`SPSR`/`SPDR`) are real memory-mapped `volatile` hardware -
  the `volatile` lesson from Modern Embedded C++ applies verbatim, on the master side of the wire
  this time.

---

