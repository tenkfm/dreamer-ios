@preconcurrency import AVFoundation
import Foundation
import os

/// The audio of one recording, kept only for the server fallback. The file is the user's voice
/// telling a dream: it lives in a protected temporary folder and is deleted as soon as it is
/// uploaded, when the recording is abandoned, or at the next launch after a crash.
struct RecordedAudio: Sendable, Equatable {
    let url: URL
    let duration: TimeInterval

    static let contentType = "audio/m4a"

    /// Shorter recordings are a mis-tap, not a dream.
    static let minimumDuration: TimeInterval = 1

    var sizeBytes: Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Where recordings wait for the upload.
enum RecordingFiles {
    static var directory: URL {
        URL.temporaryDirectory.appending(path: "Recordings", directoryHint: .isDirectory)
    }

    static func newFileURL() throws -> URL {
        let directory = directory
        // Files created in a protected directory inherit its protection class.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.complete])
        return directory.appending(path: "\(UUID().uuidString.lowercased()).m4a")
    }

    /// At launch: a recording left by a crash or a kill mid-flow must not stay on the device.
    static func purge() {
        try? FileManager.default.removeItem(at: directory)
    }

    static var leftovers: [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    }
}

/// Writes microphone buffers to an m4a file (AAC, 16 kHz mono: plenty for speech, about 2 MB for
/// five minutes, far under the 20 MB upload limit). Buffers arrive on the audio thread, so the
/// state sits behind a lock. The file survives pauses: every listening run appends to it.
final class AudioRecordingFile: @unchecked Sendable {
    static let sampleRate: Double = 16_000

    let url: URL
    private let state: OSAllocatedUnfairLock<State>

    private struct State {
        var file: AVAudioFile?
        var converter: AVAudioConverter?
        var framesWritten: AVAudioFramePosition = 0
    }

    private static let log = Logger(subsystem: "com.braincode.dreamer.io", category: "speech")
    private static let outputFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

    init(url: URL) throws {
        self.url = url
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        state = OSAllocatedUnfairLock(uncheckedState: State(file: file))
    }

    var duration: TimeInterval {
        state.withLockUnchecked { Double($0.framesWritten) / Self.sampleRate }
    }

    /// Converts to 16 kHz mono and appends. Called on the audio thread.
    func append(_ buffer: AVAudioPCMBuffer) {
        state.withLockUnchecked { state in
            guard let file = state.file, buffer.frameLength > 0 else { return }
            // The input format can change between runs (another microphone after a call).
            if state.converter?.inputFormat != buffer.format {
                state.converter = AVAudioConverter(from: buffer.format, to: Self.outputFormat)
            }
            guard let converter = state.converter else { return }
            let ratio = Self.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
            guard let output = AVAudioPCMBuffer(pcmFormat: Self.outputFormat, frameCapacity: capacity) else { return }
            nonisolated(unsafe) var consumed = false
            var error: NSError?
            converter.convert(to: output, error: &error) { _, status in
                if consumed {
                    status.pointee = .noDataNow
                    return nil
                }
                consumed = true
                status.pointee = .haveData
                return buffer
            }
            guard error == nil, output.frameLength > 0 else { return }
            do {
                try file.write(from: output)
                state.framesWritten += AVAudioFramePosition(output.frameLength)
            } catch {
                // A full disk: the text path still works, only the fallback loses this part.
                Self.log.error("Recording write failed")
            }
        }
    }

    /// Closes the file (AVAudioFile finishes the m4a when released; `close()` is iOS 18+).
    func finish() -> RecordedAudio {
        let duration = state.withLockUnchecked { state in
            state.file = nil
            state.converter = nil
            return Double(state.framesWritten) / Self.sampleRate
        }
        return RecordedAudio(url: url, duration: duration)
    }
}

/// The server fallback of speech-to-text, in the two steps the backend offers. The backend deletes
/// the audio after the first transcribe call whatever its outcome, so only the upload can be
/// retried; a failed transcription means typing the dream.
protocol RecordingTranscriber: Sendable {
    /// Presigned upload. On success the local file is deleted and the recording id returned.
    func upload(_ audio: RecordedAudio) async throws(APIError) -> String
    /// The text of an uploaded recording (at most 20 a day). Callable once per recording.
    func transcribe(recordingID: String) async throws(APIError) -> String
}

struct APIRecordingTranscriber: RecordingTranscriber {
    let client: APIClient

    func upload(_ audio: RecordedAudio) async throws(APIError) -> String {
        let data: Data
        do {
            data = try Data(contentsOf: audio.url)
        } catch {
            throw APIError.invalidResponse(status: nil)
        }
        let target = try await client.recordingUploadURL(contentType: RecordedAudio.contentType, sizeBytes: data.count)
        // The presigned URL carries its own signature: no Authorization header leaves for storage.
        var request = URLRequest(url: target.uploadURL, timeoutInterval: 60)
        request.httpMethod = "PUT"
        request.setValue(RecordedAudio.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(String(data.count), forHTTPHeaderField: "Content-Length")
        let response: URLResponse
        do {
            (_, response) = try await client.session.upload(for: request, from: data)
        } catch {
            throw APIError.fromTransport(error)
        }
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
            throw APIError.invalidResponse(status: (response as? HTTPURLResponse)?.statusCode)
        }
        // The storage has it: the voice does not stay on the phone a moment longer.
        audio.delete()
        return target.recordingId
    }

    func transcribe(recordingID: String) async throws(APIError) -> String {
        try await client.transcribeRecording(id: recordingID)
    }
}
