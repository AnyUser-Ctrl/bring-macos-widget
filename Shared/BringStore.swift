import Foundation

/// Single source of truth for persisted state, shared between the container
/// app and the widget extension via App Group UserDefaults.
///
/// Persists the password in plain text inside the App Group container.
/// Trade-off chosen explicitly for this private use case: the Keychain
/// prompts on every re-build under ad-hoc development signing were too
/// annoying, and the App Group container is already scoped to the user's
/// account. Do **not** ship this configuration outside your own machine.
final class BringStore {
    /// Team-ID-prefixed (macOS-native) so the group container is usable
    /// without a provisioning profile — see the signing note in project.yml.
    /// Injected at build time (BRING_APP_GROUP → Info.plist key BringAppGroup),
    /// the same value the .entitlements files get.
    static let appGroup: String = {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "BringAppGroup") as? String,
              !id.isEmpty, !id.hasPrefix("."), !id.contains("$(") else {
            fatalError("BringAppGroup missing in Info.plist – set DEVELOPMENT_TEAM in Config/Team.xcconfig")
        }
        return id
    }()

    static let shared = BringStore()

    private let defaults: UserDefaults

    private init() {
        self.defaults = UserDefaults(suiteName: BringStore.appGroup)
            ?? .standard
    }

    private enum Key {
        static let email = "bring.email"
        static let password = "bring.password"
        static let selectedListUuid = "bring.selectedListUuid"
        static let selectedListName = "bring.selectedListName"
        static let userUuid = "bring.userUuid"
        static let publicUuid = "bring.publicUuid"
        static let accessToken = "bring.accessToken"
        static let refreshToken = "bring.refreshToken"
        static let accessTokenExpiresAt = "bring.accessTokenExpiresAt"
        static let cachedItems = "bring.cachedItems.v1"
        static let listArticleLanguages = "bring.listArticleLanguages"
        static let macArticleLocale = "bring.macArticleLocale"
    }

    // MARK: - Credentials

    var email: String? {
        get { defaults.string(forKey: Key.email) }
        set { defaults.set(newValue, forKey: Key.email) }
    }

    var password: String? {
        get { defaults.string(forKey: Key.password) }
        set { defaults.set(newValue, forKey: Key.password) }
    }

    // MARK: - List selection

    var selectedListUuid: String? {
        get { defaults.string(forKey: Key.selectedListUuid) }
        set { defaults.set(newValue, forKey: Key.selectedListUuid) }
    }

    var selectedListName: String? {
        get { defaults.string(forKey: Key.selectedListName) }
        set { defaults.set(newValue, forKey: Key.selectedListName) }
    }

    /// listUuid → Bring article language ("de-DE", "en-US", …) from
    /// /v2/bringusersettings. Lists without the setting are absent.
    var listArticleLanguages: [String: String] {
        get { defaults.dictionary(forKey: Key.listArticleLanguages) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: Key.listArticleLanguages) }
    }

    /// Bring locale picked from the Mac's languages by the app process.
    var macArticleLocale: String? {
        get { defaults.string(forKey: Key.macArticleLocale) }
        set { defaults.set(newValue, forKey: Key.macArticleLocale) }
    }

    var selectedListArticleLanguage: String? {
        selectedListUuid.flatMap { listArticleLanguages[$0] }
    }

    // MARK: - Auth tokens

    var userUuid: String? {
        get { defaults.string(forKey: Key.userUuid) }
        set { defaults.set(newValue, forKey: Key.userUuid) }
    }

    var publicUuid: String? {
        get { defaults.string(forKey: Key.publicUuid) }
        set { defaults.set(newValue, forKey: Key.publicUuid) }
    }

    var accessToken: String? {
        get { defaults.string(forKey: Key.accessToken) }
        set { defaults.set(newValue, forKey: Key.accessToken) }
    }

    var refreshToken: String? {
        get { defaults.string(forKey: Key.refreshToken) }
        set { defaults.set(newValue, forKey: Key.refreshToken) }
    }

    var accessTokenExpiresAt: Date? {
        get {
            let ts = defaults.double(forKey: Key.accessTokenExpiresAt)
            return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        }
        set {
            if let v = newValue {
                defaults.set(v.timeIntervalSince1970, forKey: Key.accessTokenExpiresAt)
            } else {
                defaults.removeObject(forKey: Key.accessTokenExpiresAt)
            }
        }
    }

    var isAuthenticated: Bool {
        accessToken != nil && userUuid != nil
    }

    // MARK: - Mutations

    func saveAuth(_ response: BringAuthResponse, password: String? = nil) {
        userUuid = response.uuid
        publicUuid = response.publicUuid
        accessToken = response.accessToken
        refreshToken = response.refreshToken
        accessTokenExpiresAt = Date().addingTimeInterval(TimeInterval(response.expiresIn))
        email = response.email
        if let password { self.password = password }
        if selectedListUuid == nil, let listUuid = response.bringListUUID {
            selectedListUuid = listUuid
        }
    }

    func updateAccessToken(_ token: String, expiresIn: Int) {
        accessToken = token
        accessTokenExpiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
    }

    func clearAuth() {
        userUuid = nil
        publicUuid = nil
        accessToken = nil
        refreshToken = nil
        accessTokenExpiresAt = nil
        password = nil
        clearCache()
        selectedListUuid = nil
        selectedListName = nil
    }

    // MARK: - Item Cache

    func cachedItems() -> CachedItems? {
        guard let data = defaults.data(forKey: Key.cachedItems) else { return nil }
        return try? JSONDecoder().decode(CachedItems.self, from: data)
    }

    func saveCachedItems(_ items: CachedItems) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: Key.cachedItems)
    }

    func clearCache() {
        defaults.removeObject(forKey: Key.cachedItems)
    }
}
