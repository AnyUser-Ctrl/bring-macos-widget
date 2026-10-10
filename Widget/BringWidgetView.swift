import SwiftUI
import WidgetKit

// Thin alias layer over DesignTokens (generated from design/tokens.json) —
// the single source of truth for colors. Widget surfaces are deliberately mode-invariant
// (widgetSurface/-Raised are navy in light and dark mode), and so are the accents.
enum BringTheme {
    static let background = DesignTokens.widgetSurface
    static let backgroundLighter = DesignTokens.widgetSurfaceRaised
    static let coral = DesignTokens.accent
    static let coralBorder = DesignTokens.accentBorder
    static let mint = DesignTokens.success
}

private let bringWebBaseURL = URL(string: "https://web.getbring.com")!

private func bringListURL(_ listUuid: String?) -> URL {
    if let id = listUuid, !id.isEmpty {
        return URL(string: "https://web.getbring.com/app/lists/\(id)") ?? bringWebBaseURL
    }
    return bringWebBaseURL
}

/// Wraps content in a Button bound to `BringRefreshIntent`. Used for the
/// header + grid region so a click anywhere there reloads the list.
private struct RefreshClickRegion<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        if #available(macOS 14.0, *) {
            Button(intent: BringRefreshIntent()) {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }
}

struct BringWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BringEntry

    var body: some View {
        ZStack {
            content
        }
        .foregroundStyle(.white)
        // Click-action split per region:
        //   Header + Items  → Button(intent: BringRefreshIntent)  (in ReadyLayout)
        //   Footer          → Link(destination: bringListURL)      (in Footer view)
        // WidgetKit allows only one action per region; we differentiate by
        // placing them in non-overlapping regions.
    }

    @ViewBuilder
    private var content: some View {
        let webURL = bringListURL(entry.listUuid)
        switch entry.state {
        case .ready(let listName, let items, let asOf):
            ReadyLayout(listName: listName, items: items, asOf: asOf, family: family, webURL: webURL)
        case .empty(let listName, let asOf):
            EmptyLayout(listName: listName, asOf: asOf, family: family, webURL: webURL)
        case .notSignedIn:
            HintLayout(
                title: "Not Signed In",
                subtitle: "Open the Bring Widget app and sign in."
            )
        case .noListSelected:
            HintLayout(
                title: "No List Selected",
                subtitle: "Choose a list in the app."
            )
        }
    }
}

// MARK: - Ready layout

private struct ReadyLayout: View {
    let listName: String
    let items: [BringItem]
    let asOf: Date
    let family: WidgetFamily
    let webURL: URL

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 5 : 6) {
            // Header → click opens the corresponding list on web.getbring.com
            Link(destination: webURL) {
                Header(listName: displayListName, totalCount: items.count, asOf: asOf, family: family)
            }
            // Item grid → click triggers BringRefreshIntent (live reload)
            RefreshClickRegion {
                ItemGrid(items: visibleItems, family: family)
            }
        }
        .padding(.top, 6)
    }

    private var displayListName: String {
        let trimmed = listName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "Shopping List") : trimmed
    }

    private var visibleLimit: Int {
        switch family {
        case .systemSmall: return 4
        case .systemMedium: return 6
        case .systemLarge: return 15
        default: return 6
        }
    }

    private var visibleItems: [BringItem] {
        Array(items.prefix(visibleLimit))
    }
}

private struct Header: View {
    let listName: String
    let totalCount: Int
    let asOf: Date
    let family: WidgetFamily

    /// Follows the user's 12/24-hour setting, like the app's preview header.
    /// The small widget has no room for "AM"/"PM", so it drops the marker.
    private var asOfText: String {
        family == .systemSmall
            ? asOf.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
            : asOf.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        switch family {
        case .systemSmall:
            compactHeader(badge: 18, name: 13, sub: 9)
        case .systemMedium:
            compactHeader(badge: 22, name: 15, sub: 9)
        case .systemLarge:
            largeHeader
        default:
            largeHeader
        }
    }

    /// Single-line header for small + medium — list name + counter share one row.
    /// The tiny `↗` next to the name signals that tapping the header opens
    /// web.getbring.com.
    private func compactHeader(badge: CGFloat, name: CGFloat, sub: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 6) {
            CartBadge(size: badge)
            Text(listName)
                .font(.system(size: name, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .widgetAccentable(true)
            Image(systemName: "arrow.up.forward")
                .font(.system(size: sub, weight: .semibold))
                .foregroundStyle(.secondary)
                .widgetAccentable(true)
            Spacer(minLength: 4)
            Text("\(totalCount) · \(asOfText)")
                .font(.system(size: sub, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .widgetAccentable(true)
        }
    }

    /// Two-line header reserved for large — there's room to breathe.
    private var largeHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            CartBadge(size: 28)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(listName)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .widgetAccentable(true)
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .widgetAccentable(true)
                }
                (Text("\(totalCount) items") + Text(verbatim: " · ") + Text("as of \(asOfText)"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .widgetAccentable(true)
            }
            Spacer(minLength: 4)
        }
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
        }
    }
}

