import SwiftUI
import WidgetKit

private extension NexusWidgetKind {
    var settingsKind: Self {
        self == .industryList ? .industryOverview : self
    }

    var settingsTitle: String {
        settingsKind == .industryOverview
            ? String(localized: "Widget_Industry_Settings", table: "Widgets", bundle: WidgetLocalization.bundle)
            : title
    }
}

struct WidgetSettingsView: View {
    @ObservedObject private var service = WidgetRefreshService.shared
    @AppStorage(WidgetMarketWatchlist.key, store: WidgetMarketWatchlist.defaults) private var storedItems: Data?

    var body: some View {
        List {
            Section {
                ForEach(NexusWidgetKind.allCases.filter { $0 == $0.settingsKind }, id: \.self) { kind in
                    NavigationLink {
                        WidgetConfigurationView(kind: kind)
                    } label: {
                        HStack(spacing: 12) {
                            Image(kind.iconAsset)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 36, height: 36)
                                .clipShape(.rect(cornerRadius: 6))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.settingsTitle)
                                selectionSummary(for: kind)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Widget_Add_Instructions", tableName: "Widgets")
                    Text("Widget_Settings_Scope", tableName: "Widgets")
                }
            }

            if service.storageError {
                Section {
                    Text("Widget_Storage_Error", tableName: "Widgets")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .monospacedDigit()
        .navigationTitle(Text("Widget_Settings_Title", tableName: "Widgets"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { service.reconcileCharacters() }
    }

    private func selectionSummary(for kind: NexusWidgetKind) -> Text {
        if kind == .market {
            let count = WidgetMarketWatchlist.decode(storedItems).count
            return Text("Widget_Item_Count \(count)", tableName: "Widgets")
        }
        return Text("Widget_Character_Count \(service.selectedIDs(for: kind).count)", tableName: "Widgets")
    }
}

struct WidgetConfigurationView: View {
    let kind: NexusWidgetKind

    @ObservedObject private var service = WidgetRefreshService.shared
    @AppStorage(WidgetMarketWatchlist.key, store: WidgetMarketWatchlist.defaults) private var storedItems: Data?
    @State private var isShowingItemPicker = false
    @State private var isShowingMarketLimit = false

    init(kind: NexusWidgetKind) {
        self.kind = kind.settingsKind
    }

    private var items: [WidgetChoice] {
        WidgetMarketWatchlist.decode(storedItems)
    }

    var body: some View {
        List {
            if kind == .market {
                marketSettings
            } else if service.characters.isEmpty {
                Text("Widget_No_Accounts", tableName: "Widgets")
                    .foregroundStyle(.secondary)
            } else {
                characterSettings
            }
        }
        .listStyle(.insetGrouped)
        .monospacedDigit()
        .navigationTitle(kind.settingsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if kind == .market {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingItemPicker = true
                    } label: {
                        Label("Main_Market_Watch_List_Add_Item", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingItemPicker) {
            MarketItemSelectorView(
                databaseManager: .shared,
                existingItems: Set(items.map(\.id)),
                onItemSelected: { addItems([$0]) },
                onBatchItemsSelected: addItems,
                onItemDeselected: { item in saveItems(items.filter { $0.id != item.id }) },
                showSelected: true,
                allowTypeIDs: nil
            )
            .alert(
                Text("Widget_Market_Maximum \(WidgetMarketWatchlist.maximumItems)", tableName: "Widgets"),
                isPresented: $isShowingMarketLimit
            ) {
                Button("Common_Done", role: .cancel) {}
            }
        }
        .onAppear { service.reconcileCharacters() }
    }

    private var characterSettings: some View {
        let characters = service.characters
        let expired = Set(characters.filter(\.refreshTokenExpired).map(\.CharacterID))
        return MultiCharacterSelectionSection(
            availableCharacters: characters.map { ($0.CharacterID, $0.CharacterName) },
            selectedCharacterIds: Binding(
                get: { service.selectedIDs(for: kind) },
                set: { service.setSelectedIDs($0, for: kind) }
            ),
            showsSelectAllFirst: true
        ) { id, name in
            WidgetCharacterPreviewRow(
                kind: kind, characterID: id, name: name, isExpired: expired.contains(id)
            )
        }
    }

    private var marketSettings: some View {
        Section {
            if items.isEmpty {
                Text("Main_Market_Watch_List_Empty")
                    .foregroundStyle(.secondary)
            }
            ForEach(items, id: \.id) { item in
                Label {
                    Text(ItemInfoMap.typeName(for: item.id) ?? item.name)
                } icon: {
                    IconManager.shared.loadImage(for: ItemInfoMap.iconFilename(for: item.id))
                        .resizable()
                        .frame(width: 34, height: 34)
                        .clipShape(.rect(cornerRadius: 6))
                        .accessibilityHidden(true)
                }
            }
            .onDelete { indices in
                var updated = items
                updated.remove(atOffsets: indices)
                saveItems(updated)
            }
            .onMove { indices, destination in
                var updated = items
                updated.move(fromOffsets: indices, toOffset: destination)
                saveItems(updated)
            }
        } header: {
            if !items.isEmpty {
                Text("Widget_Followed_Items", tableName: "Widgets")
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Widget_Market_Maximum \(WidgetMarketWatchlist.maximumItems)", tableName: "Widgets")
                if items.count > 1 {
                    Text("Widget_Market_Watchlist_Order", tableName: "Widgets")
                }
            }
        }
    }

    private func addItems(_ selected: [DatabaseListItem]) {
        let current = items
        var existing = Set(current.map(\.id))
        let additions = selected.compactMap { item -> WidgetChoice? in
            guard existing.insert(item.id).inserted else { return nil }
            return WidgetChoice(id: item.id, name: item.name)
        }
        let remaining = max(0, WidgetMarketWatchlist.maximumItems - current.count)
        saveItems(current + additions.prefix(remaining))
        if additions.count > remaining {
            isShowingMarketLimit = true
        }
    }

    private func saveItems(_ updated: [WidgetChoice]) {
        let updated = WidgetMarketWatchlist.limited(updated)
        guard updated != items, let data = try? JSONEncoder().encode(updated) else { return }
        storedItems = data
        service.preferencesDidChange(for: .market)
    }
}
