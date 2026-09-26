import Foundation
import HTTPTypes
import OpenAPIRuntime
import os
@testable import Dreamer

/// Answers requests from canned responses. Each test uses its own host, so tests running in
/// parallel never see each other's stubs.
final class StubURLProtocol: URLProtocol {
    struct Response: Sendable {
        var status: Int
        var headers: [String: String] = ["Content-Type": "application/json"]
        var body: Data
        /// Thrown instead of answering (e.g. URLError(.notConnectedToInternet)).
        var error: URLError? = nil
    }

    typealias Handler = @Sendable (URLRequest) -> Response

    private static let handlers = OSAllocatedUnfairLock<[String: Handler]>(initialState: [:])
    private static let recorded = OSAllocatedUnfairLock<[String: [URLRequest]]>(initialState: [:])

    /// A client whose every request goes to `handler`.
    static func makeClient(tokens: (any AccessTokenProvider)? = nil,
                           middlewares: [any ClientMiddleware] = [],
                           innerMiddlewares: [any ClientMiddleware] = [],
                           retry: RetryMiddleware = RetryMiddleware(baseDelay: .milliseconds(1)),
                           reporter: (any CrashReporter)? = nil,
                           handler: @escaping Handler) -> (APIClient, host: String) {
        let host = "stub-\(UUID().uuidString.lowercased()).test"
        handlers.withLock { $0[host] = handler }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return (APIClient(baseURL: URL(string: "https://\(host)")!, tokens: tokens, session: session,
                          extraMiddlewares: middlewares, innerMiddlewares: innerMiddlewares, retry: retry,
                          reporter: reporter), host)
    }

    /// A plain session whose requests to `host` go to `handler`, for code that talks to a third
    /// party without APIClient (Google's token endpoint). One test per host, or they collide.
    static func makeSession(host: String, handler: @escaping Handler) -> URLSession {
        handlers.withLock { $0[host] = handler }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func requests(for host: String) -> [URLRequest] {
        recorded.withLock { $0[host] ?? [] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let host = request.url?.host(), let handler = Self.handlers.withLock({ $0[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        var captured = request
        // URLSession moves the body into a stream; keep it readable for assertions.
        if captured.httpBody == nil, let stream = request.httpBodyStream {
            captured.httpBody = Data(reading: stream)
        }
        let recordedRequest = captured
        Self.recorded.withLock { $0[host, default: []].append(recordedRequest) }

        let response = handler(recordedRequest)
        if let error = response.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let http = HTTPURLResponse(url: request.url!, statusCode: response.status, httpVersion: "HTTP/1.1",
                                   headerFields: response.headers)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

extension StubURLProtocol.Response {
    static func json(_ status: Int = 200, _ body: String, headers: [String: String] = [:]) -> Self {
        var all = ["Content-Type": "application/json"]
        all.merge(headers) { $1 }
        return .init(status: status, headers: all, body: Data(body.utf8))
    }

    static func empty(_ status: Int) -> Self {
        .init(status: status, headers: [:], body: Data())
    }
}

private extension Data {
    init(reading stream: InputStream) {
        self.init()
        stream.open()
        defer { stream.close() }
        let size = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: size)
            guard read > 0 else { break }
            append(buffer, count: read)
        }
    }
}

/// Records request bodies of the generated client (URLSession uploads them, so URLProtocol never
/// sees them).
final class BodyRecorder: ClientMiddleware, Sendable {
    private let bodies = OSAllocatedUnfairLock<[Data]>(initialState: [])

    var last: Data? { bodies.withLock { $0.last } }

    func intercept(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String,
                   next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?))
    async throws -> (HTTPResponse, HTTPBody?) {
        if let body {
            let data = try await Data(collecting: body, upTo: 1024 * 1024)
            bodies.withLock { $0.append(data) }
            return try await next(request, HTTPBody(data), baseURL)
        }
        return try await next(request, body, baseURL)
    }
}
