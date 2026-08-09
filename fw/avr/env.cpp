// -----------------------------------------------------------------------------
// Freestanding C++ runtime support for the ATmega328P build.
//
// avr-libc ships no C++ runtime, so a few symbols the compiler emits for
// ordinary C++ have to be provided by hand or the link fails. This file
// supplies them.
//
// It is AVR-only. On the host build, libstdc++ already defines these, so this
// file must NOT live under source/ (which the host Makefile compiles): keeping
// it here in avr/ keeps it out of the g++ link, and avoids replacing the host's
// thread-safe static guards with the single-threaded versions below.
//
//   operator delete(void*)          a virtual destructor's vtable references the
//   operator delete(void*, size)    deleting operator delete even when nothing
//                                   ever deletes through a base pointer. Both
//                                   forms are needed: C++14 onwards the compiler
//                                   calls the sized form, but it requires the
//                                   unsized one to exist alongside it, and only
//                                   the unsized one is emitted under
//                                   -fno-sized-deallocation. On AVR size_t is
//                                   unsigned int (16-bit).
//   __cxa_pure_virtual              called if a pure virtual is ever invoked;
//                                   every abstract class' vtable names it.
//   __cxa_guard_acquire/release/    guard a function-local static's one-time
//   __cxa_guard_abort               initialization. Single-threaded is all a
//                                   bare-metal target needs.
// -----------------------------------------------------------------------------

void operator delete(void*) noexcept {}
void operator delete(void*, unsigned int) noexcept {}

extern "C" void __cxa_pure_virtual() {}

extern "C" int __cxa_guard_acquire(volatile void* g) { return !*(char*)g; }
extern "C" void __cxa_guard_release(volatile void* g) { *(char*)g = 1; }
extern "C" void __cxa_guard_abort(volatile void*) {}
