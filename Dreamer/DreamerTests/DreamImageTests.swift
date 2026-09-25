import Foundation
import os
import Testing
import UIKit
@testable import Dreamer

private let dreamID = UUID(uuidString: "0B6F3C55-1D3C-4B8E-9F1E-2C7A8E5D4F10")!

private func pngData() -> Data {
    UIGraphicsImageRenderer(size: CGSize(width: 4, height: 6)).pngData { context in
        UIColor.systemTeal.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 6))
    }
}

private func tempCache() -> DreamImageCache {
    DreamImageCache(directory: URL.temporaryDirectory.appending(path: "DreamImagesTest-\(UUID().uuidString)"))
}

/// Hands out fresh links, like GET /v1/dreams/{id}.
private final class FreshLinks: DreamImageActions, @unchecked Sendable {
    let image: DreamImageInfo
    private let count = OSAllocatedUnfairLock(initialState: 0)
    var refreshes: Int { count.withLock { $0 } }
    init(image: DreamImageInfo) { self.image = image }

    func refreshDream(id: UUID) async throws(APIError) -> Dream {
        count.withLock { $0 += 1 }
        var dream = MockData.seedDreams()[0]
        dream.image = image
        return dream
    }

    func regenerateImage(id: UUID) async throws(APIError) -> Dream { throw APIError.offline }
}

struct RemoteDreamImageLoaderTests {
    private func ready(host: String, path: String = "/img/v1.jpg", version: Int = 1) -> DreamImageInfo {
        DreamImageInfo(status: .ready, url: URL(string: "https://\(host)\(path)?sig=1"),
                       thumbnailURL: URL(string: "https://\(host)/img/thumb.jpg?sig=1"), version: version)
    }

    @Test func downloadsOnceThenServesFromTheCache() async throws {
        let image = pngData()
        let (client, host) = StubURLProtocol.makeClient { _ in .init(status: 200, headers: ["Content-Type": "image/png"], body: image) }
        let cache = tempCache()
        let loader = RemoteDreamImageLoader(session: client.session, cache: cache, actions: FreshLinks(image: ready(host: host)))

        let first = try await loader.imageData(dreamID: dreamID, image: ready(host: host), size: .full)
        let second = try await loader.imageData(dreamID: dreamID, image: ready(host: host), size: .full)

        #expect(first == image && second == image)
        #expect(StubURLProtocol.requests(for: host).count == 1)
        // A relaunch (new memory) still finds it on disk.
        let relaunched = RemoteDreamImageLoader(session: client.session, cache: cache, actions: FreshLinks(image: ready(host: host)))
        _ = try await relaunched.imageData(dreamID: dreamID, image: ready(host: host), size: .full)
        #expect(StubURLProtocol.requests(for: host).count == 1)
    }

    @Test func anExpiredLinkIsReplacedByAFreshOne() async throws {
        let image = pngData()
        let (client, host) = StubURLProtocol.makeClient { request in
            request.url?.path() == "/img/expired.jpg" ? .empty(403) : .init(status: 200, body: image)
        }
        let actions = FreshLinks(image: ready(host: host, path: "/img/fresh.jpg"))
        let loader = RemoteDreamImageLoader(session: client.session, cache: tempCache(), actions: actions)

        let data = try await loader.imageData(dreamID: dreamID, image: ready(host: host, path: "/img/expired.jpg"), size: .full)

        #expect(data == image)
        #expect(actions.refreshes == 1)
        #expect(StubURLProtocol.requests(for: host).map { $0.url?.path() } == ["/img/expired.jpg", "/img/fresh.jpg"])
    }

    @Test func aNewVersionIsDownloadedAgain() async throws {
        let (client, host) = StubURLProtocol.makeClient { _ in .init(status: 200, body: pngData()) }
        let loader = RemoteDreamImageLoader(session: client.session, cache: tempCache(), actions: FreshLinks(image: ready(host: host)))

        _ = try await loader.imageData(dreamID: dreamID, image: ready(host: host, version: 1), size: .full)
        _ = try await loader.imageData(dreamID: dreamID, image: ready(host: host, path: "/img/v2.jpg", version: 2), size: .full)

        #expect(StubURLProtocol.requests(for: host).count == 2)
    }

    @Test func thumbnailsUseTheirOwnLink() async throws {
        let (client, host) = StubURLProtocol.makeClient { _ in .init(status: 200, body: pngData()) }
        let loader = RemoteDreamImageLoader(session: client.session, cache: tempCache(), actions: FreshLinks(image: ready(host: host)))
        _ = try await loader.imageData(dreamID: dreamID, image: ready(host: host), size: .thumbnail)
        #expect(StubURLProtocol.requests(for: host).first?.url?.path() == "/img/thumb.jpg")
    }

    @Test func signingOutEmptiesTheCache() async throws {
        let (client, host) = StubURLProtocol.makeClient { _ in .init(status: 200, body: pngData()) }
        let loader = RemoteDreamImageLoader(session: client.session, cache: tempCache(), actions: FreshLinks(image: ready(host: host)))
        _ = try await loader.imageData(dreamID: dreamID, image: ready(host: host), size: .full)

        await loader.removeAll()
        _ = try await loader.imageData(dreamID: dreamID, image: ready(host: host), size: .full)

        #expect(StubURLProtocol.requests(for: host).count == 2)
    }
}

