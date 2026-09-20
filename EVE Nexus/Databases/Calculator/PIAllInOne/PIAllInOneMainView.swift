import SwiftUI

struct PIAllInOneMainView: View {
    let characterId: Int?

    @State private var selectedSystemID: Int?
    @State private var selectedSystemName: String?
    @State private var isLoading = false
    @State private var showSystemSelector = false
    @State private var singlePlanetProducts: [AllInOneSinglePlanetProductResult] = []
    @State private var systemPlanetCounts: [String: Int] = [:]

    /// 单星球分析器
    private let singlePlanetAnalyzer = SinglePlanetProductAnalyzer()

    var body: some View {
        List {
            // 星系选择器
            Section(header: Text(NSLocalizedString("System_Search_Title", comment: "选择星系"))) {
                Button(action: {
                    showSystemSelector = true
                }) {
                    HStack {
                        Text(NSLocalizedString("System_Search_Title", comment: "选择星系"))
                            .foregroundColor(.primary)
                        Spacer()
                        Text(
                            selectedSystemName?.isEmpty == false
                                ? selectedSystemName!
                                : NSLocalizedString("Main_Planetary_Not_Selected", comment: "未选择")
                        )
                        .foregroundColor(.gray)
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                    }
                }
            }

            // 加载状态指示器
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                            .scaleEffect(0.8)
                        Text(NSLocalizedString("Misc_Calculating", comment: ""))
                            .foregroundColor(.blue)
                            .padding(.leading, 8)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }

            // 功能描述（当没有选择星系或没有结果时显示）
            if selectedSystemID == nil && !isLoading {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(
                            NSLocalizedString(
                                "AllInOne_Calculator_Description_Title", comment: "单球生产计算器"
                            )
                        )
                        .font(.headline)
                        .foregroundColor(.primary)

                        Text(
                            NSLocalizedString(
                                "AllInOne_Calculator_Description_Text", comment: "功能描述"
                            )
                        )
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // 行星分布信息
            if selectedSystemID != nil && !isLoading {
                Section {
                    NavigationLink(
                        destination: AllInOnePlanetDistributionView(
                            systemId: selectedSystemID!,
                            systemName: selectedSystemName ?? "Unknown"
                        )
                    ) {
                        Text(NSLocalizedString("PI_Output_View_Planets", comment: "查看行星分布"))
                    }
                }
            }

            // 结果展示区域
            if !singlePlanetProducts.isEmpty {
                // 按产品等级分组显示（P4-P3-P2-P1顺序）
                ForEach([4, 3, 2, 1], id: \.self) { level in
                    if let products = groupedProducts[level], !products.isEmpty {
                        Section(
                            header: Text(
                                "P\(level) (\(products.count) \(NSLocalizedString("Types", comment: "")))"
                            )
                        ) {
                            ForEach(products, id: \.productId) { product in
                                AllInOneSinglePlanetProductRowView(
                                    product: product,
                                    systemPlanetCounts: systemPlanetCounts
                                )
                            }
                        }
                    }
                }
            } else if !isLoading && selectedSystemID != nil {
                // 没有结果时的提示
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.orange)

                        Text(
                            NSLocalizedString("All_in_One_No_Products_Found", comment: "没有找到单星球产品")
                        )
                        .font(.headline)

                        Text(
                            NSLocalizedString(
                                "All_in_One_No_Products_Description",
                                comment: "该星系中没有可以在单颗行星上完成完整生产链的产品"
                            )
                        )
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            }
        }
        .navigationTitle(NSLocalizedString("Planet_All-in-One_Calc", comment: ""))
        .sheet(isPresented: $showSystemSelector) {
            SystemPickerSheet(
                title: NSLocalizedString("System_Search_Title", comment: "选择星系"),
                currentSelection: selectedSystemID,
                showsSovereignty: true,
                onSelect: { systemId, systemName in
                    selectedSystemID = systemId
                    selectedSystemName = systemName
                    showSystemSelector = false
                    // 选择星系后自动开始计算
                    calculateSinglePlanetProducts()
                },
                onCancel: {
                    showSystemSelector = false
                }
            )
        }
    }

    /// 按产品等级分组
    private var groupedProducts: [Int: [AllInOneSinglePlanetProductResult]] {
        Dictionary(grouping: singlePlanetProducts) { $0.productLevel }
    }

    /// 计算单星球产品
    private func calculateSinglePlanetProducts() {
        guard let systemId = selectedSystemID else { return }

        isLoading = true
        singlePlanetProducts.removeAll()
        systemPlanetCounts.removeAll()

        DispatchQueue.global(qos: .userInitiated).async {
            // 获取该星系的单星球产品
            let allProducts = singlePlanetAnalyzer.getAllSinglePlanetProducts()

            // 筛选该星系支持的单星球产品
            var supportedProducts: [AllInOneSinglePlanetProductResult] = []
            var systemPlanetCountsTemp: [String: Int] = [:]

            // 内存索引查询该星系的行星数量
            if let systemInfo = SDEMemoryStore.universeSystems[systemId] {
                // 遍历所有单星球产品，检查该星系是否能支持
                for product in allProducts {
                    var canSupport = false
                    var totalPlanetCount = 0

                    // 检查每个兼容的行星类型
                    for planetType in product.compatiblePlanetTypes {
                        if let columnName = PlanetaryUtils.planetTypeToColumn[planetType.typeId] {
                            let planetCount = systemInfo.planetCounts[columnName] ?? 0
                            if planetCount > 0 {
                                canSupport = true
                                totalPlanetCount += planetCount
                            }
                        }
                    }

                    if canSupport {
                        supportedProducts.append(product)
                        systemPlanetCountsTemp["\(product.productId)"] = totalPlanetCount
                    }
                }
            }

            // 按产品等级、可用行星数量和type_id排序（P4-P3-P2-P1顺序）
            supportedProducts.sort { lhs, rhs in
                if lhs.productLevel == rhs.productLevel {
                    // 同等级内，首先按可用行星总数量降序排序
                    let lhsTotalPlanetCount = systemPlanetCountsTemp["\(lhs.productId)"] ?? 0
                    let rhsTotalPlanetCount = systemPlanetCountsTemp["\(rhs.productId)"] ?? 0
                    if lhsTotalPlanetCount == rhsTotalPlanetCount {
                        // 可用行星总数量相同时，按type_id升序排序
                        return lhs.productId < rhs.productId
                    }
                    return lhsTotalPlanetCount > rhsTotalPlanetCount // 可用行星总数量多的优先
                }
                return lhs.productLevel > rhs.productLevel // 高等级优先
            }

            DispatchQueue.main.async {
                self.singlePlanetProducts = supportedProducts
                self.systemPlanetCounts = systemPlanetCountsTemp
                self.isLoading = false
            }
        }
    }
}

