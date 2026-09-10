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
            // A cook is a decision call plus up to four style calls.
            configuration.timeoutIntervalForRequest = 45
            configuration.timeoutIntervalForResource = 90
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
        guard let url = resolvedURL(path: path) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // TODO(auth): attach Authorization from the Better Auth session once auth exists
        request.httpBody = try encoder.encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
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

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    private func resolvedURL(path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else {
            return nil
        }
        return baseURL.appending(path: trimmed)
    }
}
