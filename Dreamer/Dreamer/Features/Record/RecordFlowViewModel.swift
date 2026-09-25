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
    /// One id for this dream across retries, so the backend never creates it twice.
    private let clientId = UUID().uuidString.lowercased()
    private let recordedAt = Date.now
    private let onFinish: (Dream.ID) -> Void
    private let onCancel: () -> Void

    init(speech: any SpeechService,
         permissions: any SpeechPermissions = MockSpeechPermissions(),
         analysisService: any DreamAnalysisService,
         store: any DreamStore,
         drafts: DraftQueue? = nil,
         onFinish: @escaping (Dream.ID) -> Void,
         onCancel: @escaping () -> Void) {
        record = RecordViewModel(speech: speech, permissions: permissions)
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
                  analysisService: dependencies.analysis,
                  store: dependencies.dreamStore,
                  drafts: dependencies.drafts,
                  onFinish: onFinish,
                  onCancel: onCancel)
    }

    /// "I’m done".
    func finishRecording() {
        record.stop()
        details = DetailsViewModel(transcript: record.trimmedTranscript, clientId: clientId)
        step = .details
    }

    /// "Interpret my dream" (with details) or "Skip" (without).
    func interpret(includeDetails: Bool) {
        var draft = includeDetails
            ? details?.draft ?? DreamDraft(clientId: clientId, transcript: record.trimmedTranscript)
            : DreamDraft(clientId: clientId, transcript: record.trimmedTranscript)
        draft.recordedAt = recordedAt
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
        onCancel()
    }
}
