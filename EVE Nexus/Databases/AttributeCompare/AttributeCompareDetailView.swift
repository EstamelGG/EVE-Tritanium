import SwiftUI

/// 属性对比列表详情视图
struct AttributeCompareDetailView: View {
    let databaseManager: DatabaseManager
    @State var compare: AttributeCompare
    @State private var isShowingItemSelector = false
    @State private var items: [DatabaseListItem] = []
    @State private var isExpanded: Bool = false
    @State private var compareResult: AttributeCompareUtil.CompareResult?
    @State private var isCalculating: Bool = false
    @State private var marketPrices: [Int: Double] = [:]
    @State private var isLoadingPrices: Bool = false
    @State private var hasListChanges = false // 编辑会话内列表是否有增/删，关闭选择器时据此统一重算
    @AppStorage("showOnlyDifferences") private var showOnlyDifferences: Bool = false

    init(databaseManager: DatabaseManager, compare: AttributeCompare) {
        self.databaseManager = databaseManager

        // 在初始化时加载数据
        var initialCompare = compare
        var temporaryItems: [DatabaseListItem] = []

        if !compare.items.isEmpty {
            // 内存索引批量构建（已按 id 升序）
            temporaryItems = DatabaseListItem.listItems(
                for: compare.items.map(\.typeID),
                databaseManager: databaseManager
            )

            // 确保 compare.items 的顺序与加载的物品顺序一致
            if !temporaryItems.isEmpty {
                initialCompare.items = temporaryItems.map { item in
                    AttributeCompareItem(typeID: item.id)
                }
            }
        }

        // 设置初始状态
        _compare = State(initialValue: initialCompare)
        _items = State(initialValue: temporaryItems)
    }

