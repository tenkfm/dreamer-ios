import AVFoundation
import Foundation
import Testing
@testable import Dreamer

/// A file standing for a recording, in the recordings folder.
private func makeAudioFile(bytes: Int = 2048, duration: TimeInterval = 3) throws -> RecordedAudio {
    let url = try RecordingFiles.newFileURL()
    try Data(repeating: 7, count: bytes).write(to: url)
    return RecordedAudio(url: url, duration: duration)
}

private func exists(_ audio: RecordedAudio) -> Bool {
    FileManager.default.fileExists(atPath: audio.url.path(percentEncoded: false))
}

struct AudioRecordingFileTests {
    /// A sine tone in the microphone's format.
    private func tone(seconds: Double, sampleRate: Double, channels: AVAudioChannelCount) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<Int(channels) {
            let samples = buffer.floatChannelData![channel]
            for index in 0..<Int(frames) {
                samples[index] = 0.3 * sin(2 * .pi * 440 * Float(index) / Float(sampleRate))
            }
        }
        return buffer
    }

    @Test func microphoneBuffersBecomeASmallM4a() throws {
        let file = try AudioRecordingFile(url: RecordingFiles.newFileURL())
        // Buffers as the tap delivers them (about 0.1 s each), across two formats as after a route change.
        for _ in 0..<10 { file.append(tone(seconds: 0.1, sampleRate: 44_100, channels: 1)) }
        for _ in 0..<10 { file.append(tone(seconds: 0.1, sampleRate: 48_000, channels: 2)) }
        let audio = file.finish()
        defer { audio.delete() }

        #expect(abs(audio.duration - 2) < 0.1)
        let written = try AVAudioFile(forReading: audio.url)
        #expect(written.fileFormat.settings[AVFormatIDKey] as? UInt32 == kAudioFormatMPEG4AAC)
        #expect(written.fileFormat.sampleRate == AudioRecordingFile.sampleRate)
        #expect(written.fileFormat.channelCount == 1)
        #expect(abs(Double(written.length) / written.fileFormat.sampleRate - 2) < 0.15)
        // About 32 kbit/s: five minutes (the recording limit) stay far under the 20 MB upload limit.
        let fiveMinutes = Double(audio.sizeBytes) / audio.duration * 300
        #expect(audio.sizeBytes > 0 && fiveMinutes < 20_971_520 / 4)
    }

    @Test func appendingAfterFinishIsIgnored() throws {
        let file = try AudioRecordingFile(url: RecordingFiles.newFileURL())
        file.append(tone(seconds: 0.5, sampleRate: 44_100, channels: 1))
        let audio = file.finish()
        defer { audio.delete() }
        file.append(tone(seconds: 0.5, sampleRate: 44_100, channels: 1))
        #expect(abs(file.duration - 0.5) < 0.05)
    }
}

@Suite(.serialized)
struct RecordingFilesTests {
    @Test func purgeRemovesRecordingsLeftByACrash() throws {
        let leftover = try makeAudioFile()
        #expect(exists(leftover))
        RecordingFiles.purge()
        #expect(!exists(leftover))
        #expect(RecordingFiles.leftovers.isEmpty)
    }
}

struct RecognizerChoiceTests {
    /// A language no iPhone recognizes: with the server fallback there is no live recognizer
    /// (the audio is transcribed at the end); without it, US English is better than nothing.
    @Test func unsupportedLocaleUsesTheServerWhenAllowed() {
        let unsupported = Locale(identifier: "tlh-001")
        #expect(OnDeviceSpeechService.recognizer(for: unsupported, serverFallback: true) == nil)
        let fallback = OnDeviceSpeechService.recognizer(for: unsupported, serverFallback: false)
        #expect(fallback?.locale.identifier == "en-US")
    }
}

