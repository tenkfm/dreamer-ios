import Foundation

/// What `GET /v1/dreams/{id}/events` reports while a dream is being read.
enum DreamEvent: Sendable, Equatable {
    /// A step of the Analysis checklist completed (0...4).
    case step(Int)
    /// Text of the main lens as it is written. `reset` = discard what was received so far (the
    /// backend switched to its fallback provider); it comes with an empty delta.
    case text(lens: Lens, delta: String, reset: Bool)
    /// Done: the whole dream.
    case ready(Dream)
    case failed(APIErrorCode, message: String)
}

// MARK: - Server-Sent Events parsing

/// One `event:` / `data:` block of a text/event-stream.
struct SSEMessage: Equatable, Sendable {
    var event: String
    var data: String
}

/// Incremental SSE parser: feed it lines (without their line endings), it returns a message on the
/// blank line that ends each block. Comments (`: keep-alive`) and unknown fields are ignored.
struct SSEParser {
    private var event = ""
    private var data: [String] = []

    mutating func consume(line: String) -> SSEMessage? {
        if line.isEmpty {
            defer { event = ""; data = [] }
            guard !data.isEmpty else { return nil }
            return SSEMessage(event: event.isEmpty ? "message" : event, data: data.joined(separator: "\n"))
        }
        if line.hasPrefix(":") { return nil }
        let field: Substring
        var value: Substring
        if let colon = line.firstIndex(of: ":") {
            field = line[..<colon]
            value = line[line.index(after: colon)...]
            if value.hasPrefix(" ") { value = value.dropFirst() }
        } else {
            field = Substring(line)
            value = ""
        }
        switch field {
        case "event": event = String(value)
        case "data": data.append(String(value))
        default: break
        }
        return nil
    }
}

extension DreamEvent {
    /// Decodes one message of the dream event stream. Unknown events return nil (the contract may
    /// add events; old apps ignore them).
    static func decode(_ message: SSEMessage) throws -> DreamEvent? {
        let data = Data(message.data.utf8)
        switch message.event {
        case "step":
            struct Step: Decodable { let analysisStep: Int }
            return .step(try JSONDecoder().decode(Step.self, from: data).analysisStep)
        case "text":
            struct Text: Decodable { let lens: String; let delta: String; let reset: Bool? }
            let text = try JSONDecoder().decode(Text.self, from: data)
            guard let lens = Lens(rawValue: text.lens) else { return nil }
            return .text(lens: lens, delta: text.delta, reset: text.reset ?? false)
        case "ready":
            struct Ready: Decodable { let dream: Components.Schemas.DreamDetail }
            return .ready(try Dream(try contractDecoder.decode(Ready.self, from: data).dream))
        case "error":
            struct Failure: Decodable { let code: String; let message: String }
            let failure = try JSONDecoder().decode(Failure.self, from: data)
            return .failed(APIErrorCode(contractValue: failure.code), message: failure.message)
        default:
            return nil
        }
    }

    /// Decodes generated contract types outside the generated client (dates as the API writes them).
    private static let contractDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            guard let date = APIDates.parse(string) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: string))
            }
            return date
        }
        return decoder
    }()
}

// MARK: - Stream

extension APIClient {
    /// One connection to the dream's event stream. Ends after `ready` / `failed`, or when the
    /// server closes it (after 120 s) - the caller then falls back to polling.
    func dreamEventStream(id dreamID: UUID) -> AsyncThrowingStream<DreamEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let bytes = try await openEventStream(dreamID: dreamID)
                    var parser = SSEParser()
                    var line = [UInt8]()
                    for try await byte in bytes {
                        guard byte == UInt8(ascii: "\n") else {
                            line.append(byte)
                            continue
                        }
                        if line.last == UInt8(ascii: "\r") { line.removeLast() }
                        let text = String(decoding: line, as: UTF8.self)
                        line.removeAll(keepingCapacity: true)
                        guard let message = parser.consume(line: text), let event = try DreamEvent.decode(message) else { continue }
                        continuation.yield(event)
                        if case .ready = event { break }
                        if case .failed = event { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: APIError.unwrap(error) ?? APIError.fromTransport(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func openEventStream(dreamID: UUID) async throws(APIError) -> URLSession.AsyncBytes {
        let request = makeRequest(path: "/v1/dreams/\(dreamID.uuidString.lowercased())/events", accept: "text/event-stream")
        var result: URLSession.AsyncBytes?
        _ = try await authorizing(request) { authorized throws(APIError) in
            let (bytes, http) = try await self.openBytes(authorized)
            result = bytes
            return (Data(), http)
        }
        guard let result else { throw APIError.invalidResponse(status: nil) }
        return result
    }

    private func openBytes(_ request: URLRequest) async throws(APIError) -> (URLSession.AsyncBytes, HTTPURLResponse) {
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            throw APIError.fromTransport(error)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse(status: nil) }
        guard (200..<300).contains(http.statusCode) else {
            var body = Data()
            do {
                for try await byte in bytes {
                    body.append(byte)
                    if body.count > 64 * 1024 { break }
                }
            } catch {}
            throw APIError.fromResponse(status: http.statusCode, body: body,
                                        retryAfterHeader: http.value(forHTTPHeaderField: "Retry-After"))
        }
        return (bytes, http)
    }
}
