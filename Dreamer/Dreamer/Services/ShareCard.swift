import Foundation
import UIKit

/// The 9:16 share card of a dream (1080 x 1920), rendered by the backend.
protocol ShareCardProviding: Sendable {
    func cardImage(dreamID: UUID) async throws(APIError) -> Data
}

/// `GET /v1/dreams/{id}/share-card`: the card, or 202 while it is rendered (asked again after
/// `Retry-After`), then the image from its presigned link.
struct APIShareCardProvider: ShareCardProviding {
    let client: APIClient
    /// About 15 s of rendering at the backend's one-second pace.
    var maxAttempts = 15
    /// Tests: instead of the server's Retry-After.
    var retryDelay: Duration?

    func cardImage(dreamID: UUID) async throws(APIError) -> Data {
        for _ in 0..<maxAttempts {
            switch try await client.shareCard(id: dreamID) {
            case .ready(let card):
                return try await download(card.url)
            case .rendering(let retryAfter):
                try? await Task.sleep(for: retryDelay ?? .seconds(retryAfter))
                if Task.isCancelled { throw APIError.timeout }
            }
        }
        throw APIError.timeout
    }

    private func download(_ url: URL) async throws(APIError) -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await client.session.data(from: url)
        } catch {
            throw APIError.fromTransport(error)
        }
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status), !data.isEmpty else {
            throw APIError.invalidResponse(status: (response as? HTTPURLResponse)?.statusCode)
        }
        return data
    }
}

/// Instagram's documented Stories share: the image goes on the pasteboard for five minutes,
/// then the `instagram-stories` URL (with the Meta app id) opens the Stories editor with it.
@MainActor
enum InstagramStories {
    static func shareURL(appID: String) -> URL? {
        var components = URLComponents()
        components.scheme = "instagram-stories"
        components.host = "share"
        components.queryItems = [URLQueryItem(name: "source_application", value: appID)]
        return components.url
    }

    /// Instagram is installed and the build has a Meta app id.
    static func isAvailable(appID: String?) -> Bool {
        guard let appID, let url = shareURL(appID: appID) else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// The dream film as the story's background (vertical, so it fills the story).
    static func share(backgroundVideo video: Data, appID: String) async -> Bool {
        guard let url = shareURL(appID: appID) else { return false }
        UIPasteboard.general.setItems([["com.instagram.sharedSticker.backgroundVideo": video]],
                                      options: [.expirationDate: Date.now.addingTimeInterval(5 * 60)])
        return await UIApplication.shared.open(url)
    }

    static func share(background image: Data, appID: String) async -> Bool {
        guard let url = shareURL(appID: appID) else { return false }
        UIPasteboard.general.setItems([["com.instagram.sharedSticker.backgroundImage": image]],
                                      options: [.expirationDate: Date.now.addingTimeInterval(5 * 60)])
        return await UIApplication.shared.open(url)
    }
}
