import Foundation
import Observation
import UIKit

/// 11 Interpretation. The main lens is the account's preferred lens (the one the backend used for
/// the dream), so a change in Settings shows on dreams already open; the other two are alternatives.
@MainActor
@Observable
final class InterpretationViewModel {
    private(set) var dream: Dream?
    /// Opened from the journal list without the dream on the device yet.
    private(set) var isLoadingDream = false
    private let dreamID: Dream.ID
    private(set) var expandedLenses: Set<Lens> = []
    private(set) var isSavingImage = false
    private(set) var imagePhase: ImagePhase = .asset
    /// The downloaded dream image (nil: the asset or the sky placeholder shows).
    private(set) var loadedImage: UIImage?
    private(set) var isRegeneratingImage = false
    /// A new value restarts `loadImage` (after a regeneration).
    private(set) var imageRequest = UUID()
    /// The share card is being fetched (the backend renders it on the first ask).
    private(set) var isPreparingShare = false
    /// Set to present the share sheet with the card or the film.
    var shareItem: ShareItem?

    struct ShareItem: Identifiable {
        enum Content {
            case image(UIImage)
            /// The downloaded MP4: the share sheet offers Save Video, Messages, Instagram...
            case video(URL)
        }
        let id = UUID()
        let content: Content

        var activityItems: [Any] {
            switch content {
            case .image(let image): [image]
            case .video(let file): [file]
            }
        }
    }

    /// Set to play the dream film full screen.
    var videoPlayback: VideoPlayback?
    /// The share sheet over the player: the screen's own sheet cannot open while the player covers it.
    var playerShareItem: ShareItem?

    struct VideoPlayback: Identifiable {
        let id = UUID()
        let url: URL
    }

    /// A fresh link is being fetched before the film plays.
    private(set) var isPreparingVideo = false
    var toastMessage: String?
    /// Saved on the device at once and on the backend a moment after typing stops.
    var notes: String {
        didSet { notesChanged() }
    }

    static let notesLimit = 4000

    enum ImagePhase: Equatable {
        /// Mock data and dreams without a backend image: the asset catalog (or the sky placeholder).
        case asset
        /// The backend is painting it (up to ~20 s after the interpretation).
        case generating
        case loading
        case ready
        /// Painting or downloading failed: the sky stays; a new image can be asked for.
        case failed
    }

    let readAloud: any ReadAloudService
    private let store: any DreamStore
    private let appState: AppState
    private let imageSaver: any ImageSaving
    private let dateFormatter: DreamDateFormatter
    private let supportContent: any SupportContentProvider
    private let analytics: any Analytics
    /// Nil in mock mode (notes stay on the device).
    private let notesService: (any DreamNotesService)?
    private let notesDebounce: Duration
    @ObservationIgnored private var notesTask: Task<Void, Never>?
    /// Notes typed since the backend last confirmed them.
    @ObservationIgnored private var unsentNotes: String?
    /// Nil in mock mode.
    private let imageLoader: (any DreamImageLoading)?
    private let imageActions: (any DreamImageActions)?
    /// The imageGenerationEnabled kill switch.
    private let imageGenerationEnabled: Bool
    private let imagePollInterval: Duration
    @ObservationIgnored private var loadedImageData: Data?
    /// Nil in mock mode: the dream image is shared instead.
    private let shareCards: (any ShareCardProviding)?
    private let instagramAppID: String?
    @ObservationIgnored private var cardData: Data?
    private let region: Locale.Region?
    private let videoPollInterval: Duration
    private let now: () -> Date
    /// When the dream's links were last fetched from the server (the film's is signed for ~an hour).
    @ObservationIgnored private var mediaFetchedAt: Date?

