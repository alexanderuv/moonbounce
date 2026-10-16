// Retired-instruction counts, from the operating system's per-process (macOS)
// or per-thread (Linux) counters. Windows has none without a kernel driver.

#include "CounterShims.h"

#if defined(__APPLE__)

#include <libproc.h>
#include <sys/resource.h>
#include <unistd.h>

uint64_t instruction_count(void) {
    struct rusage_info_v4 info;
    if (proc_pid_rusage(getpid(), RUSAGE_INFO_V4, (rusage_info_t *)&info) != 0) {
        return 0;
    }
    return info.ri_instructions;
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
    // This thread, on whichever CPU it runs.
    counter = (int)syscall(SYS_perf_event_open, &attributes, 0, -1, -1, 0);
    return counter >= 0;
}

uint64_t instruction_count(void) {
    uint64_t count = 0;
    if (counter < 0 || read(counter, &count, sizeof count) != sizeof count) {
        return 0;
    }
    return count;
}

#else

bool start_instruction_count(void) { return false; }

uint64_t instruction_count(void) { return 0; }

#endif
