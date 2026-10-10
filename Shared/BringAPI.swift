import Foundation

enum BringAPIError: LocalizedError {
    case invalidCredentials
    case notAuthenticated
    case badResponse(Int, String?)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return String(localized: "Sign-in failed — wrong email or password.")
        case .notAuthenticated:
            return String(localized: "Not signed in.")
        case .badResponse(let code, let body):
            if let body, !body.isEmpty {
                return String(localized: "Bring! responded with status \(code): \(body)")
            }
            return String(localized: "Bring! responded with status \(code).")
        case .decoding(let err):
            return String(localized: "Could not read the response: \(err.localizedDescription)")
        case .transport(let err):
            return String(localized: "Network error: \(err.localizedDescription)")
        }
    }
}

/// Thin async/await wrapper around the unofficial Bring! REST API.
/// Endpoints are derived from the publicly available open-source clients
/// (miaucl/bring-api, foxriver76/node-bring-api).
final class BringAPI {
    static let shared = BringAPI()

    private let session: URLSession
    private let baseURL = URL(string: "https://api.getbring.com/rest/")!
    private let store = BringStore.shared

    // Public API key extracted from the official mobile app — same value used
    // by every Bring client. Not a secret.
    private let apiKey = "cof4Nc6D8saplXjE3h3HXqHH8m7VU2i1Gs0g85Sp"

    private init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public calls

    func login(email: String, password: String) async throws -> BringAuthResponse {
        let url = baseURL.appendingPathComponent("v2/bringauth")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyDefaultHeaders(to: &request)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncoded([
            "email": email,
            "password": password
        ])

        let (data, response) = try await sendRequest(request)
        guard let http = response as? HTTPURLResponse else {
            throw BringAPIError.badResponse(0, nil)
        }
        switch http.statusCode {
        case 200..<300:
            do {
                let decoded = try JSONDecoder().decode(BringAuthResponse.self, from: data)
                store.saveAuth(decoded, password: password)
                return decoded
            } catch {
                throw BringAPIError.decoding(error)
            }
        case 401, 403:
            throw BringAPIError.invalidCredentials
        default:
            throw BringAPIError.badResponse(http.statusCode, String(data: data, encoding: .utf8))
        }
    }

    func refreshAccessTokenIfNeeded() async throws {
        // Token still valid? Skip everything.
        if store.accessToken != nil,
           let expiry = store.accessTokenExpiresAt,
           expiry > Date().addingTimeInterval(60) {
            return
        }

        // Try the refresh-token path first.
        if let refresh = store.refreshToken {
            let url = baseURL.appendingPathComponent("v2/bringauth/token")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            applyDefaultHeaders(to: &request, includeAuth: false)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = formEncoded(["refresh_token": refresh])

            do {
                let (data, response) = try await sendRequest(request)
                if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                    let decoded = try JSONDecoder().decode(BringTokenRefreshResponse.self, from: data)
                    store.updateAccessToken(decoded.accessToken, expiresIn: decoded.expiresIn)
                    return
                }
                // Non-2xx — fall through to password re-login.
            } catch {
                // Network/decoding failure — also fall through.
            }
        }

        // Fall back to a full re-login using the stored password. This is the
        // primary reason for keeping the password in the App Group container:
        // App and Widget can recover their session silently after any kind of
        // token expiry without prompting the user.
        if let email = store.email, let password = store.password {
            _ = try await login(email: email, password: password)
            return
        }

        store.clearAuth()
        throw BringAPIError.notAuthenticated
    }

    func fetchLists() async throws -> [BringList] {
        try await refreshAccessTokenIfNeeded()
        guard let uuid = store.userUuid else { throw BringAPIError.notAuthenticated }
        let url = baseURL.appendingPathComponent("v2/bringusers/\(uuid)/lists")
        var request = URLRequest(url: url)
        applyDefaultHeaders(to: &request)
        let (data, response) = try await sendRequest(request)
        try ensureSuccess(response, data: data)
        do {
            return try JSONDecoder().decode(BringListsResponse.self, from: data).lists
        } catch {
            throw BringAPIError.decoding(error)
        }
    }

    func fetchItems(listUuid: String) async throws -> BringItemsResponse {
        try await refreshAccessTokenIfNeeded()
        let url = baseURL.appendingPathComponent("v2/bringlists/\(listUuid)")
        var request = URLRequest(url: url)
        applyDefaultHeaders(to: &request)
        let (data, response) = try await sendRequest(request)
        try ensureSuccess(response, data: data)
        do {
            return try JSONDecoder().decode(BringItemsResponse.self, from: data)
        } catch {
            throw BringAPIError.decoding(error)
        }
    }

    /// listUuid → listArticleLanguage, the per-list catalog language the
    /// user picked in Bring ("Article language"). Same endpoint the Bring
    /// web app reads (v2/bringusersettings/{userUuid}).
    func fetchListArticleLanguages() async throws -> [String: String] {
        try await refreshAccessTokenIfNeeded()
        guard let uuid = store.userUuid else { throw BringAPIError.notAuthenticated }
        let url = baseURL.appendingPathComponent("v2/bringusersettings/\(uuid)")
        var request = URLRequest(url: url)
        applyDefaultHeaders(to: &request)
        let (data, response) = try await sendRequest(request)
        try ensureSuccess(response, data: data)
        do {
            let settings = try JSONDecoder().decode(BringUserSettingsResponse.self, from: data)
            var result: [String: String] = [:]
            for list in settings.userlistsettings {
                if let lang = list.usersettings.first(where: { $0.key == "listArticleLanguage" })?.value {
                    result[list.listUuid] = lang
                }
            }
            return result
        } catch {
            throw BringAPIError.decoding(error)
        }
    }

    // MARK: - Helpers

    private func applyDefaultHeaders(to request: inout URLRequest, includeAuth: Bool = true) {
        request.setValue(apiKey, forHTTPHeaderField: "X-BRING-API-KEY")
        request.setValue("android", forHTTPHeaderField: "X-BRING-CLIENT")
        request.setValue("bring", forHTTPHeaderField: "X-BRING-APPLICATION")
        request.setValue("DE", forHTTPHeaderField: "X-BRING-COUNTRY")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if includeAuth {
            if let token = store.accessToken {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            if let uuid = store.userUuid {
                request.setValue(uuid, forHTTPHeaderField: "X-BRING-USER-UUID")
            }
            if let pub = store.publicUuid {
                request.setValue(pub, forHTTPHeaderField: "X-BRING-PUBLIC-USER-UUID")
            }
        }
    }

    private func sendRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw BringAPIError.transport(error)
        }
    }

    private func ensureSuccess(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw BringAPIError.badResponse(0, nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw BringAPIError.badResponse(http.statusCode, String(data: data, encoding: .utf8))
        }
    }

    private func formEncoded(_ params: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }
}
