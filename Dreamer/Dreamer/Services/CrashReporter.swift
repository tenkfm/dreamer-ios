import Foundation
import Sentry

/// Crashes and non-fatal errors. Reports carry codes, tags and the anonymous user id only:
/// never dream texts, notes, email or names.
protocol CrashReporter: Sendable {
    /// `code` is a stable error code (for example an API error code) used to group reports.
    func recordNonFatal(_ error: any Error, code: String?, context: [String: String])
    /// Backend user id after sign-in, nil after sign-out. Never an email or a name.
    func setUserID(_ id: String?)
}

struct NoopCrashReporter: CrashReporter {
    func recordNonFatal(_ error: any Error, code: String?, context: [String: String]) {}
    func setUserID(_ id: String?) {}
}

/// Sentry-backed reporter. Nil when the configuration has no DSN.
final class SentryCrashReporter: CrashReporter {
    init?(config: AppConfig) {
        guard let dsn = config.sentryDSN else { return nil }
        SentrySDK.start { options in
            options.dsn = dsn
            options.environment = config.environment.rawValue
            // Privacy: screens and view hierarchies show dream texts, request URLs carry search
            // queries, and the IP address identifies the user - none of it leaves the device.
            options.sendDefaultPii = false
            options.attachScreenshot = false
            options.attachViewHierarchy = false
            options.enableNetworkBreadcrumbs = false
            options.enableCaptureFailedRequests = false
            options.tracesSampleRate = 0
            options.beforeSend = { event in
                event.request = nil
                event.user?.ipAddress = nil
                event.user?.email = nil
                event.user?.username = nil
                return event
            }
        }
    }

    func recordNonFatal(_ error: any Error, code: String?, context: [String: String]) {
        SentrySDK.capture(error: error) { scope in
            if let code { scope.setTag(value: code, key: "error_code") }
            for (key, value) in context { scope.setTag(value: value, key: key) }
        }
    }

    func setUserID(_ id: String?) {
        SentrySDK.setUser(id.map { User(userId: $0) })
    }
}

enum CrashReporting {
    /// Starts crash reporting as early as possible in the launch.
    static func makeReporter(config: AppConfig) -> any CrashReporter {
        let reporter: any CrashReporter = SentryCrashReporter(config: config) ?? NoopCrashReporter()
        #if DEBUG || STAGING
        runTestTriggers(reporter: reporter)
        #endif
        return reporter
    }

    #if DEBUG || STAGING
    /// `-crashTestNonFatal` sends a test error, `-crashTestCrash` crashes on purpose, to check
    /// symbolication in the console. Not compiled into App Store builds.
    private static func runTestTriggers(reporter: any CrashReporter) {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-crashTestNonFatal") {
            reporter.recordNonFatal(CrashTestError(), code: "CRASH_TEST", context: ["source": "launch_argument"])
        }
        if arguments.contains("-crashTestCrash") {
            SentrySDK.crash()
        }
    }

    private struct CrashTestError: LocalizedError {
        var errorDescription: String? { "Crash reporting test" }
    }
    #endif
}
