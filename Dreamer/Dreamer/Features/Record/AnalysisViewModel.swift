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
    /// The main lens as the backend writes it (first words well before the dream is ready).
    private(set) var writtenText = ""
    private(set) var errorMessage: String?
    /// Set when the failure came from the backend (paywall, limit, sign-in...).
    private(set) var errorState: ErrorState?

    /// The dream could not be sent (no connection): it waits in the draft queue.
    private(set) var isSavedOffline = false

    let draft: DreamDraft
    private let service: any DreamAnalysisService
    private let store: any DreamStore
    private let drafts: DraftQueue?

    init(draft: DreamDraft, service: any DreamAnalysisService, store: any DreamStore, drafts: DraftQueue? = nil) {
        self.draft = draft
        self.service = service
        self.store = store
        self.drafts = drafts
    }

    var isFinished: Bool { result != nil }

    /// "Try again" makes sense unless the answer is "wait until later" or "sign in".
    var canRetry: Bool {
        guard let errorState else { return true }
        return errorState.action == .retry && errorState.retryAfter == nil
    }

    func status(of step: AnalysisStep) -> StepStatus {
        if completed.contains(step) { return .done }
        let firstPending = steps.first { !completed.contains($0) }
        return step == firstPending && errorMessage == nil ? .active : .pending
    }

    func run() async {
        guard result == nil else { return }
        errorMessage = nil
        errorState = nil
        isSavedOffline = false
        completed = []
        writtenText = ""
        // Saved before sending: a crash or a relaunch mid-request still has the dream.
        drafts?.save(draft)
        do {
            for try await progress in service.analyze(draft) {
                switch progress {
                case .accepted:
                    drafts?.markSent(clientId: draft.clientId)
                case .completed(let step):
                    completed.insert(step)
                case .writing(let text):
                    writtenText = text
                case .finished(let dream):
                    // A crisis-flagged dream gets the support screen: no reading stays in view.
                    if dream.interpretation?.safetyFlag == true { writtenText = "" }
                    store.save(dream)
                    result = dream
                }
            }
        } catch is CancellationError {
            return
        } catch let error as APIError where (error == .offline || error == .timeout) && drafts != nil {
            // Not lost: the draft queue sends it when the connection is back.
            isSavedOffline = true
        } catch let error as APIError {
            errorState = ErrorState(error)
            errorMessage = errorState?.message
        } catch {
            errorMessage = String(localized: "We couldn’t read this dream right now. Please try again.")
        }
    }
}
