import Foundation

/// Settings -> "Export my data": the account's JSON export (`dreamer-export-v1`).
protocol DataExporting: Sendable {
    /// The response body exactly as the server sent it.
    func exportData() async throws(APIError) -> Data
}

extension APIClient: DataExporting {}

/// Mock mode and previews: a small export of the same shape.
struct MockDataExport: DataExporting {
    var result: Result<Data, APIError> = .success(Data(#"{"format":"dreamer-export-v1","dreams":[]}"#.utf8))

    func exportData() async throws(APIError) -> Data { try result.get() }
}

/// The export as a file for the share sheet. It holds every dream in full, so it lives only in the
/// temporary directory, unreadable while the phone is locked, and is deleted when the sheet closes.
enum DataExportFile {
    /// `mooncatch-export-YYYY-MM-DD.json`, the local date.
    static func name(on date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "mooncatch-export-%04d-%02d-%02d.json", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func write(_ data: Data, on date: Date, calendar: Calendar = .current) throws -> URL {
        let url = URL.temporaryDirectory.appending(path: name(on: date, calendar: calendar))
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
