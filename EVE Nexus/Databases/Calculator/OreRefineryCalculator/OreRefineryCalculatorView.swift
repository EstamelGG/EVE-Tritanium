import SwiftUI

struct OreRefineryCalculatorView: View {
    @ObservedObject var databaseManager: DatabaseManager

    // 精炼设置相关状态
    @State var selectedLocation: Int = MarketManager.theForgeRegionID // 默认The Forge
    @State var orderType: OrderType = .sell
    @State var showRegionPicker = false
    @State var showRefinerySettings = false
    @State var isShowingItemSelector = false

    /// 当前选中地点的类型信息（星域/星系/建筑）
    var locationType: MarketLocationType? {
        MarketLocationType.from(id: selectedLocation)
    }

    /// 选中地点的显示名称
    var selectedRegionName: String {
        locationType?.displayName ?? ""
    }

    /// ESI 查询用的星域 ID（对星系返回其所属星域 ID，对建筑返回虚拟 ID）
    var selectedRegionID: Int {
        locationType?.regionID ?? selectedLocation
    }

    // 精炼设置参数
    @State var systemSecurity: SystemSecurity = .nullSec
    @State var structure: Structure = .structure2
    @State var structureRigs: StructureRigs = .t2
    @State var implant: Implant = .implant3
    @State var taxRate: Double = UserDefaultsManager.shared.refineryTaxRate

    // 记录选择的typeID
    @State var selectedStructureTypeID: Int = 35836 // 默认精炼建筑
    @State var selectedImplantTypeID: Int = 27174 // 默认精炼植入体

    // 技能相关状态
    @State var selectedCharacterSkills: [Int: Int] = [:]
    @State var selectedCharacterName: String = ""
    @State var selectedCharacterId: Int = 0

    // 计算相关状态
    @State var isLoadingOrders = false
    @State var marketOrders: [Int: [MarketOrder]] = [:]
    @State var structureOrdersProgress: StructureOrdersProgress? = nil
    @State var isEditingQuantity = false
    @State var considerOrderQuantity = true // 是否考虑订单数量，默认选中

    // 导入导出相关状态
    @State var isShowingClipboardAlert = false
    @State var clipboardResult = ""
    @State var isShowingExportAlert = false
    @State var exportResult = ""
    @State var isShowingImportConfirmation = false
    @State var clipboardContentToImport = ""

    // 矿石列表和相关数据
    @State var oreItems: [QuickbarItem] = []
    @State var items: [DatabaseListItem] = []
    @State var itemQuantities: [Int: Int64] = [:]
    @State var itemVolumes: [Int: Double] = [:]

    // 精炼比例状态
    @State var itemRefineryRatios: [Int: Double] = [:] // 物品ID -> 精炼比例
    @State var itemRefineryStatus: [Int: RefineryStatus] = [:] // 物品ID -> 精炼状态

    /// 精炼结果状态
    @State var refineryResultData: RefineryResultData? = nil