struct APIRecordingTranscriberTests {
    private static func uploadURLJSON(host: String) -> String {
        #"{"recordingId":"rec_1","uploadUrl":"https://\#(host)/storage/rec_1.m4a?X-Amz-Signature=abc","expiresAt":"2026-10-21T08:10:00.000Z"}"#
    }

    @Test func uploadsWithTheSignedUrlAndDeletesTheFile() async throws {
        let audio = try makeAudioFile(bytes: 4096)
        let (client, host) = StubURLProtocol.makeClient(tokens: StaticTokens()) { request in
            switch (request.httpMethod, request.url?.path()) {
            case ("POST", "/v1/recordings/upload-url"): .json(201, Self.uploadURLJSON(host: request.url!.host()!))
            case ("PUT", "/storage/rec_1.m4a"): .empty(200)
            default: .empty(404)
            }
        }
        let recordingID = try await APIRecordingTranscriber(client: client).upload(audio)

        #expect(recordingID == "rec_1")
        #expect(!exists(audio))
        let requests = StubURLProtocol.requests(for: host)
        let ask = try #require(requests.first { $0.url?.path() == "/v1/recordings/upload-url" })
        let body = try JSONSerialization.jsonObject(with: ask.httpBody ?? Data()) as? [String: Any]
        #expect(body?["contentType"] as? String == "audio/m4a")
        #expect(body?["sizeBytes"] as? Int == 4096)
        let put = try #require(requests.first { $0.httpMethod == "PUT" })
        #expect(put.value(forHTTPHeaderField: "Content-Type") == "audio/m4a")
        #expect(put.value(forHTTPHeaderField: "Content-Length") == "4096")
        // Storage gets the signature from the URL, never the user's token.
        #expect(put.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func aRejectedUploadKeepsTheFileForTryAgain() async throws {
        let audio = try makeAudioFile()
        defer { audio.delete() }
        let (client, _) = StubURLProtocol.makeClient(tokens: StaticTokens()) { request in
            request.httpMethod == "PUT" ? .empty(403) : .json(201, Self.uploadURLJSON(host: request.url!.host()!))
        }
        await #expect(throws: APIError.invalidResponse(status: 403)) {
            _ = try await APIRecordingTranscriber(client: client).upload(audio)
        }
        #expect(exists(audio))
    }

    @Test func offlineUploadKeepsTheFile() async throws {
        let audio = try makeAudioFile()
        defer { audio.delete() }
        let (client, _) = StubURLProtocol.makeClient(tokens: StaticTokens()) { _ in
            .init(status: 0, body: Data(), error: URLError(.notConnectedToInternet))
        }
        await #expect(throws: APIError.offline) {
            _ = try await APIRecordingTranscriber(client: client).upload(audio)
        }
        #expect(exists(audio))
    }

    @Test func transcribeReturnsTheText() async throws {
        let (client, host) = StubURLProtocol.makeClient(tokens: StaticTokens()) { _ in
            .json(200, #"{"recordingId":"rec_1","text":"I was flying over the sea."}"#)
        }
        let text = try await APIRecordingTranscriber(client: client).transcribe(recordingID: "rec_1")
        #expect(text == "I was flying over the sea.")
        #expect(StubURLProtocol.requests(for: host).map { $0.url?.path() } == ["/v1/recordings/rec_1/transcribe"])
    }

    @Test func providerUnavailableIsNotRetried() async throws {
        let (client, host) = StubURLProtocol.makeClient(tokens: StaticTokens()) { _ in
            .json(503, #"{"error":{"code":"PROVIDER_UNAVAILABLE","message":"Speech recognition is not configured"}}"#)
        }
        await #expect(throws: APIError.self) {
            _ = try await APIRecordingTranscriber(client: client).transcribe(recordingID: "rec_1")
        }
        // The backend deletes the audio on the first call: a second one could only be a 404.
        #expect(StubURLProtocol.requests(for: host).count == 1)
    }
}

