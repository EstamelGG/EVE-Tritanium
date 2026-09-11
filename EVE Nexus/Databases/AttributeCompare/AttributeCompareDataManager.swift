import Foundation

// MARK: - 市场分组策略

/// 属性对比可选物品的顶级市场分组范围（与 `AttributeItemSelectorView` / `MarketItemSelectorIntegratedView` 一致）
enum AttributeCompareMarketPolicy {
    static let allowedTopMarketGroupIDs: Set<Int> = [4, 9, 157, 11, 477, 2202, 2203, 24, 955]

    /// 允许属性对比/快速比对的全部市场目录 ID（顶级白名单及其所有子孙组）
    /// 首次访问时从 SDE 一次性展开并缓存；SDE 更新后需调用 `reload()` 重置
    private static let lock = NSLock()
    private static var cache: Set<Int>?

    static var eligibleMarketGroupIDs: Set<Int> {
        lock.lock()
        if let cached = cache {
            lock.unlock()
            return cached
        }
        let computed = computeEligible()
        cache = computed
        lock.unlock()
        return computed
    }

    /// SDE 更新后重置缓存，下次访问时重新从 SDE 展开
    static func reload() {
        lock.lock()
        cache = nil
        lock.unlock()
    }

    private static func computeEligible() -> Set<Int> {
        let tree = MarketManager.shared.buildTree(
            from: MarketManager.shared.loadMarketGroups(databaseManager: .shared)
        )
        return Set(tree.allSubGroupIDs(fromRoots: allowedTopMarketGroupIDs))
    }
}

// MARK: - 数据模型

/// 属性对比列表项目
struct AttributeCompare: Identifiable, Codable {
    let id: UUID
    var name: String
    var items: [AttributeCompareItem]
    var lastUpdated: Date

    init(
        id: UUID = UUID(), name: String, items: [AttributeCompareItem] = []
    ) {
        self.id = id
        self.name = name
        self.items = items
        lastUpdated = Date()
    }
}

struct AttributeCompareItem: Codable, Equatable {
    let typeID: Int
}

// MARK: - 文件存储

/// 管理属性对比列表的文件存储
class AttributeCompareManager {
    static let shared = AttributeCompareManager()

    /// 手动拖动排序的 UserDefaults key（存储 UUID 字符串数组）
    private static let manualOrderKey = "AttributeCompareManualOrder"

    private init() {
        createCompareDirectory()
    }

