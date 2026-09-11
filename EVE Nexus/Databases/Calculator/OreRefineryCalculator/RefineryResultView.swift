import SwiftUI

struct RefineryResultView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let taxRate: Double

    // 精炼结果数据
    let refineryOutputs: [Int: Int] // 输出材料ID -> 总数量
    let materialNameMap: [Int: String] // 材料ID -> 材料名称
    let remainingItems: [Int: Int64] // 剩余物品ID -> 剩余数量

    // 输出市场设置状态变量（精炼后产品的市场）
    @State private var selectedLocation: Int = MarketManager.theForgeRegionID // 默认 The Forge
    @State private var showRegionPicker = false

    /// 当前选中地点的类型信息（星域/星系/建筑）
    private var locationType: MarketLocationType? {
        MarketLocationType.from(id: selectedLocation)
    }

    /// 选中地点的显示名称
    private var selectedRegionName: String {
        locationType?.displayName ?? ""
    }

    /// ESI 查询用的星域 ID（对星系返回其所属星域 ID，对建筑返回虚拟 ID）
    private var selectedRegionID: Int {
        locationType?.regionID ?? selectedLocation
    }

    // 状态变量
    @State private var isLoadingPrices = false
    @State private var outputPrices: [Int: MarketPriceData] = [:]
    @State private var remainingPrices: [Int: MarketPriceData] = [:]
    @State private var outputVolumes: [Int: Double] = [:]
    @State private var remainingVolumes: [Int: Double] = [:]
    @State private var structureOrdersProgress: StructureOrdersProgress? = nil

    // EIV相关状态变量
    @State private var isLoadingEIV = false
    @State private var outputEIVPrices: [Int: MarketPriceData] = [:]

    // 市场订单买卖价相关状态变量（根据用户选择的市场）
    @State private var isLoadingBuySellPrices = false
    @State private var marketOrders: [Int: [MarketOrder]] = [:]
    @State private var sellPrices: [Int: Double] = [:]
    @State private var buyPrices: [Int: Double] = [:]

    init(
        databaseManager: DatabaseManager,
        taxRate: Double,
        refineryOutputs: [Int: Int],
        materialNameMap: [Int: String],
        remainingItems: [Int: Int64]
    ) {
        self.databaseManager = databaseManager
        self.taxRate = taxRate
        self.refineryOutputs = refineryOutputs
        self.materialNameMap = materialNameMap
        self.remainingItems = remainingItems

        Logger.info("=== RefineryResultView init ===")
        Logger.info("taxRate: \(taxRate)")
        Logger.info("refineryOutputs count: \(refineryOutputs.count)")
        Logger.info("materialNameMap count: \(materialNameMap.count)")
        Logger.info("remainingItems count: \(remainingItems.count)")

        for (materialID, quantity) in refineryOutputs {
            let materialName = materialNameMap[materialID] ?? "Unknown"
            Logger.info("Init Output: \(materialID) (\(materialName)) -> \(quantity)")
        }

        for (itemID, quantity) in remainingItems {
            Logger.info("Init Remaining: \(itemID) -> \(quantity)")
        }
    }

    var body: some View {
        List {
            // Section 1: 市场设置
            Section {
                // 输出市场选择器
                HStack {
                    Text(NSLocalizedString("Ore_Refinery_Result_Output_Market", comment: "输出市场"))
                    Spacer()
                    Button {
                        showRegionPicker = true
                    } label: {
                        HStack {
                            Text(
                                selectedRegionName.isEmpty
                                    ? NSLocalizedString("Main_Market_Select_Location", comment: "")
                                    : selectedRegionName
                            )
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
            } header: {
                Text(NSLocalizedString("Ore_Refinery_Result_Market_Settings", comment: "市场设置"))
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

            // Section 2: 产品价值和税率
            Section {
                // 精炼后产品总价（市场卖价）
                HStack {
                    Text(NSLocalizedString("Ore_Refinery_Result_Product_Sell_Value", comment: "精炼后产品卖价"))
                    Spacer()
                    if isLoadingBuySellPrices {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        let sellValue = calculateTotalOutputSellValue()
                        Text("\(FormatUtil.formatISK(sellValue))")
                            .foregroundColor(.secondary)
                    }
                }

                // 精炼后产品总价（市场买价）
                HStack {
                    Text(NSLocalizedString("Ore_Refinery_Result_Product_Buy_Value", comment: "精炼后产品买价"))
                    Spacer()
                    if isLoadingBuySellPrices {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        let buyValue = calculateTotalOutputBuyValue()
                        Text("\(FormatUtil.formatISK(buyValue))")
                            .foregroundColor(.secondary)
                    }
                }

                // 税额（基于EIV计算）
                HStack {
                    Text(NSLocalizedString("Ore_Refinery_Result_Tax_Amount", comment: ""))
                    Spacer()
                    if isLoadingEIV {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        let taxAmount = calculateTaxAmount()
                        if taxRate == 0.0 {
                            Text(
                                "0 ISK (\(NSLocalizedString("Ore_Refinery_Tax_Rate", comment: "")): \(FormatUtil.formatPercentFrom100(taxRate)))"
                            )
                            .foregroundColor(.secondary)
                        } else {
                            Text("\(FormatUtil.formatISK(taxAmount))")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                HStack {
                    Text(NSLocalizedString("Ore_Refinery_Result_Total_Volume", comment: ""))
                    Spacer()
                    if isLoadingPrices {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        let totalVolume = calculateTotalOutputVolume()
                        Text("\(FormatUtil.formatForUI(totalVolume, maxFractionDigits: 2)) m³")
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                HStack {
                    Text(NSLocalizedString("Ore_Refinery_Result_Product_Value", comment: ""))

                    Spacer()

                    // 显示价格来源和加载进度
                    if isLoadingPrices {
                        if StructureMarketManager.isStructureId(selectedRegionID),
                           let progress = structureOrdersProgress
                        {
                            switch progress {
                            case let .loading(currentPage, totalPages):
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                    Text("\(currentPage)/\(totalPages)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            case .completed:
                                EmptyView()
                            }
                        } else {
                            ProgressView()
                                .scaleEffect(0.6)
                        }
                    } else {
                        Text(selectedRegionName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Section 2: 精炼结果清单
            if !refineryOutputs.isEmpty {
                Section {
                    ForEach(Array(refineryOutputs.keys.sorted()), id: \.self) { materialID in
                        if let quantity = refineryOutputs[materialID] {
                            refineryOutputRow(materialID: materialID, quantity: quantity)
                        }
                    }
                } header: {
                    HStack {
                        Text(NSLocalizedString("Ore_Refinery_Result_Output_List", comment: ""))

                        Spacer()

                        Button {
                            copyRefineryOutputsToClipboard()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                                Text(NSLocalizedString("Misc_Copy", comment: "复制"))
                                    .font(.caption)
                            }
                            .foregroundColor(.accentColor)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            } else {
                Section {
                    Text(NSLocalizedString("Ore_Refinery_Output_List_Empty", comment: ""))
                        .foregroundColor(.secondary)
                        .italic()
                } header: {
                    Text(NSLocalizedString("Ore_Refinery_Result_Output_List", comment: ""))
                }
            }

            // Section 3: 精炼剩余物品清单
            if !remainingItems.isEmpty {
                Section {
                    ForEach(Array(remainingItems.keys.sorted()), id: \.self) { itemID in
                        if let quantity = remainingItems[itemID] {
                            remainingItemRow(itemID: itemID, quantity: quantity)
                        }
                    }
                } header: {
                    Text(NSLocalizedString("Ore_Refinery_Result_Remaining_List", comment: ""))
                }
            } else {
                Section {
                    Text(NSLocalizedString("Ore_Refinery_Remaining_List_Empty", comment: ""))
                        .foregroundColor(.secondary)
                        .italic()
                } header: {
                    Text(NSLocalizedString("Ore_Refinery_Result_Remaining_List", comment: ""))
                }
            }
        }
        .navigationTitle(NSLocalizedString("Ore_Refinery_Result_Title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            loadPricesAndVolumes()
        }
        .sheet(isPresented: $showRegionPicker) {
            MarketRegionPickerView(
                selectedLocation: $selectedLocation,
                saveSelection: .constant(false),
                databaseManager: databaseManager
            )
            .presentationDragIndicator(.visible)
        }
        .onChange(of: selectedLocation) { oldValue, newValue in
            if oldValue != newValue {
                loadPricesAndVolumes()
            }
        }
        .onAppear {
            Logger.info("=== RefineryResultView onAppear ===")
            Logger.info("refineryOutputs count: \(refineryOutputs.count)")
            Logger.info("remainingItems count: \(remainingItems.count)")
            Logger.info("taxRate: \(taxRate)")

            for (materialID, quantity) in refineryOutputs {
                Logger.info("Output material: \(materialID) -> \(quantity)")
            }

            for (itemID, quantity) in remainingItems {
                Logger.info("Remaining item: \(itemID) -> \(quantity)")
            }

            // 初始化默认市场
            loadPricesAndVolumes()
        }
    }

    /// 精炼输出物品行
    private func refineryOutputRow(materialID: Int, quantity: Int) -> some View {
        HStack(spacing: 12) {
            // 物品图标
            IconManager.shared.loadImage(for: getItemIconFileName(itemID: materialID))
                .resizable()
                .frame(width: 32, height: 32)

            // 物品信息
            VStack(alignment: .leading, spacing: 2) {
                Text(materialNameMap[materialID] ?? "Unknown Material")
                    .lineLimit(1)

                // 价格信息或加载状态
                if isLoadingPrices {
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
                    if let priceData = outputPrices[materialID] {
                        let marketPrice = priceData.averagePrice
                        if marketPrice > 0 {
                            Text(
                                "\(NSLocalizedString("Ore_Refinery_Result_Avg_Price", comment: "")): \(FormatUtil.format(marketPrice)) ISK"
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }

                        let totalValue = marketPrice * Double(quantity)
                        Text(
                            "\(NSLocalizedString("Ore_Refinery_Result_Total_Value", comment: "")): \(FormatUtil.formatISK(totalValue))"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    } else {
                        Text(NSLocalizedString("Ore_Refinery_Result_No_Price", comment: ""))
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }

            Spacer()

            // 数量
            Text("\(quantity)")
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    /// 剩余物品行
    private func remainingItemRow(itemID: Int, quantity: Int64) -> some View {
        HStack(spacing: 12) {
            // 物品图标
            IconManager.shared.loadImage(for: getItemIconFileName(itemID: itemID))
                .resizable()
                .frame(width: 32, height: 32)

            // 物品信息
            VStack(alignment: .leading, spacing: 2) {
                Text(getItemName(itemID: itemID))
                    .lineLimit(1)

                // 价格信息或加载状态
                if isLoadingPrices {
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
                    if let priceData = remainingPrices[itemID] {
                        let marketPrice = priceData.averagePrice
                        if marketPrice > 0 {
                            Text(
                                "\(NSLocalizedString("Ore_Refinery_Result_Avg_Price", comment: "")): \(FormatUtil.format(marketPrice)) ISK"
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }

                        let totalValue = marketPrice * Double(quantity)
                        Text(
                            "\(NSLocalizedString("Ore_Refinery_Result_Total_Value", comment: "")): \(FormatUtil.formatISK(totalValue))"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    } else {
                        Text(NSLocalizedString("Ore_Refinery_Result_No_Price", comment: ""))
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }

            Spacer()

            // 数量
            Text("\(quantity)")
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    /// 加载价格和体积信息
    private func loadPricesAndVolumes() {
        Logger.info("=== loadPricesAndVolumes called ===")
        Logger.info("refineryOutputs keys: \(Array(refineryOutputs.keys))")
        Logger.info("remainingItems keys: \(Array(remainingItems.keys))")
        Logger.info("selectedRegionID: \(selectedRegionID)")

        isLoadingPrices = true
        isLoadingEIV = true
        isLoadingBuySellPrices = true

        Task {
            // 并发加载不同类型的价格数据
            async let outputMarketPricesTask: Void = loadOutputMarketPrices()

            async let eivPricesTask: Void = loadEIVPrices()
            async let buySellPricesTask: Void = loadOutputBuySellPrices()
            async let volumesTask: Void = loadVolumes()

            // 等待所有任务完成
            _ = await (outputMarketPricesTask, eivPricesTask, buySellPricesTask, volumesTask)

            await MainActor.run {
                self.isLoadingPrices = false
                self.isLoadingEIV = false
                self.isLoadingBuySellPrices = false
                Logger.info("Finished loading prices, EIV, buy/sell prices, and volumes")
            }
        }
    }

    /// 加载输出市场价格（精炼后产品）- 自动判断星域/建筑
    private func loadOutputMarketPrices() async {
        // 合并所有需要价格的物品ID
        var allTypeIds: [Int] = []
        allTypeIds.append(contentsOf: Array(refineryOutputs.keys))
        allTypeIds.append(contentsOf: Array(remainingItems.keys))

        guard !allTypeIds.isEmpty else { return }

        Logger.info("Loading market prices for \(allTypeIds.count) items from regionID: \(selectedRegionID)")

        // 使用工具类自动判断并加载订单（星域或建筑）
        let ordersMap = await MarketOrdersUtil.loadOrders(
            typeIds: allTypeIds,
            regionID: selectedRegionID,
            forceRefresh: false,
            progressCallback: { progress in
                Task { @MainActor in
                    structureOrdersProgress = progress
                }
            }
        )

        Logger.info("Got \(ordersMap.count) items orders")

        // 计算每个物品的平均价格并分类
        var outputPricesTemp: [Int: MarketPriceData] = [:]
        var remainingPricesTemp: [Int: MarketPriceData] = [:]

        for (typeId, orders) in ordersMap {
            let averagePrice = calculateAveragePrice(from: orders)
            let priceData = MarketPriceData(
                adjustedPrice: averagePrice,
                averagePrice: averagePrice
            )

            if refineryOutputs.keys.contains(typeId) {
                outputPricesTemp[typeId] = priceData
            }
            if remainingItems.keys.contains(typeId) {
                remainingPricesTemp[typeId] = priceData
            }
        }

        await MainActor.run {
            self.outputPrices = outputPricesTemp
            self.remainingPrices = remainingPricesTemp
            Logger.info("Set market prices: output=\(outputPricesTemp.count), remaining=\(remainingPricesTemp.count)")
        }
    }

    /// 计算订单的平均价格（使用通用工具类）
    private func calculateAveragePrice(from orders: [MarketOrder]) -> Double {
        // 星系市场按所选星系过滤；星域/建筑市场不限制
        return MarketOrdersUtil.calculateAveragePrice(from: orders, systemId: locationType?.systemID)
    }

    /// 计算市场卖价（使用通用工具类）
    private func calculateSellPrice(from orders: [MarketOrder]) -> Double {
        return MarketOrdersUtil.calculatePrice(from: orders, orderType: .sell, quantity: nil, systemId: locationType?.systemID).price ?? 0.0
    }

    /// 计算市场买价（使用通用工具类）
    private func calculateBuyPrice(from orders: [MarketOrder]) -> Double {
        return MarketOrdersUtil.calculatePrice(from: orders, orderType: .buy, quantity: nil, systemId: locationType?.systemID).price ?? 0.0
    }

    // MARK: - EIV价格加载和计算方法

    /// 加载EIV价格数据（使用MarketPriceUtil）
    private func loadEIVPrices() async {
        Logger.info("=== loadEIVPrices called ===")

        // 合并所有需要查询EIV价格的物品ID
        var allTypeIds: [Int] = []
        allTypeIds.append(contentsOf: Array(refineryOutputs.keys))
        allTypeIds.append(contentsOf: Array(remainingItems.keys))

        guard !allTypeIds.isEmpty else {
            Logger.info("No items to load EIV prices for")
            return
        }

        Logger.info("Loading EIV prices for \(allTypeIds.count) items")

        // 使用MarketPriceUtil获取EIV价格
        let eivPrices = await MarketPriceUtil.getMarketPrices(typeIds: allTypeIds)
        Logger.info("Got EIV prices for \(eivPrices.count) items")

        await MainActor.run {
            // 只保存输出物品的EIV价格
            var outputEIVTemp: [Int: MarketPriceData] = [:]

            for (typeId, priceData) in eivPrices {
                if refineryOutputs.keys.contains(typeId) || remainingItems.keys.contains(typeId) {
                    outputEIVTemp[typeId] = priceData
                }
            }

            self.outputEIVPrices = outputEIVTemp

            Logger.info("Set EIV prices: output=\(outputEIVTemp.count)")
        }
    }

    /// 加载输出市场订单并计算买价和卖价（根据用户选择的市场）
    private func loadOutputBuySellPrices() async {
        Logger.info("=== loadOutputBuySellPrices called ===")

        let outputTypeIDs = Array(refineryOutputs.keys)
        guard !outputTypeIDs.isEmpty else {
            Logger.info("No output items to load market orders for")
            return
        }

        Logger.info("Loading market orders for \(outputTypeIDs.count) output items from regionID: \(selectedRegionID)")

        // 使用工具类加载用户选择市场的订单（自动判断星域/建筑）
        let orders = await MarketOrdersUtil.loadOrders(
            typeIds: outputTypeIDs,
            regionID: selectedRegionID,
            forceRefresh: false,
            progressCallback: { progress in
                Task { @MainActor in
                    structureOrdersProgress = progress
                }
            }
        )
        Logger.info("Got market orders for \(orders.count) items")

        // 计算每个物品的买价和卖价
        var sellPricesTemp: [Int: Double] = [:]
        var buyPricesTemp: [Int: Double] = [:]

        for (typeId, itemOrders) in orders {
            let sellPrice = calculateSellPrice(from: itemOrders)
            let buyPrice = calculateBuyPrice(from: itemOrders)

            if sellPrice > 0 {
                sellPricesTemp[typeId] = sellPrice
            }
            if buyPrice > 0 {
                buyPricesTemp[typeId] = buyPrice
            }
        }

        await MainActor.run {
            self.marketOrders = orders
            self.sellPrices = sellPricesTemp
            self.buyPrices = buyPricesTemp
            Logger.info("Set market prices: sell=\(sellPricesTemp.count), buy=\(buyPricesTemp.count)")
        }
    }

    /// 加载体积信息
    private func loadVolumes() async {
        Logger.info("=== loadVolumes called ===")

        // 加载精炼输出物品的体积
        let outputTypeIDs = Array(refineryOutputs.keys)
        Logger.info("Loading volumes for output items: \(outputTypeIDs)")
        if !outputTypeIDs.isEmpty {
            let volumes = await loadItemVolumes(typeIDs: outputTypeIDs)
            Logger.info("Got \(volumes.count) output volumes")
            await MainActor.run {
                self.outputVolumes = volumes
            }
        }

        // 加载剩余物品的体积
        let remainingTypeIDs = Array(remainingItems.keys)
        Logger.info("Loading volumes for remaining items: \(remainingTypeIDs)")
        if !remainingTypeIDs.isEmpty {
            let volumes = await loadItemVolumes(typeIDs: remainingTypeIDs)
            Logger.info("Got \(volumes.count) remaining volumes")
            await MainActor.run {
                self.remainingVolumes = volumes
            }
        }
    }

    /// 从内存索引加载物品体积
    private func loadItemVolumes(typeIDs: [Int]) async -> [Int: Double] {
        guard !typeIDs.isEmpty else { return [:] }

        Logger.info("=== loadItemVolumes called ===")
        Logger.info("typeIDs: \(typeIDs)")

        var volumes: [Int: Double] = [:]
        for typeID in typeIDs {
            if let volume = ItemInfoMap.typeInfo(for: typeID)?.volume {
                volumes[typeID] = volume
                Logger.info("Found volume for \(typeID): \(volume)")
            }
        }

        Logger.info("Returning \(volumes.count) volumes")
        return volumes
    }

    /// 计算产品市场卖价总价值（根据用户选择的市场）
    private func calculateTotalOutputSellValue() -> Double {
        var totalValue: Double = 0

        Logger.info("=== calculateTotalOutputSellValue called ===")
        Logger.info("refineryOutputs count: \(refineryOutputs.count)")
        Logger.info("sellPrices count: \(sellPrices.count)")

        for (materialID, quantity) in refineryOutputs {
            if let sellPrice = sellPrices[materialID] {
                Logger.info("Found sell price for \(materialID): \(sellPrice)")
                if sellPrice > 0 {
                    let itemValue = sellPrice * Double(quantity)
                    totalValue += itemValue
                    Logger.info("Added \(itemValue) to sell total (now \(totalValue))")
                }
            } else {
                Logger.info("No sell price found for \(materialID)")
            }
        }

        Logger.info("Final sell total value: \(totalValue)")
        return totalValue
    }

    /// 计算产品市场买价总价值（根据用户选择的市场）
    private func calculateTotalOutputBuyValue() -> Double {
        var totalValue: Double = 0

        Logger.info("=== calculateTotalOutputBuyValue called ===")
        Logger.info("refineryOutputs count: \(refineryOutputs.count)")
        Logger.info("buyPrices count: \(buyPrices.count)")

        for (materialID, quantity) in refineryOutputs {
            if let buyPrice = buyPrices[materialID] {
                Logger.info("Found buy price for \(materialID): \(buyPrice)")
                if buyPrice > 0 {
                    let itemValue = buyPrice * Double(quantity)
                    totalValue += itemValue
                    Logger.info("Added \(itemValue) to buy total (now \(totalValue))")
                }
            } else {
                Logger.info("No buy price found for \(materialID)")
            }
        }

        Logger.info("Final buy total value: \(totalValue)")
        return totalValue
    }

    /// 计算产品EIV（用于税额计算，使用adjustedPrice）
    private func calculateTotalOutputEIV() -> Double {
        var totalEIV: Double = 0

        Logger.info("=== calculateTotalOutputEIV called ===")
        Logger.info("refineryOutputs count: \(refineryOutputs.count)")
        Logger.info("outputEIVPrices count: \(outputEIVPrices.count)")

        for (materialID, quantity) in refineryOutputs {
            Logger.info("Processing EIV for material \(materialID) with quantity \(quantity)")
            if let priceData = outputEIVPrices[materialID] {
                let adjustedPrice = priceData.adjustedPrice
                Logger.info(
                    "Found EIV price data for \(materialID): adjustedPrice = \(adjustedPrice)"
                )
                if adjustedPrice > 0 {
                    let itemEIV = adjustedPrice * Double(quantity)
                    totalEIV += itemEIV
                    Logger.info("Added \(itemEIV) to EIV total (now \(totalEIV))")
                } else {
                    Logger.info("Adjusted price is 0 or negative for \(materialID)")
                }
            } else {
                Logger.info("No EIV price data found for \(materialID)")
            }
        }

        Logger.info("Final total EIV: \(totalEIV)")
        return totalEIV
    }

    /// 计算税额
    private func calculateTaxAmount() -> Double {
        Logger.info("=== calculateTaxAmount called ===")
        Logger.info("taxRate: \(taxRate)%")

        let totalEIV = calculateTotalOutputEIV()
        Logger.info("Total EIV: \(totalEIV)")

        let taxAmount = totalEIV * (taxRate / 100.0)
        Logger.info("Tax calculation: EIV \(totalEIV) × taxRate \(taxRate)% = \(taxAmount)")

        return taxAmount
    }

    /// 计算精炼输出总体积
    private func calculateTotalOutputVolume() -> Double {
        var totalVolume: Double = 0

        Logger.info("=== calculateTotalOutputVolume called ===")
        Logger.info("refineryOutputs count: \(refineryOutputs.count)")
        Logger.info("outputVolumes count: \(outputVolumes.count)")

        for (materialID, quantity) in refineryOutputs {
            Logger.info("Processing volume for material \(materialID) with quantity \(quantity)")
            if let volume = outputVolumes[materialID] {
                let itemVolume = volume * Double(quantity)
                totalVolume += itemVolume
                Logger.info(
                    "Found volume for \(materialID): \(volume), item volume: \(itemVolume), total: \(totalVolume)"
                )
            } else {
                Logger.info("No volume data found for \(materialID)")
            }
        }

        Logger.info("Final total volume: \(totalVolume)")
        return totalVolume
    }

    /// 获取物品名称
    private func getItemName(itemID: Int) -> String {
        ItemInfoMap.typeName(for: itemID) ?? "Unknown Item"
    }

    /// 获取物品图标文件名
    private func getItemIconFileName(itemID: Int) -> String {
        ItemInfoMap.iconFilename(for: itemID)
    }

    /// 复制精炼输出物品到剪贴板
    private func copyRefineryOutputsToClipboard() {
        var exportLines: [String] = []

        // 按材料ID排序，确保输出顺序一致
        let sortedMaterialIDs = Array(refineryOutputs.keys).sorted()

        for materialID in sortedMaterialIDs {
            if let quantity = refineryOutputs[materialID] {
                let materialName = materialNameMap[materialID] ?? "Unknown Material"
                let line = "\(materialName)\t\(quantity)"
                exportLines.append(line)
            }
        }

        // 将所有行合并为一个字符串，以换行符分隔
        let exportContent = exportLines.joined(separator: "\n")

        // 复制到剪贴板
        UIPasteboard.general.string = exportContent

        Logger.success("成功复制 \(exportLines.count) 个精炼输出物品到剪贴板")
    }
}
