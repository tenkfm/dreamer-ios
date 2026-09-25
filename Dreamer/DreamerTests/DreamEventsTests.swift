import Foundation
import os
import Testing
@testable import Dreamer

struct SSEParserTests {
    @Test func parsesEventsCommentsAndMultilineData() {
        var parser = SSEParser()
        let lines = [": keep-alive", "", "event: step", "data: {\"type\":\"step\",\"analysisStep\":2}", "",
                     "event: text", "data: line one", "data: line two", "", "data: no event name", ""]
        let messages = lines.compactMap { parser.consume(line: $0) }

        #expect(messages == [
            SSEMessage(event: "step", data: "{\"type\":\"step\",\"analysisStep\":2}"),
            SSEMessage(event: "text", data: "line one\nline two"),
            SSEMessage(event: "message", data: "no event name")
        ])
    }

    @Test func decodesTheContractEvents() throws {
        #expect(try DreamEvent.decode(.init(event: "step", data: #"{"type":"step","analysisStep":3}"#)) == .step(3))
        #expect(try DreamEvent.decode(.init(event: "text", data: #"{"type":"text","lens":"psychology","delta":"Hello"}"#))
                == .text(lens: .psychology, delta: "Hello", reset: false))
        #expect(try DreamEvent.decode(.init(event: "text", data: #"{"type":"text","lens":"psychology","delta":"","reset":true}"#))
                == .text(lens: .psychology, delta: "", reset: true))
        #expect(try DreamEvent.decode(.init(event: "error", data: #"{"type":"error","code":"DREAM_FAILED","message":"x"}"#))
                == .failed(.dreamFailed, message: "x"))
        #expect(try DreamEvent.decode(.init(event: "future", data: "{}")) == nil)

        let ready = try DreamEvent.decode(.init(event: "ready", data: #"{"type":"ready","dream":\#(APIClientTests.dreamJSON)}"#))
        guard case .ready(let dream) = ready else { Issue.record("Expected ready"); return }
        #expect(dream.title == "The house with endless stairs")
    }
}

struct DreamProgressTrackerTests {
    static let dreamID = UUID(uuidString: "0B6F3C55-1D3C-4B8E-9F1E-2C7A8E5D4F10")!

    static func sse(_ events: [(String, String)], keepAlive: Bool = true) -> String {
        var body = keepAlive ? ": keep-alive\r\n\r\n" : ""
        // The server writes JSON.stringify output: one line per event.
        for (name, data) in events {
            body += "event: \(name)\r\ndata: \(data.replacingOccurrences(of: "\n", with: " "))\r\n\r\n"
        }
        return body
    }

    private func collect(_ stream: AsyncThrowingStream<DreamEvent, any Error>) async throws -> [DreamEvent] {
        var events: [DreamEvent] = []
        for try await event in stream { events.append(event) }
        return events
    }

    @Test func streamsStepsTextAndTheResult() async throws {
        let body = Self.sse([
            ("step", #"{"type":"step","analysisStep":1}"#),
            ("text", #"{"type":"text","lens":"spiritual","delta":"Going down "}"#),
            ("text", #"{"type":"text","lens":"spiritual","delta":"","reset":true}"#),
            ("text", #"{"type":"text","lens":"spiritual","delta":"Stairs"}"#),
            ("ready", #"{"type":"ready","dream":\#(APIClientTests.dreamJSON)}"#)
        ])
        let (client, host) = StubURLProtocol.makeClient(tokens: StaticTokens()) { _ in
            .init(status: 200, headers: ["Content-Type": "text/event-stream"], body: Data(body.utf8))
        }
        let events = try await collect(DreamProgressTracker(client: client).events(for: Self.dreamID))

        #expect(events.count == 5)
        #expect(events[0] == .step(1))
        #expect(events[2] == .text(lens: .spiritual, delta: "", reset: true))
        guard case .ready(let dream) = events.last else { Issue.record("Expected ready last"); return }
        #expect(dream.mainLens == .spiritual)
        let request = try #require(StubURLProtocol.requests(for: host).first)
        #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-1")
    }

    @Test func fallsBackToPollingWhenTheStreamEndsEarly() async throws {
        let polls = OSAllocatedUnfairLock(initialState: 0)
        let (client, host) = StubURLProtocol.makeClient(tokens: StaticTokens()) { request in
            let path = request.url?.path() ?? ""
            if path.hasSuffix("/events") {
                // The server closed the stream (120 s) before the dream was ready.
                return .init(status: 200, headers: ["Content-Type": "text/event-stream"],
                             body: Data(Self.sse([("step", #"{"type":"step","analysisStep":1}"#)]).utf8))
            }
            if path.hasSuffix("/status") {
                let n = polls.withLock { $0 += 1; return $0 }
                if n == 1 { return .init(status: 0, body: Data(), error: URLError(.networkConnectionLost)) }
                let status = n < 3 ? "analyzing" : "ready"
                return .json(200, #"{"id":"0b6f3c55-1d3c-4b8e-9f1e-2c7a8e5d4f10","status":"\#(status)","analysisStep":\#(n < 3 ? 2 : 4),"title":null,"errorCode":null}"#)
            }
            return .json(200, APIClientTests.dreamJSON)
        }
        let tracker = DreamProgressTracker(client: client, pollInterval: .milliseconds(5))
        let events = try await collect(tracker.events(for: Self.dreamID))

        #expect(events.first == .step(1))
        #expect(events.contains(.step(2)))
        #expect(events.contains(.step(4)))
        guard case .ready = events.last else { Issue.record("Expected ready last"); return }
        #expect(StubURLProtocol.requests(for: host).last?.url?.path() == "/v1/dreams/0b6f3c55-1d3c-4b8e-9f1e-2c7a8e5d4f10")
    }

    @Test func failedDreamEndsWithTheErrorCode() async throws {
        let (client, _) = StubURLProtocol.makeClient(tokens: StaticTokens()) { _ in
            .init(status: 200, headers: ["Content-Type": "text/event-stream"],
                  body: Data(Self.sse([("error", #"{"type":"error","code":"DREAM_FAILED","message":"Try again"}"#)]).utf8))
        }
        let events = try await collect(DreamProgressTracker(client: client).events(for: Self.dreamID))
        #expect(events == [.failed(.dreamFailed, message: "Try again")])
    }
}
