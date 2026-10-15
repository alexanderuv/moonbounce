#if os(Windows)
import WinSDK

/// The Windows clocks and thread settings the runner measures with.
///
/// Windows has no retired-instruction counter without a kernel driver, so
/// thread cycles stand in for instructions.
enum Counters {
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

    /// Cycles the calling thread has run for, from `QueryThreadCycleTime`.
    /// Windows counts them with the time-stamp counter, which ticks at a fixed
    /// rate, so they measure the thread's CPU time rather than core clock
    /// cycles: unlike wall time, they leave out any time the thread was not
    /// running.
    @inline(__always)
    static func threadCycles() -> UInt64 {
        var cycles: ULONG64 = 0
        QueryThreadCycleTime(GetCurrentThread(), &cycles)
        return cycles
    }

    /// `duration` in `QueryPerformanceCounter` ticks.
    static func ticks(_ duration: Duration) -> Int64 {
        let (seconds, attoseconds) = duration.components
        return Int64((Double(seconds) + Double(attoseconds) / 1e18) * Double(ticksPerSecond))
    }

    /// Nanoseconds in `ticks` `QueryPerformanceCounter` ticks.
    static func nanoseconds(_ ticks: Double) -> Double {
        ticks * 1e9 / Double(ticksPerSecond)
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
}
#endif
