import SwiftUI

/// location_flag → 本地化 key，新增 flag 只需在此添加一项
private let locationFlagLocalizationKeys: [String: String] = [
    "Hangar": "Location_Flag_Hangar",
    "CorpSAG1": "Location_Flag_CorpSAG1", "CorpSAG2": "Location_Flag_CorpSAG2",
    "CorpSAG3": "Location_Flag_CorpSAG3", "CorpSAG4": "Location_Flag_CorpSAG4",
    "CorpSAG5": "Location_Flag_CorpSAG5", "CorpSAG6": "Location_Flag_CorpSAG6",
    "CorpSAG7": "Location_Flag_CorpSAG7", "CorpDeliveries": "Location_Flag_CorpDeliveries",
    "AutoFit": "Location_Flag_AutoFit", "Cargo": "Location_Flag_Cargo",
    "DroneBay": "Location_Flag_DroneBay", "FleetHangar": "Location_Flag_FleetHangar",
    "Deliveries": "Location_Flag_Deliveries", "HiddenModifiers": "Location_Flag_HiddenModifiers",
    "ShipHangar": "Location_Flag_ShipHangar", "FighterBay": "Location_Flag_FighterBay",
    "FighterTubes": "Location_Flag_FighterTubes", "SubSystemBay": "Location_Flag_SubSystemBay",
    "SubSystemSlots": "Location_Flag_SubSystemSlots", "HiSlots": "Location_Flag_HiSlots",
    "MedSlots": "Location_Flag_MedSlots", "LoSlots": "Location_Flag_LoSlots",
    "RigSlots": "Location_Flag_RigSlots",
    "SpecializedAmmoHold": "Location_Flag_SpecializedAmmoHold",
    "SpecializedCommandCenterHold": "Location_Flag_SpecializedCommandCenterHold",
    "SpecializedFuelBay": "Location_Flag_SpecializedFuelBay",
    "SpecializedGasHold": "Location_Flag_SpecializedGasHold",
    "SpecializedIndustrialShipHold": "Location_Flag_SpecializedIndustrialShipHold",
    "SpecializedLargeShipHold": "Location_Flag_SpecializedLargeShipHold",
    "SpecializedMaterialBay": "Location_Flag_SpecializedMaterialBay",
    "SpecializedMediumShipHold": "Location_Flag_SpecializedMediumShipHold",
    "SpecializedMineralHold": "Location_Flag_SpecializedMineralHold",
    "SpecializedOreHold": "Location_Flag_SpecializedOreHold",
    "SpecializedPlanetaryCommoditiesHold": "Location_Flag_SpecializedPlanetaryCommoditiesHold",
    "SpecializedSalvageHold": "Location_Flag_SpecializedSalvageHold",
    "SpecializedShipHold": "Location_Flag_SpecializedShipHold",
    "SpecializedSmallShipHold": "Location_Flag_SpecializedSmallShipHold",
    "StructureDeedBay": "Location_Flag_StructureDeedBay",
    "Unlocked": "Location_Flag_Unlocked", "Wardrobe": "Location_Flag_Wardrobe",
]

private func formatLocationFlag(_ flag: String) -> String {
    guard let key = locationFlagLocalizationKeys[flag] else { return flag }
    return NSLocalizedString(key, comment: "")
}

/// 与 `LocationAssetsViewModel.processFlag` 一致：将 ESI 的逐槽位 flag 归并为分组名
private func normalizedAssetLocationFlag(_ flag: String) -> String {
    switch flag {
    case let f where f.hasPrefix("HiSlot"): return "HiSlots"
    case let f where f.hasPrefix("MedSlot"): return "MedSlots"
    case let f where f.hasPrefix("LoSlot"): return "LoSlots"
    case let f where f.hasPrefix("RigSlot"): return "RigSlots"
    case let f where f.hasPrefix("SubSystemSlot"): return "SubSystemSlots"
    case let f where f.hasPrefix("FighterTube"): return "FighterTubes"
    default: return flag
    }
}

// MARK: - 从资产导出装配（DNA → 本地装配）

private enum AssetShipFittingExport {
    static let slotFlags: Set<String> = ["HiSlots", "MedSlots", "LoSlots", "RigSlots"]

    /// category=6 且 marketGroupID 非空，视为可上架装配的飞船
    static func isMarketShip(typeId: Int, databaseManager _: DatabaseManager) -> Bool {
        guard let info = SDEMemoryStore.type(for: typeId) else { return false }
        return info.categoryID == 6 && info.marketGroupID != nil
    }

    static func hasAnySlotFitting(in items: [AssetTreeNode]) -> Bool {
        items.contains { slotFlags.contains(normalizedAssetLocationFlag($0.location_flag)) }
    }

