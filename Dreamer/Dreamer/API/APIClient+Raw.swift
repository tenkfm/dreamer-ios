import Foundation

// Calls that do not go through the generated client (the event stream, the data export). They get
// the same bearer token, refresh-and-retry and error mapping as the generated calls.

extension APIClient {
    /// `GET /v1/me/export`: everything the backend holds about the user (GDPR), as the server's own
    /// bytes. Decoding into the generated model and encoding again would drop the fields this build
    /// does not know and reorder the rest. Not through the generated client, so no middleware sees
    /// the body; the session has no URL cache.
    func exportData() async throws(APIError) -> Data {
        try await sendAuthorized(path: "/v1/me/export").0
    }

    /// Builds a request to `path` (with query) on the API host.
    func makeRequest(path: String, method: String = "GET", accept: String = "application/json") -> URLRequest {
        let url = URL(string: path, relativeTo: baseURL) ?? baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(accept, forHTTPHeaderField: "Accept")
        return request
    }

    /// Adds the bearer token; a rejected (expired) token is refreshed once and the request retried.
    func authorizing(_ request: URLRequest,
                     send: (URLRequest) async throws(APIError) -> (Data, HTTPURLResponse)) async throws(APIError)
    -> (Data, HTTPURLResponse) {
        guard let tokens else { throw APIError.signedOut }
        let token: String?
        do { token = try await tokens.accessToken() } catch { throw APIError.fromTransport(error) }
        guard let token else { throw APIError.signedOut }

        var authorized = request
        authorized.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            return try await send(authorized)
        } catch where error.code == .authInvalidToken {
            let fresh: String
            do { fresh = try await tokens.refreshAfterRejection(of: token) } catch { throw APIError.fromTransport(error) }
            authorized.setValue("Bearer \(fresh)", forHTTPHeaderField: "Authorization")
            return try await send(authorized)
        }
    }

    private func sendAuthorized(path: String) async throws(APIError) -> (Data, HTTPURLResponse) {
        try await authorizing(makeRequest(path: path)) { request throws(APIError) in
            try await self.send(request)
        }
    }

    /// Sends a request and maps non-2xx answers to `APIError`.
    func send(_ request: URLRequest) async throws(APIError) -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.fromTransport(error)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse(status: nil) }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.fromResponse(status: http.statusCode, body: data,
                                        retryAfterHeader: http.value(forHTTPHeaderField: "Retry-After"))
        }
        return (data, http)
    }
}