private struct CartBadge: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(BringTheme.coral)
            Image(systemName: "cart.fill")
                .font(.system(size: size * 0.55, weight: .bold))
                .foregroundStyle(.white)
                .widgetAccentable(true)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Item grid

private struct ItemGrid: View {
    let items: [BringItem]
    let family: WidgetFamily

    private var columnCount: Int {
        switch family {
        case .systemSmall: return 2
        case .systemMedium: return 3
        case .systemLarge: return 3
        default: return 2
        }
    }

    private var spacing: CGFloat {
        switch family {
        case .systemSmall: return 5
        case .systemMedium: return 6
        case .systemLarge: return 4
        default: return 6
        }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnCount)
    }

    /// Tiles may shrink from their preferred height down to this before a
    /// row is dropped.
    private var minTileHeight: CGFloat {
        family == .systemSmall ? 40 : 44
    }

    var body: some View {
        // Desktop widget sizes differ per display (e.g. a large widget is
        // 344 pt tall on some Macs, 376 pt on others), so fit the rows to the
        // space that is really there instead of clipping the last one.
        GeometryReader { geo in
            let fit = fit(height: geo.size.height)
            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(items.prefix(fit.count)) { item in
                    ItemTile(item: item, family: family, height: fit.tileHeight)
                }
            }
        }
    }

    private func fit(height: CGFloat) -> (count: Int, tileHeight: CGFloat) {
        let preferred = ItemTile.preferredHeight(for: family)
        var rows = (items.count + columnCount - 1) / columnCount
        while rows > 1 {
            let tile = (height - CGFloat(rows - 1) * spacing) / CGFloat(rows)
            if tile >= minTileHeight {
                return (min(items.count, rows * columnCount), min(preferred, tile))
            }
            rows -= 1
        }
        return (min(items.count, columnCount), min(preferred, max(height, minTileHeight)))
    }
}

private struct ItemTile: View {
    let item: BringItem
    let family: WidgetFamily
    let height: CGFloat

    static func preferredHeight(for family: WidgetFamily) -> CGFloat {
        family == .systemSmall ? 48 : 56
    }

    private var initial: String {
        let trimmed = item.localizedName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.first.map { String($0).uppercased() } ?? "?"
    }