    /// 子位置视图：可显示「导出装配」的条件
    static func isExportableFittedShip(parentNode: AssetTreeNode, databaseManager: DatabaseManager) -> Bool {
        guard let items = parentNode.items, !items.isEmpty else { return false }
        guard isMarketShip(typeId: parentNode.type_id, databaseManager: databaseManager) else { return false }
        return hasAnySlotFitting(in: items)
    }

    /// 仅统计高/中/低/改装件槽内物品，按 type_id 合并数量后生成 DNA
    static func buildDNAString(shipTypeId: Int, items: [AssetTreeNode]) -> String {
        var sums: [Int: Int] = [:]
        for item in items {
            let g = normalizedAssetLocationFlag(item.location_flag)
            guard slotFlags.contains(g) else { continue }
            sums[item.type_id, default: 0] += item.quantity
        }
        let pairs = sums.keys.sorted().map { (typeId: $0, quantity: sums[$0]!) }
        return DNAParser.encodeFittingDNA(shipTypeId: shipTypeId, modules: pairs)
    }

    /// - Returns: 保存后的本地装配 `fitting_id`（UUID）
    @discardableResult
    static func exportToLocalFitting(
        parentNode: AssetTreeNode,
        databaseManager: DatabaseManager,
        displayName: String
    ) throws -> UUID {
        let dna = buildDNAString(shipTypeId: parentNode.type_id, items: parentNode.items ?? [])
        guard let dnaResult = DNAParser.parseDNA(dna, displayName: displayName) else {
            throw NSError(
                domain: "AssetShipFittingExport", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "DNA parse failed"]
            )
        }
        guard let base = DNAParser.dnaResultToLocalFitting(dnaResult, databaseManager: databaseManager) else {
            throw NSError(
                domain: "AssetShipFittingExport", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "DNA to LocalFitting failed"]
            )
        }
        let uniqueId = UUID()
        let toSave = base.duplicated(newId: uniqueId, name: base.name)
        try FitConvert.saveLocalFitting(toSave)
        return uniqueId
    }
}

/// 用于 `.sheet(item:)` 打开已保存的本地装配
private struct SavedFittingSheetItem: Identifiable {
    let fittingId: UUID
    var id: UUID {
        fittingId
    }
}

/// 扩展，提供共用的获取位置名称方法
extension AssetTreeNode {
    func getLocationName(
        stationNameCache: [Int64: String]? = nil, solarSystemNameCache: [Int: String]? = nil
    ) -> String {
        // 如果有自定义名称，优先使用
        if let name = name {
            return HTMLUtils.decodeHTMLEntities(name)
        }

        // 如果是空间站类型，从缓存中获取
        if location_type == "station", let cache = stationNameCache {
            if let name = cache[location_id] {
                return HTMLUtils.decodeHTMLEntities(name)
            }
        }

        // 如果有星系ID，尝试显示星系名称
        if let systemId = system_id, let cache = solarSystemNameCache,
           let name = cache[systemId]
        {
            return HTMLUtils.decodeHTMLEntities(name)
        }

        // 最后的回退选项
        return String(location_id)
    }
}

/// 主资产列表视图
struct LocationAssetsView: View {
    let location: AssetTreeNode
    @StateObject private var viewModel: LocationAssetsViewModel
    let stationNameCache: [Int64: String]?
    let solarSystemNameCache: [Int: String]?
    let dynamicResultingTypeIds: Set<Int>
    let showOwner: Bool
    let ownerId: Int?
    let ownerName: String?
    let ownerPortrait: UIImage?
    let typeFilterContext: AssetTypeFilterContext

    init(
        location: AssetTreeNode, preloadedItemInfo: [Int: ItemInfo]? = nil,
        stationNameCache: [Int64: String]? = nil, solarSystemNameCache: [Int: String]? = nil,
        dynamicResultingTypeIds: Set<Int> = [],
        showOwner: Bool = false, ownerId: Int? = nil, ownerName: String? = nil,
        ownerPortrait: UIImage? = nil,
        typeFilterContext: AssetTypeFilterContext = .inactive
    ) {
        self.location = location
        self.stationNameCache = stationNameCache
        self.solarSystemNameCache = solarSystemNameCache
        self.dynamicResultingTypeIds = dynamicResultingTypeIds
        self.showOwner = showOwner
        self.ownerId = ownerId
        self.ownerName = ownerName
        self.ownerPortrait = ownerPortrait
        self.typeFilterContext = typeFilterContext
        _viewModel = StateObject(
            wrappedValue: LocationAssetsViewModel(
                location: location, preloadedItemInfo: preloadedItemInfo,
                dynamicResultingTypeIds: dynamicResultingTypeIds,
                typeFilterContext: typeFilterContext
            )
        )
    }

