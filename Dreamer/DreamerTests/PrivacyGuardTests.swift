import Foundation
import Testing
@testable import Dreamer

/// Guards against personal data leaking through logs, caches or plain HTTP.
struct PrivacyGuardTests {
    /// The app's Swift sources.
    private static var sources: [(name: String, text: String)] {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "Dreamer")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        return files.compactMap { url in (try? String(contentsOf: url, encoding: .utf8)).map { (url.lastPathComponent, $0) } }
    }

    @Test func nothingIsPrintedToTheDeviceLog() throws {
        // A call, not a name ending in "print" (setFingerprint): start of line, space or bracket before it.
        let printCall = try Regex(#"(^|[\s({\[;,=])(print|debugPrint)\("#).anchorsMatchLineEndings()
        for source in Self.sources {
            #expect(source.text.firstMatch(of: printCall) == nil, "\(source.name) prints")
            #expect(!source.text.contains("NSLog("), "\(source.name) uses NSLog")
            #expect(!source.text.contains("os_log("), "\(source.name) uses os_log")
        }
    }

    /// Every interpolated value in a Logger message says whether it may show (only enums and codes).
    @Test func loggerInterpolationsAreMarked() throws {
        let call = try Regex(#"\.(debug|info|notice|error|warning|fault|log)\("([^"]*)"\)"#)
        for source in Self.sources where source.text.contains("Logger(") {
            for match in source.text.matches(of: call) {
                let message = String(source.text[match.range])
                let interpolations = message.components(separatedBy: #"\("#).count - 1
                let marked = message.components(separatedBy: "privacy:").count - 1
                #expect(interpolations == marked, "\(source.name): \(message)")
            }
        }
    }

    @Test func noPlainHTTPAndNoTransportExceptions() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "NSAppTransportSecurity") == nil)
        for source in Self.sources {
            #expect(!source.text.contains("\"http://"), "\(source.name) has a plain http URL")
        }
    }

    @Test func apiAnswersAndMediaAreNeverCachedOnDisk() {
        let api = APIClient.makeSession().configuration
        #expect(api.urlCache == nil)
        #expect(api.requestCachePolicy == .reloadIgnoringLocalCacheData)
        #expect(APIClient.mediaSession.configuration.urlCache == nil)
    }
}
