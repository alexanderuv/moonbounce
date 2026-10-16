// The counters BenchmarkRunner reads that Swift can't reach on its own: the
// allocation count, kept by replacing the C allocator's entry points, and
// retired instructions, which Linux exposes only through a system call that
// Swift can't make.

#ifndef BENCHMARKS_COUNTER_SHIMS_H
#define BENCHMARKS_COUNTER_SHIMS_H

#include <stdbool.h>
#include <stdint.h>

/// True on macOS and on Linux with glibc. Windows' C runtime allocator can't
/// be replaced from a program, and other C libraries don't export their
/// allocator under a second name to forward to, so those count no allocations.
bool allocations_are_counted(void);

/// Allocations made so far, by every thread, through the C allocator. The
/// Swift runtime allocates there, so this counts Swift's heap allocations too.
/// Always 0 where `allocations_are_counted()` is false.
uint64_t allocation_count(void);

/// Starts counting retired instructions. Returns false where they can't be
/// counted: on Windows, and wherever the machine doesn't expose them, such as
/// a Linux kernel with `perf_event_paranoid` above 2 or a virtual machine
/// without a hardware performance counter. On Linux it counts the calling
/// thread only, so call it from the thread that measures.
bool start_instruction_count(void);

/// Retired instructions so far. The two platforms count different things:
/// - macOS: the whole process's, from `proc_pid_rusage`, kernel instructions
///   included, so a system call, page fault or interrupt adds to it. Each read
///   is itself a system call, and a measurement's two reads add about 6,000
///   instructions to it. The Jolt harness reads the same way, so comparisons
///   between the two stay even.
/// - Linux: the thread that called `start_instruction_count()`, in user space
///   only.
uint64_t instruction_count(void);

/// False once a read has failed, or on Linux once the counter ran for less
/// time than the thread did. The count is then incomplete and should be
/// reported as missing.
bool instruction_count_is_reliable(void);

#endif