/// The record screen's side of the fallback.
@MainActor
struct ServerFallbackRecordTests {
    /// No live text; hands over a recording file once.
    final class AudioOnlySpeech: SpeechService {
        var recording: RecordedAudio?
        private(set) var takes = 0
        private(set) var discards = 0
        init(recording: RecordedAudio?) { self.recording = recording }
        var keepsAudio: Bool { true }
        func start() -> AsyncThrowingStream<SpeechEvent, any Error> {
            AsyncThrowingStream { $0.yield(.liveTextUnavailable) }
        }
        func stop() {}
        func takeRecording() -> RecordedAudio? {
            takes += 1
            defer { recording = nil }
            return recording
        }
        func discardRecording() {
            discards += 1
            recording?.delete()
            recording = nil
        }
    }

    final class FakeTranscriber: RecordingTranscriber, @unchecked Sendable {
        var uploadResults: [Result<String, APIError>]
        var transcribeResult: Result<String, APIError>
        private(set) var uploads: [RecordedAudio] = []
        private(set) var transcribed: [String] = []

        init(upload: [Result<String, APIError>] = [.success("rec_1")],
             transcribe: Result<String, APIError> = .success("I was flying over the sea.")) {
            uploadResults = upload
            transcribeResult = transcribe
        }

        func upload(_ audio: RecordedAudio) async throws(APIError) -> String {
            uploads.append(audio)
            let result = uploadResults.removeFirst()
            if case .success = result { audio.delete() }
            return try result.get()
        }

        func transcribe(recordingID: String) async throws(APIError) -> String {
            transcribed.append(recordingID)
            return try transcribeResult.get()
        }
    }

    nonisolated private static func serverError(_ status: Int, _ code: APIErrorCode) -> APIError {
        .server(.init(code: code, message: "x", status: status))
    }

    @Test func liveTextKeepsTheAudioOffTheServer() async throws {
        let audio = try makeAudioFile()
        let speech = AudioOnlySpeech(recording: audio)
        let transcriber = FakeTranscriber()
        let viewModel = RecordViewModel(speech: speech, transcriber: transcriber)
        viewModel.transcript = "I was flying."

        let recorded = await viewModel.finish()

        #expect(recorded == .init(transcript: "I was flying."))
        #expect(transcriber.uploads.isEmpty)
        #expect(speech.discards == 1)
        #expect(!exists(audio))
    }

    @Test func noLiveTextIsWrittenDownOnTheServer() async throws {
        let audio = try makeAudioFile()
        let transcriber = FakeTranscriber()
        let viewModel = RecordViewModel(speech: AudioOnlySpeech(recording: audio), transcriber: transcriber)
        viewModel.start()
        try await Task.sleep(for: .milliseconds(30))
        #expect(viewModel.isLiveTextUnavailable)

        let recorded = await viewModel.finish()

        #expect(recorded == .init(transcript: "I was flying over the sea.", recordingID: "rec_1"))
        #expect(viewModel.transcript == "I was flying over the sea.")
        #expect(transcriber.transcribed == ["rec_1"])
        #expect(viewModel.serverTranscription == nil)
        #expect(!exists(audio))
    }

    @Test func offlineUploadCanBeTriedAgainWithTheSameAudio() async throws {
        let audio = try makeAudioFile()
        let speech = AudioOnlySpeech(recording: audio)
        let transcriber = FakeTranscriber(upload: [.failure(.offline), .success("rec_2")])
        let viewModel = RecordViewModel(speech: speech, transcriber: transcriber)

        #expect(await viewModel.finish() == nil)
        #expect(viewModel.serverTranscription == .failed(.offline))
        #expect(viewModel.pauseMessage == RecordViewModel.TranscriptionFailure.offline.message)
        #expect(exists(audio))
        #expect(viewModel.canFinish)

        let recorded = await viewModel.finish()
        #expect(recorded?.recordingID == "rec_2")
        #expect(speech.takes == 1)
        #expect(transcriber.uploads == [audio, audio])
    }

