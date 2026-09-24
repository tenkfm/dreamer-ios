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
    private let onFinish: (Dream.ID) -> Void
    private let onCancel: () -> Void

    init(speech: any SpeechService,
         analysisService: any DreamAnalysisService,
         store: any DreamStore,
         onFinish: @escaping (Dream.ID) -> Void,
         onCancel: @escaping () -> Void) {
        record = RecordViewModel(speech: speech)
        self.analysisService = analysisService
        self.store = store
        self.onFinish = onFinish
        self.onCancel = onCancel
    }

    convenience init(dependencies: AppDependencies,
                     onFinish: @escaping (Dream.ID) -> Void,
                     onCancel: @escaping () -> Void) {
        self.init(speech: dependencies.makeSpeechService(),
                  analysisService: dependencies.analysis,
                  store: dependencies.dreamStore,
                  onFinish: onFinish,
                  onCancel: onCancel)
    }

    /// "I’m done".
    func finishRecording() {
        record.stop()
        details = DetailsViewModel(transcript: record.trimmedTranscript)
        step = .details
    }

    /// "Interpret my dream" (with details) or "Skip" (without).
    func interpret(includeDetails: Bool) {
        let draft = includeDetails
            ? details?.draft ?? DreamDraft(transcript: record.trimmedTranscript)
            : DreamDraft(transcript: record.trimmedTranscript)
        analysis = AnalysisViewModel(draft: draft, service: analysisService, store: store)
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
