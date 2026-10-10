import AppIntents
import SwiftUI
import WidgetKit

/// User-initiated reload of the Bring widget. Bound to the refresh button
/// inside the widget view. The system treats AppIntent-triggered reloads
/// as user actions and does not rate-limit them the way it rate-limits
/// timeline policies.
@available(macOS 14.0, *)
struct BringRefreshIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Bring! List"
    static var description = IntentDescription(
        "Fetches the selected Bring! list directly from api.getbring.com and re-renders the widget."
    )

    init() {}

    func perform() async throws -> some IntentResult {
        // Best-effort fetch so the next render finds fresh items.
        // Failures fall back to the cached entry on the provider side.
        let store = BringStore.shared
        if let listUuid = store.selectedListUuid {
            if let response = try? await BringAPI.shared.fetchItems(listUuid: listUuid) {
                let listName = store.selectedListName ?? String(localized: "Shopping List")
                store.saveCachedItems(
                    CachedItems(
                        listUuid: listUuid,
                        listName: listName,
                        items: response.purchase.map {
                            .init(name: $0.name, specification: $0.specification)
                        },
                        fetchedAt: Date()
                    )
                )
                await BringIcons.prefetch(itemNames: response.purchase.map(\.name))
                await BringArticleNames.prefetch(locale: BringArticleNames.currentLocale())
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct BringWidget: Widget {
    let kind: String = "BringWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BringTimelineProvider()) { entry in
            BringWidgetView(entry: entry)
                .containerBackground(BringTheme.background, for: .widget)
        }
        .configurationDisplayName("Bring! Shopping List")
        .description("Shows your selected Bring! list. Click to open web.getbring.com.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

enum BringEntryState {
    case ready(listName: String, items: [BringItem], asOf: Date)
    case empty(listName: String, asOf: Date)
    case notSignedIn
    case noListSelected
}

struct BringEntry: TimelineEntry {
    let date: Date
    let state: BringEntryState
    let listUuid: String?
}

struct BringTimelineProvider: TimelineProvider {
    private let refreshInterval: TimeInterval = 20 * 60

    func placeholder(in context: Context) -> BringEntry {
        BringEntry(
            date: Date(),
            state: .ready(
                listName: String(localized: "Shopping List"),
                items: previewItems,
                asOf: Date()
            ),
            listUuid: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (BringEntry) -> Void) {
        completion(BringEntry(
            date: Date(),
            state: .ready(
                listName: nonEmpty(BringStore.shared.selectedListName) ?? String(localized: "Shopping List"),
                items: previewItems,
                asOf: Date()
            ),
            listUuid: BringStore.shared.selectedListUuid
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BringEntry>) -> Void) {
        Task {
            let entry = await loadEntry()
            let next = Date().addingTimeInterval(refreshInterval)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private func loadEntry() async -> BringEntry {
        let store = BringStore.shared

        guard store.isAuthenticated || store.password != nil else {
            return BringEntry(date: Date(), state: .notSignedIn, listUuid: nil)
        }
        guard let listUuid = store.selectedListUuid else {
            return BringEntry(date: Date(), state: .noListSelected, listUuid: nil)
        }

        do {
            let response = try await BringAPI.shared.fetchItems(listUuid: listUuid)
            let listName = nonEmpty(store.selectedListName) ?? String(localized: "Shopping List")
            await BringIcons.prefetch(itemNames: response.purchase.map(\.name))
            await BringArticleNames.prefetch(locale: BringArticleNames.currentLocale())
            store.saveCachedItems(
                CachedItems(
                    listUuid: listUuid,
                    listName: listName,
                    items: response.purchase.map {
                        .init(name: $0.name, specification: $0.specification)
                    },
                    fetchedAt: Date()
                )
            )
            if response.purchase.isEmpty {
                return BringEntry(date: Date(),
                                  state: .empty(listName: listName, asOf: Date()),
                                  listUuid: listUuid)
            }
            return BringEntry(
                date: Date(),
                state: .ready(listName: listName, items: response.purchase, asOf: Date()),
                listUuid: listUuid
            )
        } catch {
            if let cached = store.cachedItems() {
                let items = cached.items.map { BringItem(name: $0.name, specification: $0.specification) }
                if items.isEmpty {
                    return BringEntry(date: Date(),
                                      state: .empty(listName: cached.listName, asOf: cached.fetchedAt),
                                      listUuid: listUuid)
                }
                return BringEntry(
                    date: Date(),
                    state: .ready(listName: cached.listName, items: items, asOf: cached.fetchedAt),
                    listUuid: listUuid
                )
            }
            return BringEntry(date: Date(), state: .notSignedIn, listUuid: listUuid)
        }
    }
}

private func nonEmpty(_ s: String?) -> String? {
    guard let trimmed = s?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
        return nil
    }
    return trimmed
}

private let previewItems: [BringItem] = [
    .init(name: "Milch", specification: "1 L"),
    .init(name: "Brot", specification: String(localized: "whole grain")),
    .init(name: "Tomaten", specification: ""),
    .init(name: "Käse", specification: "Gouda"),
    .init(name: "Äpfel", specification: String(localized: "organic")),
    .init(name: "Kaffee", specification: "")
]