    private var displayName: String {
        // Bring lets users paste URLs into item names (via specification on
        // the web). Strip them so tiles stay readable.
        let name = item.localizedName
        let withoutURL = name
            .replacingOccurrences(of: #"https?://[^\s]+"#,
                                  with: "",
                                  options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return withoutURL.isEmpty ? name : withoutURL
    }

    private var sizing: (initial: CGFloat, name: CGFloat, spec: CGFloat,
                         padV: CGFloat, padH: CGFloat, corner: CGFloat) {
        switch family {
        case .systemSmall:
            return (18, 9, 7, 4, 3, 6)
        case .systemMedium, .systemLarge:
            // Identical tile size in medium and large per user request.
            return (22, 10, 8, 5, 4, 7)
        default:
            return (20, 10, 8, 6, 4, 6)
        }
    }

    private var cachedImage: NSImage? {
        BringIcons.loadCachedImage(forName: item.name)
    }

    private var iconSize: CGFloat {
        switch family {
        case .systemSmall: return 22
        case .systemMedium: return 28
        case .systemLarge: return 20
        default: return 26
        }
    }

    /// < 1 when ItemGrid had to shrink the tile below its preferred height;
    /// icon and padding shrink with it so the label stays inside the tile.
    private var compression: CGFloat {
        min(1, height / Self.preferredHeight(for: family))
    }

    var body: some View {
        let s = sizing
        VStack(spacing: 1) {
            Group {
                if let nsImage = cachedImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: iconSize * compression, height: iconSize * compression)
                } else {
                    Text(initial)
                        .font(.system(size: s.initial * compression, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .widgetAccentable(true)

            Text(displayName)
                .font(.system(size: s.name, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.55)
                .foregroundStyle(.white)
                .widgetAccentable(true)

            if !item.specification.isEmpty {
                Text(item.specification)
                    .font(.system(size: s.spec, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .widgetAccentable(true)
            }
        }
        .padding(.vertical, compression < 1 ? 0 : s.padV)
        .padding(.horizontal, s.padH)
        // Fixed height (min == max) so the grid's total height is
        // predictable — header and footer never get pushed out when an
        // item name needs two lines. ItemGrid picks the height.
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .center)
        .background(BringTheme.coral)
        .clipShape(RoundedRectangle(cornerRadius: s.corner, style: .continuous))
    }
}

// MARK: - Empty + Hint layouts

private struct EmptyLayout: View {
    let listName: String
    let asOf: Date
    let family: WidgetFamily
    let webURL: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Link(destination: webURL) {
                Header(listName: listName, totalCount: 0, asOf: asOf, family: family)
            }
            RefreshClickRegion {
                VStack(alignment: .leading, spacing: 6) {
                    Spacer(minLength: 4)
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(BringTheme.mint)
                                .widgetAccentable(true)
                            Text("List is empty")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .widgetAccentable(true)
                        }
                        Spacer()
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.top, 6)
    }
}

private struct HintLayout: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "cart")
                    .foregroundStyle(BringTheme.coral)
                    .widgetAccentable(true)
                Text("Bring!")
                    .font(.headline)
                    .widgetAccentable(true)
                Spacer()
            }
            Spacer(minLength: 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                    .widgetAccentable(true)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .widgetAccentable(true)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    BringWidget()
} timeline: {
    BringEntry(date: Date(), state: .ready(
        listName: "Home",
        items: [
            .init(name: "Milch", specification: "1 L"),
            .init(name: "Brot", specification: ""),
            .init(name: "Tomaten", specification: ""),
            .init(name: "Käse", specification: "Gouda"),
            .init(name: "Bananen", specification: "")
        ],
        asOf: Date()
    ), listUuid: nil)
}

#Preview("Medium", as: .systemMedium) {
    BringWidget()
} timeline: {
    BringEntry(date: Date(), state: .ready(
        listName: "Home",
        items: [
            .init(name: "Eier", specification: "10 pcs"),
            .init(name: "Butter", specification: ""),
            .init(name: "Milch", specification: "1 L"),
            .init(name: "Brot", specification: ""),
            .init(name: "Tomaten", specification: "organic"),
            .init(name: "Avocado", specification: ""),
            .init(name: "Salat", specification: ""),
            .init(name: "Bananen", specification: "")
        ],
        asOf: Date()
    ), listUuid: nil)
}

#Preview("Large", as: .systemLarge) {
    BringWidget()
} timeline: {
    BringEntry(date: Date(), state: .ready(
        listName: "Weekly Shop",
        items: (0..<18).map { BringItem(name: "Item \($0)", specification: $0.isMultiple(of: 3) ? "organic" : "") },
        asOf: Date()
    ), listUuid: nil)
}

#Preview("Empty", as: .systemMedium) {
    BringWidget()
} timeline: {
    BringEntry(date: Date(), state: .empty(listName: "Home", asOf: Date()), listUuid: nil)
}

#Preview("Signed out", as: .systemMedium) {
    BringWidget()
} timeline: {
    BringEntry(date: Date(), state: .notSignedIn, listUuid: nil)
}

// MARK: - Vibrant (Desktop Unfocused) previews
//
// The `#Preview(_, as:)` widget-macro doesn't expose a way to force the
// widget rendering mode. We use plain SwiftUI previews instead — they
// accept `.environment(\.widgetRenderingMode, .vibrant)`, which is exactly
// what macOS applies when the desktop is unfocused.

#Preview("Medium · Vibrant (Unfocused)") {
    BringWidgetView(entry: BringEntry(date: Date(), state: .ready(
        listName: "Home",
        items: [
            .init(name: "Eier", specification: "10 pcs"),
            .init(name: "Butter", specification: ""),
            .init(name: "Milch", specification: "1 L"),
            .init(name: "Brot", specification: ""),
            .init(name: "Tomaten", specification: "organic"),
            .init(name: "Avocado", specification: "")
        ],
        asOf: Date()
    ), listUuid: nil))
    .containerBackground(BringTheme.background, for: .widget)
    .environment(\.widgetRenderingMode, .vibrant)
    .frame(width: 360, height: 170)
}

#Preview("Large · Vibrant (Unfocused)") {
    BringWidgetView(entry: BringEntry(date: Date(), state: .ready(
        listName: "Weekly Shop",
        items: (0..<18).map { BringItem(name: "Item \($0)", specification: $0.isMultiple(of: 3) ? "organic" : "") },
        asOf: Date()
    ), listUuid: nil))
    .containerBackground(BringTheme.background, for: .widget)
    .environment(\.widgetRenderingMode, .vibrant)
    .frame(width: 360, height: 376)
}