    @Test(arguments: [
        (serverError(503, .providerUnavailable), RecordViewModel.TranscriptionFailure.unavailable),
        (serverError(429, .limitReached), .limitReached),
        (serverError(404, .notFound), .unavailable),
        (APIError.offline, .unavailable)
    ])
    func failedTranscriptionAsksToType(error: APIError, expected: RecordViewModel.TranscriptionFailure) async throws {
        let audio = try makeAudioFile()
        let viewModel = RecordViewModel(speech: AudioOnlySpeech(recording: audio),
                                        transcriber: FakeTranscriber(transcribe: .failure(error)))

        #expect(await viewModel.finish() == nil)
        #expect(viewModel.serverTranscription == .failed(expected))
        // The server heard it once and deleted it: nothing to send again, and nothing kept here.
        #expect(!expected.canRetry)
        #expect(!exists(audio))
    }

    @Test func silenceGivesNoWords() async throws {
        let viewModel = RecordViewModel(speech: AudioOnlySpeech(recording: try makeAudioFile()),
                                        transcriber: FakeTranscriber(transcribe: .success("  ")))
        #expect(await viewModel.finish() == nil)
        #expect(viewModel.serverTranscription == .failed(.noWords))
    }

    @Test func tooShortRecordingGivesNoWords() async {
        let viewModel = RecordViewModel(speech: AudioOnlySpeech(recording: nil), transcriber: FakeTranscriber())
        #expect(await viewModel.finish() == nil)
        #expect(viewModel.serverTranscription == .failed(.noWords))
    }

    @Test func typingClearsTheFailure() async throws {
        let viewModel = RecordViewModel(speech: AudioOnlySpeech(recording: try makeAudioFile()),
                                        transcriber: FakeTranscriber(transcribe: .failure(Self.serverError(503, .providerUnavailable))))
        _ = await viewModel.finish()
        viewModel.switchToTyping()
        #expect(viewModel.serverTranscription == nil)
        viewModel.transcript = "Typed instead."
        #expect(await viewModel.finish() == .init(transcript: "Typed instead."))
    }

    @Test func doneNeedsWordsOrServerAudio() async throws {
        let withServer = RecordViewModel(speech: AudioOnlySpeech(recording: nil), transcriber: FakeTranscriber(),
                                         tick: .milliseconds(5))
        #expect(!withServer.canFinish)
        withServer.start()
        try await Task.sleep(for: .milliseconds(60))
        #expect(withServer.canFinish)
        withServer.stop()

        let withoutServer = RecordViewModel(speech: AudioOnlySpeech(recording: nil), tick: .milliseconds(5))
        withoutServer.start()
        try await Task.sleep(for: .milliseconds(60))
        #expect(!withoutServer.canFinish)
        withoutServer.stop()
    }

    @Test func theDreamLinksToItsRecording() async throws {
        let store = InMemoryDreamStore()
        let flow = RecordFlowViewModel(speech: AudioOnlySpeech(recording: try makeAudioFile()),
                                       transcriber: FakeTranscriber(),
                                       analysisService: MockDreamAnalysisService(stepDuration: .zero),
                                       store: store, onFinish: { _ in }, onCancel: {})
        await flow.finishRecording()
        #expect(flow.step == .details)
        #expect(flow.details?.transcript == "I was flying over the sea.")
        flow.interpret(includeDetails: false)
        let draft = try #require(flow.analysis).draft
        #expect(draft.recordingId == "rec_1")
    }

    @Test func closingTheFlowDeletesTheRecording() async throws {
        let audio = try makeAudioFile()
        let speech = AudioOnlySpeech(recording: audio)
        let viewModel = RecordViewModel(speech: speech, transcriber: FakeTranscriber(upload: [.failure(.offline)]))
        _ = await viewModel.finish()
        #expect(exists(audio))

        viewModel.discardAudio()
        #expect(!exists(audio))
        #expect(speech.discards == 1)
    }
}
