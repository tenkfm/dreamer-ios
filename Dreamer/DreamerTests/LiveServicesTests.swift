import Foundation
import Testing
@testable import Dreamer

struct ServiceModeTests {
    private let staging = AppConfig(infoDictionary: ["DreamerAPIBaseURL": "https://api-staging-0ea4.up.railway.app"])

    @Test func buildWithoutAnAPIHostUsesMocks() {
        #expect(AppDependencies.mode(config: AppConfig(infoDictionary: [:]), arguments: []) == .mock)
    }

    @Test func mockServicesArgumentKeepsMocks() {
        #expect(AppDependencies.mode(config: staging, arguments: ["Dreamer", "-mockServices"]) == .mock)
    }

    @Test func stagingBuildTalksToTheBackend() {
        #expect(AppDependencies.mode(config: staging, arguments: ["Dreamer"]) == .live)
    }
}

@MainActor
struct APIDreamAnalysisServiceTests {
    private func run(_ service: APIDreamAnalysisService, draft: DreamDraft) async throws -> [AnalysisProgress] {
        var progress: [AnalysisProgress] = []
        for try await item in service.analyze(draft) { progress.append(item) }
        return progress
    }

    private func steps(_ progress: [AnalysisProgress]) -> [AnalysisStep] {
        progress.compactMap { if case .completed(let step) = $0 { step } else { nil } }
    }

    /// The fixture as a dream still being read (only the dream's own status: the audio has one too).
    nonisolated private static func analyzingDream() -> String {
        var json = APIClientTests.dreamJSON
        if let range = json.range(of: #""status": "ready""#) {
            json.replaceSubrange(range, with: #""status": "analyzing""#)
        }
        return json.replacingOccurrences(of: #""analysisStep": 4"#, with: #""analysisStep": 1"#)
    }

    @Test func createsTheDreamAndFollowsItToTheEnd() async throws {
        let recorder = BodyRecorder()
        let (client, _) = StubURLProtocol.makeClient(tokens: StaticTokens(), middlewares: [recorder]) { request in
            if request.url?.path().hasSuffix("/events") == true {
                let body = DreamProgressTrackerTests.sse([
                    ("step", #"{"type":"step","analysisStep":3}"#),
                    ("ready", #"{"type":"ready","dream":\#(APIClientTests.dreamJSON)}"#)
                ])
                return .init(status: 200, headers: ["Content-Type": "text/event-stream"], body: Data(body.utf8))
            }
            return .json(201, Self.analyzingDream())
        }
        let draft = DreamDraft(clientId: "client-abc", transcript: "I was back in the house", emotions: [.anxiety],
                               recurrence: .often, someoneSpecific: true)
        let progress = try await run(APIDreamAnalysisService(client: client), draft: draft)

        #expect(steps(progress) == AnalysisStep.allCases)
        guard case .finished(let dream) = progress.last else { Issue.record("Expected the dream last"); return }
        #expect(dream.status == .ready)

        let body = try #require(recorder.last)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["clientId"] as? String == "client-abc")
        #expect((json["details"] as? [String: Any])?["recurrence"] as? String == "often")
    }

    @Test func anAlreadyReadDreamFinishesAtOnce() async throws {
        let (client, host) = StubURLProtocol.makeClient(tokens: StaticTokens()) { _ in .json(200, APIClientTests.dreamJSON) }
        let progress = try await run(APIDreamAnalysisService(client: client), draft: DreamDraft(transcript: "Again"))

        #expect(steps(progress).count == 4)
        #expect(StubURLProtocol.requests(for: host).count == 1)
    }

    @Test func failedAnalysisBecomesAnErrorState() async throws {
        let (client, _) = StubURLProtocol.makeClient(tokens: StaticTokens()) { request in
            if request.url?.path().hasSuffix("/events") == true {
                let body = DreamProgressTrackerTests.sse([("error", #"{"type":"error","code":"DREAM_FAILED","message":"Try again"}"#)])
                return .init(status: 200, headers: ["Content-Type": "text/event-stream"], body: Data(body.utf8))
            }
            return .json(201, Self.analyzingDream())
        }
        let viewModel = AnalysisViewModel(draft: DreamDraft(transcript: "A dream"),
                                          service: APIDreamAnalysisService(client: client), store: InMemoryDreamStore(seed: []))
        await viewModel.run()

        #expect(viewModel.errorState?.kind == .dreamFailed)
        #expect(viewModel.result == nil)
    }

    @Test func premiumRequiredShowsThePaywallState() async {
        let (client, _) = StubURLProtocol.makeClient(tokens: StaticTokens()) { _ in
            .json(402, #"{"error":{"code":"PREMIUM_REQUIRED","message":"Subscribe"}}"#)
        }
        let viewModel = AnalysisViewModel(draft: DreamDraft(transcript: "A dream"),
                                          service: APIDreamAnalysisService(client: client), store: InMemoryDreamStore(seed: []))
        await viewModel.run()

        #expect(viewModel.errorState?.action == .openPaywall)
    }
}