    var body: some View {
        List {
            if compare.items.isEmpty {
                Text(NSLocalizedString("Main_Attribute_Compare_Empty", comment: ""))
                    .foregroundColor(.secondary)
            } else {
                // 物品列表部分
                Section {
                    DisclosureGroup(
                        isExpanded: $isExpanded,
                        content: {
                            ForEach(items) { item in
                                NavigationLink {
                                    MarketItemDetailView(
                                        databaseManager: databaseManager,
                                        itemID: item.id
                                    )
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(
                                            uiImage: IconManager.shared.loadUIImage(
                                                for: item.iconFileName
                                            )
                                        )
                                        .resizable()
                                        .frame(width: 36, height: 36)
                                        .cornerRadius(6)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.name)
                                                .lineLimit(1)

                                            Text(item.groupName ?? "")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                            .onDelete { indexSet in
                                let itemsToDelete = indexSet.map { items[$0].id }
                                compare.items.removeAll { itemsToDelete.contains($0.typeID) }
                                items.remove(atOffsets: indexSet)
                                AttributeCompareManager.shared.saveCompare(compare)
                                refreshCompareAfterListChange()
                            }
                        },
                        label: {
                            Text(
                                String(
                                    format: NSLocalizedString(
                                        "Main_Attribute_Compare_Items", comment: ""
                                    ),
                                    compare.items.count
                                )
                            )
                        }
                    )

                    // 在物品列表下方添加"只展示有差异的属性"开关
                    // （@AppStorage 自动持久化开关状态，切换无需任何处理）
                    if items.count >= 2 {
                        Toggle(
                            NSLocalizedString(
                                "Main_Attribute_Compare_Show_Only_Differences", comment: ""
                            ),
                            isOn: $showOnlyDifferences
                        )
                        .padding(.top, 4)
                    }
                } header: {
                    Text(NSLocalizedString("Main_Attribute_Compare_Item_List", comment: ""))
                }

                // 市场价格部分 - 只在超过2个物品时显示
                if items.count >= 2 {
                    Section {
                        if isLoadingPrices {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .padding()
                                Spacer()
                            }
                        } else {
                            ForEach(items) { item in
                                HStack {
                                    Image(
                                        uiImage: IconManager.shared.loadUIImage(
                                            for: item.iconFileName
                                        )
                                    )
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(4)

                                    Text(item.name)
                                        .font(.body)

                                    Spacer()

                                    if let price = marketPrices[item.id] {
                                        Text(FormatUtil.formatISK(price))
                                            .font(.body)
                                            .foregroundColor(getPriceColor(for: item))
                                    } else {
                                        Text("N/A")
                                            .font(.body)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                        }
                    } header: {
                        HStack {
                            Image("isk")
                                .resizable()
                                .frame(width: 24, height: 24)
                                .cornerRadius(6)

                            Text(NSLocalizedString("Main_Market_Price_Jita", comment: "Jita 市场价格"))
                                .font(.headline)
                        }
                    }
                }

                // 计算中指示器
                if isCalculating {
                    CalculatingSection()
                }

                // 对比结果部分 - 显示每个属性的对比
                if let result = compareResult, items.count >= 2 {
                    AttributeCompareResultSections(
                        result: result,
                        items: items,
                        showOnlyDifferences: showOnlyDifferences
                    )
                }
            }
        }
        .navigationTitle(compare.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isShowingItemSelector = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingItemSelector, onDismiss: {
            // 列表编辑结束（点 X 或下拉关闭）：有改动才统一重算，无改动零开销
            if hasListChanges {
                hasListChanges = false
                // 统一提交：保存列表文件 + 重算对比结果
                AttributeCompareManager.shared.saveCompare(compare)
                refreshCompareAfterListChange()
            }
        }) {
            AttributeItemSelectorView(
                databaseManager: databaseManager,
                allowedTopMarketGroupIDs: AttributeCompareMarketPolicy.allowedTopMarketGroupIDs,
                existingItems: Set(compare.items.map { $0.typeID }),
                onItemSelected: { item in
                    if !compare.items.contains(where: { $0.typeID == item.id }) {
                        // 排序后同步 items 与 compare.items
                        let sorted = (items + [item]).sorted(by: { $0.id < $1.id })
                        items = sorted
                        compare.items = sorted.map { item in
                            AttributeCompareItem(typeID: item.id)
                        }
                        // 编辑期间不保存不重算，关闭选择器时统一处理
                        hasListChanges = true
                    }
                },
                onItemDeselected: { item in
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        items.remove(at: index)
                        compare.items.removeAll { $0.typeID == item.id }
                        // 编辑期间不保存不重算，关闭选择器时统一处理
                        hasListChanges = true
                    }
                }
            )
        }
        .onAppear {
            // 视图出现时，如果有至少两个物品，自动计算属性对比
            if items.count >= 2 {
                calculateCompare()
            }
        }
    }

    /// 列表变更后的统一刷新：至少两个物品则重算对比，否则清空对比结果和市场价格
    private func refreshCompareAfterListChange() {
        if items.count >= 2 {
            calculateCompare()
        } else {
            compareResult = nil
            marketPrices = [:]
        }
    }

    /// 获取市场价格颜色
    private func getPriceColor(for item: DatabaseListItem) -> Color {
        guard let currentPrice = marketPrices[item.id] else {
            return .secondary
        }

        let allPrices = marketPrices.values.filter { $0 > 0 }

        if allPrices.count < 2 {
            return .secondary
        }

        let maxPrice = allPrices.max() ?? currentPrice
        let minPrice = allPrices.min() ?? currentPrice

        if maxPrice == minPrice {
            return .secondary
        }

        if currentPrice == maxPrice {
            return .green
        } else if currentPrice == minPrice {
            return .orange
        } else {
            return .secondary
        }
    }

    /// 获取市场价格
    private func loadMarketPrices() {
        if items.count < 2 {
            Logger.info("需要至少两个物品才能获取市场价格")
            return
        }

        let typeIDs = items.map { $0.id }
        isLoadingPrices = true

        Task {
            Logger.info("开始获取市场价格，物品数量: \(typeIDs.count)")
            let prices = await MarketPriceUtil.getJitaOrderPricesFromESI(typeIds: typeIDs)

            await MainActor.run {
                self.marketPrices = prices
                self.isLoadingPrices = false
                Logger.info("市场价格获取完成，获得价格数量: \(prices.count)")
            }
        }
    }

    /// 计算属性对比
    private func calculateCompare() {
        if items.count < 2 {
            Logger.info("需要至少两个物品才能进行对比")
            return
        }

        let typeIDs = items.map { $0.id }

        isCalculating = true

        // 同时获取市场价格
        loadMarketPrices()

        DispatchQueue.global(qos: .userInitiated).async {
            let result = AttributeCompareUtil.compareAttributesWithResult(
                typeIDs: typeIDs, databaseManager: databaseManager
            )

            DispatchQueue.main.async {
                self.compareResult = result
                self.isCalculating = false
            }
        }
    }
}
