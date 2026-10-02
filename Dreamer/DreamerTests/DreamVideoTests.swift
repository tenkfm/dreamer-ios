import Foundation
import os
import Testing
@testable import Dreamer

/// The dream film of contract 1.4.0: mapping, waiting for it, playing and sharing it.
struct DreamVideoMappingTests {
    private let id = UUID(uuidString: "0B6F3C55-1D3C-4B8E-9F1E-2C7A8E5D4F10")!

    @Test func theContractExampleMapsToAFilm() async throws {
        let dream = try await ContractExamples.client("getDream", status: 200).dream(id: id)
        let video = try #require(dream.video)
        #expect(video.status == .ready)
        #expect(video.url?.pathExtension == "mp4")
        #expect(video.duration == 72.8)
        #expect(video.lens == .psychology)
        #expect(video.width == 1080 && video.height == 1920)
    }

    /// A dream from before the films, and a response with keys the app does not know yet: the old
    /// contract rejected unknown keys, and one new field broke every dream screen.
    @Test func noFilmAndUnknownKeysStillDecode() async throws {
        var example = try #require(ContractExamples.all["getDream"]?["200"] as? [String: Any])
        example["video"] = NSNull()
        example["somethingNew"] = ["nested": true]
        let body = try JSONSerialization.data(withJSONObject: example)
        let client = StubURLProtocol.makeClient(tokens: StaticTokens()) { _ in
            .init(status: 200, headers: ["Content-Type": "application/json"], body: body)
        }.0

        let dream = try await client.dream(id: id)
        #expect(dream.video == nil)
    }
}

@MainActor
struct InterpretationVideoTests {
    /// GET /v1/dreams/{id}: the film is pending for the first `pendingFor` asks, then ready, with a
    /// new signed link on every answer.
    final class Cutter: DreamImageActions, @unchecked Sendable {
        let base: Dream
        let pendingFor: Int
        private let count = OSAllocatedUnfairLock(initialState: 0)
        var refreshes: Int { count.withLock { $0 } }

        init(base: Dream, pendingFor: Int) {
            self.base = base
            self.pendingFor = pendingFor
        }

        func refreshDream(id: UUID) async throws(APIError) -> Dream {
            let n = count.withLock { $0 += 1; return $0 }
            var dream = base
            dream.notes = "server notes"
            dream.video = n <= pendingFor ? Self.pending : Self.ready(link: n)
            return dream
        }

        func regenerateImage(id: UUID) async throws(APIError) -> Dream { throw APIError.offline }

        static let pending = DreamVideo(status: .pending, url: nil, duration: nil, lens: .psychology, width: 1080, height: 1920)

        static func ready(link: Int) -> DreamVideo {
            DreamVideo(status: .ready, url: URL(string: "https://media.mock/video.mp4?sig=\(link)"), duration: 72.8,
                       lens: .psychology, width: 1080, height: 1920)
        }
    }

    final class Clock: @unchecked Sendable {
        var date = Date(timeIntervalSince1970: 1_800_000_000)
    }

    private func makeViewModel(video: DreamVideo?, actions: (any DreamImageActions)?, readAloud: MockReadAloudService = MockReadAloudService(),
                               clock: Clock = Clock()) -> (InterpretationViewModel, InMemoryDreamStore) {
        let store = InMemoryDreamStore()
        var dream = store.dreams[0]
        dream.video = video
        dream.notes = "typed here"
        store.save(dream)
        // A file left by another test would be played instead of the link.
        DreamVideoFiles.remove(dreamID: dream.id)
        let viewModel = InterpretationViewModel(dreamID: dream.id, store: store, appState: AppState(store: InMemoryPreferencesStore()),
                                                readAloud: readAloud, imageSaver: MockImageSaver(),
                                                imageActions: actions, videoPollInterval: .zero, now: { clock.date })
        return (viewModel, store)
    }

    @Test func aPendingFilmIsAskedForUntilItIsReady() async {
        let base = InMemoryDreamStore().dreams[0]
        let cutter = Cutter(base: base, pendingFor: 2)
        let (viewModel, store) = makeViewModel(video: Cutter.pending, actions: cutter)
        #expect(viewModel.isVideoPending)

        await viewModel.watchVideo()

        #expect(cutter.refreshes == 3)
        #expect(viewModel.isVideoReady)
        #expect(viewModel.videoDurationText == "1:13")
        // Only the media is taken from the server copy: the notes typed meanwhile stay.
        #expect(viewModel.dream?.notes == "typed here")
        #expect(viewModel.dream.flatMap { store.dream(id: $0.id) }?.video?.status == .ready)
    }

