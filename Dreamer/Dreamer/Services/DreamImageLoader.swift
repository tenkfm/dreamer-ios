import CryptoKit
import Foundation
import os

/// Which of the three renditions the backend makes of a dream image.
enum DreamImageSize: String, Sendable {
    /// The hero of Interpretation.
    case full
    /// 540 px wide.
    case preview
    /// 270 px wide, for lists.
    case thumbnail

    func url(in image: DreamImageInfo) -> URL? {
        switch self {
        case .full: image.url ?? image.previewURL
        case .preview: image.previewURL ?? image.url
        case .thumbnail: image.thumbnailURL ?? image.previewURL ?? image.url
        }
    }
}

/// Image bytes of a ready dream image, from the cache or the network.
protocol DreamImageLoading: Sendable {
    func imageData(dreamID: UUID, image: DreamImageInfo, size: DreamImageSize) async throws(APIError) -> Data
    /// A journal thumbnail by its link (the list has no image version; the link's path changes with it).
    func thumbnailData(dreamID: UUID, url: URL) async throws(APIError) -> Data
    /// Sign-out and account deletion: nothing of the account stays on the device.
    func removeAll() async
}

/// What the Interpretation screen asks the backend about a dream's image.
protocol DreamImageActions: Sendable {
    /// The dream as it is now (the image status and fresh presigned links).
    func refreshDream(id: UUID) async throws(APIError) -> Dream
    /// A new image; the returned dream has the next version as `pending` (daily limit: 429).
    func regenerateImage(id: UUID) async throws(APIError) -> Dream
}

extension APIClient: DreamImageActions {
    func refreshDream(id: UUID) async throws(APIError) -> Dream { try await dream(id: id) }
}

/// Dream images on disk, keyed by dream, version and size. The version grows with every
/// regeneration, so a new image never shows an old cached one, and the presigned links (which
/// expire) are not part of the key.
actor DreamImageCache {
    private let directory: URL
    private var memory: [String: Data] = [:]
    private var order: [String] = []
    /// About 12 hero images in memory.
    private let memoryLimit: Int

    init(directory: URL = URL.cachesDirectory.appending(path: "DreamImages", directoryHint: .isDirectory),
         memoryLimit: Int = 12) {
        self.directory = directory
        self.memoryLimit = memoryLimit
    }

    static func key(dreamID: UUID, version: Int, size: DreamImageSize) -> String {
        "\(versionPrefix(dreamID))\(version)-\(size.rawValue)"
    }

    static func versionPrefix(_ dreamID: UUID) -> String {
        "\(dreamID.uuidString.lowercased())-v"
    }

    static func thumbnailKey(dreamID: UUID, url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.path(percentEncoded: false).utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return "\(thumbnailPrefix(dreamID))\(digest)"
    }

    static func thumbnailPrefix(_ dreamID: UUID) -> String {
        "\(dreamID.uuidString.lowercased())-t"
    }

    func data(for key: String) -> Data? {
        if let data = memory[key] { return data }
        guard let data = try? Data(contentsOf: fileURL(key)) else { return nil }
        remember(data, for: key)
        return data
    }

    /// Stores `data`; files of this dream that `isStale` says will never show again are removed.
    func store(_ data: Data, for key: String, isStale: @Sendable (String) -> Bool = { _ in false }) {
        remember(data, for: key)
        if let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)) {
            for file in files where isStale(file) {
                try? FileManager.default.removeItem(at: directory.appending(path: file))
            }
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.protectionKey: FileProtectionType.complete])
            try data.write(to: fileURL(key), options: [.atomic, .completeFileProtection])
        } catch {
            // Disk full: the image still shows from memory; it is downloaded again next time.
        }
    }

    func removeAll() {
        memory = [:]
        order = []
        try? FileManager.default.removeItem(at: directory)
    }

    private func fileURL(_ key: String) -> URL {
        directory.appending(path: key + ".img")
    }

    private func remember(_ data: Data, for key: String) {
        if memory[key] == nil { order.append(key) }
        memory[key] = data
        while order.count > memoryLimit {
            memory[order.removeFirst()] = nil
        }
    }
}

/// Downloads dream images by their presigned links. A link that expired (403) is replaced by
/// asking the backend for the dream again, once.
struct RemoteDreamImageLoader: DreamImageLoading {
    let session: URLSession
    let cache: DreamImageCache
    let actions: any DreamImageActions

    init(session: URLSession = .shared, cache: DreamImageCache = DreamImageCache(), actions: any DreamImageActions) {
        self.session = session
        self.cache = cache
        self.actions = actions
    }

    func imageData(dreamID: UUID, image: DreamImageInfo, size: DreamImageSize) async throws(APIError) -> Data {
        let key = DreamImageCache.key(dreamID: dreamID, version: image.version, size: size)
        if let cached = await cache.data(for: key) { return cached }
        guard image.status == .ready, let url = size.url(in: image) else { throw APIError.invalidResponse(status: nil) }

        let data: Data
        do {
            data = try await download(url)
        } catch .invalidResponse(status: 403) {
            // The presigned link expired: the dream comes back with fresh ones.
            guard let fresh = try await actions.refreshDream(id: dreamID).image, let url = size.url(in: fresh) else {
                throw APIError.invalidResponse(status: 403)
            }
            data = try await download(url)
        }
        // Older versions of this dream's image will never be shown again (other sizes of this one may).
        let current = DreamImageCache.versionPrefix(dreamID) + "\(image.version)-"
        await cache.store(data, for: key) { file in
            file.hasPrefix(DreamImageCache.versionPrefix(dreamID)) && !file.hasPrefix(current)
        }
        return data
    }

    func thumbnailData(dreamID: UUID, url: URL) async throws(APIError) -> Data {
        let key = DreamImageCache.thumbnailKey(dreamID: dreamID, url: url)
        if let cached = await cache.data(for: key) { return cached }
        // An expired link fails here; the next journal refresh brings a fresh one.
        let data = try await download(url)
        await cache.store(data, for: key) { file in
            file.hasPrefix(DreamImageCache.thumbnailPrefix(dreamID)) && !file.hasPrefix(key)
        }
        return data
    }

    func removeAll() async {
        await cache.removeAll()
    }

    private func download(_ url: URL) async throws(APIError) -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw APIError.fromTransport(error)
        }
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status), !data.isEmpty else {
            throw APIError.invalidResponse(status: (response as? HTTPURLResponse)?.statusCode)
        }
        return data
    }
}
