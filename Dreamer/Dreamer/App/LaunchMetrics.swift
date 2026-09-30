#if DEBUG || STAGING
import Darwin
import Foundation
import os

/// Debug and Staging builds: time from process start to the first frame of the root view, in the unified log
/// (`log show --predicate 'category == "launch"'`), to compare cold starts before and after a change.
enum LaunchMetrics {
    private static let log = Logger(subsystem: "com.braincode.dreamer.io", category: "launch")
    private static let reported = OSAllocatedUnfairLock(initialState: false)

    static func firstFrameShown() {
        guard !reported.withLock({ done in defer { done = true }; return done }), let start = processStart() else { return }
        let milliseconds = Int(Date.now.timeIntervalSince(start) * 1000)
        log.notice("first frame after \(milliseconds, privacy: .public) ms")
    }

    private static func processStart() -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }
}
#endif
