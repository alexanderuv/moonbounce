// Retired-instruction counts, from the operating system's per-process (macOS)
// or per-thread (Linux) counters. Windows has none without a kernel driver.
//
// A read that fails, or on Linux one that missed part of the thread's run
// time, marks the count unreliable for the rest of the run and returns the
// last good value, so the count never goes backwards.

#include "CounterShims.h"

#if defined(__APPLE__) || defined(__linux__)

static bool reliable = true;
static uint64_t last_count = 0;

bool instruction_count_is_reliable(void) { return reliable; }

#endif

#if defined(__APPLE__)

#include <libproc.h>
#include <sys/resource.h>
#include <unistd.h>

uint64_t instruction_count(void) {
    struct rusage_info_v4 info;
    if (proc_pid_rusage(getpid(), RUSAGE_INFO_V4, (rusage_info_t *)&info) != 0) {
        reliable = false;
        return last_count;
    }
    last_count = info.ri_instructions;
    return last_count;
}

// A virtual machine without the counter reports 0.
bool start_instruction_count(void) { return instruction_count() != 0; }

#elif defined(__linux__)

#include <linux/perf_event.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>

static int counter = -1;

bool start_instruction_count(void) {
    struct perf_event_attr attributes;
    memset(&attributes, 0, sizeof attributes);
    attributes.type = PERF_TYPE_HARDWARE;
    attributes.size = sizeof attributes;
    attributes.config = PERF_COUNT_HW_INSTRUCTIONS;
    attributes.exclude_kernel = 1;
    attributes.exclude_hv = 1;
    // How long the event was enabled and how long it actually counted. They
    // differ when the kernel shares the counter with other events, or when
    // the thread ran on a core type whose counter this event isn't on, as on
    // a CPU that mixes core types.
    attributes.read_format = PERF_FORMAT_TOTAL_TIME_ENABLED | PERF_FORMAT_TOTAL_TIME_RUNNING;
    // This thread, on whichever CPU it runs.
    counter = (int)syscall(SYS_perf_event_open, &attributes, 0, -1, -1, 0);
    return counter >= 0;
}

uint64_t instruction_count(void) {
    struct {
        uint64_t value;
        uint64_t time_enabled;
        uint64_t time_running;
    } sample;
    if (counter < 0 || read(counter, &sample, sizeof sample) != sizeof sample
        || sample.time_running != sample.time_enabled) {
        reliable = false;
        return last_count;
    }
    last_count = sample.value;
    return last_count;
}

#else

bool start_instruction_count(void) { return false; }

uint64_t instruction_count(void) { return 0; }

bool instruction_count_is_reliable(void) { return false; }

#endif