    @Test func waitingStopsAfterThreeMinutes() async {
        let cutter = Cutter(base: InMemoryDreamStore().dreams[0], pendingFor: .max)
        let (viewModel, _) = makeViewModel(video: Cutter.pending, actions: cutter)

        await viewModel.watchVideo()

        #expect(cutter.refreshes == InterpretationViewModel.maxVideoPolls)
        #expect(viewModel.isVideoPending)
    }

    @Test func aReadyOrMissingFilmIsNotAskedFor() async {
        let cutter = Cutter(base: InMemoryDreamStore().dreams[0], pendingFor: 0)
        await makeViewModel(video: Cutter.ready(link: 0), actions: cutter).0.watchVideo()
        await makeViewModel(video: nil, actions: cutter).0.watchVideo()
        #expect(cutter.refreshes == 0)
    }

    @Test func playingStopsTheVoiceAndUsesTheLinkWhileItIsFresh() async {
        let readAloud = MockReadAloudService()
        let cutter = Cutter(base: InMemoryDreamStore().dreams[0], pendingFor: 0)
        let clock = Clock()
        let (viewModel, _) = makeViewModel(video: Cutter.pending, actions: cutter, readAloud: readAloud, clock: clock)
        await viewModel.watchVideo()
        readAloud.play(ReadAloudItem(text: "reading", lens: .psychology))

        await viewModel.playVideo()

        #expect(readAloud.state == .idle)
        #expect(viewModel.videoPlayback?.url.query() == "sig=1")
        #expect(cutter.refreshes == 1)
    }

    /// The signed link lives about an hour: an old one is never handed to the player.
    @Test func aStaleLinkIsFetchedAgain() async {
        let cutter = Cutter(base: InMemoryDreamStore().dreams[0], pendingFor: 0)
        let clock = Clock()
        let (viewModel, _) = makeViewModel(video: Cutter.pending, actions: cutter, clock: clock)
        await viewModel.watchVideo()

        clock.date += InterpretationViewModel.videoLinkLifetime + 1
        await viewModel.playVideo()

        #expect(cutter.refreshes == 2)
        #expect(viewModel.videoPlayback?.url.query() == "sig=2")
    }

    @Test func aDownloadedFilmPlaysAndSharesFromTheFile() async throws {
        let cutter = Cutter(base: InMemoryDreamStore().dreams[0], pendingFor: 0)
        let (viewModel, _) = makeViewModel(video: Cutter.ready(link: 0), actions: cutter)
        let dreamID = try #require(viewModel.dream?.id)
        let file = DreamVideoFiles.file(for: dreamID)
        try FileManager.default.createDirectory(at: DreamVideoFiles.directory, withIntermediateDirectories: true)
        try Data("mp4".utf8).write(to: file)
        defer { DreamVideoFiles.remove(dreamID: dreamID) }

        await viewModel.playVideo()
        #expect(viewModel.videoPlayback?.url == file)

        await viewModel.share()
        guard case .video(let shared) = viewModel.shareItem?.content else {
            Issue.record("the share sheet should get the film")
            return
        }
        #expect(shared == file)
        #expect(cutter.refreshes == 0)
    }

    @Test func withoutAFilmTheCardIsShared() async {
        let (viewModel, _) = makeViewModel(video: DreamVideo(status: .failed, url: nil, duration: nil, lens: nil, width: 1080, height: 1920),
                                           actions: nil)
        #expect(!viewModel.isVideoReady && !viewModel.isVideoPending)
        await viewModel.share()
        if case .video = viewModel.shareItem?.content { Issue.record("a failed film is never shared") }
    }
}

struct DreamVideoFilesTests {
    @Test func downloadsOnceAndSignOutRemovesIt() async throws {
        let film = Data("film".utf8)
        let (client, host) = StubURLProtocol.makeClient { _ in .init(status: 200, headers: ["Content-Type": "video/mp4"], body: film) }
        let dreamID = UUID()
        let url = try #require(URL(string: "https://\(host)/video.mp4?sig=1"))

        let first = try await DreamVideoFiles.local(dreamID: dreamID, from: url, session: client.session)
        let second = try await DreamVideoFiles.local(dreamID: dreamID, from: url, session: client.session)

        #expect(try Data(contentsOf: first) == film)
        #expect(first == second)
        #expect(StubURLProtocol.requests(for: host).count == 1)
        DreamVideoFiles.remove(dreamID: dreamID)
        #expect(!FileManager.default.fileExists(atPath: first.path()))
    }

    @Test func anExpiredLinkLeavesNoFile() async throws {
        let (client, host) = StubURLProtocol.makeClient { _ in .empty(403) }
        let dreamID = UUID()
        let url = try #require(URL(string: "https://\(host)/video.mp4"))

        await #expect(throws: URLError.self) {
            try await DreamVideoFiles.local(dreamID: dreamID, from: url, session: client.session)
        }
        #expect(!FileManager.default.fileExists(atPath: DreamVideoFiles.file(for: dreamID).path()))
    }
}
