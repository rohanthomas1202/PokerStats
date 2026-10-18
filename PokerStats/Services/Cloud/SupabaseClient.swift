import Foundation

// MARK: - Supporting Types

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

enum AuthProvider: String, Sendable {
    case apple
}

struct AuthSession: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let expiresAt: Double?
    let user: AuthUser
}

struct AuthUser: Codable, Sendable {
    let id: UUID
    let email: String?
    let identities: [AuthIdentity]?
}

struct AuthIdentity: Codable, Sendable {
    let provider: String
    let identityId: String?
}

struct StorageObject: Codable, Sendable {
    let name: String
    let id: String?
    let createdAt: String?
}

enum SupabaseError: LocalizedError, Sendable {
    case httpError(statusCode: Int, message: String)
    case sessionExpired
    /// A token refresh failed for a non-auth reason (offline, timeout, 5xx).
    /// The session is kept; the next request tries again.
    case refreshUnavailable
    case networkError(String)
    case decodingError(String)
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .httpError(let code, let message): "HTTP \(code): \(message)"
        case .sessionExpired: "Session expired. Please sign in again."
        case .refreshUnavailable: "Couldn't reach the server. Check your connection and try again."
        case .networkError(let message): "Network error: \(message)"
        case .decodingError(let message): "Decoding error: \(message)"
        case .notAuthenticated: "Not authenticated."
        }
    }
}

// MARK: - Supabase Client

final class SupabaseClient: Sendable {
    static let shared = SupabaseClient()