/// 单星球产品行视图
struct AllInOneSinglePlanetProductRowView: View {
    let product: AllInOneSinglePlanetProductResult
    let systemPlanetCounts: [String: Int]
    @State private var showItemDetail = false

    var body: some View {
        Button(action: {
            showItemDetail = true
        }) {
            HStack {
                // 产品图标
                Image(uiImage: IconManager.shared.loadUIImage(for: product.iconFileName))
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(4)

                VStack(alignment: .leading, spacing: 4) {
                    // 产品名称
                    Text(product.productName)
                        .font(.headline)
                        .foregroundColor(.primary)

                    // 支持的行星类型
                    Text(
                        String(
                            format: NSLocalizedString(
                                "All_in_One_Compatible_Planets", comment: "支持行星: %@"
                            ),
                            product.compatiblePlanetTypes.map { $0.name }.joined(separator: ", ")
                        )
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)

                    // 可用行星数量
                    if let count = systemPlanetCounts["\(product.productId)"] {
                        Text(
                            String(
                                format: NSLocalizedString(
                                    "All_in_One_Available_Planets", comment: "可用行星: %d 颗"
                                ), count
                            )
                        )
                        .font(.caption)
                        .foregroundColor(.green)
                        .fontWeight(.medium)
                    }
                }

                Spacer()

                // P等级标识
                Text("P\(product.productLevel)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(levelColor(for: product.productLevel))
                    .cornerRadius(4)

                // 箭头指示器
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.leading, 4)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showItemDetail) {
            NavigationView {
                ShowPlanetaryInfo(
                    itemID: product.productId,
                    databaseManager: DatabaseManager.shared
                )
            }
            .presentationDragIndicator(.visible)
        }
    }

    /// 根据产品等级返回颜色
    private func levelColor(for level: Int) -> Color {
        switch level {
        case 1: return .blue
        case 2: return .green
        case 3: return .orange
        case 4: return .red
        default: return .gray
        }
    }
}

/// 单星球产品结果模型
struct AllInOneSinglePlanetProductResult {
    let productId: Int
    let productName: String
    let productLevel: Int
    let iconFileName: String
    let compatiblePlanetTypes: [AllInOnePlanetTypeInfo]
    let requiredP0Resources: [AllInOneP0ResourceInfo]
}

/// All-in-One 行星类型信息
struct AllInOnePlanetTypeInfo: Hashable {
    let typeId: Int
    let name: String
    let iconFileName: String

