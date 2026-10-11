import SwiftUI

struct MarketOrdersView: View {
    let itemID: Int
    let itemName: String
    let regionID: Int
    @ObservedObject var databaseManager: DatabaseManager
    @State private var orders: [MarketOrder] = []
    @State private var showBuyOrders = false
    @State private var locationInfos: [Int64: LocationInfoDetail] = [:]
    @State private var isLoadingOrders = false
    @State private var isLoadingLocations = false

    init(
        itemID: Int, itemName: String, regionID: Int, initialOrders: [MarketOrder] = [],
        databaseManager: DatabaseManager
    ) {
        self.itemID = itemID
        self.itemName = itemName
        self.regionID = regionID
        self.databaseManager = databaseManager
        _orders = State(initialValue: initialOrders)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部选择器
            Picker("", selection: $showBuyOrders) {
                Text(
                    "\(NSLocalizedString("Orders_Sell", comment: "")) (\(orders.filter { !$0.isBuyOrder }.count))"
                ).tag(false)
                Text(
                    "\(NSLocalizedString("Orders_Buy", comment: "")) (\(orders.filter { $0.isBuyOrder }.count))"
                ).tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 4)

            // 内容视图
            TabView(selection: $showBuyOrders) {
                OrderListView(
                    orders: orders.filter { !$0.isBuyOrder },
                    locationInfos: locationInfos,
                    isLoadingLocations: isLoadingLocations,
                    hidesLocation: itemID == MarketManager.plexTypeID
                )
                .tag(false)

                OrderListView(
                    orders: orders.filter { $0.isBuyOrder },
                    locationInfos: locationInfos,
                    isLoadingLocations: isLoadingLocations,
                    hidesLocation: itemID == MarketManager.plexTypeID
                )
                .tag(true)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(edges: .bottom)

            if isLoadingOrders || isLoadingLocations {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(
                        isLoadingOrders
                            ? NSLocalizedString("Loading_Orders", comment: "正在加载订单...")
                            : NSLocalizedString("Loading_Location_Info", comment: "正在加载地点信息...")
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(Color(UIColor.systemGroupedBackground))
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(itemName)
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea(edges: .bottom)
        .task {
            // 如果没有初始订单数据，先加载订单
            if orders.isEmpty {
                await loadOrdersData()
            }

            // 加载位置信息
            await loadLocationInfo()
        }
        .refreshable {
            // 同时刷新订单数据和位置信息
            await loadOrdersData(forceRefresh: true)
            await loadLocationInfo()
        }
    }

    // MARK: - 数据加载方法

    private func loadOrdersData(forceRefresh: Bool = false) async {
        isLoadingOrders = true
        defer { isLoadingOrders = false }

        do {
            let newOrders: [MarketOrder]

            // 判断是否选择了建筑
            if StructureMarketManager.isStructureId(regionID) {
                // 选择了建筑，使用建筑订单API
                guard let structureId = StructureMarketManager.getStructureId(from: regionID) else {
                    Logger.error("无效的建筑ID: \(regionID)")
                    await MainActor.run {
                        orders = []
                    }
                    return
                }

                // 获取建筑对应的角色ID
                guard let structure = getStructureById(structureId) else {
                    Logger.error("未找到建筑信息: \(structureId)")
                    await MainActor.run {
                        orders = []
                    }
                    return
                }

                newOrders = try await StructureMarketManager.shared.getItemOrdersInStructure(
                    structureId: structureId,
                    characterId: structure.characterId,
                    typeId: itemID,
                    forceRefresh: forceRefresh
                )

                Logger.info("从建筑 \(structure.structureName) 获取到 \(newOrders.count) 个订单")
            } else {
                // 选择了星域，使用原有的API
                newOrders = try await MarketOrdersAPI.shared.fetchMarketOrders(
                    typeID: itemID,
                    regionID: regionID,
                    forceRefresh: forceRefresh
                )
            }

            await MainActor.run {
                orders = newOrders
            }
        } catch {
            Logger.error("加载市场订单失败: \(error)")
            await MainActor.run {
                orders = []
            }
        }
    }

    private func loadLocationInfo() async {
        // PLEX 走全球市场，位置信息不可解析，直接不显示
        guard itemID != MarketManager.plexTypeID, !orders.isEmpty else { return }

        isLoadingLocations = true
        defer { isLoadingLocations = false }

        // 收集所有订单的位置ID
        let locationIds = Set(orders.map { $0.locationId })

        // 按类型分组位置ID
        let groupedIds = Dictionary(grouping: locationIds) { LocationType.from(id: $0) }

        // 清空之前的位置信息
        await MainActor.run {
            locationInfos = [:]
        }

        // 使用时再创建 loader，确保拿到当前选择的角色（与钱包/订单等页面保持一致）
        let currentCharacterId = UserDefaults.standard.integer(forKey: "currentCharacterId")
        let locationInfoLoader = LocationInfoLoader(
            databaseManager: databaseManager, characterId: Int64(currentCharacterId)
        )

        // 1. 优先加载空间站信息（通常在本地数据库中，速度快）
        if let stationIds = groupedIds[.station], !stationIds.isEmpty {
            let stationInfos = await locationInfoLoader.loadLocationInfo(
                locationIds: Set(stationIds)
            )

            await MainActor.run {
                locationInfos.merge(stationInfos) { _, new in new }
            }
        }

        // 2. 优先加载星系信息（通常在本地数据库中，速度快）
        if let systemIds = groupedIds[.solarSystem], !systemIds.isEmpty {
            let systemInfos = await locationInfoLoader.loadLocationInfo(
                locationIds: Set(systemIds)
            )

            await MainActor.run {
                locationInfos.merge(systemInfos) { _, new in new }
            }
        }

        // 3. 最后加载建筑物信息（需要API查询，速度慢）
        if let structureIds = groupedIds[.structure], !structureIds.isEmpty {
            let structureInfos = await locationInfoLoader.loadLocationInfo(
                locationIds: Set(structureIds)
            )

            await MainActor.run {
                locationInfos.merge(structureInfos) { _, new in new }
            }
        }
    }

    /// 订单列表视图
    private struct OrderListView: View {
        let orders: [MarketOrder]
        let locationInfos: [Int64: LocationInfoDetail]
        let isLoadingLocations: Bool
        let hidesLocation: Bool

        private var sortedOrders: [MarketOrder] {
            orders.sorted { order1, order2 -> Bool in
                if order1.isBuyOrder {
                    return order1.price > order2.price // 买单按价格从高到低
                } else {
                    return order1.price < order2.price // 卖单按价格从低到高
                }
            }
        }

        var body: some View {
            List {
                if orders.isEmpty {
                    Section {
                        NoDataSection()
                    }
                } else {
                    Section {
                        ForEach(sortedOrders, id: \.orderId) { order in
                            OrderRow(
                                order: order,
                                locationInfo: locationInfos[order.locationId],
                                isLoadingLocation: isLoadingLocations,
                                hidesLocation: hidesLocation
                            )
                        }
                    }
                    .listSectionSpacing(.compact)
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    /// 订单行视图
    private struct OrderRow: View {
        let order: MarketOrder
        let locationInfo: LocationInfoDetail?
        let isLoadingLocation: Bool
        let hidesLocation: Bool

        var body: some View {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(
                            order.price < 1_000_000
                                ? "\(FormatUtil.format(order.price, maxFractionDigits: 2)) ISK"
                                : FormatUtil.formatISK(order.price)
                        )
                        .font(.system(.headline, design: .monospaced))
                        Spacer()
                        Text("Qty: \(order.volumeRemain)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    if !hidesLocation {
                        if let locationInfo = locationInfo {
                            LocationInfoView(
                                stationName: locationInfo.stationName,
                                solarSystemName: locationInfo.solarSystemName,
                                security: locationInfo.security,
                                font: .caption,
                                textColor: .secondary
                            )
                        } else if isLoadingLocation {
                            // 地点信息加载中的占位视图
                            HStack(spacing: 4) {
                                Text(NSLocalizedString("Loading_Location", comment: "加载中..."))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                ProgressView()
                                    .scaleEffect(0.5)
                            }
                        } else {
                            Text(NSLocalizedString("Assets_Unknown_Location", comment: ""))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    /// 根据建筑ID获取建筑信息
    private func getStructureById(_ structureId: Int64) -> MarketStructure? {
        return MarketStructureManager.shared.structures.first { $0.structureId == Int(structureId) }
    }
}