    private let projectURL: String
    private let anonKey: String

    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    let tokenStore: any TokenStore
    private let transport: Transport
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Tests pass a fake transport and token store.
    init(
        tokenStore: any TokenStore = KeychainTokenStore(),
        transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }
    ) {
        projectURL = Secrets.supabaseURL
        anonKey = Secrets.supabaseAnonKey
        self.tokenStore = tokenStore
        self.transport = transport

        encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Generic Request

    func request(
        endpoint: String,
        method: HTTPMethod,
        body: (any Encodable & Sendable)? = nil,
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:],
        authenticated: Bool = true
    ) async throws -> Data {
        var components = URLComponents(string: projectURL + endpoint)!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = method.rawValue
        urlRequest.setValue(anonKey, forHTTPHeaderField: "apikey")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if authenticated {
            guard let token = try await validAccessToken() else {
                throw SupabaseError.notAuthenticated
            }
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        for (key, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        if let body {
            urlRequest.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await performRequest(urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.networkError("Invalid response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.httpError(statusCode: httpResponse.statusCode, message: message)
        }

        return data
    }

    // MARK: - Auth API

    /// `nonce` is the raw value whose SHA-256 was sent to the identity
    /// provider; Supabase rejects the ID token unless they match.
    func signInWithIdToken(provider: AuthProvider, idToken: String, nonce: String) async throws -> AuthSession {
        let urlRequest = try makeSignInWithIdTokenRequest(provider: provider, idToken: idToken, nonce: nonce)
        let (data, response) = try await performRequest(urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.networkError("Invalid response")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.httpError(statusCode: httpResponse.statusCode, message: message)
        }
        return try decoder.decode(AuthSession.self, from: data)
    }

    /// Builds the ID-token grant POST. Separate so tests can check the body.
    func makeSignInWithIdTokenRequest(provider: AuthProvider, idToken: String, nonce: String) throws -> URLRequest {
        struct SignInBody: Encodable, Sendable {
            let provider: String
            let idToken: String
            let nonce: String
        }

        var urlRequest = URLRequest(url: URL(string: projectURL + "/auth/v1/token?grant_type=id_token")!)
        urlRequest.httpMethod = HTTPMethod.post.rawValue
        urlRequest.setValue(anonKey, forHTTPHeaderField: "apikey")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try encoder.encode(
            SignInBody(provider: provider.rawValue, idToken: idToken, nonce: nonce)
        )
        return urlRequest
    }

    func refreshSession(refreshToken: String) async throws -> AuthSession {
        struct RefreshBody: Encodable, Sendable {
            let refreshToken: String
        }

        let data = try await request(
            endpoint: "/auth/v1/token?grant_type=refresh_token",
            method: .post,
            body: RefreshBody(refreshToken: refreshToken),
            authenticated: false
        )
        return try decoder.decode(AuthSession.self, from: data)
    }

    func signOut(accessToken: String) async throws {
        var urlRequest = URLRequest(url: URL(string: projectURL + "/auth/v1/logout")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(anonKey, forHTTPHeaderField: "apikey")
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        _ = try await performRequest(urlRequest)
    }

    // MARK: - Storage API

    func uploadFile(bucket: String, path: String, data: Data, contentType: String) async throws {
        guard let token = try await validAccessToken() else {
            throw SupabaseError.notAuthenticated
        }

        let url = URL(string: "\(projectURL)/storage/v1/object/\(bucket)/\(path)")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(anonKey, forHTTPHeaderField: "apikey")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("true", forHTTPHeaderField: "x-upsert")
        urlRequest.httpBody = data

        let (responseData, response) = try await performRequest(urlRequest)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: responseData, encoding: .utf8) ?? "Upload failed"
            throw SupabaseError.httpError(
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
                message: message
            )
        }
    }

    func downloadFile(bucket: String, path: String) async throws -> Data {
        guard let token = try await validAccessToken() else {
            throw SupabaseError.notAuthenticated
        }

        let url = URL(string: "\(projectURL)/storage/v1/object/\(bucket)/\(path)")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue(anonKey, forHTTPHeaderField: "apikey")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await performRequest(urlRequest)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Download failed"
            throw SupabaseError.httpError(
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
                message: message
            )
        }

        return data
    }

    func deleteFile(bucket: String, path: String) async throws {
        guard let token = try await validAccessToken() else {
            throw SupabaseError.notAuthenticated
        }

        let url = URL(string: "\(projectURL)/storage/v1/object/\(bucket)/\(path)")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "DELETE"
        urlRequest.setValue(anonKey, forHTTPHeaderField: "apikey")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await performRequest(urlRequest)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Delete failed"
            throw SupabaseError.httpError(
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
                message: message
            )
        }
    }

    func listFiles(bucket: String, prefix: String) async throws -> [StorageObject] {
        struct ListBody: Encodable, Sendable {
            let prefix: String
            let limit: Int
        }

        let data = try await request(
            endpoint: "/storage/v1/object/list/\(bucket)",
            method: .post,
            body: ListBody(prefix: prefix, limit: 20)
        )
        return try decoder.decode([StorageObject].self, from: data)
    }

    // MARK: - Edge Functions

    func callEdgeFunction(_ name: String, body: (any Encodable & Sendable)? = nil) async throws {
        guard let token = try await validAccessToken() else {
            throw SupabaseError.notAuthenticated
        }

        let urlRequest = try makeEdgeFunctionRequest(name, accessToken: token, body: body)

        let (data, response) = try await performRequest(urlRequest)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Function call failed"
            throw SupabaseError.httpError(
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
                message: message
            )
        }
    }

    /// Builds the POST for an edge function call. Separate so tests can check
    /// the exact body this client sends.
    func makeEdgeFunctionRequest(
        _ name: String,
        accessToken: String,
        body: (any Encodable & Sendable)?
    ) throws -> URLRequest {
        let url = URL(string: "\(projectURL)/functions/v1/\(name)")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(anonKey, forHTTPHeaderField: "apikey")
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let body {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = try encoder.encode(body)
        }
        return urlRequest
    }

    // MARK: - Token Management

    private func validAccessToken() async throws -> String? {
        guard let token = tokenStore.read(.accessToken) else {
            return nil
        }
        if isTokenExpired(token) {
            return try await refreshStoredSession().accessToken
        }
        return token
    }

    /// Refreshes with the stored refresh token. See `SessionRefresher` for
    /// which failures sign the user out and which keep the session.
    func refreshStoredSession() async throws -> AuthSession {
        try await SessionRefresher(
            store: tokenStore,
            refresh: { try await self.refreshSession(refreshToken: $0) },
            onInvalidated: {
                await MainActor.run {
                    NotificationCenter.default.post(name: .supabaseSessionInvalidated, object: self)
                }
            }
        ).refreshStoredSession()
    }

    private func isTokenExpired(_ jwt: String) -> Bool {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else { return true }

        // Base64-decode the payload (second part)
        var base64 = String(parts[1])
        // Pad to multiple of 4
        while base64.count % 4 != 0 {
            base64 += "="
        }

        guard let payloadData = Data(base64Encoded: base64),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let exp = payload["exp"] as? TimeInterval else {
            return true
        }

        // Add 30-second buffer before actual expiry
        return Date().timeIntervalSince1970 >= (exp - 30)
    }

    // MARK: - Network

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await transport(request)
        } catch {
            throw SupabaseError.networkError(error.localizedDescription)
        }
    }
}