    private var compareDirectory: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("AttributeCompares", isDirectory: true)
    }

    private func createCompareDirectory() {
        do {
            try FileManager.default.createDirectory(
                at: compareDirectory, withIntermediateDirectories: true
            )
        } catch {
            Logger.error("创建属性对比列表目录失败: \(error)")
        }
    }

    func saveCompare(_ compare: AttributeCompare) {
        let fileName = "attribute_compare_\(compare.id).json"
        let fileURL = compareDirectory.appendingPathComponent(fileName)

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .formatted(DateFormatter.iso8601Full)
            let data = try encoder.encode(compare)
            try data.write(to: fileURL)
            Logger.debug("保存属性对比列表成功: \(fileName)")
        } catch {
            Logger.error("保存属性对比列表失败: \(error)")
        }
    }

    func loadCompares() -> [AttributeCompare] {
        let fileManager = FileManager.default

        do {
            Logger.debug("开始加载属性对比列表")
            let files = try fileManager.contentsOfDirectory(
                at: compareDirectory, includingPropertiesForKeys: nil
            )
            Logger.debug("找到文件数量: \(files.count)")

            let compares = files.filter { url in
                url.lastPathComponent.hasPrefix("attribute_compare_") && url.pathExtension == "json"
            }
            .compactMap { url -> AttributeCompare? in
                do {
                    Logger.debug("尝试解析文件: \(url.lastPathComponent)")
                    let data = try Data(contentsOf: url)

                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .formatted(DateFormatter.iso8601Full)
                    return try decoder.decode(AttributeCompare.self, from: data)
                } catch {
                    Logger.error("读取属性对比列表失败: \(error)")
                    try? FileManager.default.removeItem(at: url)
                    return nil
                }
            }
            .sorted { $0.lastUpdated < $1.lastUpdated }

            let ordered = applyingManualOrder(to: compares)
            Logger.success("成功加载属性对比列表数量: \(ordered.count)")
            return ordered

        } catch {
            Logger.error("读取属性对比列表目录失败: \(error)")
            return []
        }
    }

    /// 保存手动拖动排序
    func saveManualOrder(_ compares: [AttributeCompare]) {
        UserDefaults.standard.set(
            compares.map(\.id.uuidString), forKey: Self.manualOrderKey
        )
    }

    /// 应用手动排序：已记录顺序的按记录排，未记录的（新列表）按更新时间升序追加在末尾
    private func applyingManualOrder(to compares: [AttributeCompare]) -> [AttributeCompare] {
        let savedOrder = UserDefaults.standard.stringArray(forKey: Self.manualOrderKey) ?? []
        var rank: [String: Int] = [:]
        for (index, id) in savedOrder.enumerated() where rank[id] == nil {
            rank[id] = index
        }

        let known = compares
            .filter { rank[$0.id.uuidString] != nil }
            .sorted { rank[$0.id.uuidString]! < rank[$1.id.uuidString]! }
        let unknown = compares
            .filter { rank[$0.id.uuidString] == nil }
            .sorted { $0.lastUpdated < $1.lastUpdated }
        return known + unknown
    }

    func deleteCompare(_ compare: AttributeCompare) {
        let fileName = "attribute_compare_\(compare.id).json"
        let fileURL = compareDirectory.appendingPathComponent(fileName)

        do {
            try FileManager.default.removeItem(at: fileURL)
            Logger.debug("删除属性对比列表成功: \(fileName)")
        } catch {
            Logger.error("删除属性对比列表失败: \(error)")
        }

        // 同步清理手动排序记录
        var order = UserDefaults.standard.stringArray(forKey: Self.manualOrderKey) ?? []
        order.removeAll { $0 == compare.id.uuidString }
        UserDefaults.standard.set(order, forKey: Self.manualOrderKey)
    }
}

// MARK: - 属性对比工具

/// 属性对比功能实用工具
enum AttributeCompareUtil {
    /// 所有用于JSON序列化的结构都必须遵循Codable
    struct AttributeValueInfo: Codable {
        let value: Double
        let unitID: Int?
    }

    /// 完整的对比结果结构，全部基于Codable
    struct CompareResult: Codable {
        /// 属性对比数据 - 格式: [attributeID: [typeID: {value, unitID}]]
        let compareResult: [String: [String: AttributeValueInfo]]

        /// 物品名称信息 - 格式: [typeID: name]
        let typeInfo: [String: String]

        /// 已发布属性名称信息 - 格式: [attributeID: display_name]
        let publishedAttributeInfo: [String: String]

        /// 属性图标信息 - 格式: [attributeID: iconFileName]
        let attributeIcons: [String: String]

        /// 属性的highIsGood信息 - 格式: [attributeID: highIsGood]
        let attributeHighIsGood: [String: Bool]

        /// 编码键名映射
        enum CodingKeys: String, CodingKey {
            case compareResult = "compare_result"
            case typeInfo = "type_info"
            case publishedAttributeInfo = "published_attribute_info"
            case attributeIcons = "attribute_icons"
            case attributeHighIsGood = "attribute_high_is_good"
        }
    }

    // MARK: - 共享辅助方法

