import SwiftUI

struct ShowMutationInfo: View {
    let itemID: Int
    @ObservedObject var databaseManager: DatabaseManager

    @State private var itemDetails: ItemDetails?
    @State private var mutationAttributes: [SDEMemoryStore.DynamicItemAttributeInfo] = []
    @State private var applicableItems: [(typeID: Int, name: String, iconFileName: String)] = []
    @State private var resultingItem: (typeID: Int, name: String, iconFileName: String)?

    var body: some View {
        List {
            if let itemDetails {
                ItemBasicInfoView(
                    itemDetails: itemDetails,
                    databaseManager: databaseManager,
                    modifiedAttributes: nil
                )
            }

            IndustrySection(
                itemID: itemID,
                databaseManager: databaseManager,
                itemDetails: itemDetails
            )

            if !mutationAttributes.isEmpty {
                Section(
                    header: Text(NSLocalizedString("Main_Database_Mutation_Attribute", comment: ""))
                        .font(.headline)
                ) {
                    ForEach(mutationAttributes, id: \.attributeID) { attribute in
                        HStack {
                            HStack(spacing: 8) {
                                if let iconFileName = attribute.iconFileName {
                                    IconManager.shared.loadImage(for: iconFileName)
                                        .resizable()
                                        .frame(width: 24, height: 24)
                                }
                                Text(attribute.name)
                                    .font(.body)
                            }

                            Spacer()

                            HStack(spacing: 4) {
                                Text(
                                    formatValue(
                                        attribute.highIsGood
                                            ? attribute.minValue : attribute.maxValue
                                    )
                                )
                                .foregroundColor(.red)
                                Text("-")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Text(
                                    formatValue(
                                        attribute.highIsGood
                                            ? attribute.maxValue : attribute.minValue
                                    )
                                )
                                .foregroundColor(.green)
                            }
                        }
                    }
                    .listRowInsets(itemSectionRowInsets)
                }
            }

            if !applicableItems.isEmpty {
                Section(
                    header: Text(NSLocalizedString("Main_Database_Mutation_Source", comment: ""))
                        .font(.headline)
                ) {
                    ForEach(applicableItems, id: \.typeID) { item in
                        NavigationLink {
                            ShowItemInfo(databaseManager: databaseManager, itemID: item.typeID)
                        } label: {
                            mutationItemLabel(icon: item.iconFileName, name: item.name)
                        }
                    }
                    .listRowInsets(itemSectionRowInsets)
                }

                if let resultingItem {
                    Section(
                        header: Text(
                            NSLocalizedString("Main_Database_Mutation_Results", comment: "")
                        )
                        .font(.headline)
                    ) {
                        NavigationLink {
                            ShowItemInfo(
                                databaseManager: databaseManager,
                                itemID: resultingItem.typeID
                            )
                        } label: {
                            mutationItemLabel(
                                icon: resultingItem.iconFileName,
                                name: resultingItem.name
                            )
                        }
                        .listRowInsets(itemSectionRowInsets)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Item_Info", comment: ""))
        .onAppear {
            itemDetails = databaseManager.getItemDetails(for: itemID)
            loadMutationData()
        }
    }

    private func mutationItemLabel(icon: String, name: String) -> some View {
        HStack {
            IconManager.shared.loadImage(for: icon)
                .resizable()
                .frame(width: 32, height: 32)
                .cornerRadius(4)
            Text(name)
                .font(.body)
        }
    }

    private func formatValue(_ value: Double) -> String {
        String(format: "%+.2f%%", (value - 1) * 100)
    }

    private func loadMutationData() {
        // 突变属性范围（含覆盖后的 highIsGood）从 SDEMemoryStore 内存缓存取
        mutationAttributes = SDEMemoryStore.dynamicItemAttributes(forTypeID: itemID)

        // 映射数据从 SDEMemoryStore 获取（已随 SDE 初始化缓存到内存）
        let mappings = SDEMemoryStore.dynamicMappings(forTypeID: itemID)
        let sorted = mappings.sorted { lhs, rhs in
            let lMeta = SDEMemoryStore.type(for: lhs.applicableType)?.metaGroupID ?? 0
            let rMeta = SDEMemoryStore.type(for: rhs.applicableType)?.metaGroupID ?? 0
            if lMeta != rMeta {
                return lMeta < rMeta
            }
            return lhs.applicableType < rhs.applicableType
        }

        var seenTypeIDs = Set<Int>()
        applicableItems = sorted.compactMap { mapping in
            let typeID = mapping.applicableType
            if seenTypeIDs.contains(typeID) {
                return nil
            }
            seenTypeIDs.insert(typeID)
            guard let info = SDEMemoryStore.type(for: typeID) else { return nil }
            return (typeID: typeID, name: info.name, iconFileName: info.iconFilename)
        }

        if let first = sorted.first,
           let info = SDEMemoryStore.type(for: first.resultingType)
        {
            resultingItem = (
                typeID: first.resultingType, name: info.name, iconFileName: info.iconFilename
            )
        }
    }
}