    /// 实现 Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(typeId)
    }

    /// 实现 Equatable
    static func == (lhs: AllInOnePlanetTypeInfo, rhs: AllInOnePlanetTypeInfo) -> Bool {
        return lhs.typeId == rhs.typeId
    }
}

/// All-in-One P0资源信息
struct AllInOneP0ResourceInfo: Hashable {
    let resourceId: Int
    let resourceName: String
    let iconFileName: String

    /// 实现 Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(resourceId)
    }

    /// 实现 Equatable
    static func == (lhs: AllInOneP0ResourceInfo, rhs: AllInOneP0ResourceInfo) -> Bool {
        return lhs.resourceId == rhs.resourceId
    }
}

/// 单星球产品分析器
class SinglePlanetProductAnalyzer {
    private let databaseManager = DatabaseManager.shared

    // 缓存数据，避免重复查询
    private var cachedPlanetTypes: [Int: AllInOnePlanetTypeInfo]?
    private var cachedIconMap: [Int: String] = [:]
    private var cachedP0ResourceInfo: [Int: AllInOneP0ResourceInfo] = [:]
    private var cachedP0PlanetMapping: [Int: Set<Int>] = [:]

    func getAllSinglePlanetProducts() -> [AllInOneSinglePlanetProductResult] {
        // 预加载缓存数据
        preloadCacheData()

        // 使用PIResourceCache来获取所有P1-P4产品，与其他模块保持一致
        var products: [AllInOneSinglePlanetProductResult] = []

        guard let planetTypes = cachedPlanetTypes else { return products }

        // 遍历PIResourceCache中的所有资源
        for (typeId, resourceInfo) in PIResourceCache.shared.getAllResourceInfo() {
            // 只处理P1-P4级别的资源
            if let resourceLevel = PIResourceCache.shared.getResourceLevel(for: typeId),
               [PIResourceLevel.p1, .p2, .p3, .p4].contains(resourceLevel)
            {
                // 分析该产品是否可以单星球生产
                if let productInfo = analyzeProduct(
                    productId: typeId,
                    productName: resourceInfo.name,
                    productLevel: resourceLevel.rawValue,
                    planetTypes: planetTypes
                ) {
                    products.append(productInfo)
                }
            }
        }

        // 按产品等级和type_id排序（P4-P3-P2-P1顺序）
        // 注：在全局分析中，我们按type_id排序；在具体星系中，会按可用行星数量重新排序
        products.sort { lhs, rhs in
            if lhs.productLevel == rhs.productLevel {
                return lhs.productId < rhs.productId // 按type_id升序排序
            }
            return lhs.productLevel > rhs.productLevel // 高等级优先
        }

        return products
    }