    /// 按属性ID数字大小排序的已发布属性ID列表
    static func sortedAttributeIDs(in result: CompareResult) -> [String] {
        result.publishedAttributeInfo.keys.sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }
    }

    /// 找出对比中有差异的属性ID（按数字大小排序）
    /// - 参数:
    ///   - result: 对比结果
    ///   - itemCount: 物品总数（用于判断"部分物品有此属性"也算差异）
    static func attributeIDsWithDifferences(
        in result: CompareResult,
        itemCount: Int
    ) -> [String] {
        var diffs: [String] = []

        for (attributeID, values) in result.compareResult {
            // 如果不是所有物品都有这个属性，则视为有差异
            if values.count != itemCount {
                diffs.append(attributeID)
                continue
            }

            // 检查是否所有值都相同
            var allSame = true
            let firstValue = values.values.first?.value

            for (_, info) in values {
                if info.value != firstValue {
                    allSame = false
                    break
                }
            }

            if !allSame {
                diffs.append(attributeID)
            }
        }

        return diffs.sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }
    }

    /// 根据开关返回要展示的属性ID列表（已按数字排序）
    /// - 参数:
    ///   - result: 对比结果
    ///   - itemCount: 物品总数
    ///   - showOnlyDifferences: 是否只展示有差异的属性
    static func visibleAttributeIDs(
        in result: CompareResult,
        itemCount: Int,
        showOnlyDifferences: Bool
    ) -> [String] {
        let sorted = sortedAttributeIDs(in: result)
        guard showOnlyDifferences else { return sorted }
        let diffs = Set(attributeIDsWithDifferences(in: result, itemCount: itemCount))
        return sorted.filter { diffs.contains($0) }
    }

    // MARK: - 计算对比结果

    /// 获取多个物品的属性对比数据，并返回结果
    static func compareAttributesWithResult(typeIDs: [Int], databaseManager: DatabaseManager)
        -> CompareResult?
    {
        // 如果物品数量少于2个，不进行对比
        if typeIDs.count < 2 {
            Logger.info("需要至少两个物品才能进行对比")
            return nil
        }

        // 去重处理
        let uniqueTypeIDs = Array(Set(typeIDs))

        if uniqueTypeIDs.count < 2 {
            Logger.info("去重后物品数量少于2个，无法进行对比")
            return nil
        }

        Logger.info("开始属性对比，物品ID: \(uniqueTypeIDs)")

        // 首先加载属性单位信息并初始化AttributeDisplayConfig
        let attributeUnits = databaseManager.loadAttributeUnits()
        AttributeDisplayConfig.initializeUnits(with: attributeUnits)
        Logger.info("加载了 \(attributeUnits.count) 个属性单位")

        // 构建SQL查询条件
        let typeIDsString = uniqueTypeIDs.map { String($0) }.joined(separator: ",")

        // 查询SQL - 获取属性值和单位信息
        let query = """
            SELECT
                ta.type_id,
                ta.attribute_id,
                a.display_name,
                a.name,
                ta.value,
                COALESCE(ta.unitID, a.unitID) as unitID,
                a.unitName,
                a.iconID,
                COALESCE(a.icon_filename, '') as icon_filename,
                a.highIsGood
            FROM
                typeAttributes ta
            LEFT JOIN
                dogmaAttributes a ON ta.attribute_id = a.attribute_id
            WHERE
                ta.type_id IN (\(typeIDsString))
            ORDER BY 
                ta.attribute_id
        """

        // 执行查询
        guard case let .success(rows) = databaseManager.executeQuery(query) else {
            Logger.error("获取物品属性对比数据失败")
            return nil
        }

        Logger.info("查询到 \(rows.count) 行原始数据")

        // 初始化结果字典 - 格式: [attributeID: [typeID: {value, unitID}]]
        var attributeValues: [String: [String: AttributeValueInfo]] = [:]

        // 存储属性图标信息
        var attributeIcons: [String: String] = [:]

        // 存储属性的highIsGood信息
        var attributeHighIsGood: [String: Bool] = [:]

        // 处理查询结果
        for row in rows {
            guard let typeID = row["type_id"] as? Int,
                  let attributeID = row["attribute_id"] as? Int,
                  let value = row["value"] as? Double
            else {
                continue
            }

            let unitID = row["unitID"] as? Int
            let iconID = row["iconID"] as? Int
            let iconFileName = (row["icon_filename"] as? String) ?? ""
            let highIsGood = (row["highIsGood"] as? Int) == 1

            let attributeIDString = String(attributeID)
            let typeIDString = String(typeID)

            if attributeValues[attributeIDString] == nil {
                attributeValues[attributeIDString] = [:]
            }

            attributeValues[attributeIDString]?[typeIDString] = AttributeValueInfo(
                value: value, unitID: unitID
            )

            // 保存属性图标信息（只需保存一次）
            if !attributeIcons.keys.contains(attributeIDString), iconID != nil, iconID != 0 {
                let finalIconFileName =
                    iconFileName.isEmpty ? IconManager.defaultIcon : iconFileName
                attributeIcons[attributeIDString] = finalIconFileName
            }

            // 保存属性的highIsGood信息（只需保存一次）
            if !attributeHighIsGood.keys.contains(attributeIDString) {
                attributeHighIsGood[attributeIDString] = highIsGood
            }
        }

        // 查询 types 表中的额外属性值 - mass(4), capacity(38), volume(161)
        let typesQuery = """
            SELECT 
                type_id, 
                name,
                volume,
                capacity,
                mass
            FROM 
                types
            WHERE 
                type_id IN (\(typeIDsString))
        """

        var typeInfo: [String: String] = [:]

        // types 表属性的真实属性ID映射
        let typesAttributeMapping = [
            (161, "volume"),
            (38, "capacity"),
            (4, "mass"),
        ]

        if case let .success(typeRows) = databaseManager.executeQuery(typesQuery) {
            for row in typeRows {
                guard let typeID = row["type_id"] as? Int,
                      let name = row["name"] as? String
                else {
                    continue
                }

                typeInfo[String(typeID)] = name

                // 处理 types 表中的属性值，使用真实的属性ID
                for (realAttributeID, columnName) in typesAttributeMapping {
                    if let value = row[columnName] as? Double {
                        let attributeIDString = String(realAttributeID)
                        let typeIDString = String(typeID)

                        if attributeValues[attributeIDString] == nil {
                            attributeValues[attributeIDString] = [:]
                        }

                        // 单位ID先设为nil，后面从dogmaAttributes获取
                        attributeValues[attributeIDString]?[typeIDString] = AttributeValueInfo(
                            value: value, unitID: nil
                        )
                    }
                }
            }
        }

        // 获取属性信息并区分已发布和未发布
        let attributeIDs = Array(attributeValues.keys).compactMap { Int($0) }
        let attributeIDsString = attributeIDs.map { String($0) }.joined(separator: ",")

        let attributeQuery = """
            SELECT 
                attribute_id, 
                display_name,
                name,
                highIsGood,
                COALESCE(unitID, 0) as unitID,
                iconID,
                COALESCE(icon_filename, '') as icon_filename
            FROM 
                dogmaAttributes
            WHERE 
                attribute_id IN (\(attributeIDsString))
            AND (unitID IS NULL OR unitID NOT IN (115, 116, 119))  -- typeid类的属性值不看，NULL值也包含在内
        """

        // 已发布属性信息 (有 display_name 的)
        var publishedAttributeInfo: [String: String] = [:]

        if case let .success(attributeRows) = databaseManager.executeQuery(attributeQuery) {
            for row in attributeRows {
                guard let attributeID = row["attribute_id"] as? Int else {
                    continue
                }

                let displayName = row["display_name"] as? String
                let attributeIDString = String(attributeID)
                let unitID = row["unitID"] as? Int
                let iconID = row["iconID"] as? Int
                let iconFileName = (row["icon_filename"] as? String) ?? ""
                let highIsGood = (row["highIsGood"] as? Int) == 1

                if let displayName = displayName, !displayName.isEmpty {
                    publishedAttributeInfo[attributeIDString] = displayName
                }

                // 更新 types 表属性的单位ID
                if let attributeTypeValues = attributeValues[attributeIDString] {
                    var updatedValues: [String: AttributeValueInfo] = [:]
                    for (typeIDString, valueInfo) in attributeTypeValues {
                        updatedValues[typeIDString] = AttributeValueInfo(
                            value: valueInfo.value,
                            unitID: unitID
                        )
                    }
                    attributeValues[attributeIDString] = updatedValues
                }

                if !attributeIcons.keys.contains(attributeIDString), iconID != nil, iconID != 0 {
                    let finalIconFileName =
                        iconFileName.isEmpty ? IconManager.defaultIcon : iconFileName
                    attributeIcons[attributeIDString] = finalIconFileName
                }

                if !attributeHighIsGood.keys.contains(attributeIDString) {
                    attributeHighIsGood[attributeIDString] = highIsGood
                }
            }
        }

        // 构建符合Codable的结果对象
        let result = CompareResult(
            compareResult: attributeValues,
            typeInfo: typeInfo,
            publishedAttributeInfo: publishedAttributeInfo,
            attributeIcons: attributeIcons,
            attributeHighIsGood: attributeHighIsGood
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            _ = try encoder.encode(result)
        } catch {
            Logger.error("无法将结果转换为JSON: \(error)")
        }

        return result
    }
}
