import Foundation
import SwiftUI

struct MarketQuickbarDetailView: View {
    let databaseManager: DatabaseManager
    @State var quickbar: MarketQuickbar
    @State private var isShowingItemSelector = false
    @State var items: [DatabaseListItem] = []
    @State private var isEditingQuantity = false
    @State var itemQuantities: [Int: Int64] = [:] // typeID: quantity
    @State private var marketOrders: [Int: [MarketOrder]] = [:] // typeID: orders
    @State private var isLoadingOrders = false
    @State private var orderType: OrderType = .sell // 新增：订单类型选择
    @State private var hasLoadedOrders = false // 标记是否已加载过订单
    @State private var showRegionPicker = false // 新增：控制星域选择器显示
    @State private var selectedLocation: Int = 0 // 选中的市场位置ID（星域/星系/建筑）
    @State private var structureOrdersProgress: StructureOrdersProgress? // 建筑订单加载进度
    @State private var loadedOrdersCount: Int = 0 // 已加载订单的物品数量（用于显示进度）
    @State private var itemVolumes: [Int: Double] = [:] // 存储物品体积信息
    @State private var jitaPrices: [Int: (buy: Double, sell: Double)] = [:] // Jita 市场价格
    @State var isShowingClipboardAlert = false // 新增：控制剪贴板导入提示
    @State var clipboardResult = "" // 新增：存储剪贴板导入结果
    @State var isShowingExportAlert = false // 新增：控制剪贴板导出提示
    @State var exportResult = "" // 新增：存储剪贴板导出结果
    @State var showClipboardImportModeDialog = false
    @State var clipboardContentToImport = "" // 新增：存储待导入的剪贴板内容
    @State private var showQuantityEditAlert = false
    @State var quantityEditTypeID: Int?
    @State var quantityEditText = ""
    @State private var showDistinctTypeLimitAlert = false
    @State private var hasListChanges = false // 编辑会话内列表是否有增/删，关闭选择器时据此统一加载订单

    /// 新增：订单类型枚举
    private enum OrderType: String, CaseIterable {
        case buy = "Main_Market_Order_Buy"
        case sell = "Main_Market_Order_Sell"

        var localizedName: String {
            NSLocalizedString(rawValue, comment: "")
        }
    }

    /// 当前选中的地点类型
    private var locationType: MarketLocationType? {
        MarketLocationType.from(id: selectedLocation)
    }

    /// 选中的地点显示名称
    private var selectedRegionName: String {
        locationType?.displayName ?? ""
    }

    /// 获取当前选择的星域ID（星系返回其所属星域，建筑返回虚拟ID）
    private var currentRegionID: Int {
        locationType?.regionID ?? selectedLocation
    }

    /// 判断选定市场是否就是 Jita（The Forge 星域或 Jita 星系）
    private var isSelectedMarketJita: Bool {
        selectedLocation == 30_000_142 || currentRegionID == MarketManager.theForgeRegionID
    }

    var sortedItems: [DatabaseListItem] {
        items.sorted(by: { $0.id < $1.id })
    }

