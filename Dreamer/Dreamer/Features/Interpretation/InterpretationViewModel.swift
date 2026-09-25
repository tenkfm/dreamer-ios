import Foundation
import Observation
import UIKit

/// 11 Interpretation. The main lens is the account's preferred lens (the one the backend used for
/// the dream), so a change in Settings shows on dreams already open; the other two are alternatives.
@MainActor
@Observable
final class InterpretationViewModel {
    private(set) var dream: Dream?
    private(set) var expandedLenses: Set<Lens> = []
    private(set) var isSavingImage = false
    private(set) var imagePhase: ImagePhase = .asset
    /// The downloaded dream image (nil: the asset or the sky placeholder shows).
    private(set) var loadedImage: UIImage?
    private(set) var isRegeneratingImage = false
    /// A new value restarts `loadImage` (after a regeneration).
    private(set) var imageRequest = UUID()
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
    private let region: Locale.Region?

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
         dateFormatter: DreamDateFormatter = DreamDateFormatter()) {
        let dream = store.dream(id: dreamID)
        self.dream = dream
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
        let seconds = Int(dream?.interpretation?.readDurations[mainLens] ?? 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    func isExpanded(_ lens: Lens) -> Bool { expandedLenses.contains(lens) }

    // MARK: Actions

    func togglePlayback() {
        if readAloud.state == .playing {
            readAloud.pause()
        } else {
            readAloud.play(text(for: mainLens))
        }
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
            guard let image = UIImage(data: data) else { throw APIError.invalidResponse(status: nil) }
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
            loadedImage = nil
            loadedImageData = nil
            imagePhase = .generating
            imageRequest = UUID()
        } catch {
            toastMessage = switch error.code {
            case .rateLimited, .limitReached: "That’s all the new images for today. Try again tomorrow."
            default: "Couldn’t make a new image. Please try again."
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

    func saveImage() async {
        guard !isSavingImage else { return }
        guard imagePhase == .asset || loadedImageData != nil else {
            toastMessage = "The image isn’t ready yet"
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
            toastMessage = "Saved to Photos"
        } catch ImageSavingError.accessDenied {
            toastMessage = "Allow Photos access in Settings to save"
        } catch {
            toastMessage = "Couldn’t save the image"
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
