import Foundation
import Observation

/// 11 Interpretation. Main lens = on-screen override ?? preferred lens; the other two are alternatives.
@MainActor
@Observable
final class InterpretationViewModel {
    private(set) var dream: Dream?
    private(set) var lensOverride: Lens?
    private(set) var expandedLenses: Set<Lens> = []
    private(set) var isSavingImage = false
    var toastMessage: String?
    var notes: String {
        didSet { saveNotes() }
    }

    let readAloud: any ReadAloudService
    private let store: any DreamStore
    private let appState: AppState
    private let imageSaver: any ImageSaving
    private let dateFormatter: DreamDateFormatter
    private let supportContent: any SupportContentProvider
    private let region: Locale.Region?

    init(dreamID: Dream.ID,
         store: any DreamStore,
         appState: AppState,
         readAloud: any ReadAloudService,
         imageSaver: any ImageSaving,
         supportContent: any SupportContentProvider = PendingSupportContent(),
         region: Locale.Region? = Locale.current.region,
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
    }

    // MARK: Content

    /// A crisis-flagged dream: the support screen replaces the reading, the image, the voice and
    /// sharing (the backend generates neither image nor voice for it).
    var support: SupportContent? {
        guard dream?.interpretation?.safetyFlag == true else { return nil }
        return supportContent.content(for: region)
    }

    var mainLens: Lens { lensOverride ?? appState.preferredLens }

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

    /// "Make this my main lens": swaps it into the main card, resets the player, collapses both.
    func promote(_ lens: Lens) {
        readAloud.stop()
        lensOverride = lens
        expandedLenses = []
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

    private func saveNotes() {
        guard var dream, dream.notes != notes else { return }
        dream.notes = notes
        self.dream = dream
        store.save(dream)
    }
}
