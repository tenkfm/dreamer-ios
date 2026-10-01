import Foundation
import Observation

/// Record -> Details -> Analysis, presented as one full-screen cover.
@MainActor
@Observable
final class RecordFlowViewModel {
    enum Step { case record, details, analysis }

    private(set) var step: Step = .record
    let record: RecordViewModel
    private(set) var details: DetailsViewModel?
    private(set) var analysis: AnalysisViewModel?

    private let analysisService: any DreamAnalysisService
    private let store: any DreamStore
    private let drafts: DraftQueue?
    private let analytics: any Analytics
    /// One id for this dream across retries, so the backend never creates it twice.
    private let clientId = UUID().uuidString.lowercased()
    private let recordedAt = Date.now
    /// The server transcription the text came from (IOS-04.5), sent with the dream.
    private var recordingID: String?
    private let onFinish: (Dream.ID) -> Void
    private let onCancel: () -> Void

    init(speech: any SpeechService,
         permissions: any SpeechPermissions = MockSpeechPermissions(),
         transcriber: (any RecordingTranscriber)? = nil,
         analytics: any Analytics = NoopAnalytics(),
         analysisService: any DreamAnalysisService,
         store: any DreamStore,
         drafts: DraftQueue? = nil,
         onFinish: @escaping (Dream.ID) -> Void,
         onCancel: @escaping () -> Void) {
        record = RecordViewModel(speech: speech, permissions: permissions, transcriber: transcriber, analytics: analytics)
        self.analytics = analytics
        self.analysisService = analysisService
        self.store = store
        self.drafts = drafts
        self.onFinish = onFinish
        self.onCancel = onCancel
    }

    convenience init(dependencies: AppDependencies,
                     onFinish: @escaping (Dream.ID) -> Void,
                     onCancel: @escaping () -> Void) {
        self.init(speech: dependencies.makeSpeechService(),
                  permissions: dependencies.makeSpeechPermissions(),
                  transcriber: dependencies.transcriber,
                  analytics: dependencies.analytics,
                  analysisService: dependencies.analysis,
                  store: dependencies.dreamStore,
                  drafts: dependencies.drafts,
                  onFinish: onFinish,
                  onCancel: onCancel)
    }

    /// "I’m done".
    func finishRecording() async {
        guard let recorded = await record.finish() else { return }
        showDetails(for: recorded)
    }

    func showDetails(for recorded: RecordViewModel.RecordedDream) {
        recordingID = recorded.recordingID
        details = DetailsViewModel(transcript: recorded.transcript, clientId: clientId)
        step = .details
    }

    /// "Interpret my dream" (with details) or "Skip" (without).
    func interpret(includeDetails: Bool) {
        var draft = includeDetails
            ? details?.draft ?? DreamDraft(clientId: clientId, transcript: record.trimmedTranscript)
            : DreamDraft(clientId: clientId, transcript: record.trimmedTranscript)
        draft.recordedAt = recordedAt
        draft.recordingId = recordingID
        analytics.track(.detailsSubmitted(skipped: !includeDetails, emotionsCount: draft.emotions.count))
        analysis = AnalysisViewModel(draft: draft, service: analysisService, store: store, drafts: drafts)
        step = .analysis
    }

    /// A dream told before and never read: straight to Analysis with it.
    func read(_ draft: DreamDraft) {
        analysis = AnalysisViewModel(draft: draft, service: analysisService, store: store, drafts: drafts)
        step = .analysis
    }

    /// "See my interpretation".
    func showInterpretation() {
        guard let dream = analysis?.result else { return }
        onFinish(dream.id)
    }

    func cancel() {
        record.stop()
        record.discardAudio()
        onCancel()
    }
}
