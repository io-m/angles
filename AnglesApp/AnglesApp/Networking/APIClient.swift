import Foundation

enum APIError: Error, Equatable, Sendable {
    case invalidURL
    case network(String)
    case httpStatus(Int, String?)
    case decoding(String)
}

extension APIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The request URL was invalid."
        case .network(let message):
            return "Network error: \(message)"
        case .httpStatus(let code, let body):
            if let body, !body.isEmpty {
                return "Server returned \(code): \(body)"
            }
            return "Server returned status \(code)."
        case .decoding(let message):
            return "Could not decode the response: \(message)"
        }
    }
}

final class APIClient: @unchecked Sendable {
    private let session: URLSession
    private let baseURL: URL?
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: URL? = AppConfig.baseURL, session: URLSession? = nil) {
        self.baseURL = baseURL
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            // Server cook budget is 10s; this is slack for the network, not a hang.
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 30
            configuration.httpShouldSetCookies = false
            configuration.httpCookieAcceptPolicy = .never
            configuration.httpAdditionalHeaders = ["Accept": "application/json"]
            self.session = URLSession(configuration: configuration)
        }
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    func post<Body: Encodable, Response: Decodable>(
        path: String,
        body: Body,
        timeout: TimeInterval? = nil
    ) async throws -> Response {
        try await decode(try await send(path: path, method: "POST", body: body, timeout: timeout))
    }

    func postCapturingHeader<Body: Encodable>(
        path: String,
        body: Body,
        header: String,
        timeout: TimeInterval? = nil
    ) async throws -> (Data, String?) {
        let (data, response) = try await execute(
            path: path,
            method: "POST",
            queryItems: [],
            bodyData: try encoder.encode(body),
            contentType: "application/json",
            timeout: timeout
        )
        return (data, response.value(forHTTPHeaderField: header))
    }

    /// `bearer` overrides the shared session token, so a sign-out can still revoke the session
    /// it just cleared locally.
    func postEmpty(path: String, bearer: String? = nil, timeout: TimeInterval? = nil) async throws {
        _ = try await execute(
            path: path,
            method: "POST",
            queryItems: [],
            bodyData: Data("{}".utf8),
            contentType: "application/json",
            timeout: timeout,
            bearer: bearer
        )
    }

    func get<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        timeout: TimeInterval? = nil
    ) async throws -> Response {
        try await decode(try await send(path: path, method: "GET", queryItems: queryItems, timeout: timeout))
    }

    func put<Response: Decodable>(path: String, timeout: TimeInterval? = nil) async throws -> Response {
        try await decode(try await send(path: path, method: "PUT", timeout: timeout))
    }

    func patch<Body: Encodable, Response: Decodable>(
        path: String,
        body: Body,
        timeout: TimeInterval? = nil
    ) async throws -> Response {
        try await decode(try await send(path: path, method: "PATCH", body: body, timeout: timeout))
    }

    func delete(path: String, timeout: TimeInterval? = nil) async throws {
        _ = try await send(path: path, method: "DELETE", timeout: timeout)
    }

    func deleteJSON<Response: Decodable>(path: String, timeout: TimeInterval? = nil) async throws -> Response {
        try await decode(try await send(path: path, method: "DELETE", timeout: timeout))
    }

    func putData<Response: Decodable>(
        path: String,
        body: Data,
        contentType: String,
        timeout: TimeInterval? = nil
    ) async throws -> Response {
        try await decode(
            try await perform(
                path: path,
                method: "PUT",
                queryItems: [],
                bodyData: body,
                contentType: contentType,
                timeout: timeout
            )
        )
    }

    private func decode<Response: Decodable>(_ data: Data) throws -> Response {
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    private func send(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        timeout: TimeInterval? = nil
    ) async throws -> Data {
        try await perform(path: path, method: method, queryItems: queryItems, bodyData: nil, contentType: nil, timeout: timeout)
    }

    private func send<Body: Encodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        body: Body,
        timeout: TimeInterval? = nil
    ) async throws -> Data {
        try await perform(
            path: path,
            method: method,
            queryItems: queryItems,
            bodyData: try encoder.encode(body),
            contentType: "application/json",
            timeout: timeout
        )
    }

    private func perform(
        path: String,
        method: String,
        queryItems: [URLQueryItem],
        bodyData: Data?,
        contentType: String?,
        timeout: TimeInterval?
    ) async throws -> Data {
        try await execute(
            path: path,
            method: method,
            queryItems: queryItems,
            bodyData: bodyData,
            contentType: contentType,
            timeout: timeout
        ).0
    }

    private func execute(
        path: String,
        method: String,
        queryItems: [URLQueryItem],
        bodyData: Data?,
        contentType: String?,
        timeout: TimeInterval?,
        bearer: String? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        guard let url = resolvedURL(path: path, queryItems: queryItems) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        if let timeout {
            request.timeoutInterval = timeout
        }
        if let origin = originHeader(for: url) {
            request.setValue(origin, forHTTPHeaderField: "Origin")
        }
        let sentToken = bearer ?? AuthCredentials.shared.bearerToken
        if let sentToken, !sentToken.isEmpty {
            request.setValue("Bearer \(sentToken)", forHTTPHeaderField: "Authorization")
        }
        if let bodyData {
            if let contentType {
                request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            }
            request.httpBody = bodyData
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw urlError
        } catch {
            throw APIError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.network("Response was not HTTP.")
        }

        guard (200 ... 299).contains(http.statusCode) else {
            if http.statusCode == 401, let sentToken, !sentToken.isEmpty,
               AuthCredentials.shared.clear(ifMatching: sentToken) {
                NotificationCenter.default.post(name: .anglesSessionInvalidated, object: sentToken)
            }
            let message = String(data: data, encoding: .utf8)
            throw APIError.httpStatus(http.statusCode, message)
        }

        return (data, http)
    }

    private func originHeader(for url: URL) -> String? {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        return components.string
    }

    private func resolvedURL(path: String, queryItems: [URLQueryItem] = []) -> URL? {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let baseURL, !trimmed.isEmpty else {
            return nil
        }
        let url = baseURL.appending(path: trimmed)
        let items = queryItems.filter { item in
            guard let value = item.value else {
                return false
            }
            return !value.isEmpty
        }
        guard !items.isEmpty else {
            return url
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = items
        return components.url
    }
}
