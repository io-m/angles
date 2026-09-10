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
    private let baseURL: URL
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: URL = AppConfig.baseURL, session: URLSession? = nil) {
        self.baseURL = baseURL
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            // Server cook budget is 10s; this is slack for the network, not a hang.
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 30
            configuration.httpAdditionalHeaders = ["Accept": "application/json"]
            self.session = URLSession(configuration: configuration)
        }
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    func post<Body: Encodable, Response: Decodable>(
        path: String,
        body: Body
    ) async throws -> Response {
        try await decode(try await send(path: path, method: "POST", body: body))
    }

    func get<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        try await decode(try await send(path: path, method: "GET", queryItems: queryItems))
    }

    func patch<Body: Encodable, Response: Decodable>(
        path: String,
        body: Body
    ) async throws -> Response {
        try await decode(try await send(path: path, method: "PATCH", body: body))
    }

    func delete(path: String) async throws {
        _ = try await send(path: path, method: "DELETE")
    }

    private func decode<Response: Decodable>(_ data: Data) throws -> Response {
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    private func send(path: String, method: String, queryItems: [URLQueryItem] = []) async throws -> Data {
        try await perform(path: path, method: method, queryItems: queryItems, bodyData: nil)
    }

    private func send<Body: Encodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        body: Body
    ) async throws -> Data {
        try await perform(
            path: path,
            method: method,
            queryItems: queryItems,
            bodyData: try encoder.encode(body)
        )
    }

    private func perform(
        path: String,
        method: String,
        queryItems: [URLQueryItem],
        bodyData: Data?
    ) async throws -> Data {
        guard let url = resolvedURL(path: path, queryItems: queryItems) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        // TODO(auth): attach Authorization from the Better Auth session once auth exists
        if let bodyData {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
            let message = String(data: data, encoding: .utf8)
            throw APIError.httpStatus(http.statusCode, message)
        }

        return data
    }

    private func resolvedURL(path: String, queryItems: [URLQueryItem] = []) -> URL? {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else {
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