@MainActor
struct InterpretationImageTests {
    /// Regeneration answers, and records whether it was asked.
    final class Regenerator: DreamImageActions, @unchecked Sendable {
        let result: Result<Dream, APIError>
        init(_ result: Result<Dream, APIError>) { self.result = result }
        func refreshDream(id: UUID) async throws(APIError) -> Dream { try result.get() }
        func regenerateImage(id: UUID) async throws(APIError) -> Dream { try result.get() }
    }

    private func makeViewModel(image: DreamImageInfo?, loader: (any DreamImageLoading)?, actions: (any DreamImageActions)?,
                               saver: any ImageSaving = MockImageSaver(), generationEnabled: Bool = true,
                               flagged: Bool = false) -> (InterpretationViewModel, InMemoryDreamStore) {
        let store = InMemoryDreamStore()
        var dream = store.dreams[0]
        dream.image = image
        dream.interpretation?.safetyFlag = flagged
        store.save(dream)
        let viewModel = InterpretationViewModel(dreamID: dream.id, store: store, appState: AppState(store: InMemoryPreferencesStore()),
                                                readAloud: MockReadAloudService(), imageSaver: saver,
                                                imageLoader: loader, imageActions: actions,
                                                imageGenerationEnabled: generationEnabled, imagePollInterval: .milliseconds(5))
        return (viewModel, store)
    }

    @Test func aPaintedImageAppearsWithoutReopeningTheScreen() async {
        var dream = MockData.seedDreams()[0]
        dream.image = DreamImageInfo(status: .pending, version: 1)
        let service = MockDreamImageService(dream: dream)
        let (viewModel, store) = makeViewModel(image: dream.image, loader: service, actions: service)

        await viewModel.loadImage()

        #expect(viewModel.imagePhase == .ready)
        #expect(viewModel.loadedImage != nil)
        let id = try? #require(viewModel.dream?.id)
        #expect(id.flatMap { store.dream(id: $0) }?.image?.status == .ready)
    }

    @Test func mockDreamsKeepTheirAsset() async {
        let (viewModel, _) = makeViewModel(image: nil, loader: nil, actions: nil)
        await viewModel.loadImage()
        #expect(viewModel.imagePhase == .asset)
    }

    @Test func aFailedPaintingOffersANewImage() async {
        let failed = DreamImageInfo(status: .failed, version: 1)
        var dream = MockData.seedDreams()[0]
        dream.image = DreamImageInfo(status: .pending, version: 2)
        let (viewModel, _) = makeViewModel(image: failed, loader: MockDreamImageService(dream: dream),
                                           actions: Regenerator(.success(dream)))
        await viewModel.loadImage()
        #expect(viewModel.imagePhase == .failed)
        #expect(viewModel.canRegenerateImage)

        await viewModel.regenerateImage()
        #expect(viewModel.imagePhase == .generating)
    }

    @Test func theDailyLimitIsExplained() async {
        let (viewModel, _) = makeViewModel(image: DreamImageInfo(status: .failed, version: 1), loader: nil,
                                           actions: Regenerator(.failure(.server(.init(code: .rateLimited, message: "", status: 429)))))
        await viewModel.regenerateImage()
        #expect(viewModel.toastMessage == "That’s all the new images for today. Try again tomorrow.")
    }

    @Test func theKillSwitchAndCrisisDreamsHideRegeneration() {
        let info = DreamImageInfo(status: .failed, version: 1)
        let actions = Regenerator(.failure(.offline))
        #expect(!makeViewModel(image: info, loader: nil, actions: actions, generationEnabled: false).0.canRegenerateImage)
        #expect(!makeViewModel(image: info, loader: nil, actions: actions, flagged: true).0.canRegenerateImage)
    }

    @Test func savingUsesTheDownloadedFile() async {
        final class SpySaver: ImageSaving, @unchecked Sendable {
            var data: Data?
            var names: [String] = []
            func saveImage(named assetName: String) async throws { names.append(assetName) }
            func saveImage(data: Data) async throws { self.data = data }
        }
        var dream = MockData.seedDreams()[0]
        dream.image = DreamImageInfo(status: .ready, url: URL(string: "https://media.mock/a.jpg"), version: 1)
        let saver = SpySaver()
        let (viewModel, _) = makeViewModel(image: dream.image, loader: MockDreamImageService(dream: dream), actions: nil, saver: saver)

        await viewModel.loadImage()
        await viewModel.saveImage()

        #expect(saver.data != nil)
        #expect(saver.names.isEmpty)
        #expect(viewModel.toastMessage == "Saved to Photos")
    }

    @Test func savingWaitsForThePainting() async {
        var dream = MockData.seedDreams()[0]
        dream.image = DreamImageInfo(status: .pending, version: 1)
        // No way to ask for news: it stays "painting".
        let (viewModel, _) = makeViewModel(image: dream.image, loader: MockDreamImageService(dream: dream), actions: nil)
        let loading = Task { await viewModel.loadImage() }
        try? await Task.sleep(for: .milliseconds(20))
        await viewModel.saveImage()
        #expect(viewModel.toastMessage == "The image isn’t ready yet")
        loading.cancel()
    }
}
