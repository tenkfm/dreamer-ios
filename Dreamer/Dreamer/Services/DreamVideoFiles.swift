import Foundation

/// Downloaded dream films, for sharing (the share sheet and Instagram need a file) and replaying
/// offline. The links are signed for about an hour, so the file is what lasts. In Caches, and
/// removed with the account's other media at sign-out: the film carries the dream's words.
enum DreamVideoFiles {
    static var directory: URL {
        URL.cachesDirectory.appending(path: "DreamVideos", directoryHint: .isDirectory)
    }

    static func file(for dreamID: UUID) -> URL {
        directory.appending(path: "\(dreamID.uuidString.lowercased()).mp4")
    }

    /// The film on the device, downloaded from `url` the first time.
    static func local(dreamID: UUID, from url: URL, session: URLSession = APIClient.mediaSession) async throws -> URL {
        let target = file(for: dreamID)
        if FileManager.default.fileExists(atPath: target.path()) { return target }
        let (temporary, response) = try await session.download(from: url)
        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else {
            throw URLError(.badServerResponse)
        }
        // Like the image cache: the film carries the dream, so it is unreadable while the phone is locked.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.complete])
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: temporary, to: target)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: target.path())
        return target
    }

    /// A new film (after a new image) replaces the old file.
    static func remove(dreamID: UUID) {
        try? FileManager.default.removeItem(at: file(for: dreamID))
    }

    static func purge() {
        try? FileManager.default.removeItem(at: directory)
    }
}
