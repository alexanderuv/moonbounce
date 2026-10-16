import CounterShims

#if os(macOS)
import Darwin
#elseif os(Linux)
import Glibc
#elseif os(Windows)
import WinSDK
#endif

/// The clocks and counters the runner measures with, and the thread settings
/// it measures under, on each platform.
///
/// The counter is retired instructions where the operating system exposes
/// them, macOS and Linux. Windows has no retired-instruction counter without a
/// kernel driver, so thread cycles stand in for instructions there.
/// Allocations are counted separately, by `CounterShims`.
enum Counters {
    #if os(macOS) || os(Linux)

    /// What `counter()` counts.
    static let counterName = "instructions"

    /// `ticks()` per second: the clocks below read nanoseconds.
    static let ticksPerSecond: Int64 = 1_000_000_000

    /// Wall time, in nanoseconds, from a clock that neither steps nor slews:
    /// `CLOCK_UPTIME_RAW` on macOS, `CLOCK_MONOTONIC_RAW` on Linux.
    @inline(__always)
    static func ticks() -> Int64 {
        #if os(macOS)
        Int64(clock_gettime_nsec_np(CLOCK_UPTIME_RAW))
        #else
        var now = timespec()
        clock_gettime(CLOCK_MONOTONIC_RAW, &now)
        return Int64(now.tv_sec) * 1_000_000_000 + Int64(now.tv_nsec)
        #endif
    }

    /// Starts the counter on the calling thread. Returns false when the
    /// machine doesn't expose it.
    static func startCounter() -> Bool {
        start_instruction_count()
    }

    /// Retired user-space instructions (see `instruction_count()`).
    @inline(__always)
    static func counter() -> UInt64 {
        instruction_count()
    }

    /// Asks the scheduler to prefer performance cores for the calling thread.
    /// On Apple silicon, user-interactive QoS does that; at the default QoS,
    /// the thread runs on efficiency cores too, which can make a run look 2–3×
    /// slower with an unchanged instruction count. Linux has no unprivileged
    /// equivalent, so there the thread keeps its default scheduling.
    static func keepOnPerformanceCores() -> Bool {
        #if os(macOS)
        pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0) == 0
        #else
        true
        #endif
    }

    #elseif os(Windows)

    /// What `counter()` counts.
    static let counterName = "cycles"

    /// `QueryPerformanceCounter` ticks per second.
    static let ticksPerSecond: Int64 = {
        var frequency = LARGE_INTEGER()
        QueryPerformanceFrequency(&frequency)
        return frequency.QuadPart
    }()

    /// Wall time, in `QueryPerformanceCounter` ticks.
    @inline(__always)
    static func ticks() -> Int64 {
        var now = LARGE_INTEGER()
        QueryPerformanceCounter(&now)
        return now.QuadPart
    }

    /// Thread cycles need no setup.
    static func startCounter() -> Bool {
        true
    }

    /// Cycles the calling thread has run for, from `QueryThreadCycleTime`.
    /// Windows counts them with the time-stamp counter, which ticks at a fixed
    /// rate, so they measure the thread's CPU time rather than core clock
    /// cycles: unlike wall time, they leave out any time the thread was not
    /// running.
    @inline(__always)
    static func counter() -> UInt64 {
        var cycles: ULONG64 = 0
        QueryThreadCycleTime(GetCurrentThread(), &cycles)
        return cycles
    }

    /// Asks Windows to prefer performance cores for the calling thread, with
    /// the highest priority in the process's class and execution-speed
    /// throttling off. On a hybrid CPU, Windows schedules a thread it may
    /// throttle on efficiency cores too, which can make a run several times
    /// slower. Returns whether Windows accepted both settings.
    static func keepOnPerformanceCores() -> Bool {
        let thread = GetCurrentThread()
        guard SetThreadPriority(thread, THREAD_PRIORITY_HIGHEST) else { return false }
        // Controlling execution speed with its state bit clear turns the
        // throttling off.
        var state = THREAD_POWER_THROTTLING_STATE(
            Version: ULONG(THREAD_POWER_THROTTLING_CURRENT_VERSION),
            ControlMask: ULONG(THREAD_POWER_THROTTLING_EXECUTION_SPEED),
            StateMask: 0
        )
        return SetThreadInformation(
            thread,
            ThreadPowerThrottling,
            &state,
            DWORD(MemoryLayout<THREAD_POWER_THROTTLING_STATE>.size)
        )
    }

    #else
    #error("BenchmarkRunner has no clocks or counters for this platform")
    #endif

    /// `duration` in `ticks()` ticks.
    static func ticks(_ duration: Duration) -> Int64 {
        let (seconds, attoseconds) = duration.components
        return Int64((Double(seconds) + Double(attoseconds) / 1e18) * Double(ticksPerSecond))
    }

    /// Nanoseconds in `ticks` `ticks()` ticks.
    static func nanoseconds(_ ticks: Double) -> Double {
        ticks * 1e9 / Double(ticksPerSecond)
    }
}
