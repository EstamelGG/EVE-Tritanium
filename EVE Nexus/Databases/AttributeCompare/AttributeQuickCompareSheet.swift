import SwiftUI

/// 市场详情内：与同市场叶子组内全部物品做属性对比，不写盘
struct AttributeQuickCompareSheet: View {
    @ObservedObject var databaseManager: DatabaseManager
    let marketGroupID: Int
    @Environment(\.dismiss) private var dismiss

    @State private var items: [DatabaseListItem] = []
    @State private var compareResult: AttributeCompareUtil.CompareResult?
    @State private var isCalculating = false
    @AppStorage("showOnlyDifferences") private var showOnlyDifferences: Bool = false

    var body: some View {
        NavigationStack {
            List {
                if items.isEmpty {
                    Text(NSLocalizedString("Main_Attribute_Compare_Empty", comment: ""))
                        .foregroundColor(.secondary)
                } else if items.count < 2 {
                    ContentUnavailableView {
                        Label(
                            NSLocalizedString("Main_Attribute_Quick_Compare_Need_Two", comment: ""),
                            systemImage: "square.split.2x1"
                        )
                    } description: {
                        Text(
                            String.localizedStringWithFormat(
                                NSLocalizedString(
                                    "Main_Attribute_Quick_Compare_Single_Item_Format",
                                    comment: ""
                                ),
                                items.count
                            )
                        )
                    }
                } else {
                    Section {
                        Toggle(
                            NSLocalizedString(
                                "Main_Attribute_Compare_Show_Only_Differences",
                                comment: ""
                            ),
                            isOn: $showOnlyDifferences
                        )
                        .padding(.top, 4)
                    } header: {
                        Text(
                            String.localizedStringWithFormat(
                                NSLocalizedString("Main_Attribute_Quick_Compare_Count_Format", comment: ""),
                                items.count
                            )
                        )
                    }

                    if isCalculating {
                        CalculatingSection()
                    }

                    if let result = compareResult {
                        AttributeCompareResultSections(
                            result: result,
                            items: items,
                            showOnlyDifferences: showOnlyDifferences
                        )
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Main_Attribute_Quick_Compare", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Common_Done", comment: "")) {
                        dismiss()
                    }
                }
            }
            .onAppear(perform: loadAndCompare)
        }
    }

    private func loadAndCompare() {
        items = databaseManager.searchItemsMemory(
            filter: { _, info in info.marketGroupID == marketGroupID }
        )
        .sorted { $0.id < $1.id }

        guard items.count >= 2 else {
            compareResult = nil
            return
        }

        isCalculating = true
        let typeIDs = items.map(\.id)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = AttributeCompareUtil.compareAttributesWithResult(
                typeIDs: typeIDs,
                databaseManager: databaseManager
            )
            DispatchQueue.main.async {
                self.compareResult = result
                self.isCalculating = false
            }
        }
    }
}
