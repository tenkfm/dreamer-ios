import Foundation
import Observation

/// The backend's insights: this week (Home strip), the morning line (Home card) and the month
/// (Journal summary). All three are computed on the server in the user's time zone.
protocol InsightService: Sendable {
    func weekInsight() async throws(APIError) -> WeekInsight
    /// Nil: nothing worth saying yet (the card is hidden).
    func morningInsight() async throws(APIError) -> MorningInsight?
    /// `month` is "YYYY-MM"; nil = the current month.
    func monthInsight(month: String?) async throws(APIError) -> MonthInsight
}

extension APIClient: InsightService {}

/// The last insights, kept on the device so Home and Journal show real numbers offline and at
/// launch before the server answers. They say things about the user's dreams, so the file sits in
/// the protected Dreamer folder and is removed at sign-out.
@MainActor
@Observable
final class InsightStore {
    struct Snapshot: Codable, Equatable {
        var week: WeekInsight?
        var morning: MorningInsight?
        /// Distinguishes "no morning insight" from "never asked".
        var morningLoaded = false
        var month: MonthInsight?
    }

    private(set) var snapshot: Snapshot

    @ObservationIgnored private let service: any InsightService
    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private var isRefreshing = false

    init(service: any InsightService, fileURL: URL? = InsightStore.defaultFileURL) {
        self.service = service
        self.fileURL = fileURL
        snapshot = fileURL.flatMap { try? JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: $0)) } ?? Snapshot()
    }

    static var defaultFileURL: URL {
        URL.applicationSupportDirectory.appending(path: "Dreamer/insights.json")
    }

    var week: WeekInsight? { snapshot.week }
    var morning: MorningInsight? { snapshot.morning }
    var hasMorningAnswer: Bool { snapshot.morningLoaded }
    var month: MonthInsight? { snapshot.month }

    /// All three at once; each keeps its cached value when its call fails (offline).
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        async let week = try? service.weekInsight()
        async let morning = Self.morning(from: service)
        async let month = try? service.monthInsight(month: nil)
        var next = snapshot
        if let week = await week { next.week = week }
        if let morning = await morning {
            next.morning = morning.value
            next.morningLoaded = true
        }
        if let month = await month { next.month = month }
        guard next != snapshot else { return }
        snapshot = next
        save()
    }

    /// Sign-out and account deletion.
    func clear() {
        snapshot = Snapshot()
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
    }

    /// Nil when the call failed; `.some(nil)` when the server has no morning insight.
    private struct MorningAnswer { var value: MorningInsight? }

    private static func morning(from service: any InsightService) async -> MorningAnswer? {
        do {
            return MorningAnswer(value: try await service.morningInsight())
        } catch {
            return nil
        }
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                 attributes: [.protectionKey: FileProtectionType.complete])
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
