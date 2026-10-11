import SwiftUI

private let environmentCategoryRowInsets = EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
private let environmentSelectionRowInsets = EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)

struct EnvironmentSettingsView: View {
    let databaseManager: DatabaseManager
    @ObservedObject var viewModel: FittingEditorViewModel
    @Binding var selectedTypeId: Int?
    @Binding var pendingSelectionItem: DatabaseListItem?
    let onCommit: () -> Void

    var body: some View {
        List {
            Section {
                Button {
                    selectedTypeId = nil
                    pendingSelectionItem = nil
                } label: {
                    HStack {
                        Image(systemName: "trash.fill")
                            .foregroundColor(.red)
                            .frame(width: 32, height: 32)
                        Text(NSLocalizedString("Environment_Clear_Selection", comment: "清空选项"))
                        Spacer()
                    }
                }
                .foregroundColor(.primary)
                .disabled(selectedTypeId == nil)
            }
            .listRowInsets(environmentCategoryRowInsets)

            Section(header: Text(NSLocalizedString("Environment_Select_Category", comment: "选择类别"))) {
                ForEach(EnvironmentOptions.Category.allCases) { category in
                    NavigationLink {
                        EnvironmentEffectListView(
                            databaseManager: databaseManager,
                            category: category,
                            selectedTypeId: $selectedTypeId,
                            onItemSelected: { item in
                                pendingSelectionItem = item
                            }
                        )
                    } label: {
                        EnvironmentCategoryRow(category: category)
                    }
                    .foregroundColor(.primary)
                }
            }
            .listRowInsets(environmentCategoryRowInsets)

            if let item = pendingSelectionItem {
                Section(header: Text(NSLocalizedString("Environment_Current_Selection", comment: "当前选择"))) {
                    EnvironmentEffectRowContent(
                        item: item,
                        rowIconAssetName: EnvironmentEffectNaming.item(for: item.id)?.rowIconAssetName
                    )
                }
                .listRowInsets(environmentCategoryRowInsets)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Environment_Settings_Title", comment: "环境设置"))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            onCommit()
        }
    }
}

private struct EnvironmentCategoryRow: View {
    let category: EnvironmentOptions.Category

    var body: some View {
        HStack(spacing: 12) {
            Image(category.iconAssetName)
                .resizable()
                .frame(width: 32, height: 32)
                .cornerRadius(6)

            Text(category.title)
                .foregroundColor(.primary)
        }
    }
}

struct EnvironmentEffectListView: View {
    @Environment(\.dismiss) private var dismiss

    let databaseManager: DatabaseManager
    let category: EnvironmentOptions.Category
    @Binding var selectedTypeId: Int?
    let onItemSelected: (DatabaseListItem) -> Void

    @State private var sections: [EnvironmentEffectSection] = []
    @State private var flatItems: [EnvironmentEffectItem] = []
    @State private var descriptions: [Int: String] = [:]
    @State private var isLoading = true

    private var isGroupedList: Bool {
        category == .wormhole || category == .abyssal
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if isGroupedList ? sections.isEmpty : flatItems.isEmpty {
                ContentUnavailableView {
                    Label(
                        NSLocalizedString("Misc_No_Data", comment: "无数据"),
                        systemImage: "exclamationmark.triangle"
                    )
                }
            } else {
                List {
                    if isGroupedList {
                        ForEach(sections) { section in
                            Section(header: Text(section.title)) {
                                ForEach(section.items) { item in
                                    environmentSelectionRow(for: item)
                                }
                            }
                        }
                    } else {
                        ForEach(flatItems) { item in
                            environmentSelectionRow(for: item)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadItems()
        }
    }

    private func environmentSelectionRow(for item: EnvironmentEffectItem) -> some View {
        EnvironmentEffectSelectionRow(
            item: item.asDatabaseListItem(),
            rowIconAssetName: item.rowIconAssetName,
            effectDescription: descriptions[item.typeId] ?? "",
            isSelected: selectedTypeId == item.typeId
        ) {
            selectedTypeId = item.typeId
            onItemSelected(item.asDatabaseListItem())
            dismiss()
        }
    }

    private func loadItems() {
        isLoading = true

        let typeIds = category.typeIds(from: EnvironmentOptions.shared)
        guard !typeIds.isEmpty else {
            sections = []
            flatItems = []
            isLoading = false
            return
        }

        // 内存索引构建环境效果物品
        let loadedItems: [EnvironmentEffectItem] = typeIds.compactMap { typeId in
            EnvironmentEffectNaming.item(for: typeId)
        }

        descriptions = EnvironmentEffectSummary.descriptions(typeIds: typeIds, databaseManager: databaseManager)

        switch category {
        case .wormhole:
            sections = EnvironmentEffectNaming.wormholeSections(from: loadedItems)
            flatItems = []
        case .abyssal:
            sections = EnvironmentEffectNaming.abyssalSections(from: loadedItems)
            flatItems = []
        case .other:
            sections = []
            flatItems = loadedItems.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        }

        isLoading = false
    }
}

private struct EnvironmentEffectSelectionRow: View {
    let item: DatabaseListItem
    let rowIconAssetName: String?
    let effectDescription: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                EnvironmentEffectRowContent(
                    item: item,
                    rowIconAssetName: rowIconAssetName,
                    effectDescription: effectDescription.isEmpty
                        ? NSLocalizedString("Environment_Effect_Unavailable", comment: "")
                        : effectDescription
                )

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(.primary)
        .listRowInsets(environmentSelectionRowInsets)
    }
}

/// 分类列表与当前选择共用环境图标，避免深渊效果回退到缺失的物品图标。
private struct EnvironmentEffectRowContent: View {
    let item: DatabaseListItem
    let rowIconAssetName: String?

    var effectDescription: String? = nil

    var body: some View {
        HStack(alignment: effectDescription == nil ? .center : .top, spacing: 12) {
            if let rowIconAssetName {
                Image(rowIconAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
            } else {
                Image(uiImage: IconManager.shared.loadUIImage(for: item.iconFileName))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .foregroundColor(.primary)
                if let effectDescription {
                    Text(effectDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, effectDescription == nil ? 0 : 4)
    }
}
