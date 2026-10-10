import AppKit
import Foundation

/// Resolves and caches Bring item icons from the public Bring web assets at
/// `https://web.getbring.com/assets/images/items/{normalized}.png`.
///
/// The normalization mirrors `BringItem.normalizeStringPath` in Bring's
/// JavaScript bundle: lowercase, spaces/dashes → `_`, ä/ö/ü/é → ae/oe/ue/e,
/// `!` stripped.
///
/// Cache strategy: every fetch writes a file into the App Group container.
/// A zero-byte file marks a 404 (so we don't retry every refresh). The widget
/// view loads the cached file synchronously and falls back to the first
/// letter when no image is available.
enum BringIcons {
    private static let baseURL = URL(string: "https://web.getbring.com/assets/images/items")!

    // Avoid hammering web.getbring.com when the list has lots of items.
    private static let concurrentDownloadLimit = 6

    // MARK: - Normalization

    static func normalize(_ name: String) -> String {
        var result = name.lowercased()
        let replacements: [(String, String)] = [
            (" ", "_"),
            ("-", "_"),
            ("!", ""),
            ("ä", "ae"),
            ("ö", "oe"),
            ("ü", "ue"),
            ("é", "e"),
            ("ß", "ss")
        ]
        for (from, to) in replacements {
            result = result.replacingOccurrences(of: from, with: to)
        }
        result = result.replacingOccurrences(
            of: #"[^a-z0-9_]"#,
            with: "",
            options: .regularExpression
        )
        return result
    }

    // MARK: - URLs

    static func remoteURL(forName name: String) -> URL? {
        let key = normalize(name)
        guard !key.isEmpty else { return nil }
        return baseURL.appendingPathComponent("\(key).png")
    }

    static var cacheDirectory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: BringStore.appGroup)?
            .appendingPathComponent("Icons", isDirectory: true)
    }

    static func cachedFileURL(forName name: String) -> URL? {
        guard let dir = cacheDirectory else { return nil }
        let key = normalize(name)
        guard !key.isEmpty else { return nil }
        return dir.appendingPathComponent("\(key).png")
    }

    // MARK: - Read

    /// Synchronously loads a cached icon. Returns nil if not cached or if the
    /// cache file is the 0-byte 404 marker.
    static func loadCachedImage(forName name: String) -> NSImage? {
        guard let url = cachedFileURL(forName: name) else { return nil }
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? Int, size == 0 {
            return nil // 404 marker
        }
        return NSImage(contentsOfFile: path)
    }

    // MARK: - Prefetch

    /// Downloads missing icons for the given item names in parallel batches.
    static func prefetch(itemNames: [String]) async {
        guard let dir = cacheDirectory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Filter to ones that are not yet cached.
        let missing: [(name: String, url: URL, file: URL)] = itemNames.compactMap { name in
            guard let remote = remoteURL(forName: name),
                  let file = cachedFileURL(forName: name) else { return nil }
            if FileManager.default.fileExists(atPath: file.path) { return nil }
            return (name, remote, file)
        }

        guard !missing.isEmpty else { return }

        // Batched parallel downloads.
        let chunks = stride(from: 0, to: missing.count, by: concurrentDownloadLimit).map {
            Array(missing[$0..<min($0 + concurrentDownloadLimit, missing.count)])
        }

        for chunk in chunks {
            await withTaskGroup(of: Void.self) { group in
                for entry in chunk {
                    group.addTask {
                        await download(url: entry.url, to: entry.file)
                    }
                }
            }
        }
    }

    private static func download(url: URL, to fileURL: URL) async {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse else { return }
            if http.statusCode == 200 {
                try? data.write(to: fileURL, options: .atomic)
            } else {
                // Write empty 404 marker so we don't refetch every refresh.
                try? Data().write(to: fileURL, options: .atomic)
            }
        } catch {
            // Transient failure — leave un-cached so next refresh retries.
        }
    }
}
