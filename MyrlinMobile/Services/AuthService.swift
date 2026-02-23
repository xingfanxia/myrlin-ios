import Foundation
import Security

/// Manages authentication: login, token storage in Keychain, logout.
final class AuthService {
    static let shared = AuthService()
    private init() {}

    // MARK: - Keychain Keys
    private static let serverURLKey = "myrlin.serverURL"
    private static let tokenKey = "myrlin.authToken"

    // MARK: - In-Memory Cache
    private var _serverURL: String?
    private var _token: String?

    var serverURL: String? {
        get { _serverURL ?? keychainRead(key: Self.serverURLKey) }
        set {
            _serverURL = newValue
            if let v = newValue { keychainWrite(key: Self.serverURLKey, value: v) }
            else { keychainDelete(key: Self.serverURLKey) }
        }
    }

    var token: String? {
        get { _token ?? keychainRead(key: Self.tokenKey) }
        set {
            _token = newValue
            if let v = newValue { keychainWrite(key: Self.tokenKey, value: v) }
            else { keychainDelete(key: Self.tokenKey) }
        }
    }

    // MARK: - Auth Actions

    /// Login: POST /api/auth/login with password, store token in Keychain.
    func login(serverURL: String, password: String) async throws {
        let normalizedURL = serverURL.hasSuffix("/") ? String(serverURL.dropLast()) : serverURL
        guard let url = URL(string: "\(normalizedURL)/api/auth/login") else {
            throw AuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["password": password])
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.networkError("Invalid response")
        }
        guard httpResponse.statusCode == 200 else {
            let body = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            let msg = body["error"] as? String ?? "Login failed (\(httpResponse.statusCode))"
            throw AuthError.loginFailed(msg)
        }

        struct LoginResponse: Decodable { let success: Bool; let token: String? }
        let decoded = try JSONDecoder().decode(LoginResponse.self, from: data)
        guard let tok = decoded.token else { throw AuthError.loginFailed("No token in response") }

        self.serverURL = normalizedURL
        self.token = tok
    }

    func logout() {
        token = nil
    }

    // MARK: - Keychain Helpers

    private func keychainWrite(key: String, value: String) {
        let data = value.data(using: .utf8)!
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "MyrlinMobile",
            kSecAttrAccount: key,
            kSecValueData: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func keychainRead(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "MyrlinMobile",
            kSecAttrAccount: key,
            kSecReturnData: kCFBooleanTrue!,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }

    private func keychainDelete(key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "MyrlinMobile",
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum AuthError: LocalizedError {
    case invalidURL
    case networkError(String)
    case loginFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid server URL"
        case .networkError(let m): return "Network error: \(m)"
        case .loginFailed(let m): return m
        }
    }
}