    var body: some View {
        List {
            locationInfoSection
            ForEach(viewModel.groupedSections, id: \.flag) { group in
                assetGroupSection(for: group)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Main_Assets", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadItemInfo()
        }
    }

    private var locationInfoSection: some View {
        Section {
            AssetLocationRowContent(
                location: location,
                stationNameCache: stationNameCache,
                solarSystemNameCache: solarSystemNameCache,
                typeCount: typeFilterContext.matchingTypeCount(in: location),
                showOwner: showOwner,
                ownerId: ownerId,
                ownerName: ownerName,
                ownerPortrait: ownerPortrait
            )
        } header: {
            Text(NSLocalizedString("ESI_Tag_Location", comment: ""))
                .fontWeight(.semibold)
                .font(.system(size: 18))
                .foregroundColor(.primary)
                .textCase(.none)
        }
    }

    /// 将Section提取为单独的函数
    private func assetGroupSection(for group: (flag: String, items: [AssetTreeNode])) -> some View {
        Section(
            header: Text(formatLocationFlag(group.flag))
                .fontWeight(.semibold)
                .font(.system(size: 18))
                .foregroundColor(.primary)
                .textCase(.none)
        ) {
            ForEach(group.items, id: \.item_id) { node in
                assetRow(for: node)
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
    }

    /// 将资产行提取为单独的函数
    @ViewBuilder
    private func assetRow(for node: AssetTreeNode) -> some View {
        if node.items != nil {
            // 容器类物品
            containerLink(for: node)
        } else {
            // 非容器物品
            itemLink(for: node)
        }
    }

    /// 容器链接
    private func containerLink(for node: AssetTreeNode) -> some View {
        NavigationLink {
            SubLocationAssetsView(
                parentNode: node, preloadedItemInfo: viewModel.preloadedItemInfo,
                stationNameCache: stationNameCache, solarSystemNameCache: solarSystemNameCache,
                dynamicResultingTypeIds: dynamicResultingTypeIds,
                typeFilterContext: typeFilterContext.containerContext(for: node)
            )
        } label: {
            AssetItemView(
                node: node,
                itemInfo: viewModel.itemInfo(for: node.type_id),
                typeCount: typeFilterContext.matchingTypeCount(in: node)
            )
        }
    }

    /// 物品链接（深渊变异产物跳转深渊详情，其余跳转市场）
    @ViewBuilder
    private func itemLink(for node: AssetTreeNode) -> some View {
        if dynamicResultingTypeIds.contains(node.type_id) {
            NavigationLink {
                DynamicItemDetailView(
                    typeId: node.type_id,
                    itemId: node.item_id,
                    itemName: viewModel.itemInfo(for: node.type_id)?.name ?? ""
                )
            } label: {
                AssetItemView(node: node, itemInfo: viewModel.itemInfo(for: node.type_id), showItemId: true)
            }
        } else {
            NavigationLink {
                MarketItemDetailView(databaseManager: viewModel.databaseManager, itemID: node.type_id)
            } label: {
                AssetItemView(node: node, itemInfo: viewModel.itemInfo(for: node.type_id))
            }
        }
    }
}

/// 容器详情行：type name + 第二行自定义名称
private struct ContainerInfoRow: View {
    let node: AssetTreeNode
    let itemInfo: ItemInfo?
    var showItemId: Bool = false

    private var decodedCustomName: String? {
        guard let customName = node.name, !customName.isEmpty, customName != "None" else {
            return nil
        }
        return HTMLUtils.decodeHTMLEntities(customName)
    }

    var body: some View {
        HStack {
            AssetIconView(
                iconName: node.resolvedIconName(itemInfo: itemInfo)
            )
            VStack(alignment: .leading, spacing: 2) {
                if let itemInfo {
                    Text(itemInfo.name).lineLimit(1)
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = itemInfo.name
                            } label: {
                                Label(
                                    NSLocalizedString("Misc_Copy_Item_Name", comment: ""),
                                    systemImage: "doc.on.doc"
                                )
                            }
                        }
                    if let customName = decodedCustomName {
                        Text(customName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Text("Type ID: \(node.type_id)")
                }
                if showItemId {
                    Text("ID: \(node.item_id)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

/// 容器容积 / 内容物体积进度行（绿/黄/红按占比着色）
private struct ContainerVolumeRow: View {
    let capacity: Double
    let contentVolume: Double

    private var hasCapacity: Bool {
        capacity > 0
    }

    private var ratio: Double {
        hasCapacity ? contentVolume / capacity : 0
    }

    private var progressColor: Color {
        guard hasCapacity else { return .gray }
        if ratio >= 1.0 { return .red }
        if ratio >= 0.8 { return .yellow }
        return .green
    }

    private var contentsText: String {
        String(
            format: NSLocalizedString("%@ m³", comment: ""),
            FormatUtil.format(contentVolume, maxFractionDigits: 2)
        )
    }

    private var capacityText: String {
        hasCapacity
            ? String(
                format: NSLocalizedString("%@ m³", comment: ""),
                FormatUtil.format(capacity, maxFractionDigits: 2)
            )
            : "∞"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: min(max(ratio, 0), 1), total: 1)
                .progressViewStyle(.linear)
                .tint(progressColor)

            HStack(spacing: 4) {
                Text(
                    "\(NSLocalizedString("Assets_Container_Contents", comment: "")) \(contentsText)"
                )
                Spacer()
                Text(
                    "\(NSLocalizedString("Assets_Container_Capacity", comment: "")) \(capacityText)"
                )
                if hasCapacity {
                    Text(FormatUtil.formatPercent(ratio, fractionDigits: 0))
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// 单个资产项的视图
struct AssetItemView: View {
    let node: AssetTreeNode
    let itemInfo: ItemInfo?
    /// 容器内容种类数（递归去重，按过滤器），nil 则不显示
    var typeCount: Int?
    let showCustomName: Bool
    /// 是否显示 item_id（用于突变物品，同 type_id 但不同实例需要区分）
    let showItemId: Bool

    init(
        node: AssetTreeNode, itemInfo: ItemInfo?,
        typeCount: Int? = nil,
        showCustomName: Bool = true, showItemId: Bool = false
    ) {
        self.node = node
        self.itemInfo = itemInfo
        self.typeCount = typeCount
        self.showCustomName = showCustomName
        self.showItemId = showItemId
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                AssetIconView(
                    iconName: node.resolvedIconName(itemInfo: itemInfo)
                )
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if let itemInfo = itemInfo {
                            Text(itemInfo.name).lineLimit(1)
                                .contextMenu {
                                    Button {
                                        UIPasteboard.general.string = itemInfo.name
                                    } label: {
                                        Label(
                                            NSLocalizedString("Misc_Copy_Item_Name", comment: ""),
                                            systemImage: "doc.on.doc"
                                        )
                                    }
                                }
                            if showCustomName, let customName = node.name, node.items != nil,
                               !customName.isEmpty, customName != "None"
                            {
                                Text("[\(HTMLUtils.decodeHTMLEntities(customName))]")
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            if node.quantity > 1 {
                                Text("×\(node.quantity)")
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("Type ID: \(node.type_id)")
                        }
                    }
                    if let isBlueprintCopy = node.is_blueprint_copy, isBlueprintCopy {
                        Text(NSLocalizedString("Assets_is_BPC", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if showItemId {
                        Text("ID: \(node.item_id)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let typeCount {
                        Text(
                            String(
                                format: NSLocalizedString(
                                    "Assets_Item_Summary_Format", comment: ""
                                ),
                                typeCount
                            )
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

/// 子位置资产视图
struct SubLocationAssetsView: View {
    let parentNode: AssetTreeNode
    @StateObject private var viewModel: LocationAssetsViewModel
    let stationNameCache: [Int64: String]?
    let solarSystemNameCache: [Int: String]?
    let dynamicResultingTypeIds: Set<Int>
    let typeFilterContext: AssetTypeFilterContext

    private let containerCapacity: Double
    private let isShip: Bool
    private let contentVolume: Double

    @State private var isExportableFittedShip = false
    @State private var showExportConfirm = false
    @State private var exportErrorMessage: String?
    @State private var showExportSuccessPrompt = false
    // 成功保存后、在「是否查看」对话框中使用
    @State private var exportSuccessFittingId: UUID?
    @State private var savedFittingSheetItem: SavedFittingSheetItem?

    init(
        parentNode: AssetTreeNode, preloadedItemInfo: [Int: ItemInfo]? = nil,
        stationNameCache: [Int64: String]? = nil, solarSystemNameCache: [Int: String]? = nil,
        dynamicResultingTypeIds: Set<Int> = [],
        typeFilterContext: AssetTypeFilterContext = .inactive
    ) {
        self.parentNode = parentNode
        self.stationNameCache = stationNameCache
        self.solarSystemNameCache = solarSystemNameCache
        self.dynamicResultingTypeIds = dynamicResultingTypeIds
        self.typeFilterContext = typeFilterContext

        let parentInfo = ItemInfoMap.typeInfo(for: parentNode.type_id)
        let ship = parentInfo?.categoryID == 6
        containerCapacity = parentInfo?.capacity ?? 0
        isShip = ship
        contentVolume = (parentNode.items ?? []).reduce(0) { sum, item in
            if ship && item.location_flag != "Cargo" {
                return sum
            }
            let info = ItemInfoMap.typeInfo(for: item.type_id)
            let volume =
                item.is_singleton
                    ? (info?.volume ?? 0)
                    : (info?.repackagedVolume ?? info?.volume ?? 0)
            return sum + volume * Double(item.quantity)
        }

        _viewModel = StateObject(
            wrappedValue: LocationAssetsViewModel(
                location: parentNode, preloadedItemInfo: preloadedItemInfo,
                dynamicResultingTypeIds: dynamicResultingTypeIds,
                typeFilterContext: typeFilterContext
            )
        )
    }

    var body: some View {
        List {
            if parentNode.items != nil {
                // 容器本身的信息
                containerInfoSection

                // 容器内的物品
                ForEach(viewModel.groupedSections, id: \.flag) { group in
                    containerContentSection(for: group)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(getContainerTypeName())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isExportableFittedShip {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showExportConfirm = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel(Text(NSLocalizedString("Assets_Export_Fitting", comment: "")))
                }
            }
        }
        .alert(
            NSLocalizedString("Assets_Export_Fitting_Confirm_Title", comment: ""),
            isPresented: $showExportConfirm,
            actions: {
                Button(NSLocalizedString("Common_Confirm", comment: "")) {
                    exportFittingToSimulator()
                }
                Button(NSLocalizedString("Common_Cancel", comment: ""), role: .cancel) {}
            },
            message: {
                Text(
                    String(
                        format: NSLocalizedString("Assets_Export_Fitting_Confirm_Message", comment: ""),
                        getContainerTypeName()
                    )
                )
            }
        )
        .alert(
            NSLocalizedString("Assets_Export_Fitting_Alert_Title", comment: ""),
            isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { if !$0 { exportErrorMessage = nil } }
            ),
            actions: {
                Button(NSLocalizedString("OK", comment: ""), role: .cancel) { exportErrorMessage = nil }
            },
            message: {
                Text(exportErrorMessage ?? "")
            }
        )
        .alert(
            NSLocalizedString("Assets_Export_Fitting_Success_Prompt_Title", comment: ""),
            isPresented: $showExportSuccessPrompt,
            actions: {
                Button(NSLocalizedString("Assets_Export_Fitting_View_Yes", comment: "")) {
                    if let lastId = exportSuccessFittingId {
                        savedFittingSheetItem = SavedFittingSheetItem(fittingId: lastId)
                    }
                    exportSuccessFittingId = nil
                }
                Button(
                    NSLocalizedString("Assets_Export_Fitting_View_Later", comment: ""),
                    role: .cancel
                ) {
                    exportSuccessFittingId = nil
                }
            },
            message: {
                Text(NSLocalizedString("Assets_Export_Fitting_Success_Ask_View", comment: ""))
            }
        )
        .sheet(item: $savedFittingSheetItem) { item in
            NavigationStack {
                ShipFittingView(fittingId: item.fittingId, databaseManager: viewModel.databaseManager)
            }
        }
        .task {
            await viewModel.loadItemInfo()
            isExportableFittedShip = AssetShipFittingExport.isExportableFittedShip(
                parentNode: parentNode,
                databaseManager: viewModel.databaseManager
            )
        }
    }

    private func exportFittingToSimulator() {
        let displayName =
            viewModel.itemInfo(for: parentNode.type_id)?.name
                ?? HTMLUtils.decodeHTMLEntities(parentNode.name ?? "")
        let name = displayName.isEmpty ? String(parentNode.type_id) : displayName
        do {
            let fittingId = try AssetShipFittingExport.exportToLocalFitting(
                parentNode: parentNode,
                databaseManager: viewModel.databaseManager,
                displayName: name
            )
            exportSuccessFittingId = fittingId
            showExportSuccessPrompt = true
        } catch {
            Logger.error("资产导出装配失败: \(error)")
            exportErrorMessage = String(
                format: NSLocalizedString("Assets_Export_Fitting_Error_Format", comment: ""),
                error.localizedDescription
            )
        }
    }

    /// 容器类型名称（用于导航标题）
    private func getContainerTypeName() -> String {
        viewModel.itemInfo(for: parentNode.type_id)?.name ?? String(parentNode.type_id)
    }

    /// 容器信息部分（深渊变异产物跳转深渊详情，其余跳转市场）
    private var containerInfoSection: some View {
        let isDynamic = dynamicResultingTypeIds.contains(parentNode.type_id)
        return Section {
            NavigationLink {
                if isDynamic {
                    DynamicItemDetailView(
                        typeId: parentNode.type_id,
                        itemId: parentNode.item_id,
                        itemName: viewModel.itemInfo(for: parentNode.type_id)?.name ?? ""
                    )
                } else {
                    MarketItemDetailView(
                        databaseManager: viewModel.databaseManager, itemID: parentNode.type_id
                    )
                }
            } label: {
                ContainerInfoRow(
                    node: parentNode,
                    itemInfo: viewModel.itemInfo(for: parentNode.type_id),
                    showItemId: isDynamic
                )
            }

            ContainerVolumeRow(
                capacity: containerCapacity,
                contentVolume: contentVolume
            )
        } header: {
            Text(NSLocalizedString("Container_Basic_Info", comment: ""))
                .fontWeight(.semibold)
                .font(.system(size: 18))
                .foregroundColor(.primary)
                .textCase(.none)
        }
    }

    /// 容器内容部分
    private func containerContentSection(for group: (flag: String, items: [AssetTreeNode]))
        -> some View
    {
        Section(
            header: Text(formatLocationFlag(group.flag))
                .fontWeight(.semibold)
                .font(.system(size: 18))
                .foregroundColor(.primary)
                .textCase(.none)
        ) {
            ForEach(group.items, id: \.item_id) { node in
                containerItemRow(for: node)
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
    }

    /// 容器内物品行（深渊变异产物跳转深渊详情，其余跳转市场）
    @ViewBuilder
    private func containerItemRow(for node: AssetTreeNode) -> some View {
        if let subitems = node.items, !subitems.isEmpty {
            // 子容器
            NavigationLink {
                SubLocationAssetsView(
                    parentNode: node,
                    preloadedItemInfo: viewModel.preloadedItemInfo,
                    stationNameCache: stationNameCache,
                    solarSystemNameCache: solarSystemNameCache,
                    dynamicResultingTypeIds: dynamicResultingTypeIds,
                    typeFilterContext: typeFilterContext.containerContext(for: node)
                )
            } label: {
                AssetItemView(
                    node: node,
                    itemInfo: viewModel.itemInfo(for: node.type_id),
                    typeCount: typeFilterContext.matchingTypeCount(in: node)
                )
            }
        } else if dynamicResultingTypeIds.contains(node.type_id) {
            // 深渊变异产物，跳转深渊详情
            NavigationLink {
                DynamicItemDetailView(
                    typeId: node.type_id,
                    itemId: node.item_id,
                    itemName: viewModel.itemInfo(for: node.type_id)?.name ?? ""
                )
            } label: {
                AssetItemView(node: node, itemInfo: viewModel.itemInfo(for: node.type_id), showItemId: true)
            }
        } else {
            // 普通物品
            NavigationLink {
                MarketItemDetailView(
                    databaseManager: viewModel.databaseManager, itemID: node.type_id
                )
            } label: {
                AssetItemView(node: node, itemInfo: viewModel.itemInfo(for: node.type_id))
            }
        }
    }
}

/// LocationAssetsViewModel
class LocationAssetsViewModel: ObservableObject {
    private let location: AssetTreeNode
    private var itemInfoCache: [Int: ItemInfo] = [:]
    let databaseManager: DatabaseManager

    @Published private(set) var groupedSections: [(flag: String, items: [AssetTreeNode])] = []

    /// 添加一个标志来跟踪是否正在加载
    private var isLoadingItems = false

    let preloadedItemInfo: [Int: ItemInfo]?

    /// 深渊变异产物 type_id 集合，不可合并、不可跳转市场
    let dynamicResultingTypeIds: Set<Int>
    private let typeFilterContext: AssetTypeFilterContext

    /// 优先显示的货物集装箱的 marketGroupID 列表
    private let priorityMarketGroups = [1651, 1652, 1653, 1657, 1658]
    /// 对应 type_id 集合，只查一次数据库后缓存
    private var cachedPriorityContainerTypeIds: Set<Int>?

    init(
        location: AssetTreeNode, databaseManager: DatabaseManager = DatabaseManager(),
        preloadedItemInfo: [Int: ItemInfo]? = nil,
        dynamicResultingTypeIds: Set<Int> = [],
        typeFilterContext: AssetTypeFilterContext = .inactive
    ) {
        self.location = location
        self.databaseManager = databaseManager
        self.preloadedItemInfo = preloadedItemInfo
        self.dynamicResultingTypeIds = dynamicResultingTypeIds
        self.typeFilterContext = typeFilterContext
    }

    func itemInfo(for typeId: Int) -> ItemInfo? {
        // 从缓存中查找该类型的物品信息
        return itemInfoCache[typeId]
    }

    /// 优先容器 type_id 集合，首次访问时查库并缓存
    private var priorityContainerTypeIds: Set<Int> {
        if let cached = cachedPriorityContainerTypeIds { return cached }
        let groups = Set(priorityMarketGroups)
        var typeIds = Set<Int>()
        for (typeId, info) in SDEMemoryStore.types {
            if let mg = info.marketGroupID, groups.contains(mg) {
                typeIds.insert(typeId)
            }
        }
        cachedPriorityContainerTypeIds = typeIds
        return typeIds
    }

    /// 按location_flag分组的资产（结果缓存在 groupedSections）
    private func rebuildGroupedSections() {
        let rawItems = location.items ?? []
        let items = typeFilterContext.filterNodesForDisplay(rawItems)
        if items.isEmpty {
            groupedSections = []
            return
        }

        // 获取优先显示的容器类型ID集合（带缓存，避免每次 groupedAssets 都查库）
        let priorityTypeIds = priorityContainerTypeIds

        var groups: [String: [AssetTreeNode]] = [:]

        // 第一步：按flag分组
        for item in items {
            let flag = normalizedAssetLocationFlag(item.location_flag)
            if groups[flag] == nil {
                groups[flag] = []
            }
            groups[flag]?.append(item)
        }

        // 第二步：在每个分组内处理物品
        var mergedGroups: [String: [AssetTreeNode]] = [:]
        for (flag, items) in groups {
            // 将物品分为容器和非容器两类
            let containers = items.filter { $0.items != nil && !$0.items!.isEmpty }
            let normalItems = items.filter { $0.items == nil || $0.items!.isEmpty }

            // 将非容器物品分为：突变物品（不可合并）与普通物品（可按 type_id 合并）
            let dynamicItems = normalItems.filter { dynamicResultingTypeIds.contains($0.type_id) }
            let mergableItems = normalItems.filter { !dynamicResultingTypeIds.contains($0.type_id) }

            // 突变物品按 item_id 排序，逐个展示
            let sortedDynamicItems = dynamicItems.sorted { $0.item_id < $1.item_id }

            // 处理可合并的普通物品：按type_id分组并合并
            var typeGroups: [Int: [AssetTreeNode]] = [:]
            for item in mergableItems {
                if typeGroups[item.type_id] == nil {
                    typeGroups[item.type_id] = []
                }
                typeGroups[item.type_id]?.append(item)
            }

            // 合并相同类型的非容器物品
            var mergedNormalItems: [AssetTreeNode] = []
            for items in typeGroups.values {
                if items.count == 1 {
                    mergedNormalItems.append(items[0])
                } else {
                    // 对相同type_id的物品按item_id排序
                    let sortedItems = items.sorted { $0.item_id < $1.item_id }
                    let firstItem = sortedItems[0]
                    let totalQuantity = sortedItems.reduce(0) { $0 + $1.quantity }
                    let mergedItem = AssetTreeNode(
                        location_id: firstItem.location_id,
                        item_id: firstItem.item_id,
                        type_id: firstItem.type_id,
                        location_type: firstItem.location_type,
                        location_flag: firstItem.location_flag,
                        quantity: totalQuantity,
                        name: firstItem.name,
                        is_singleton: false,
                        is_blueprint_copy: firstItem.is_blueprint_copy,
                        system_id: firstItem.system_id,
                        region_id: firstItem.region_id,
                        security_status: firstItem.security_status
                    )
                    mergedNormalItems.append(mergedItem)
                }
            }

            // 直接使用预先获取的type_id集合来确定优先容器
            let priorityContainers = containers.filter { priorityTypeIds.contains($0.type_id) }
            let normalContainers = containers.filter { !priorityTypeIds.contains($0.type_id) }

            // 分别对优先容器和普通容器进行排序
            let sortedPriorityContainers = priorityContainers.sorted { item1, item2 in
                let name1 = itemInfo(for: item1.type_id)?.name ?? ""
                let name2 = itemInfo(for: item2.type_id)?.name ?? ""
                if name1 != name2 {
                    return name1.localizedCompare(name2) == .orderedAscending
                }
                return item1.item_id < item2.item_id
            }

            let sortedNormalContainers = normalContainers.sorted { item1, item2 in
                let name1 = itemInfo(for: item1.type_id)?.name ?? ""
                let name2 = itemInfo(for: item2.type_id)?.name ?? ""
                if name1 != name2 {
                    return name1.localizedCompare(name2) == .orderedAscending
                }
                return item1.item_id < item2.item_id
            }

            // 再对普通物品按名称排序
            let sortedNormalItems = mergedNormalItems.sorted { item1, item2 in
                let name1 = itemInfo(for: item1.type_id)?.name ?? ""
                let name2 = itemInfo(for: item2.type_id)?.name ?? ""
                if name1 != name2 {
                    return name1.localizedCompare(name2) == .orderedAscending
                }
                return item1.item_id < item2.item_id
            }

            // 优先容器 + 普通容器 + 突变物品（按item_id） + 普通物品
            let allItems = sortedPriorityContainers + sortedNormalContainers + sortedDynamicItems + sortedNormalItems
            mergedGroups[flag] = allItems
        }

        // 第三步：按预定义顺序排序
        let result = flagOrder.compactMap { flag in
            if let items = mergedGroups[flag], !items.isEmpty {
                return (flag: flag, items: items)
            }
            return nil
        }

        // 如果没有预定义的分组，添加剩余的分组
        let remainingGroups = mergedGroups.filter { !flagOrder.contains($0.key) }
        let remainingResult = remainingGroups.map { (flag: $0.key, items: $0.value) }
            .sorted { $0.flag < $1.flag }

        groupedSections = result + remainingResult
    }

    private let flagOrder = [
        "HiSlots", "MedSlots", "LoSlots", "RigSlots", "SubSystemSlots",
        "FighterBay", "FighterTubes", "DroneBay", "Cargo", "Hangar", "ShipHangar", "FleetHangar",
        "CorpSAG1", "CorpSAG2", "CorpSAG3", "CorpSAG4", "CorpSAG5", "CorpSAG6", "CorpSAG7",
        "CorpDeliveries", "Deliveries", "SpecializedAmmoHold", "SpecializedCommandCenterHold",
        "SpecializedFuelBay",
        "SpecializedGasHold", "SpecializedIndustrialShipHold", "SpecializedLargeShipHold",
        "SpecializedMaterialBay", "SpecializedMediumShipHold", "SpecializedMineralHold",
        "SpecializedOreHold", "SpecializedPlanetaryCommoditiesHold", "SpecializedSalvageHold",
        "SpecializedShipHold", "SpecializedSmallShipHold",
    ]

    @MainActor
    func loadItemInfo() async {
        // 如果已经在加载中，直接返回
        guard !isLoadingItems else {
            return
        }

        // 设置加载标志
        isLoadingItems = true

        // 如果有预加载的物品信息，直接使用
        if let preloadedInfo = preloadedItemInfo {
            itemInfoCache = preloadedInfo
            rebuildGroupedSections()
            isLoadingItems = false
            return
        }

        // 收集需要查询的type_id和已有的图标
        var typeIds = Set<Int>()
        var typeIdToNodes: [Int: [AssetTreeNode]] = [:]

        // 添加当前位置节点
        collectNode(location, typeIds: &typeIds, typeIdToNodes: &typeIdToNodes)

        // 处理子项
        if let items = location.items {
            for item in items {
                collectNode(item, typeIds: &typeIds, typeIdToNodes: &typeIdToNodes)
            }
        }

        // 查询所有物品的名称
        if !typeIds.isEmpty {
            for typeId in typeIds {
                guard let info = SDEMemoryStore.type(for: typeId) else { continue }
                if typeIdToNodes[typeId] != nil {
                    itemInfoCache[typeId] = ItemInfo(from: info)
                }
            }
            rebuildGroupedSections()
        }

        isLoadingItems = false
    }

    /// 收集节点信息的辅助方法
    private func collectNode(
        _ node: AssetTreeNode, typeIds: inout Set<Int>, typeIdToNodes: inout [Int: [AssetTreeNode]]
    ) {
        let typeId = node.type_id
        typeIds.insert(typeId)

        if typeIdToNodes[typeId] == nil {
            typeIdToNodes[typeId] = []
        }
        typeIdToNodes[typeId]?.append(node)
    }
}

// MARK: - 合并模式下的地点详情视图

/// 合并模式地点详情：人物列表 section，点击跳转到该人物的资产目录
struct MergedLocationAssetsView: View {
    let merged: MergedAssetLocation
    let itemInfoCache: [Int: ItemInfo]
    let stationNameCache: [Int64: String]
    let solarSystemNameCache: [Int: String]
    let dynamicResultingTypeIds: Set<Int>
    let ownerName: (Int) -> String?
    let ownerPortrait: (Int) -> UIImage?
    let typeFilterContext: AssetTypeFilterContext

    var body: some View {
        List {
            // 地点信息
            Section {
                AssetLocationRowContent(
                    location: merged.representativeLocation,
                    stationNameCache: stationNameCache,
                    solarSystemNameCache: solarSystemNameCache,
                    showItemCount: false
                )
            } header: {
                Text(NSLocalizedString("ESI_Tag_Location", comment: ""))
                    .fontWeight(.semibold)
                    .font(.system(size: 18))
                    .foregroundColor(.primary)
                    .textCase(.none)
            }

            // 人物列表：点击跳转到该人物的资产目录
            Section {
                ForEach(merged.entries, id: \.id) { entry in
                    NavigationLink {
                        LocationAssetsView(
                            location: entry.location,
                            preloadedItemInfo: itemInfoCache,
                            stationNameCache: stationNameCache,
                            solarSystemNameCache: solarSystemNameCache,
                            dynamicResultingTypeIds: dynamicResultingTypeIds,
                            showOwner: true,
                            ownerId: entry.ownerId,
                            ownerName: ownerName(entry.ownerId),
                            ownerPortrait: ownerPortrait(entry.ownerId),
                            typeFilterContext: typeFilterContext
                        )
                    } label: {
                        HStack(spacing: 8) {
                            if let portrait = ownerPortrait(entry.ownerId) {
                                AssetIconView(uiImage: portrait, size: CharacterAssetsIconSize.standard)
                            } else {
                                AssetIconView(
                                    iconName: IconManager.defaultItemIcon,
                                    size: CharacterAssetsIconSize.standard
                                )
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ownerName(entry.ownerId) ?? String(entry.ownerId))
                                    .foregroundColor(.primary)
                                let typeCount = typeFilterContext.matchingTypeCount(
                                    in: entry.location
                                )
                                if typeCount > 0 {
                                    Text(
                                        String(
                                            format: NSLocalizedString(
                                                "Assets_Item_Summary_Format", comment: ""
                                            ),
                                            typeCount
                                        )
                                    )
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            } header: {
                Text(NSLocalizedString("Assets_Characters_At_Location", comment: ""))
                    .fontWeight(.semibold)
                    .font(.system(size: 18))
                    .foregroundColor(.primary)
                    .textCase(.none)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Main_Assets", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }
}