    /// 预加载所有缓存数据
    private func preloadCacheData() {
        // 只加载一次
        if cachedPlanetTypes != nil {
            return
        }

        // 加载行星类型信息
        cachedPlanetTypes = getPlanetTypeInfo()

        // 预加载所有行星商品的图标
        preloadAllPlanetaryProductIcons()

        // 预加载所有P0资源信息和映射关系
        preloadP0ResourceData()
    }

    /// 预加载所有行星商品的图标
    private func preloadAllPlanetaryProductIcons() {
        // 获取所有行星商品的type_id (P0-P4)
        var allPlanetaryProductIds: Set<Int> = []

        // 从PIResourceCache中获取所有行星商品ID
        for (typeId, _) in PIResourceCache.shared.getAllResourceInfo() {
            allPlanetaryProductIds.insert(typeId)
        }

        // 添加行星类型ID
        if let planetTypes = cachedPlanetTypes {
            for planetTypeId in planetTypes.keys {
                allPlanetaryProductIds.insert(planetTypeId)
            }
        }

        // 批量查询所有图标
        if !allPlanetaryProductIds.isEmpty {
            for typeId in allPlanetaryProductIds {
                cachedIconMap[typeId] = ItemInfoMap.iconFilename(for: typeId)
            }
        }
    }

    /// 预加载P0资源数据
    private func preloadP0ResourceData() {
        // 获取所有P0资源ID
        let allP0ResourceIds = getAllP0ResourceIds()

        if !allP0ResourceIds.isEmpty {
            // 批量加载P0资源信息
            let p0ResourceInfos = getP0ResourceInfo(for: allP0ResourceIds)
            for resourceInfo in p0ResourceInfos {
                cachedP0ResourceInfo[resourceInfo.resourceId] = resourceInfo
            }

            // 批量加载P0资源与行星类型的映射关系
            let p0PlanetMapping = getP0PlanetMapping(for: allP0ResourceIds)
            for (resourceId, planetTypes) in p0PlanetMapping {
                cachedP0PlanetMapping[resourceId] = planetTypes
            }
        }
    }

    /// 获取所有P0资源ID
    private func getAllP0ResourceIds() -> [Int] {
        var allP0Ids: Set<Int> = []

        // 遍历所有P1-P4产品，收集它们需要的P0资源
        for (typeId, _) in PIResourceCache.shared.getAllResourceInfo() {
            if let resourceLevel = PIResourceCache.shared.getResourceLevel(for: typeId),
               [PIResourceLevel.p1, .p2, .p3, .p4].contains(resourceLevel)
            {
                let p0Resources = getRequiredP0ResourceIds(for: typeId)
                allP0Ids.formUnion(p0Resources)
            }
        }

        return Array(allP0Ids)
    }

    /// 获取产品需要的P0资源ID（不创建对象，只返回ID）
    private func getRequiredP0ResourceIds(for productId: Int) -> Set<Int> {
        var allP0Resources: Set<Int> = []
        var toProcess: [Int] = [productId]
        var processed: Set<Int> = []

        while !toProcess.isEmpty {
            let currentId = toProcess.removeFirst()
            if processed.contains(currentId) {
                continue
            }
            processed.insert(currentId)

            // 检查是否是P0资源
            if let resourceLevel = PIResourceCache.shared.getResourceLevel(for: currentId),
               resourceLevel == .p0
            {
                allP0Resources.insert(currentId)
                continue
            }

            // 获取配方信息
            if let schematic = PIResourceCache.shared.getSchematic(for: currentId) {
                for inputId in schematic.inputTypeIds {
                    if !processed.contains(inputId) {
                        toProcess.append(inputId)
                    }
                }
            }
        }

        return allP0Resources
    }

