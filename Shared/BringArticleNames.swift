import Foundation

/// Display names for Bring! catalog items.
///
/// The list endpoint returns catalog items by their catalog key (`itemId`),
/// which is Bring's Swiss-German base name ("Rahm", "Poulet", "Gipfeli")
/// regardless of the user's language. Bring's own clients translate the key
/// client-side with the public table
/// `https://web.getbring.com/locale/articles.<locale>.json` ({key: name}).
/// Free-text items are not in the table and stay as typed.
///
/// Icons must keep using the raw key (`BringIcons.normalize(item.name)`).
enum BringArticleNames {
    /// Locales Bring ships catalogs for (web app SUPPORTED_CATALOGS,
    /// bring-api BRING_SUPPORTED_LOCALES).
    static let supportedLocales: Set<String> = [
        "de-AT", "de-CH", "de-DE", "en-AU", "en-CA", "en-GB", "en-US", "es-ES",
        "fr-CH", "fr-FR", "hu-HU", "it-CH", "it-IT", "nb-NO", "nl-NL", "pl-PL",
        "pt-BR", "ru-RU", "sv-SE", "tr-TR"
    ]

    /// Language → default locale when the region has no own catalog
    /// (mirrors bring-api MAP_LANG_TO_LOCALE).
    private static let languageDefaults: [String: String] = [
        "de": "de-DE", "en": "en-US", "es": "es-ES", "fr": "fr-FR",
        "hu": "hu-HU", "it": "it-IT", "nb": "nb-NO", "nn": "nb-NO",
        "nl": "nl-NL", "pl": "pl-PL", "pt": "pt-BR", "ru": "ru-RU",
        "sv": "sv-SE", "tr": "tr-TR"
    ]

    private static let baseURL = URL(string: "https://web.getbring.com/locale/")!
    /// The tables change rarely (Last-Modified on the CDN: July 2025).
    private static let maxAge: TimeInterval = 7 * 24 * 60 * 60

    // MARK: - Locale

    /// First of the Mac's preferred languages that Bring has a catalog for.
    /// "en-US" → en-US, "de" (region CH) → de-CH, "fr-BE" → fr-FR,
    /// "ja" then "en" → en-US, only unsupported languages → nil.
    static func bringLocale(
        preferredLanguages: [String] = Locale.preferredLanguages,
        systemRegion: String? = Locale.current.region?.identifier
    ) -> String? {
        for tag in preferredLanguages {
            let locale = Locale(identifier: tag)
            guard let language = locale.language.languageCode?.identifier else { continue }
            if let region = locale.region?.identifier ?? systemRegion,
               supportedLocales.contains("\(language)-\(region)") {
                return "\(language)-\(region)"
            }
            if let fallback = languageDefaults[language] { return fallback }
        }
        return nil
    }

    /// Locale used for display: the list's Bring article language if known,
    /// else the Mac's language.
    static func currentLocale(
        listArticleLanguage: String? = BringStore.shared.selectedListArticleLanguage
    ) -> String? {
        if let lang = listArticleLanguage, supportedLocales.contains(lang) { return lang }
        // Resolved in the app process and shared via the App Group: a widget
        // extension may not see the same preferred languages as the app.
        if let stored = BringStore.shared.macArticleLocale, supportedLocales.contains(stored) { return stored }
        return bringLocale()
    }

    // MARK: - Cache (App Group, like BringIcons)

    static var cacheDirectory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: BringStore.appGroup)?
            .appendingPathComponent("Locales", isDirectory: true)
    }

    static func cachedFileURL(locale: String) -> URL? {
        cacheDirectory?.appendingPathComponent("articles.\(locale).json")
    }

    /// Downloads the table if missing or older than `maxAge`. A failed
    /// download keeps the previous file, so the widget never loses names.
    static func prefetch(locale: String?) async {
        guard let locale, supportedLocales.contains(locale),
              let dir = cacheDirectory,
              let file = cachedFileURL(locale: locale) else { return }
        if let modified = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < maxAge {
            return
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = baseURL.appendingPathComponent("articles.\(locale).json")
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              (try? JSONDecoder().decode([String: String].self, from: data)) != nil
        else { return }
        try? data.write(to: file, options: .atomic)
    }

    // MARK: - Lookup

    private final class Memo: @unchecked Sendable {
        let lock = NSLock()
        var locale: String?
        var modified: Date?
        var table: [String: String] = [:]
    }
    private static let memo = Memo()

    /// Synchronous, memoized per locale + file date (safe to call per tile).
    static func table(locale: String) -> [String: String] {
        guard let file = cachedFileURL(locale: locale) else { return [:] }
        let modified = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
        memo.lock.lock(); defer { memo.lock.unlock() }
        if memo.locale == locale, memo.modified == modified { return memo.table }
        let table = (try? Data(contentsOf: file))
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        memo.locale = locale
        memo.modified = modified
        memo.table = table
        return table
    }

    /// Catalog key → localized name; unknown keys (own items) unchanged.
    /// Corrections for the web tables (Last-Modified July 2025), taken from the
    /// newer app tables (bring-api, Android 4.81). In de-DE the web names of
    /// these keys are separate catalog items in the current app, which shows
    /// these keys under their own name. Drop this if `baseURL` is switched to
    /// the app tables.
    private static let webTableFixes: [String: [String: String]] = {
        let deDE = ["Peperoni", "Prosecco", "Konfitüre", "Paniermehl", "WC-Reiniger",
                    "Conditioner", "Kartoffelstock", "Mettigel"]
        // Typo "Lib balm" plus four keys the web English tables lack.
        let english = ["Lippenpomade": "Lip balm", "Kaffeebohnen": "Coffee beans",
                       "Kaffeekapseln": "Coffee capsules", "Kaffeepads": "Coffee pads",
                       "Pfeffer": "Black Pepper"]
        return [
            "de-DE": Dictionary(uniqueKeysWithValues: deDE.map { ($0, $0) }),
            "en-US": english, "en-GB": english, "en-CA": english, "en-AU": english
        ]
    }()

    static func displayName(for key: String, locale: String? = currentLocale()) -> String {
        guard let locale else { return key }
        return webTableFixes[locale]?[key] ?? table(locale: locale)[key] ?? key
    }
}