    init(dreamID: Dream.ID,
         store: any DreamStore,
         appState: AppState,
         readAloud: any ReadAloudService,
         imageSaver: any ImageSaving,
         supportContent: any SupportContentProvider = PendingSupportContent(),
         region: Locale.Region? = Locale.current.region,
         analytics: any Analytics = NoopAnalytics(),
         notesService: (any DreamNotesService)? = nil,
         notesDebounce: Duration = .seconds(1),
         imageLoader: (any DreamImageLoading)? = nil,
         imageActions: (any DreamImageActions)? = nil,
         imageGenerationEnabled: Bool = true,
         imagePollInterval: Duration = .seconds(3),
         shareCards: (any ShareCardProviding)? = nil,
         instagramAppID: String? = nil,
         videoPollInterval: Duration = .seconds(5),
         now: @escaping () -> Date = Date.init,
         dateFormatter: DreamDateFormatter = DreamDateFormatter()) {
        let dream = store.dream(id: dreamID)
        self.dreamID = dreamID
        self.dream = dream
        isLoadingDream = dream == nil
        self.notes = dream?.notes ?? ""
        self.store = store
        self.appState = appState
        self.readAloud = readAloud
        self.imageSaver = imageSaver
        self.dateFormatter = dateFormatter
        self.supportContent = supportContent
        self.region = region
        self.analytics = analytics
        self.notesService = notesService
        self.notesDebounce = notesDebounce
        self.imageLoader = imageLoader
        self.imageActions = imageActions
        self.imageGenerationEnabled = imageGenerationEnabled
        self.imagePollInterval = imagePollInterval
        self.shareCards = shareCards
        self.instagramAppID = instagramAppID
        self.videoPollInterval = videoPollInterval
        self.now = now
    }

    // MARK: Content

    /// A crisis-flagged dream: the support screen replaces the reading, the image, the voice and
    /// sharing (the backend generates neither image nor voice for it).
    var support: SupportContent? {
        guard dream?.interpretation?.safetyFlag == true else { return nil }
        return supportContent.content(for: region)
    }

    var mainLens: Lens { appState.preferredLens }

    var alternativeLenses: [Lens] { Lens.allCases.filter { $0 != mainLens } }

    func text(for lens: Lens) -> String {
        dream?.interpretation?.text(for: lens) ?? ""
    }

    var forYou: String? { dream?.interpretation?.forYou }

    var dateText: String {
        guard let dream else { return "" }
        return dateFormatter.dayAndTime(dream.createdAt)
    }

    var imageName: String { dream?.imageName ?? Dream.placeholderImageName }

