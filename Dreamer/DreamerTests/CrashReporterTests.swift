import Testing
@testable import Dreamer

struct CrashReporterTests {
    @Test func withoutDSNReportingIsOff() {
        #expect(SentryCrashReporter(config: AppConfig(infoDictionary: [:])) == nil)
        #expect(CrashReporting.makeReporter(config: AppConfig(infoDictionary: [:])) is NoopCrashReporter)
    }
}