    var body: some View {
        VStack {
            List {
                Section {
                    // 市场地点选择器
                    HStack {
                        Text(NSLocalizedString("Main_Market_Location", comment: ""))
                        Spacer()
                        Button {
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

                    // 精炼设置按钮
                    Button {
                        showRefinerySettings = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(NSLocalizedString("Ore_Refinery_Settings", comment: ""))

                                // 显示当前选择的建筑和植入体
                                HStack {
                                    Text(
                                        "\(NSLocalizedString("Ore_Refinery_Structure_Label", comment: "")): \(structure.displayName)"
                                    )
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    Spacer()
                                }

                                HStack {
                                    Text(
                                        "\(NSLocalizedString("Ore_Refinery_Implant_Label", comment: "")): \(implant.displayName)"
                                    )
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    Spacer()
                                }

                                // 显示当前选择的技能
                                HStack {
                                    let skillText =
                                        selectedCharacterName.isEmpty
                                            ? NSLocalizedString(
                                                "Ore_Refinery_All_Skills_Level", comment: ""
                                            )
                                            : selectedCharacterName
                                    Text(
                                        "\(NSLocalizedString("Ore_Refinery_Skills_Label", comment: "")): \(skillText)"
                                    )
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    Spacer()
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .imageScale(.small)
                        }
                    }
                    .foregroundColor(.primary)

                    // 市场价格显示
                    HStack {
                        Text(NSLocalizedString("Main_Market_Price", comment: ""))
                        Spacer()
                        if isLoadingOrders {
                            // 显示详细的页数进度（只在这里显示）
                            if StructureMarketManager.isStructureId(selectedRegionID),
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
                                ProgressView()
                                    .scaleEffect(0.7)
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

                    // 总体积显示
                    HStack {
                        Text(NSLocalizedString("Total_volume", comment: ""))
                        Spacer()
                        let totalVolume = calculateTotalVolume()
                        Text("\(FormatUtil.formatForUI(totalVolume, maxFractionDigits: 2)) m³")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text(NSLocalizedString("Ore_Refinery_Basic_Settings", comment: ""))
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

                // 矿石列表部分 - 如果为空则显示空状态
                if oreItems.isEmpty {
                    Section {
                        VStack(spacing: 16) {
                            Image(systemName: "cube.box")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)

                            Text(NSLocalizedString("Ore_Refinery_No_Items", comment: ""))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } header: {
                        Text(NSLocalizedString("Main_Market_Item_List", comment: ""))
                    }
                } else {
                    Section {
                        ForEach(items, id: \.id) { item in
                            oreItemRow(item)
                        }
                        .onDelete { indexSet in
                            let itemsToDelete = indexSet.map { items[$0].id }
                            oreItems.removeAll { itemsToDelete.contains($0.typeID) }
                            items.removeAll { itemsToDelete.contains($0.id) }
                            for itemID in itemsToDelete {
                                itemVolumes.removeValue(forKey: itemID)
                                itemQuantities.removeValue(forKey: itemID)
                            }
                            // 删除后重新加载市场订单
                            Task {
                                await loadAllMarketOrders()
                            }
                        }
                    } header: {
                        HStack {
                            Text(NSLocalizedString("Main_Market_Item_List", comment: ""))

                            Spacer()

                            Button {
                                considerOrderQuantity.toggle()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(
                                        systemName: considerOrderQuantity
                                            ? "checkmark.circle.fill" : "circle"
                                    )
                                    .foregroundColor(considerOrderQuantity ? .blue : .secondary)
                                    Text(
                                        NSLocalizedString(
                                            "Blueprint_Calculator_Consider_Quantity",
                                            comment: "考虑订单数量"
                                        )
                                    )
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())

                            Button(
                                isEditingQuantity
                                    ? NSLocalizedString("Main_Market_Done_Edit", comment: "")
                                    : NSLocalizedString("Main_Market_Edit_Quantity", comment: "")
                            ) {
                                withAnimation {
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

            // 底部计算按钮
            Button(action: {
                // 执行精炼计算
                performRefineryCalculation()
            }) {
                Text(NSLocalizedString("Ore_Refinery_Calculate", comment: ""))
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(oreItems.isEmpty ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .disabled(oreItems.isEmpty)
            .padding()
        }
        .navigationTitle(NSLocalizedString("Ore_Refinery_Calculator", comment: ""))
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                // 导入按钮
                Button {
                    prepareImportFromClipboard()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }

                // 导出按钮
                Button {
                    exportToClipboard()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(oreItems.isEmpty)

                // 添加物品按钮
                Button {
                    isShowingItemSelector = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showRegionPicker) {
            MarketRegionPickerView(
                selectedLocation: $selectedLocation,
                saveSelection: .constant(false),
                databaseManager: databaseManager
            )
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showRefinerySettings) {
            RefinerySettingsView(
                systemSecurity: $systemSecurity,
                structure: $structure,
                structureRigs: $structureRigs,
                implant: $implant,
                taxRate: $taxRate,
                selectedCharacterSkills: $selectedCharacterSkills,
                selectedCharacterName: $selectedCharacterName,
                selectedCharacterId: $selectedCharacterId
            )
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $refineryResultData) { data in
            NavigationView {
                RefineryResultView(
                    databaseManager: databaseManager,
                    taxRate: taxRate,
                    refineryOutputs: data.outputs,
                    materialNameMap: data.materialNames,
                    remainingItems: data.remaining
                )
            }
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingItemSelector) {
            // TODO: 实现矿石选择器 - 可以复用MarketItemSelectorView但需要限制只显示矿石
            MarketItemSelectorView(
                databaseManager: databaseManager,
                existingItems: Set(oreItems.map { $0.typeID }),
                onItemSelected: { applyOreSelectorItems([$0]) },
                onBatchItemsSelected: { applyOreSelectorItems($0) },
                onItemDeselected: { item in
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        items.remove(at: index)
                        oreItems.removeAll { $0.typeID == item.id }
                        itemVolumes.removeValue(forKey: item.id)
                        // 移除物品后更新精炼比例
                        itemRefineryStatus.removeValue(forKey: item.id)
                        itemRefineryRatios.removeValue(forKey: item.id)
                    }
                },
                showSelected: true,
                allowTypeIDs: nil // TODO: 这里应该限制只显示矿石类物品
            )
            .presentationDragIndicator(.visible)
        }
        .onChange(of: selectedLocation) { oldValue, newValue in
            if oldValue != newValue {
                // 地区变化时重新加载市场订单
                Task {
                    await loadAllMarketOrders()
                }
            }
        }
        .onChange(of: structure) { _, newStructure in
            selectedStructureTypeID = newStructure.typeID
            // 建筑变化时重新计算精炼比例
            calculateBatchRefineryRatios()
        }
        .onChange(of: implant) { _, newImplant in
            selectedImplantTypeID = newImplant.typeID
            // 植入体变化时重新计算精炼比例
            calculateBatchRefineryRatios()
        }
        .onChange(of: structureRigs) { _, _ in
            // 建筑插件变化时重新计算精炼比例
            calculateBatchRefineryRatios()
        }
        .onChange(of: systemSecurity) { _, _ in
            // 安全等级变化时重新计算精炼比例
            calculateBatchRefineryRatios()
        }
        .onChange(of: selectedCharacterSkills) { _, _ in
            // 技能变化时重新计算精炼比例
            calculateBatchRefineryRatios()
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
        .alert(
            NSLocalizedString("Main_Market_Clipboard_Import_Confirm", comment: ""),
            isPresented: $isShowingImportConfirmation
        ) {
            Button(NSLocalizedString("Main_EVE_Mail_Cancel", comment: ""), role: .cancel) {
                clipboardContentToImport = ""
            }
            Button(
                NSLocalizedString("Main_Market_Clipboard_Import_Confirm_Yes", comment: ""),
                role: .destructive
            ) {
                importFromClipboard()
            }
        } message: {
            Text(
                String(
                    format: NSLocalizedString(
                        "Main_Market_Clipboard_Import_Confirm_Message", comment: ""
                    ), oreItems.count
                )
            )
        }
        .onAppear {
            loadItems()

            // 确保税率从UserDefaults正确加载
            taxRate = UserDefaultsManager.shared.refineryTaxRate
            Logger.info("主视图 onAppear - 加载保存的税率: \(taxRate)%")

            // 初始化技能为all5
            if selectedCharacterSkills.isEmpty {
                selectedCharacterSkills = CharacterSkillsUtils.getCharacterSkills(type: .all5)
                selectedCharacterName = String(
                    format: NSLocalizedString("Fitting_All_Skills", comment: "全n级"), 5
                )
                selectedCharacterId = 0
            }

            // 初始化时计算精炼比例
            calculateBatchRefineryRatios()
        }
    }

    /// 选择器批量添加矿石：一次体积与精炼比例更新、一次订单任务
    private func applyOreSelectorItems(_ newItems: [DatabaseListItem]) {
        let existingTypeIDs = Set(oreItems.map(\.typeID))
        let toAdd = newItems.filter { !existingTypeIDs.contains($0.id) }
        guard !toAdd.isEmpty else { return }
        for item in toAdd {
            items.append(item)
            oreItems.append(QuickbarItem(typeID: item.id))
        }
        let sorted = items.sorted(by: { $0.id < $1.id })
        items = sorted
        oreItems = sorted.map { item in
            QuickbarItem(
                typeID: item.id,
                quantity: oreItems.first(where: { $0.typeID == item.id })?.quantity ?? 1
            )
        }
        itemQuantities = Dictionary(uniqueKeysWithValues: oreItems.map { ($0.typeID, $0.quantity) })
        loadItemVolumes()
        calculateBatchRefineryRatios()
        Task {
            await loadAllMarketOrders()
        }
    }

    /// 矿石项目行视图
    @ViewBuilder
    private func oreItemRow(_ item: DatabaseListItem) -> some View {
        if isEditingQuantity {
            HStack(spacing: 12) {
                Image(uiImage: IconManager.shared.loadUIImage(for: item.iconFileName))
                    .resizable()
                    .frame(width: 40, height: 40)
                    .cornerRadius(6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .lineLimit(1)

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
                    } else {
                        Text(NSLocalizedString("Main_Market_No_Orders", comment: ""))
                            .font(.caption)
                            .foregroundColor(.red)
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
                                if let index = oreItems.firstIndex(where: {
                                    $0.typeID == item.id
                                }) {
                                    oreItems[index].quantity = validValue
                                }
                            } else {
                                itemQuantities[item.id] = 1
                                if let index = oreItems.firstIndex(where: {
                                    $0.typeID == item.id
                                }) {
                                    oreItems[index].quantity = 1
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
                    selectedLocation: selectedLocation // 传递当前选中的地点ID
                )
            } label: {
                HStack(spacing: 12) {
                    Image(uiImage: IconManager.shared.loadUIImage(for: item.iconFileName))
                        .resizable()
                        .frame(width: 32, height: 32)
                        .cornerRadius(6)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .lineLimit(1)

                        if isLoadingOrders {
                            // 显示简单的加载指示器
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                Text(NSLocalizedString("Main_Database_Loading", comment: "加载中..."))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            // 显示价格信息
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
                                                    oreItems.first(where: { $0.typeID == item.id })?.quantity ?? 1
                                                )
                                        )
                                        + " ISK"
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                                if priceInfo.insufficientStock {
                                    Text(
                                        NSLocalizedString(
                                            "Main_Market_Insufficient_Stock", comment: ""
                                        )
                                    )
                                    .font(.caption)
                                    .foregroundColor(.red)
                                }
                            } else {
                                Text(NSLocalizedString("Main_Market_No_Orders", comment: ""))
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }

                        // 精炼比例显示（在价格下方）
                        let refineryStatus = itemRefineryStatus[item.id] ?? .unknown
                        HStack(spacing: 4) {
                            Text(NSLocalizedString("Ore_Refinery_Ratio_Label", comment: ""))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(refineryStatus.displayText)
                                .font(.caption)
                                .fontDesign(.monospaced)
                                .fontWeight(.medium)
                                .foregroundColor(refineryStatus.isRefinable ? .green : .red)
                        }
                    }

                    Spacer()

                    Text(getItemQuantity(for: item))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    /// 计算总价格
    private func calculateTotalPrice() -> (total: Double, hasInsufficientStock: Bool) {
        var total: Double = 0
        var hasInsufficientStock = false

        for item in items {
            let priceInfo = getListPrice(for: item)
            if let price = priceInfo.price {
                let quantity = oreItems.first(where: { $0.typeID == item.id })?.quantity ?? 1
                total += price * Double(quantity)
            }
            if priceInfo.insufficientStock {
                hasInsufficientStock = true
            }
        }
        return (total, hasInsufficientStock)
    }

    /// 计算总体积
    private func calculateTotalVolume() -> Double {
        var totalVolume: Double = 0

        for item in items {
            if let volume = itemVolumes[item.id] {
                let quantity = oreItems.first(where: { $0.typeID == item.id })?.quantity ?? 1
                totalVolume += volume * Double(quantity)
            }
        }

        return totalVolume
    }

    /// 获取物品价格信息
    private func getListPrice(for item: DatabaseListItem) -> (
        price: Double?, insufficientStock: Bool
    ) {
        guard let orders = marketOrders[item.id] else { return (nil, true) }
        let quantity = oreItems.first(where: { $0.typeID == item.id })?.quantity ?? 1

        var filteredOrders = orders.filter { $0.isBuyOrder == (orderType == .buy) }
        filteredOrders.sort { orderType == .buy ? $0.price > $1.price : $0.price < $1.price }

        if filteredOrders.isEmpty {
            return (nil, true)
        }

        // 如果不考虑订单数量，直接使用最优价格
        if !considerOrderQuantity {
            let bestPrice = filteredOrders.first?.price ?? 0
            return (bestPrice, false)
        }

        // 考虑订单数量的原有逻辑
        var remainingQuantity = quantity
        var totalPrice: Double = 0
        var availableQuantity: Int64 = 0

        for order in filteredOrders {
            if remainingQuantity <= 0 { break }

            let orderQuantity = min(remainingQuantity, Int64(order.volumeRemain))
            totalPrice += Double(orderQuantity) * order.price
            remainingQuantity -= orderQuantity
            availableQuantity += orderQuantity
        }

        if remainingQuantity > 0, availableQuantity > 0 {
            return (totalPrice / Double(availableQuantity), true)
        } else if remainingQuantity > 0 {
            return (nil, true)
        }

        return (totalPrice / Double(quantity), false)
    }

    /// 获取物品数量显示文本
    private func getItemQuantity(for item: DatabaseListItem) -> String {
        let quantity = oreItems.first(where: { $0.typeID == item.id })?.quantity ?? 1
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: quantity)) ?? "1"
    }

    private func performRefineryCalculation() {
        Logger.info("=== 开始精炼计算 ===")

        // 1. 检查是否有待精炼物品
        guard !oreItems.isEmpty else {
            Logger.warning("没有待精炼物品")
            return
        }

        // 2. 获取所选人物的技能数据
        Logger.info("角色技能信息:")
        Logger.info("- 角色名称: \(selectedCharacterName)")
        Logger.info("- 角色ID: \(selectedCharacterId)")
        Logger.info("- 技能数量: \(selectedCharacterSkills.count)")

        // 显示前10个技能作为示例
        let skillExamples = Array(selectedCharacterSkills.prefix(10))
        for (skillId, level) in skillExamples {
            Logger.info("  - 技能ID \(skillId): 等级 \(level)")
        }
        if selectedCharacterSkills.count > 10 {
            Logger.info("  ... 还有 \(selectedCharacterSkills.count - 10) 个技能")
        }

        // 3. 获取精炼设置
        Logger.info("精炼设置:")
        Logger.info("- 星系安等: \(systemSecurity.localizedName)")
        Logger.info("- 建筑: \(structure.displayName) (TypeID: \(structure.typeID))")
        Logger.info("- 建筑插件: \(structureRigs.localizedName)")
        Logger.info("- 植入体: \(implant.displayName) (TypeID: \(implant.typeID))")
        Logger.info("- 建筑税率: \(taxRate)%")

        // 4. 获取当前页面已添加的待精炼物品
        Logger.info("待精炼物品列表:")
        for (index, oreItem) in oreItems.enumerated() {
            if let item = items.first(where: { $0.id == oreItem.typeID }) {
                let quantity = itemQuantities[item.id] ?? 1
                let volume = itemVolumes[item.id] ?? 0.0
                let totalVolume = volume * Double(quantity)

                Logger.info("  \(index + 1). \(item.name)")
                Logger.info("     - 物品ID: \(item.id)")
                Logger.info("     - 数量: \(quantity)")
                Logger.info(
                    "     - 单个体积: \(FormatUtil.formatForUI(volume, maxFractionDigits: 2)) m³"
                )
                Logger.info(
                    "     - 总体积: \(FormatUtil.formatForUI(totalVolume, maxFractionDigits: 2)) m³"
                )
            }
        }

        // 5. 计算总体积和总价值
        let totalVolume = calculateTotalVolume()
        let totalPrice = calculateTotalPrice()

        Logger.info("总计:")
        Logger.info("- 物品种类: \(oreItems.count)")
        Logger.info("- 总体积: \(FormatUtil.formatForUI(totalVolume, maxFractionDigits: 2)) m³")
        Logger.info("- 总价值: \(FormatUtil.formatISK(totalPrice.total)) ISK")
        if totalPrice.hasInsufficientStock {
            Logger.warning("- 部分物品库存不足")
        }

        // 6. 获取精炼输出信息
        Logger.info("=== 精炼输出信息 ===")
        var totalRefineryOutputs: [Int: Int] = [:] // 输出材料ID -> 总数量
        var materialNameMap: [Int: String] = [:] // 材料ID -> 材料名称

        // 批量获取所有物品的精炼信息和分类信息
        let allTypeIDs = items.map { $0.id }
        let allTypeMaterials = getBatchTypeMaterials(for: allTypeIDs)
        var itemCategories = getBatchItemCategories(for: allTypeIDs)

        // 更新物品分类：将没有精炼产出的物品标记为noOutput
        for typeID in allTypeIDs {
            if itemCategories[typeID] != nil, allTypeMaterials[typeID] == nil {
                // 有分类信息但没有精炼产出，标记为noOutput
                if let existingInfo = itemCategories[typeID] {
                    itemCategories[typeID] = ItemCategoryInfo(
                        typeID: existingInfo.typeID,
                        categoryID: existingInfo.categoryID,
                        groupID: existingInfo.groupID,
                        itemType: .noOutput,
                        reprocessingSkillType: existingInfo.reprocessingSkillType
                    )
                }
            }
        }

        for (index, oreItem) in oreItems.enumerated() {
            if let item = items.first(where: { $0.id == oreItem.typeID }) {
                let inputQuantity = itemQuantities[item.id] ?? 1
                let categoryInfo = itemCategories[item.id]

                Logger.info("  \(index + 1). \(item.name) (TypeID: \(item.id))")
                Logger.info("     - 输入数量: \(inputQuantity)")
                Logger.info("     - 物品类型: \(categoryInfo?.itemType.description ?? "未知")")

                // 从批量查询结果中获取该物品的精炼输出信息
                if let typeMaterials = allTypeMaterials[item.id] {
                    Logger.info("     - 精炼批次大小: \(typeMaterials.first?.process_size ?? 0)")

                    // 计算可以进行多少次精炼
                    let processSize = typeMaterials.first?.process_size ?? 1
                    let refineryCount = inputQuantity / Int64(processSize)
                    let remainder = inputQuantity % Int64(processSize)

                    Logger.info("     - 可精炼次数: \(refineryCount)")
                    if remainder > 0 {
                        Logger.info("     - 剩余无法精炼: \(remainder)")
                    }

                    // 计算精炼加成系数（使用重构后的可复用逻辑）
                    var refineryBonus = 1.0
                    if let categoryInfo = categoryInfo {
                        let context = getCurrentRefineryContext()
                        refineryBonus = calculateRefineryBonus(
                            itemID: item.id,
                            categoryInfo: categoryInfo,
                            context: context
                        )

                        // 根据物品类型记录日志
                        switch categoryInfo.itemType {
                        case .oreAndIce:
                            Logger.info("     - 精炼加成系数: \(refineryBonus)")
                        case .gas:
                            Logger.info("     - 气云解压效率: \(refineryBonus)")
                        case .other:
                            Logger.info("     - 其他物品精炼系数: \(refineryBonus)")
                        case .noOutput:
                            Logger.info("     - 无精炼产出，原样输出")
                        }
                    }

                    // 根据物品类型计算输出
                    switch categoryInfo?.itemType {
                    case .noOutput:
                        // 无精炼产出，原样输出
                        Logger.info("     - 原样输出: \(inputQuantity)")
                    // 这里可以添加原样输出的逻辑，比如添加到总输出中

                    default:
                        // 有精炼产出，计算输出材料
                        if let typeMaterials = allTypeMaterials[item.id] {
                            Logger.info("     - 精炼输出:")
                            for material in typeMaterials {
                                let baseOutputQuantity =
                                    Int64(material.outputQuantity) * refineryCount
                                let finalOutputQuantity: Int64

                                switch categoryInfo?.itemType {
                                case .gas:
                                    // 气云解压：直接应用效率系数
                                    finalOutputQuantity = Int64(
                                        Double(baseOutputQuantity) * refineryBonus
                                    )
                                case .other:
                                    // 其他物品：应用精炼系数
                                    finalOutputQuantity = Int64(
                                        Double(baseOutputQuantity) * refineryBonus
                                    )
                                default:
                                    // 矿石和冰矿：应用精炼加成
                                    finalOutputQuantity = Int64(
                                        Double(baseOutputQuantity) * refineryBonus
                                    )
                                }

                                Logger.info(
                                    "       * \(material.outputMaterialName) (TypeID: \(material.outputMaterial)): \(finalOutputQuantity) (基础: \(baseOutputQuantity), 加成后: \(finalOutputQuantity))"
                                )

                                // 累计到总输出中
                                totalRefineryOutputs[material.outputMaterial, default: 0] += Int(
                                    finalOutputQuantity
                                )

                                // 保存材料名称映射
                                materialNameMap[material.outputMaterial] =
                                    material.outputMaterialName
                            }
                        }
                    }
                } else {
                    Logger.warning("     - 未找到精炼输出信息")
                }
            }
        }

        // 7. 输出总精炼结果
        if !totalRefineryOutputs.isEmpty {
            Logger.info("=== 总精炼输出 ===")

            // 输出总精炼结果
            for (materialID, totalQuantity) in totalRefineryOutputs.sorted(by: { $0.key < $1.key }) {
                let materialName = materialNameMap[materialID] ?? "Unknown Material"
                Logger.info("  - \(materialName) (TypeID: \(materialID)): \(totalQuantity)")
            }
        } else {
            Logger.warning("没有找到任何精炼输出信息")
        }

        // 8. 计算剩余物品
        var remainingItems: [Int: Int64] = [:]
        for (_, oreItem) in oreItems.enumerated() {
            if let item = items.first(where: { $0.id == oreItem.typeID }) {
                let inputQuantity = itemQuantities[item.id] ?? 1

                // 检查是否有精炼产出
                if let typeMaterials = allTypeMaterials[item.id] {
                    let processSize = typeMaterials.first?.process_size ?? 1
                    let remainder = inputQuantity % Int64(processSize)

                    if remainder > 0 {
                        remainingItems[item.id] = remainder
                        Logger.info("剩余物品: \(item.name) (TypeID: \(item.id)): \(remainder)")
                    }
                } else {
                    // 没有精炼产出的物品，全部作为剩余物品
                    remainingItems[item.id] = inputQuantity
                    Logger.info("无精炼产出物品: \(item.name) (TypeID: \(item.id)): \(inputQuantity)")
                }
            }
        }

        // 9. 保存结果数据并显示结果页面
        refineryResultData = RefineryResultData(
            outputs: totalRefineryOutputs,
            materialNames: materialNameMap,
            remaining: remainingItems
        )

        Logger.info("=== 精炼计算完成 ===")
        Logger.info("精炼输出: \(totalRefineryOutputs.count) 种材料")
        Logger.info("剩余物品: \(remainingItems.count) 种物品")

        // 详细记录传递给结果页面的数据
        Logger.info("=== 传递给RefineryResultView的数据 ===")
        Logger.info("refineryResultData.outputs count: \(refineryResultData?.outputs.count ?? 0)")
        Logger.info(
            "refineryResultData.materialNames count: \(refineryResultData?.materialNames.count ?? 0)"
        )
        Logger.info(
            "refineryResultData.remaining count: \(refineryResultData?.remaining.count ?? 0)"
        )

        if let data = refineryResultData {
            for (materialID, quantity) in data.outputs {
                let materialName = data.materialNames[materialID] ?? "Unknown"
                Logger.info("Output: \(materialID) (\(materialName)) -> \(quantity)")
            }

            for (itemID, quantity) in data.remaining {
                Logger.info("Remaining: \(itemID) -> \(quantity)")
            }
        }

        // 显示结果页面
    }
}
