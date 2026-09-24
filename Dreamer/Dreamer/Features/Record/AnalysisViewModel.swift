import Foundation
import Observation

/// 10 Analysis: shows the service's progress and saves the resulting dream.
@MainActor
@Observable
final class AnalysisViewModel {
    enum StepStatus { case done, active, pending }

    let steps = AnalysisStep.allCases
    private(set) var completed: Set<AnalysisStep> = []
    private(set) var result: Dream?
    private(set) var errorMessage: String?

    private let draft: DreamDraft
    private let service: any DreamAnalysisService
    private let store: any DreamStore

    init(draft: DreamDraft, service: any DreamAnalysisService, store: any DreamStore) {
        self.draft = draft
        self.service = service
        self.store = store
    }

    var isFinished: Bool { result != nil }

    func status(of step: AnalysisStep) -> StepStatus {
        if completed.contains(step) { return .done }
        let firstPending = steps.first { !completed.contains($0) }
        return step == firstPending && errorMessage == nil ? .active : .pending
    }

    func run() async {
        guard result == nil else { return }
        errorMessage = nil
        completed = []
        do {
            for try await progress in service.analyze(draft) {
                switch progress {
                case .completed(let step):
                    completed.insert(step)
                case .finished(let dream):
                    store.save(dream)
                    result = dream
                }
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "We couldn’t read this dream right now. Please try again."
        }
    }
}
