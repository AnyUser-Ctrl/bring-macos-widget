import SwiftUI
import WidgetKit

struct ListPickerView: View {
    let onLogout: () -> Void

    @State private var lists: [BringList] = []
    @State private var selectedListUuid: String? = BringStore.shared.selectedListUuid
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var previewItems: [BringItem] = []
    @State private var lastRefresh: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("List for the Widget")
                        .font(.system(size: 22, weight: .bold))
                    if let email = BringStore.shared.email {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Sign Out", action: logout)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            if isLoading && lists.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .frame(minHeight: 120)
            } else if let errorMessage, lists.isEmpty {
                errorBox(errorMessage)
            } else {
                Picker("List", selection: Binding(
                    get: { selectedListUuid ?? "" },
                    set: { newValue in
                        selectedListUuid = newValue.isEmpty ? nil : newValue
                        if let list = lists.first(where: { $0.listUuid == newValue }) {
                            BringStore.shared.selectedListUuid = list.listUuid
                            BringStore.shared.selectedListName = list.name
                            Task { await refreshItems() }
                            WidgetCenter.shared.reloadAllTimelines()
                        }
                    }
                )) {
                    Text("No List").tag("")
                    ForEach(lists) { list in
                        Text(list.name).tag(list.listUuid)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Preview")
                        .font(.headline)
                    Spacer()
                    if let lastRefresh {
                        Text(lastRefresh, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        Task { await refreshItems() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(selectedListUuid == nil || isLoading)
                }

                if selectedListUuid == nil {
                    Text("Choose a list above to see a preview.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if previewItems.isEmpty {
                    Text(isLoading ? "Loading…" as LocalizedStringKey : "This list is empty.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(previewItems) { item in
                                HStack(spacing: 6) {
                                    Image(systemName: "circle")
                                        .foregroundStyle(.tertiary)
                                        .font(.caption)
                                    Text(item.localizedName)
                                        .font(.body)
                                    if !item.specification.isEmpty {
                                        Text("· \(item.specification)")
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button {
                    WidgetCenter.shared.reloadAllTimelines()
                } label: {
                    Label("Refresh Widget", systemImage: "square.grid.2x2")
                }
                .controlSize(.regular)
            }
        }
        .task { await loadLists() }
    }

    @ViewBuilder
    private func errorBox(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.callout)
                .foregroundStyle(.red)
            Button("Try Again") {
                Task { await loadLists() }
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func loadLists() async {
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await BringAPI.shared.fetchLists()
            await MainActor.run {
                self.lists = fetched
                if self.selectedListUuid == nil, let first = fetched.first {
                    self.selectedListUuid = first.listUuid
                    BringStore.shared.selectedListUuid = first.listUuid
                    BringStore.shared.selectedListName = first.name
                } else if let current = self.selectedListUuid,
                          let matching = fetched.first(where: { $0.listUuid == current }) {
                    // Keep selectedListName in sync — the widget reads it as
                    // the header title.
                    BringStore.shared.selectedListName = matching.name
                }
                self.isLoading = false
            }
            await refreshItems()
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }

    private func refreshItems() async {
        guard let listUuid = selectedListUuid,
              let list = lists.first(where: { $0.listUuid == listUuid })
                ?? (BringStore.shared.selectedListName.map { BringList(listUuid: listUuid, name: $0, theme: nil) })
        else { return }
        isLoading = true
        do {
            let response = try await BringAPI.shared.fetchItems(listUuid: listUuid)
            if let langs = try? await BringAPI.shared.fetchListArticleLanguages() {
                BringStore.shared.listArticleLanguages = langs
            }
            BringStore.shared.macArticleLocale = BringArticleNames.bringLocale()
            await BringIcons.prefetch(itemNames: response.purchase.map(\.name))
            await BringArticleNames.prefetch(locale: BringArticleNames.currentLocale())
            let cached = CachedItems(
                listUuid: listUuid,
                listName: list.name,
                items: response.purchase.map { .init(name: $0.name, specification: $0.specification) },
                fetchedAt: Date()
            )
            BringStore.shared.saveCachedItems(cached)
            await MainActor.run {
                self.previewItems = response.purchase
                self.lastRefresh = cached.fetchedAt
                self.isLoading = false
            }
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }

    private func logout() {
        BringStore.shared.clearAuth()
        WidgetCenter.shared.reloadAllTimelines()
        onLogout()
    }
}

#Preview {
    ListPickerView(onLogout: {})
        .padding()
        .frame(width: 460, height: 560)
}
