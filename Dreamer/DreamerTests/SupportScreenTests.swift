import Foundation
import Testing
@testable import Dreamer

@MainActor
struct SupportScreenTests {
    /// Approved content stands in for the pending draft.
    struct FixedSupport: SupportContentProvider {
        func content(for region: Locale.Region?) -> SupportContent {
            SupportContent(title: "Title for \(region?.identifier ?? "none")", message: "Message", emergencyNote: "Note",
                           resources: [.init(name: "Line", detail: "24/7", contact: .phone("+1 (555) 010-0000"))])
        }
    }

    private func makeViewModel(flagged: Bool, region: Locale.Region? = .unitedStates) -> InterpretationViewModel {
        let store = InMemoryDreamStore()
        var dream = store.dreams[0]
        dream.interpretation?.safetyFlag = flagged
        store.save(dream)
        return InterpretationViewModel(dreamID: dream.id, store: store, appState: AppState(store: InMemoryPreferencesStore()),
                                       readAloud: MockReadAloudService(), imageSaver: MockImageSaver(),
                                       supportContent: FixedSupport(), region: region)
    }

    @Test func aCalmDreamShowsTheReading() {
        #expect(makeViewModel(flagged: false).support == nil)
    }

    @Test func aFlaggedDreamShowsSupportForTheUsersCountry() {
        let support = makeViewModel(flagged: true, region: .germany).support
        #expect(support?.title == "Title for DE")
        #expect(support?.resources.count == 1)
    }

    @Test func phoneResourcesDialTheDigitsOnly() {
        let resource = SupportResource(name: "Line", detail: "", contact: .phone("+1 (555) 010-0000"))
        #expect(resource.url?.absoluteString == "tel:+15550100000")
    }

    /// Until Tony approves the texts and services, no phone number is guessed.
    @Test func pendingContentListsNoServices() {
        let content = PendingSupportContent().content(for: .unitedKingdom)
        #expect(content.resources.isEmpty)
        #expect(!content.emergencyNote.isEmpty)
        #expect(!content.title.contains("—") && !content.message.contains("—"))
    }

    @Test func streamedReadingDisappearsWhenTheDreamIsFlagged() async {
        struct FlaggedAnalysis: DreamAnalysisService {
            func analyze(_ draft: DreamDraft) -> AsyncThrowingStream<AnalysisProgress, Error> {
                AsyncThrowingStream { continuation in
                    var dream = MockData.analyzedDream(from: draft, at: .now)
                    dream.interpretation?.safetyFlag = true
                    continuation.yield(.writing("Stairs often mean"))
                    continuation.yield(.finished(dream))
                    continuation.finish()
                }
            }
        }
        let viewModel = AnalysisViewModel(draft: DreamDraft(transcript: "A dream"), service: FlaggedAnalysis(),
                                          store: InMemoryDreamStore(seed: []))
        await viewModel.run()
        #expect(viewModel.writtenText.isEmpty)
        #expect(viewModel.isFinished)
    }
}