    var body: some View {
        List {
            if quickbar.items.isEmpty {
                Text(NSLocalizedString("Main_Market_Watch_List_Empty", comment: ""))
                    .foregroundColor(.secondary)
            } else {
                Section {
                    // 星域选择器
                    HStack {
                        Text(NSLocalizedString("Main_Market_Location", comment: ""))
                        Spacer()
                        Button {
                            // 在打开选择器之前，确保 selectedLocation 与当前 quickbar.locationID 一致
                            selectedLocation = quickbar.locationID
                            showRegionPicker = true
                        } label: {
                            HStack {
                                Text(selectedRegionName)
                                    .foregroundColor(.primary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .foregroundColor(.secondary)
                                    .imageScale(.small)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .cornerRadius(8)
                        }
                    }
                    .onChange(of: quickbar.locationID) { _, _ in
                        MarketQuickbarManager.shared.saveQuickbar(quickbar)
                        Task { await loadAllMarketOrders() }
                    }
                    .onChange(of: selectedLocation) { _, newValue in
                        quickbar.locationID = newValue
                    }

                    // 订单类型选择器
                    HStack {
                        Text(NSLocalizedString("Main_Market_Order_Type", comment: ""))
                        Spacer()
                        Picker("", selection: $orderType) {
                            Text(OrderType.sell.localizedName).tag(OrderType.sell)
                            Text(OrderType.buy.localizedName).tag(OrderType.buy)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 140)
                    }

                    // 价格显示行
                    HStack {
                        Text(NSLocalizedString("Main_Market_Price", comment: ""))
                        Spacer()
                        if isLoadingOrders {
                            if StructureMarketManager.isStructureId(currentRegionID),
                               let progress = structureOrdersProgress
                            {
                                switch progress {
                                case let .loading(currentPage, totalPages):
                                    HStack(spacing: 4) {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                        Text("\(currentPage)/\(totalPages)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                case .completed:
                                    ProgressView()
                                        .scaleEffect(0.7)
                                }
                            } else {
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    Text("\(loadedOrdersCount)/\(items.count)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        } else {
                            let priceInfo = calculateTotalPrice()
                            if priceInfo.total > 0 {
                                Text("\(FormatUtil.formatISK(priceInfo.total))")
                                    .foregroundColor(
                                        priceInfo.hasInsufficientStock ? .red : .secondary
                                    )
                            } else {
                                Text(NSLocalizedString("Main_Market_No_Orders", comment: ""))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // 体积显示行
                    HStack {
                        Text(NSLocalizedString("Total_volume", comment: ""))
                        Spacer()
                        let totalVolume = calculateTotalVolume()
                        Text("\(FormatUtil.formatForUI(totalVolume, maxFractionDigits: 2)) m³")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text(NSLocalizedString("Main_Market_QuickBar_info", comment: ""))
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

                Section {
                    ForEach(sortedItems, id: \.id) { item in
                        itemRow(item)
                    }
                    .onDelete { indexSet in
                        let itemsToDelete = indexSet.map { sortedItems[$0].id }
                        quickbar.items.removeAll { itemsToDelete.contains($0.typeID) }
                        items.removeAll { itemsToDelete.contains($0.id) }
                        // 移除对应的体积信息
                        for itemID in itemsToDelete {
                            itemVolumes.removeValue(forKey: itemID)
                        }
                        MarketQuickbarManager.shared.saveQuickbar(quickbar)
                        // 删除物品后自动加载市场订单
                        Task {
                            // 强制刷新市场订单
                            await loadAllMarketOrders()
                        }
                    }
                } header: {
                    HStack {
                        Text(
                            "\(NSLocalizedString("Main_Market_Item_List", comment: ""))(\(sortedItems.count))"
                        )
                        Spacer()
                        Button(
                            isEditingQuantity
                                ? NSLocalizedString("Main_Market_Done_Edit", comment: "")
                                : NSLocalizedString("Main_Market_Edit_Quantity", comment: "")
                        ) {
                            withAnimation {
                                // 如果正在退出编辑模式，保存数据
                                if isEditingQuantity {
                                    Logger.info("编辑完成，进行保存")
                                    // 保存所有更改，包括物品数量和市场位置
                                    MarketQuickbarManager.shared.saveQuickbar(quickbar)
                                }
                                isEditingQuantity.toggle()
                            }
                        }
                        .foregroundColor(.accentColor)
                        .font(.system(size: 14))
                    }
                }
            }
        }
        .refreshable {
            // 强制刷新市场订单
            await loadAllMarketOrders(forceRefresh: true)
        }
        .navigationTitle(quickbar.name)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                // 剪贴板导入按钮
                Button {
                    prepareImportFromClipboard()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }

                // 剪贴板导出按钮
                Button {
                    exportToClipboard()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(quickbar.items.isEmpty)

                Button {
                    isShowingItemSelector = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert(
            NSLocalizedString("Main_Market_Clipboard_Import", comment: ""),
            isPresented: $isShowingClipboardAlert
        ) {
            Button(NSLocalizedString("Misc_Done", comment: "")) {
                clipboardResult = ""
            }
        } message: {
            Text(clipboardResult)
        }
        .alert(
            NSLocalizedString("Main_Market_Clipboard_Export", comment: ""),
            isPresented: $isShowingExportAlert
        ) {
            Button(NSLocalizedString("Misc_Done", comment: "")) {
                exportResult = ""
            }
        } message: {
            Text(exportResult)
        }
        .confirmationDialog(
            NSLocalizedString("Main_Market_Clipboard_Import_Mode_Title", comment: ""),
            isPresented: $showClipboardImportModeDialog,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("Main_Market_Clipboard_Import_Overwrite", comment: "")) {
                importFromClipboard(mode: .replace)
            }
            Button(NSLocalizedString("Main_Market_Clipboard_Import_Append", comment: "")) {
                importFromClipboard(mode: .append)
            }
            Button(NSLocalizedString("Main_EVE_Mail_Cancel", comment: ""), role: .cancel) {
                clipboardContentToImport = ""
            }
        }
        .alert(
            NSLocalizedString("Main_Market_Watch_List_Edit_Item_Quantity", comment: ""),
            isPresented: $showQuantityEditAlert
        ) {
            TextField(
                NSLocalizedString("Main_Market_Watch_List_Quantity_Field_Placeholder", comment: ""),
                text: $quantityEditText
            )
            .keyboardType(.numberPad)
            Button(NSLocalizedString("Misc_Done", comment: "")) {
                applyQuantityEditFromAlert()
            }
            Button(NSLocalizedString("Main_EVE_Mail_Cancel", comment: ""), role: .cancel) {
                quantityEditTypeID = nil
                quantityEditText = ""
            }
        } message: {
            Text(NSLocalizedString("Main_Market_Watch_List_Quantity_Prompt", comment: ""))
        }
        .alert(
            NSLocalizedString("Main_Market_Watch_List_Type_Limit_Title", comment: ""),
            isPresented: $showDistinctTypeLimitAlert
        ) {
            Button(NSLocalizedString("Misc_Done", comment: "")) {}
        } message: {
            Text(
                String(
                    format: NSLocalizedString(
                        "Main_Market_Watch_List_Type_Limit_Message",
                        comment: ""
                    ),
                    MarketQuickbarDestinationPicker.maxDistinctTypeCount
                )
            )
        }
        .sheet(isPresented: $isShowingItemSelector, onDismiss: {
            // 列表编辑结束（点 X 或下拉关闭）：有改动才统一提交，无改动零开销
            if hasListChanges {
                hasListChanges = false
                // 统一提交：保存列表文件 + 重载市场订单
                MarketQuickbarManager.shared.saveQuickbar(quickbar)
                Task {
                    await loadAllMarketOrders()
                }
            }
        }) {
            MarketItemSelectorView(
                databaseManager: databaseManager,
                existingItems: Set(quickbar.items.map { $0.typeID }),
                onItemSelected: { applyNewWatchlistItems([$0]) },
                onBatchItemsSelected: { applyNewWatchlistItems($0) },
                onItemDeselected: { item in
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        items.remove(at: index)
                        quickbar.items.removeAll { $0.typeID == item.id }
                        // 移除对应的体积信息
                        itemVolumes.removeValue(forKey: item.id)
                        // 编辑期间不保存不重载订单，关闭选择器时统一处理
                        hasListChanges = true
                    }
                },
                showSelected: true,
                allowTypeIDs: nil // 不限制物品ID
            )
        }
        .sheet(isPresented: $showRegionPicker) {
            MarketRegionPickerView(
                selectedLocation: $selectedLocation,
                saveSelection: .constant(false), // 通过市场关注列表查看和设置订单信息，不保存默认市场位置
                databaseManager: databaseManager
            )
        }
        .task {
            loadItems()

            selectedLocation = quickbar.locationID

            // 只在第一次加载时获取市场订单（函数内部 defer 会置位 hasLoadedOrders）
            if !hasLoadedOrders {
                await loadAllMarketOrders()
            }
        }
    }

    /// 加载所有物品的市场订单（使用通用工具类，支持渐进式显示）
    /// 强制刷新由 API 层统一限流（ForceRefreshThrottle），过于频繁的请求会自动降级为缓存
    func loadAllMarketOrders(forceRefresh: Bool = false) async {
        guard !items.isEmpty else { return }

        isLoadingOrders = true
        loadedOrdersCount = 0
        defer {
            isLoadingOrders = false
            hasLoadedOrders = true
        }

        // 清除旧数据
        marketOrders.removeAll()

        let typeIds = items.map { $0.id }
        // 选定市场就是 Jita 时无需加载 Jita 对比价格
        let needsJitaComparison = !isSelectedMarketJita

        // 并行加载选定市场订单和 Jita 价格（Jita 价格与选定市场无关，仅随物品列表变化）
        let jitaPriceTask = Task { () -> [Int: (buy: Double, sell: Double)] in
            guard needsJitaComparison else { return [:] }
            return (try? await GitHubMarketPriceAPI.shared.fetchMarketPrices(
                typeIds: typeIds,
                forceRefresh: forceRefresh
            )) ?? [:]
        }

        // 使用通用工具类加载订单（自动判断建筑/星域）
        // 选中星系时仅保留该星系的订单
        let systemID = locationType?.systemID
        let orders = await MarketOrdersUtil.loadOrders(
            typeIds: typeIds,
            regionID: currentRegionID,
            forceRefresh: forceRefresh,
            progressCallback: { progress in
                Task { @MainActor in
                    structureOrdersProgress = progress
                }
            },
            itemCallback: { typeId, orders in
                // 每完成一个物品的订单加载，立即更新UI显示该物品的价格
                Task { @MainActor in
                    marketOrders[typeId] = systemID.map { sid in
                        orders.filter { $0.systemId == sid }
                    } ?? orders
                    loadedOrdersCount += 1
                }
            }
        )

        // 最后确保所有数据都已更新（防止回调遗漏）
        if let sid = systemID {
            marketOrders = orders.mapValues { $0.filter { $0.systemId == sid } }
        } else {
            marketOrders = orders
        }

        // 更新 Jita 价格（失败或无需加载时为空）
        jitaPrices = await jitaPriceTask.value
    }

    /// 获取列表的总价和库存状态
    private func getListPrice(for item: DatabaseListItem) -> (
        price: Double?, insufficientStock: Bool
    ) {
        guard let orders = marketOrders[item.id] else { return (nil, true) }
        let quantity = quickbar.items.first(where: { $0.typeID == item.id })?.quantity ?? 1

        // 根据订单类型过滤订单
        var filteredOrders = orders.filter { $0.isBuyOrder == (orderType == .buy) }

        // 根据订单类型排序（买单从高到低，卖单从低到高）
        filteredOrders.sort { orderType == .buy ? $0.price > $1.price : $0.price < $1.price }

        var remainingQuantity = quantity
        var totalPrice: Double = 0
        var availableQuantity: Int64 = 0

        // 从最优价格开始累加，直到满足需求数量
        for order in filteredOrders {
            if remainingQuantity <= 0 {
                break
            }

            let orderQuantity = min(remainingQuantity, Int64(order.volumeRemain))
            totalPrice += Double(orderQuantity) * order.price
            remainingQuantity -= orderQuantity
            availableQuantity += orderQuantity
        }

        // 如果没有足够的订单满足数量需求，但有部分订单
        if remainingQuantity > 0, availableQuantity > 0 {
            return (totalPrice / Double(availableQuantity), true)
        } else if remainingQuantity > 0 {
            return (nil, true)
        }

        // 返回平均单价和库存充足状态
        return (totalPrice / Double(quantity), false)
    }

    /// 获取指定物品在 Jita 市场的价格（与当前订单类型一致）
    /// - Returns: 卖单返回最低卖价，买单返回最高买价；无数据返回 nil
    private func jitaPrice(for typeId: Int) -> Double? {
        guard let prices = jitaPrices[typeId] else { return nil }
        if orderType == .buy {
            return prices.buy > 0 ? prices.buy : nil
        } else {
            return prices.sell > 0 ? prices.sell : nil
        }
    }

    /// 计算选定市场相对于 Jita 的价格差异百分比
    /// - Returns: 正数表示选定市场更贵，负数表示更便宜；任一价格缺失返回 nil
    private func priceDiffPercentage(selectedPrice: Double, jitaPrice: Double) -> Double? {
        guard jitaPrice > 0 else { return nil }
        return (selectedPrice / jitaPrice - 1.0) * 100
    }

    /// Jita 价格对比行：展示 Jita 价格和差异百分比（正数红色=选定市场更贵，负数绿色=更便宜）
    @ViewBuilder
    private func jitaComparisonLine(for item: DatabaseListItem, selectedPrice: Double) -> some View {
        if !isSelectedMarketJita,
           let jitaPrice = jitaPrice(for: item.id),
           let diff = priceDiffPercentage(selectedPrice: selectedPrice, jitaPrice: jitaPrice)
        {
            HStack(spacing: 4) {
                Text(
                    NSLocalizedString("Main_Market_Jita_Price_Label", comment: "")
                        + FormatUtil.format(jitaPrice) + " ISK"
                )
                .font(.caption)
                .foregroundColor(.secondary)
                Text(String(format: "%+.1f%%", diff))
                    .font(.caption)
                    .foregroundColor(diff > 0 ? .red : .green)
            }
        }
    }

    @ViewBuilder
    private func itemRow(_ item: DatabaseListItem) -> some View {
        if isEditingQuantity {
            HStack(spacing: 12) {
                Image(uiImage: IconManager.shared.loadUIImage(for: item.iconFileName))
                    .resizable()
                    .frame(width: 40, height: 40)
                    .cornerRadius(6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .lineLimit(1)

                    // 细粒度加载状态：已加载的显示价格，未加载的显示加载指示器
                    if isLoadingOrders && marketOrders[item.id] == nil {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text(NSLocalizedString("Main_Database_Loading", comment: ""))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        let priceInfo = getListPrice(for: item)
                        if let price = priceInfo.price {
                            Text(
                                NSLocalizedString("Main_Market_Avg_Price", comment: "")
                                    + FormatUtil.format(price)
                                    + " ISK"
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                            HStack(spacing: 4) {
                                Text(
                                    NSLocalizedString("Main_Market_Total_Price", comment: "")
                                        + FormatUtil.format(
                                            price * Double(itemQuantities[item.id] ?? 1)
                                        )
                                        + " ISK"
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                                if priceInfo.insufficientStock {
                                    Text(
                                        NSLocalizedString("Main_Market_Insufficient_Stock", comment: "")
                                    )
                                    .font(.caption)
                                    .foregroundColor(.red)
                                }
                            }
                            jitaComparisonLine(for: item, selectedPrice: price)
                        } else {
                            Text(NSLocalizedString("Main_Market_No_Orders", comment: ""))
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }

                Spacer()

                TextField(
                    "",
                    text: Binding(
                        get: { String(itemQuantities[item.id] ?? 1) },
                        set: { newValue in
                            if let quantity = Int64(newValue) {
                                let validValue = max(1, min(999_999_999, quantity))
                                itemQuantities[item.id] = validValue
                                if let index = quickbar.items.firstIndex(where: {
                                    $0.typeID == item.id
                                }) {
                                    quickbar.items[index].quantity = validValue
                                }
                            } else {
                                itemQuantities[item.id] = 1
                                if let index = quickbar.items.firstIndex(where: {
                                    $0.typeID == item.id
                                }) {
                                    quickbar.items[index].quantity = 1
                                }
                            }
                        }
                    )
                )
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .keyboardType(.numberPad)
                .multilineTextAlignment(.leading)
                .frame(width: 80)
            }
        } else {
            NavigationLink {
                MarketItemDetailView(
                    databaseManager: databaseManager,
                    itemID: item.id,
                    selectedLocation: selectedLocation // 传递当前选中的市场位置ID
                )
            } label: {
                HStack(spacing: 12) {
                    Image(uiImage: IconManager.shared.loadUIImage(for: item.iconFileName))
                        .resizable()
                        .frame(width: 40, height: 40)
                        .cornerRadius(6)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .lineLimit(1)

                        // 细粒度加载状态：已加载的显示价格，未加载的显示加载指示器
                        if isLoadingOrders && marketOrders[item.id] == nil {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                Text(NSLocalizedString("Main_Database_Loading", comment: ""))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            let priceInfo = getListPrice(for: item)
                            if let price = priceInfo.price {
                                Text(
                                    NSLocalizedString("Main_Market_Avg_Price", comment: "")
                                        + FormatUtil.format(price)
                                        + " ISK"
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                                Text(
                                    NSLocalizedString("Main_Market_Total_Price", comment: "")
                                        + FormatUtil.format(
                                            price
                                                * Double(
                                                    quickbar.items.first(where: { $0.typeID == item.id })?.quantity ?? 1
                                                )
                                        )
                                        + " ISK"
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                                if priceInfo.insufficientStock {
                                    Text(
                                        NSLocalizedString("Main_Market_Insufficient_Stock", comment: "")
                                    )
                                    .font(.caption)
                                    .foregroundColor(.red)
                                }
                                jitaComparisonLine(for: item, selectedPrice: price)
                            } else {
                                Text(NSLocalizedString("Main_Market_No_Orders", comment: ""))
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }

                    Spacer()

                    Text(getItemQuantity(for: item))
                        .foregroundColor(.secondary)
                }
            }
            .contextMenu {
                Button {
                    quantityEditTypeID = item.id
                    quantityEditText = String(
                        quickbar.items.first(where: { $0.typeID == item.id })?.quantity ?? 1
                    )
                    showQuantityEditAlert = true
                } label: {
                    Label(
                        NSLocalizedString("Main_Market_Watch_List_Edit_Item_Quantity", comment: ""),
                        systemImage: "number"
                    )
                }
            }
        }
    }

    private func getItemQuantity(for item: DatabaseListItem) -> String {
        let quantity = quickbar.items.first(where: { $0.typeID == item.id })?.quantity ?? 1
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: quantity)) ?? "1"
    }

    func loadItems() {
        if !quickbar.items.isEmpty {
            if MarketQuickbarDestinationPicker.trimToMaxDistinctTypesRemovingFromEnd(&quickbar.items) {
                MarketQuickbarManager.shared.saveQuickbar(quickbar)
            }
            // 内存索引批量构建（已按 id 升序）
            items = DatabaseListItem.listItems(
                for: quickbar.items.map(\.typeID),
                databaseManager: databaseManager
            )
            // 更新 itemQuantities
            itemQuantities = Dictionary(
                uniqueKeysWithValues: quickbar.items.map { ($0.typeID, $0.quantity) }
            )
            // 确保 quickbar.items 的顺序与加载的物品顺序一致
            quickbar.items = items.map { item in
                QuickbarItem(
                    typeID: item.id,
                    quantity: quickbar.items.first(where: { $0.typeID == item.id })?.quantity ?? 1
                )
            }
            // 加载物品体积信息
            loadItemVolumes()
        }
    }

    /// 计算所有物品的总价格和库存状态
    private func calculateTotalPrice() -> (total: Double, hasInsufficientStock: Bool) {
        var total: Double = 0
        var hasInsufficientStock = false

        for item in items {
            let priceInfo = getListPrice(for: item)
            if let price = priceInfo.price {
                let quantity = quickbar.items.first(where: { $0.typeID == item.id })?.quantity ?? 1
                total += price * Double(quantity)
            }
            if priceInfo.insufficientStock {
                hasInsufficientStock = true
            }
        }
        return (total, hasInsufficientStock)
    }

    /// 计算所有物品的总体积
    private func calculateTotalVolume() -> Double {
        var totalVolume: Double = 0

        for item in items {
            if let volume = itemVolumes[item.id] {
                let quantity = quickbar.items.first(where: { $0.typeID == item.id })?.quantity ?? 1
                totalVolume += volume * Double(quantity)
            }
        }

        return totalVolume
    }

    /// 加载物品体积信息
    func loadItemVolumes() {
        guard !items.isEmpty else { return }

        for item in items {
            if let volume = ItemInfoMap.typeInfo(for: item.id)?.volume {
                itemVolumes[item.id] = volume
            }
        }
    }
}

// MARK: - MarketQuickbarDetailView扩展

extension MarketQuickbarDetailView {
    /// 从选择器合并新增物品：编辑期间只更新内存状态与体积查询，保存与订单加载延后到关闭选择器时统一处理
    private func applyNewWatchlistItems(_ newItems: [DatabaseListItem]) {
        let existingTypeIDs = Set(quickbar.items.map(\.typeID))
        let toAdd = newItems.filter { !existingTypeIDs.contains($0.id) }
        guard !toAdd.isEmpty else { return }
        for item in toAdd {
            items.append(item)
            quickbar.items.append(QuickbarItem(typeID: item.id))
        }
        items.sort(by: { $0.id < $1.id })
        quickbar.items = items.map { item in
            QuickbarItem(
                typeID: item.id,
                quantity: quickbar.items.first(where: { $0.typeID == item.id })?.quantity ?? 1
            )
        }
        if MarketQuickbarDestinationPicker.trimToMaxDistinctTypesRemovingFromEnd(&quickbar.items) {
            showDistinctTypeLimitAlert = true
            loadItems()
        }
        loadItemVolumes()
        // 编辑期间不保存不重载订单，关闭选择器时统一处理
        hasListChanges = true
    }
}