    private func getPlanetTypeInfo() -> [Int: AllInOnePlanetTypeInfo] {
        let planetTypeIds = Array(PlanetaryUtils.planetTypeToColumn.keys)
        var planetTypes: [Int: AllInOnePlanetTypeInfo] = [:]

        for typeId in planetTypeIds {
            guard let info = ItemInfoMap.typeInfo(for: typeId), !info.name.isEmpty else { continue }
            planetTypes[typeId] = AllInOnePlanetTypeInfo(
                typeId: typeId,
                name: info.name,
                iconFileName: info.iconFilename
            )
        }

        return planetTypes
    }

    private func analyzeProduct(
        productId: Int,
        productName: String,
        productLevel: Int,
        planetTypes: [Int: AllInOnePlanetTypeInfo]
    ) -> AllInOneSinglePlanetProductResult? {
        // 递归追踪到P0资源
        let requiredP0Resources = getRequiredP0Resources(for: productId)
        guard !requiredP0Resources.isEmpty else { return nil }

        // 从缓存获取P0资源的行星类型映射
        let p0PlanetMapping = getCachedP0PlanetMapping(
            for: requiredP0Resources.map { $0.resourceId }
        )

        // 找到能提供所有P0资源的行星类型
        var compatiblePlanetTypes: Set<Int> = Set(planetTypes.keys)

        for p0ResourceId in requiredP0Resources.map({ $0.resourceId }) {
            if let planetTypesForResource = p0PlanetMapping[p0ResourceId] {
                compatiblePlanetTypes = compatiblePlanetTypes.intersection(planetTypesForResource)
            } else {
                // 如果找不到某个P0资源的行星类型，说明无法单星球生产
                return nil
            }
        }

        // 如果没有行星类型能提供所有P0资源，则无法单星球生产
        guard !compatiblePlanetTypes.isEmpty else { return nil }

        // 转换为PlanetTypeInfo数组
        let compatiblePlanetTypeInfos = compatiblePlanetTypes.compactMap { planetTypes[$0] }

        return AllInOneSinglePlanetProductResult(
            productId: productId,
            productName: productName,
            productLevel: productLevel,
            iconFileName: getIconFileName(for: productId),
            compatiblePlanetTypes: compatiblePlanetTypeInfos,
            requiredP0Resources: requiredP0Resources
        )
    }

    private func getRequiredP0Resources(for productId: Int) -> [AllInOneP0ResourceInfo] {
        // 获取P0资源ID
        let p0ResourceIds = getRequiredP0ResourceIds(for: productId)

        // 从缓存中获取P0资源信息
        var result: [AllInOneP0ResourceInfo] = []
        for resourceId in p0ResourceIds {
            if let resourceInfo = cachedP0ResourceInfo[resourceId] {
                result.append(resourceInfo)
            }
        }

        return result
    }

    private func getP0ResourceInfo(for resourceIds: [Int]) -> [AllInOneP0ResourceInfo] {
        guard !resourceIds.isEmpty else { return [] }

        var resources: [AllInOneP0ResourceInfo] = []
        for typeId in resourceIds {
            guard let name = ItemInfoMap.typeName(for: typeId) else { continue }
            resources.append(
                AllInOneP0ResourceInfo(
                    resourceId: typeId,
                    resourceName: name,
                    iconFileName: getIconFileName(for: typeId)
                )
            )
        }
        return resources
    }

    private func getP0PlanetMapping(for resourceIds: [Int]) -> [Int: Set<Int>] {
        // 使用现有的PlanetaryResourceCalculator来获取P0资源与行星类型的映射
        // 这与PI_output_calc和PI_site_finder模块保持一致
        let resourceCalculator = PlanetaryResourceCalculator(databaseManager: databaseManager)
        let resourcePlanets = resourceCalculator.findResourcePlanets(for: resourceIds)

        var mapping: [Int: Set<Int>] = [:]

        for result in resourcePlanets {
            mapping[result.resourceId] = Set(result.availablePlanets.map { $0.id })
        }

        return mapping
    }

