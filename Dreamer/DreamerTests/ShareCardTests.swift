import Foundation
import os
import Testing
import UIKit
@testable import Dreamer

private func cardPNG() -> Data {
    UIGraphicsImageRenderer(size: CGSize(width: 9, height: 16)).pngData { context in
        UIColor.systemIndigo.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 9, height: 16))
    }
}

struct APIShareCardProviderTests {
    @Test func waitsWhileTheCardIsRenderedThenDownloadsIt() async throws {
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let png = cardPNG()
        let (client, host) = StubURLProtocol.makeClient(tokens: StaticTokens()) { request in
            if request.url?.path().hasSuffix("/share-card") == true {
                let n = calls.withLock { $0 += 1; return $0 }
                if n == 1 { return .json(202, #"{"status":"rendering"}"#, headers: ["Retry-After": "1"]) }
                return .json(200, #"{"url":"https://\#(request.url!.host()!)/cards/c.png?sig=1","width":1080,"height":1920}"#)
            }
            return .init(status: 200, headers: ["Content-Type": "image/png"], body: png)
        }
        let provider = APIShareCardProvider(client: client, retryDelay: .milliseconds(5))

        let data = try await provider.cardImage(dreamID: UUID())

        #expect(data == png)
        let paths = StubURLProtocol.requests(for: host).compactMap { $0.url?.path() }
        #expect(paths.filter { $0.hasSuffix("/share-card") }.count == 2)
        #expect(paths.last == "/cards/c.png")
        // The card itself is fetched by its signed link, without the user's token.
        #expect(StubURLProtocol.requests(for: host).last?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func givesUpAfterTheRenderingWindow() async {
        let (client, _) = StubURLProtocol.makeClient(tokens: StaticTokens()) { _ in .json(202, #"{"status":"rendering"}"#) }
        let provider = APIShareCardProvider(client: client, maxAttempts: 3, retryDelay: .milliseconds(1))
        await #expect(throws: APIError.timeout) { _ = try await provider.cardImage(dreamID: UUID()) }
    }
}

@MainActor
struct DreamSharingTests {
    struct FixedCard: ShareCardProviding {
        let result: Result<Data, APIError>
        func cardImage(dreamID: UUID) async throws(APIError) -> Data { try result.get() }
    }

    private func makeViewModel(card: (any ShareCardProviding)?, analytics: RecordingAnalytics = RecordingAnalytics(),
                               appID: String? = nil) -> InterpretationViewModel {
        let store = InMemoryDreamStore()
        return InterpretationViewModel(dreamID: store.dreams[0].id, store: store, appState: AppState(store: InMemoryPreferencesStore()),
                                       readAloud: MockReadAloudService(), imageSaver: MockImageSaver(), analytics: analytics,
                                       shareCards: card, instagramAppID: appID)
    }

    @Test func sharingShowsTheBackendCard() async throws {
        let viewModel = makeViewModel(card: FixedCard(result: .success(cardPNG())))
        await viewModel.share()
        let item = try #require(viewModel.shareItem)
        // The 9:16 card, not the dream image.
        #expect(abs(item.image.size.width / item.image.size.height - 9.0 / 16.0) < 0.001)
    }

    @Test func withoutTheCardTheDreamImageIsShared() async {
        let viewModel = makeViewModel(card: FixedCard(result: .failure(.offline)))
        await viewModel.share()
        #expect(viewModel.shareItem != nil)
    }

    @Test(arguments: [
        (UIActivity.ActivityType.saveToCameraRoll as UIActivity.ActivityType?, true, [AnalyticsEvent.dreamShared(target: .photos)]),
        (UIActivity.ActivityType.message, true, [.dreamShared(target: .shareSheet)]),
        (UIActivity.ActivityType.message, false, [])
    ])
    func finishedSharesAreTracked(activity: UIActivity.ActivityType?, completed: Bool, expected: [AnalyticsEvent]) {
        let analytics = RecordingAnalytics()
        let viewModel = makeViewModel(card: nil, analytics: analytics)
        viewModel.shareSheetClosed(activity: activity, completed: completed)
        #expect(analytics.events == expected)
        #expect(viewModel.shareItem == nil)
    }

    @Test func savingToPhotosIsTracked() async {
        let analytics = RecordingAnalytics()
        let viewModel = makeViewModel(card: nil, analytics: analytics)
        await viewModel.saveImage()
        #expect(analytics.events == [.dreamShared(target: .photos)])
    }

    @Test func storiesNeedTheMetaAppID() {
        #expect(!makeViewModel(card: nil, appID: nil).canShareToStories)
        #expect(InstagramStories.shareURL(appID: "1234567890")?.absoluteString
                == "instagram-stories://share?source_application=1234567890")
    }
}
