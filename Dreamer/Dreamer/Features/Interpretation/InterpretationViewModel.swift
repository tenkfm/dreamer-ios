import Foundation
import Observation

/// 11 Interpretation. The main lens is the account's preferred lens (the one the backend used for
/// the dream), so a change in Settings shows on dreams already open; the other two are alternatives.
@MainActor
@Observable
final class InterpretationViewModel {
    private(set) var dream: Dream?
    private(set) var expandedLenses: Set<Lens> = []
    private(set) var isSavingImage = false
    var toastMessage: String?
    /// Saved on the device at once and on the backend a moment after typing stops.
    var notes: String {
        didSet { notesChanged() }
    }

    static let notesLimit = 4000

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

    func saveImage() async {
        guard !isSavingImage else { return }
        isSavingImage = true
        defer { isSavingImage = false }
        do {
            try await imageSaver.saveImage(named: imageName)
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