    /// 从缓存获取P0资源与行星类型的映射
    private func getCachedP0PlanetMapping(for resourceIds: [Int]) -> [Int: Set<Int>] {
        var result: [Int: Set<Int>] = [:]
        for resourceId in resourceIds {
            if let planetTypes = cachedP0PlanetMapping[resourceId] {
                result[resourceId] = planetTypes
            }
        }
        return result
    }

    private func getIconFileName(for typeId: Int) -> String {
        // 所有图标都已经在预加载时缓存了，直接从缓存中获取
        return cachedIconMap[typeId] ?? "not_found"
    }
}

/// All-in-One 行星分布视图
struct AllInOnePlanetDistributionView: View {
    let systemId: Int
    let systemName: String
    @State private var planetTypeSummary:
        [(typeId: Int, name: String, count: Int, iconFileName: String)] = []
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Text(NSLocalizedString("Misc_Loading", comment: ""))
                        .foregroundColor(.gray)
                        .padding(.leading, 8)
                    Spacer()
                }
            } else if planetTypeSummary.isEmpty {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.orange)

                        Text(NSLocalizedString("All_in_One_No_Planets_Found", comment: "没有找到行星"))
                            .font(.headline)

                        Text(
                            NSLocalizedString(
                                "All_in_One_No_Planets_Description", comment: "该星系中没有行星数据"
                            )
                        )
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            } else {
                Section(
                    header: Text(
                        NSLocalizedString("All_in_One_Planet_Type_Distribution", comment: "行星类型分布")
                    )
                ) {
                    ForEach(planetTypeSummary, id: \.typeId) { planet in
                        HStack {
                            Image(uiImage: IconManager.shared.loadUIImage(for: planet.iconFileName))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 32, height: 32)
                                .cornerRadius(4)

                            Text(planet.name)
                                .font(.body)

                            Spacer()

                            Text(
                                "\(String.localizedStringWithFormat(NSLocalizedString("Planetary_Resource_Planet_Count", comment: ""), "\(planet.count)"))"
                            )
                            .foregroundColor(.secondary)
                            .font(.body)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("PI_Output_Planet_Distribution", comment: ""))
        .onAppear {
            loadPlanetTypeSummary()
        }
    }

    private func loadPlanetTypeSummary() {
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async {
            // 内存索引查询该星系的行星数量
            if let systemInfo = SDEMemoryStore.universeSystems[systemId] {
                // 获取行星类型名称
                var typeIdToName: [Int: (name: String, iconFileName: String)] = [:]
                for typeId in PlanetaryUtils.planetTypeToColumn.keys {
                    guard let info = ItemInfoMap.typeInfo(for: typeId), !info.name.isEmpty else { continue }
                    typeIdToName[typeId] = (name: info.name, iconFileName: info.iconFilename)
                }

                // 收集行星总数
                var summary: [(typeId: Int, name: String, count: Int, iconFileName: String)] = []

                for (typeId, columnName) in PlanetaryUtils.planetTypeToColumn {
                    if let count = systemInfo.planetCounts[columnName],
                       count > 0,
                       let typeInfo = typeIdToName[typeId]
                    {
                        summary.append(
                            (
                                typeId: typeId,
                                name: typeInfo.name,
                                count: count,
                                iconFileName: typeInfo.iconFileName
                            )
                        )
                    }
                }

                // 按行星数量降序排序
                summary.sort { $0.count > $1.count }

                DispatchQueue.main.async {
                    planetTypeSummary = summary
                    isLoading = false
                }
            } else {
                DispatchQueue.main.async {
                    isLoading = false
                }
            }
        }
    }
}