    var durationText: String {
        let seconds = Int(dream?.audio[mainLens]?.duration ?? dream?.interpretation?.readDurations[mainLens] ?? 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    func isExpanded(_ lens: Lens) -> Bool { expandedLenses.contains(lens) }

    // MARK: Actions

    func togglePlayback() {
        switch readAloud.state {
        case .playing: readAloud.pause()
        // A second tap while the voice is fetched gives up on it.
        case .loading: readAloud.stop()
        case .idle, .paused: readAloud.play(readAloudItem(for: mainLens))
        }
    }

    /// The main lens voice starts loading when the screen opens, so Listen plays at once.
    func prepareVoice() {
        guard support == nil else { return }
        readAloud.prepare(readAloudItem(for: mainLens))
    }

    func readAloudItem(for lens: Lens) -> ReadAloudItem {
        ReadAloudItem(text: text(for: lens), lens: lens, dreamID: dream?.id, audio: dream?.audio[lens])
    }

    func toggleExpanded(_ lens: Lens) {
        if expandedLenses.contains(lens) {
            expandedLenses.remove(lens)
        } else {
            expandedLenses.insert(lens)
        }
    }

    /// "Make this my main lens": it becomes the account's lens (every dream, and the next ones),
    /// swaps into the main card, resets the player and collapses both alternatives.
    func promote(_ lens: Lens) {
        let previous = mainLens
        guard lens != previous else { return }
        readAloud.stop()
        appState.setPreferredLens(lens)
        expandedLenses = []
        analytics.track(.lensPromoted(from: previous, to: lens))
    }

    func stopPlayback() {
        readAloud.stop()
    }

    @ObservationIgnored private var hasReportedView = false

    /// The screen opened (once per screen); crisis dreams show support, not a reading.
    func viewed() {
        guard !hasReportedView, dream != nil, support == nil else { return }
        hasReportedView = true
        analytics.track(.interpretationViewed(lens: mainLens))
    }

    /// The dream from the server: fresh status, links and voice; the cached copy shows meanwhile.
    func refreshDream() async {
        isLoadingDream = dream == nil
        defer { isLoadingDream = false }
        guard var fresh = try? await store.loadDream(id: dreamID) else { return }
        // Notes typed here and not yet confirmed win over the server's copy.
        if let unsentNotes { fresh.notes = unsentNotes }
        dream = fresh
        notes = fresh.notes
        mediaFetchedAt = now()
        imageRequest = UUID()
        viewed()
    }

    /// "Copy text": the reading of the main lens as shown, for a note or a message. The dream's
    /// words reach the pasteboard only on this tap.
    func copyInterpretation() {
        let text = text(for: mainLens)
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        copyCount += 1
        toastMessage = String(localized: "Copied")
    }

    /// Grows with every copy that happened: the view's haptic follows it, not the tap, so an empty
    /// reading gives no feedback for a copy that did not happen.
    private(set) var copyCount = 0

    /// True once when the dream was opened for its notes (`AppState.openNotes`).
    func takeNotesFocus() -> Bool {
        guard appState.notesFocus == dreamID else { return false }
        appState.notesFocus = nil
        return true
    }

    // MARK: Video

    /// The dream film; none for crisis dreams.
    var video: DreamVideo? { support == nil ? dream?.video : nil }

    var isVideoReady: Bool { video?.status == .ready && video?.url != nil }

    /// The server is cutting the film (it waits for the image and the voice).
    var isVideoPending: Bool { video?.status == .pending }

    var videoDurationText: String? {
        guard let seconds = video?.duration else { return nil }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Three minutes of asking every 5 s: there is no push for the film, and it comes 1.5-2 minutes
    /// after the interpretation.
    static let maxVideoPolls = 36

    /// While the film is being cut and the screen is open, the dream is asked for again.
    func watchVideo() async {
        guard let dreamID = dream?.id, let imageActions else { return }
        var polls = 0
        while dream?.video?.status == .pending, polls < Self.maxVideoPolls {
            try? await Task.sleep(for: videoPollInterval)
            guard !Task.isCancelled else { return }
            polls += 1
            if let fresh = try? await imageActions.refreshDream(id: dreamID) { applyMedia(from: fresh) }
        }
    }

    /// A link fetched less than this long ago is used as is.
    static let videoLinkLifetime: TimeInterval = 45 * 60

    /// "Play": the downloaded file when there is one (offline too), else a fresh link.
    func playVideo() async {
        guard isVideoReady, !isPreparingVideo, let dreamID = dream?.id else { return }
        // The film carries the main lens' voice: the player for it would talk over it.
        readAloud.stop()
        let local = DreamVideoFiles.file(for: dreamID)
        if FileManager.default.fileExists(atPath: local.path()) {
            videoPlayback = VideoPlayback(url: local)
            return
        }
        isPreparingVideo = true
        defer { isPreparingVideo = false }
        guard let url = await freshVideoURL() else {
            toastMessage = String(localized: "Couldn’t play your dream video. Please try again.")
            return
        }
        videoPlayback = VideoPlayback(url: url)
    }

    private func freshVideoURL() async -> URL? {
        // Mock mode: nothing to refresh from, and the link does not expire.
        guard imageActions != nil else { return isVideoReady ? video?.url : nil }
        if let fetched = mediaFetchedAt, now().timeIntervalSince(fetched) < Self.videoLinkLifetime, isVideoReady {
            return video?.url
        }
        guard let imageActions, let dreamID = dream?.id,
              let fresh = try? await imageActions.refreshDream(id: dreamID) else { return nil }
        applyMedia(from: fresh)
        return isVideoReady ? video?.url : nil
    }

    /// The film as a file on the device, for the share sheet and Instagram.
    private func videoFile() async -> URL? {
        guard isVideoReady, let dreamID = dream?.id else { return nil }
        let local = DreamVideoFiles.file(for: dreamID)
        if FileManager.default.fileExists(atPath: local.path()) { return local }
        guard let url = await freshVideoURL() else { return nil }
        return try? await DreamVideoFiles.local(dreamID: dreamID, from: url)
    }

    /// The media of a fresh copy (film, voices, image); the notes typed meanwhile stay.
    private func applyMedia(from fresh: Dream) {
        guard var dream else { return }
        dream.video = fresh.video
        dream.audio = fresh.audio
        if let image = fresh.image { dream.image = image }
        self.dream = dream
        store.save(dream)
        mediaFetchedAt = now()
    }

    // MARK: Image

    /// About two minutes of waiting for a painting (the backend needs up to ~20 s).
    static let maxImagePolls = 40

    /// Shows the dream image: waits while it is painted (polling the dream), then downloads it
    /// (or takes it from the cache) and reveals it.
    func loadImage() async {
        guard let dreamID = dream?.id, var info = dream?.image, let imageLoader else {
            imagePhase = .asset
            return
        }
        var polls = 0
        while info.status == .pending {
            imagePhase = .generating
            guard let imageActions, polls < Self.maxImagePolls else { return }
            try? await Task.sleep(for: imagePollInterval)
            guard !Task.isCancelled else { return }
            polls += 1
            if let fresh = try? await imageActions.refreshDream(id: dreamID), let image = fresh.image {
                info = image
                updateImageInfo(image)
            }
        }
        guard info.status == .ready else {
            imagePhase = .failed
            return
        }
        if loadedImage == nil { imagePhase = .loading }
        do {
            let data = try await imageLoader.imageData(dreamID: dreamID, image: info, size: .full)
            // The hero spans the screen width at 380 pt tall; the saved file keeps full size.
            guard let image = ImageDownsampler.image(from: data, pointSize: 600) else { throw APIError.invalidResponse(status: nil) }
            loadedImageData = data
            loadedImage = image
            imagePhase = .ready
        } catch {
            if loadedImage == nil { imagePhase = .failed }
        }
    }

    /// "Create a new image": off with the kill switch, for crisis dreams and while one is painted.
    var canRegenerateImage: Bool {
        imageGenerationEnabled && imageActions != nil && dream?.image != nil && support == nil
            && imagePhase != .generating && !isRegeneratingImage
    }

    func regenerateImage() async {
        guard canRegenerateImage, let imageActions, let dreamID = dream?.id else { return }
        isRegeneratingImage = true
        defer { isRegeneratingImage = false }
        do {
            let fresh = try await imageActions.regenerateImage(id: dreamID)
            if let image = fresh.image { updateImageInfo(image) }
            // A new image means a new film: the downloaded one is the old picture.
            DreamVideoFiles.remove(dreamID: dreamID)
            applyMedia(from: fresh)
            loadedImage = nil
            loadedImageData = nil
            imagePhase = .generating
            imageRequest = UUID()
        } catch {
            toastMessage = switch error.code {
            case .rateLimited, .limitReached: String(localized: "That’s all the new images for today. Try again tomorrow.")
            default: String(localized: "Couldn’t make a new image. Please try again.")
            }
        }
    }

    /// The status and links change; the notes typed meanwhile must not.
    private func updateImageInfo(_ image: DreamImageInfo) {
        guard var dream else { return }
        dream.image = image
        self.dream = dream
        store.save(dream)
    }

    // MARK: Sharing

    /// Instagram is installed and the build has the Meta app id; never for crisis dreams.
    var canShareToStories: Bool {
        support == nil && InstagramStories.isAvailable(appID: instagramAppID)
    }

    /// "Share": the dream film once it is ready (vertical, made for stories), else the 9:16 card.
    /// The share sheet also offers Save Video / Save Image.
    func share() async {
        guard !isPreparingShare else { return }
        if isVideoReady {
            isPreparingShare = true
            let file = await videoFile()
            isPreparingShare = false
            if let file {
                shareItem = ShareItem(content: .video(file))
            } else {
                toastMessage = String(localized: "Couldn’t prepare your dream video. Please try again.")
            }
            return
        }
        guard let data = await preparedCard(), let image = UIImage(data: data) else {
            if !isPreparingShare { toastMessage = String(localized: "Couldn’t prepare your dream card. Please try again.") }
            return
        }
        shareItem = ShareItem(content: .image(image))
    }

    /// "Share" in the player: the film itself.
    func shareFromPlayer() async {
        guard isVideoReady, !isPreparingShare else { return }
        isPreparingShare = true
        let file = await videoFile()
        isPreparingShare = false
        if let file {
            playerShareItem = ShareItem(content: .video(file))
        } else {
            toastMessage = String(localized: "Couldn’t prepare your dream video. Please try again.")
        }
    }

    func shareToStories() async {
        guard let instagramAppID, !isPreparingShare else { return }
        if isVideoReady {
            isPreparingShare = true
            let file = await videoFile()
            isPreparingShare = false
            if let file, let data = try? Data(contentsOf: file),
               await InstagramStories.share(backgroundVideo: data, appID: instagramAppID) { return }
            toastMessage = String(localized: "Couldn’t open Instagram")
            return
        }
        guard let data = await preparedCard() else { return }
        if !(await InstagramStories.share(background: data, appID: instagramAppID)) {
            toastMessage = String(localized: "Couldn’t open Instagram")
        }
    }

    /// The share sheet closed; `completed` is false when the user cancelled.
    func shareSheetClosed(activity: UIActivity.ActivityType?, completed: Bool) {
        shareItem = nil
        playerShareItem = nil
        guard completed else { return }
        analytics.track(.dreamShared(target: activity == .saveToCameraRoll ? .photos : .shareSheet))
    }

    private func preparedCard() async -> Data? {
        if let cardData { return cardData }
        isPreparingShare = true
        defer { isPreparingShare = false }
        if let shareCards, let dreamID = dream?.id, let data = try? await shareCards.cardImage(dreamID: dreamID) {
            cardData = data
            return data
        }
        // No card (mock mode, offline, still rendering): the dream image itself.
        return loadedImageData ?? DreamImage.uiImage(named: imageName)?.jpegData(compressionQuality: 0.95)
    }

    func saveImage() async {
        guard !isSavingImage else { return }
        guard imagePhase == .asset || loadedImageData != nil else {
            toastMessage = String(localized: "The image isn’t ready yet")
            return
        }
        isSavingImage = true
        defer { isSavingImage = false }
        do {
            if let loadedImageData {
                try await imageSaver.saveImage(data: loadedImageData)
            } else {
                try await imageSaver.saveImage(named: imageName)
            }
            toastMessage = String(localized: "Saved to Photos")
            analytics.track(.dreamShared(target: .photos))
        } catch ImageSavingError.accessDenied {
            toastMessage = String(localized: "Allow Photos access in Settings to save")
        } catch {
            toastMessage = String(localized: "Couldn’t save the image")
        }
    }

    private func notesChanged() {
        if notes.count > Self.notesLimit {
            notes = String(notes.prefix(Self.notesLimit))
            return
        }
        guard var dream, dream.notes != notes else { return }
        dream.notes = notes
        self.dream = dream
        store.save(dream)
        unsentNotes = notes
        notesTask?.cancel()
        notesTask = Task { [weak self, notesDebounce] in
            try? await Task.sleep(for: notesDebounce)
            guard !Task.isCancelled else { return }
            await self?.sendNotes()
        }
    }

    /// Leaving the screen: what was typed goes up now instead of after the pause.
    func flushNotes() async {
        notesTask?.cancel()
        await sendNotes()
    }

    private func sendNotes() async {
        guard let notesService, let dreamID = dream?.id, let text = unsentNotes else { return }
        do {
            try await notesService.saveNotes(text, dreamID: dreamID)
            // Typed more while this was on the way: that newer text is still unsent.
            if unsentNotes == text { unsentNotes = nil }
        } catch {
            // Kept on the device; the next edit or leaving the screen tries again.
        }
    }
}
