// The counters BenchmarkRunner reads that Swift can't reach on its own: the
// allocation count, kept by replacing the C allocator's entry points, and
// retired instructions, which Linux exposes only through a system call that
// Swift can't make.

#ifndef BENCHMARKS_COUNTER_SHIMS_H
#define BENCHMARKS_COUNTER_SHIMS_H

#include <stdbool.h>
#include <stdint.h>

/// True on macOS and Linux. Windows' C runtime allocator can't be replaced
/// from a program, so it counts no allocations.
bool allocations_are_counted(void);

/// Allocations made so far, by every thread, through the C allocator. The
/// Swift runtime allocates there, so this counts Swift's heap allocations too.
/// Always 0 where `allocations_are_counted()` is false.
uint64_t allocation_count(void);

/// Starts counting retired user-space instructions. Returns false where they
/// can't be counted: on Windows, and wherever the machine doesn't expose them,
/// such as a Linux kernel with `perf_event_paranoid` above 2 or a virtual
/// machine without a hardware performance counter. On Linux it counts the
/// calling thread only, so call it from the thread that measures.
bool start_instruction_count(void);

/// Retired user-space instructions so far: the whole process's on macOS, the
/// thread that called `start_instruction_count()` on Linux.
uint64_t instruction_count(void);

#endif
