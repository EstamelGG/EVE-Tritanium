import Foundation

extension FitConvert {
    /// 将EFT格式文本转换为LocalFitting（带飞船选择）
    /// - Parameters:
    ///   - eftText: EFT格式的配置文本
    ///   - databaseManager: 数据库管理器，用于查询物品ID
    ///   - selectedShipTypeId: 当有多个同名飞船时，用户选择的飞船ID
    /// - Returns: LocalFitting对象
    /// - Throws: 转换过程中的错误
    static func eftToLocalFitting(
        eftText: String, databaseManager: DatabaseManager, selectedShipTypeId: Int
    ) throws -> LocalFitting {
        return try eftToLocalFittingInternal(
            eftText: eftText, databaseManager: databaseManager,
            selectedShipTypeId: selectedShipTypeId
        )
    }

    /// 将EFT格式文本转换为LocalFitting
    /// - Parameters:
    ///   - eftText: EFT格式的配置文本
    ///   - databaseManager: 数据库管理器，用于查询物品ID
    /// - Returns: LocalFitting对象
    /// - Throws: 转换过程中的错误
    static func eftToLocalFitting(eftText: String, databaseManager: DatabaseManager) throws
        -> LocalFitting
    {
        return try eftToLocalFittingInternal(
            eftText: eftText, databaseManager: databaseManager, selectedShipTypeId: nil
        )
    }

    /// 内部EFT转换方法
    private static func eftToLocalFittingInternal(
        eftText: String, databaseManager: DatabaseManager, selectedShipTypeId: Int?
    ) throws -> LocalFitting {
        if AppConfiguration.Fitting.showDebug {
            Logger.info("开始将EFT格式转换为LocalFitting")
        }

        let lines = eftText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        // 找到第一个非空行
        guard let firstLineIndex = lines.firstIndex(where: { !$0.isEmpty }),
              firstLineIndex < lines.count
        else {
            throw NSError(
                domain: "EFTConvert", code: 1, userInfo: [NSLocalizedDescriptionKey: "EFT文本为空"]
            )
        }

        // 解析第一行：[飞船名称, 配置名称]
        let firstLine = lines[firstLineIndex]
        guard firstLine.hasPrefix("[") && firstLine.hasSuffix("]") else {
            throw NSError(
                domain: "EFTConvert", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "EFT格式错误：第一行应为 [飞船名称, 配置名称]"]
            )
        }

        let headerContent = String(firstLine.dropFirst().dropLast())
        let headerParts = headerContent.components(separatedBy: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard headerParts.count >= 2 else {
            throw NSError(
                domain: "EFTConvert", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "EFT格式错误：无法解析飞船和配置名称"]
            )
        }

        let shipName = headerParts[0]
        let fittingName = headerParts[1]

        // 第一步：收集所有物品名称并批量查询typeId
        var allItemNames = collectAllItemNames(lines: lines, startIndex: firstLineIndex + 1)
        allItemNames.insert(shipName)
        if AppConfiguration.Fitting.showDebug {
            Logger.info("收集到 \(allItemNames.count) 个不重复的物品名称")
        }

        // 批量查询所有物品的typeId
        let nameToTypeIdMap = try batchQueryTypeIds(
            itemNames: allItemNames, databaseManager: databaseManager
        )
        if AppConfiguration.Fitting.showDebug {
            Logger.success("成功查询到 \(nameToTypeIdMap.count) 个物品的typeId")
        }

        // 查找飞船ID（初始查找，后续会通过验证查询确认）
        guard let initialShipTypeId = nameToTypeIdMap[shipName] else {
            throw NSError(
                domain: "EFTConvert", code: 4,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "\(NSLocalizedString("Fitting_Import_Ship_notfound", comment: "")): \(shipName)",
                ]
            )
        }

        // 声明可变的飞船ID变量
        var shipTypeId = initialShipTypeId

        // 验证是否为飞船类型并查询飞船信息（全语种名匹配）
        let shipValidationQuery = """
            SELECT t.type_id, t.icon_filename,
                   \(LocalizedText.typeLangNameColumns.map { "t.\($0)" }.joined(separator: ", "))
            FROM types t
            WHERE (\(LocalizedText.typeLangNameColumns.map { "t.\($0) = ?" }.joined(separator: " OR ")))
              AND t.categoryID = 6
        """

        guard
            case let .success(rows) = databaseManager.executeQuery(
                shipValidationQuery,
                parameters: Array(repeating: shipName, count: 8)
            )
        else {
            throw NSError(
                domain: "EFTConvert", code: 5,
                userInfo: [
                    NSLocalizedDescriptionKey: String(
                        format: NSLocalizedString(
                            "Fitting_Import_Validation_Failed_Error", comment: "验证物品类型失败"
                        ), shipName
                    ),
                ]
            )
        }

        // 根据查询结果行数处理不同情况
        if rows.isEmpty {
            // 查无此飞船
            throw NSError(
                domain: "EFTConvert", code: 6,
                userInfo: [
                    NSLocalizedDescriptionKey: String(
                        format: NSLocalizedString(
                            "Fitting_Import_Not_Ship_Error", comment: "导入错误：不是飞船"
                        ), shipName
                    ),
                ]
            )
        } else if rows.count == 1 {
            // 正常情况：找到唯一的飞船
            guard let row = rows.first,
                  let validatedShipTypeId = row["type_id"] as? Int
            else {
                throw NSError(
                    domain: "EFTConvert", code: 5,
                    userInfo: [
                        NSLocalizedDescriptionKey: String(
                            format: NSLocalizedString(
                                "Fitting_Import_Validation_Failed_Error", comment: "验证物品类型失败"
                            ),
                            shipName
                        ),
                    ]
                )
            }

            // 使用验证过的飞船ID（可能与之前查询的不同）
            shipTypeId = validatedShipTypeId
            if AppConfiguration.Fitting.showDebug {
                Logger.info("验证通过：\(shipName) 是有效的飞船 (ID: \(shipTypeId))")
            }
        } else {
            // 多个同名飞船，需要用户选择
            if AppConfiguration.Fitting.showDebug {
                Logger.info("发现多个同名飞船：\(shipName)，数量：\(rows.count)")
            }

            // 如果提供了选择的飞船ID，验证并使用它
            if let selectedId = selectedShipTypeId {
                // 验证选择的飞船ID是否在查询结果中
                if rows.first(where: { ($0["type_id"] as? Int) == selectedId }) != nil {
                    shipTypeId = selectedId
                    if AppConfiguration.Fitting.showDebug {
                        Logger.info("使用用户选择的飞船：\(shipName) (ID: \(shipTypeId))")
                    }
                } else {
                    // 选择的飞船ID不在结果中，可能是无效的选择
                    throw NSError(
                        domain: "EFTConvert", code: 8,
                        userInfo: [NSLocalizedDescriptionKey: "选择的飞船ID无效"]
                    )
                }
            } else {
                // 没有提供选择，构建飞船选择信息并抛出错误
                var shipOptions: [(typeId: Int, name: String, iconFileName: String?)] = []
                for row in rows {
                    if let typeId = row["type_id"] as? Int {
                        let iconFileName = row["icon_filename"] as? String

                        // 显示名：当前语言优先
                        let displayName = LocalizedText.from(row: row).resolved()
                        shipOptions.append(
                            (
                                typeId: typeId,
                                name: displayName.isEmpty ? "Unknown Ship" : displayName,
                                iconFileName: iconFileName
                            )
                        )
                    }
                }

                // 这里需要抛出一个特殊的错误，包含飞船选择信息
                // 调用方需要处理这个错误并显示选择界面
                let userInfo: [String: Any] = [
                    NSLocalizedDescriptionKey: String(
                        format: NSLocalizedString(
                            "Fitting_Import_Multiple_Ships_Error", comment: "发现多个同名飞船，请选择"
                        ),
                        shipName
                    ),
                    "shipOptions": shipOptions,
                    "shipName": shipName,
                ]
                throw NSError(domain: "EFTConvert", code: 7, userInfo: userInfo)
            }
        }

        // 第二步：使用装备分类器对所有typeId进行批量分类
        let allTypeIds = Array(nameToTypeIdMap.values)
        let classifier = EquipmentClassifier(databaseManager: databaseManager)
        let classifications = classifier.classifyEquipments(typeIds: allTypeIds)
        if AppConfiguration.Fitting.showDebug {
            Logger.info("完成 \(allTypeIds.count) 个物品的分类")
        }

        // 解析装备、无人机、舰载机和货舱物品
        var items: [LocalFittingItem] = []
        var drones: [Drone] = []
        var cargo: [CargoItem] = []

        // 临时存储舰载机物品，稍后统一处理
        var tempFighterBayItems: [FittingItem] = []

        // 槽位计数器
        var slotCounters = SlotCounters()

        // 跳过第一行（飞船和配置名称），从下一行开始解析
        let startIndex = firstLineIndex + 1

        for index in startIndex ..< lines.count {
            let line = lines[index]
            let lineNumber = index + 1 // 实际行号（从1开始计数）

            // 跳过空行和空槽位标记
            if line.isEmpty || (line.hasPrefix("[") && line.hasSuffix("]")) {
                continue
            }

            do {
                // 检查是否为数量格式
                if isQuantityFormat(line: line) {
                    // 所有数量格式的物品都按货舱物品处理，然后根据分类决定最终归属
                    if let result = try parseQuantityItemWithClassification(
                        line: line, nameToTypeIdMap: nameToTypeIdMap,
                        classifications: classifications
                    ) {
                        switch result.category {
                        case .drone:
                            let drone = Drone(
                                type_id: result.typeId,
                                quantity: result.quantity,
                                active_count: 0,
                                muta: nil
                            )
                            drones.append(drone)
                            if AppConfiguration.Fitting.showDebug {
                                Logger.debug("数量物品归类为无人机: \(result.itemName) x\(result.quantity)")
                            }
                        case .fighter:
                            // 暂存舰载机信息，稍后统一处理
                            let fighterItem = FittingItem(
                                flag: .fighterBay,
                                quantity: result.quantity,
                                type_id: result.typeId
                            )
                            tempFighterBayItems.append(fighterItem)
                            if AppConfiguration.Fitting.showDebug {
                                Logger.debug("数量物品归类为舰载机: \(result.itemName) x\(result.quantity)")
                            }
                        default:
                            let cargoItem = CargoItem(
                                type_id: result.typeId,
                                quantity: result.quantity
                            )
                            cargo.append(cargoItem)
                            if AppConfiguration.Fitting.showDebug {
                                Logger.debug("数量物品归类为货舱: \(result.itemName) x\(result.quantity)")
                            }
                        }
                    }
                } else {
                    // 非数量格式的物品，根据分类器结果确定装备类型
                    if let item = try parseEquipmentLineWithClassification(
                        line: line, slotCounters: &slotCounters, nameToTypeIdMap: nameToTypeIdMap,
                        classifications: classifications
                    ) {
                        items.append(item)
                    }
                }
            } catch {
                Logger.warning("解析第\(lineNumber)行失败：\(line) - \(error.localizedDescription)")
                // 继续解析其他行，不因单行错误而中断
            }
        }

        // 使用智能舰载机处理逻辑
        if AppConfiguration.Fitting.showDebug {
            Logger.info("EFT导入: 准备处理舰载机配置，找到 \(tempFighterBayItems.count) 个舰载机物品")
        }
        let fighters = processFighters(
            shipTypeId: shipTypeId,
            fighterBayItems: tempFighterBayItems,
            databaseManager: databaseManager
        )
        if AppConfiguration.Fitting.showDebug {
            Logger.info("EFT导入: 舰载机处理完成，生成了 \(fighters.count) 个FighterSquad")
        }

        // 创建LocalFitting对象
        let localFitting = LocalFitting(
            description: "",
            fitting_id: UUID(), // 全局唯一，避免时间戳碰撞互相覆盖
            items: items,
            name: fittingName,
            ship_type_id: shipTypeId,
            drones: drones.isEmpty ? nil : drones,
            fighters: fighters.isEmpty ? nil : fighters,
            cargo: cargo.isEmpty ? nil : cargo,
            implants: nil,
            environment_type_id: nil
        )

        // 打印详细的解析结果
        if AppConfiguration.Fitting.showDebug {
            Logger.info("=== EFT解析结果详情 ===")
            Logger.info("Ship: \(shipName)")
            Logger.info("Fitting Name: \(fittingName)")

            // 获取所有装备的名称（用于调试日志）
            let allEquipmentTypeIds = items.map { $0.type_id }
            var equipmentNames: [Int: String] = [:]
            for typeId in allEquipmentTypeIds {
                if let name = ItemInfoMap.typeName(for: typeId) {
                    equipmentNames[typeId] = name
                }
            }

            // 打印装备详情
            for item in items {
                let equipmentName = equipmentNames[item.type_id] ?? "Unknown Equipment"
                let category = classifications[item.type_id]?.category.rawValue ?? "unknown"
                Logger.info("\(item.flag): \(equipmentName) (category: \(category))")
            }

            // 打印无人机详情
            if !drones.isEmpty {
                Logger.info("=== 无人机 ===")
                for drone in drones {
                    if let droneName = nameToTypeIdMap.first(where: { $0.value == drone.type_id })?.key {
                        let category = classifications[drone.type_id]?.category.rawValue ?? "unknown"
                        Logger.info("Drone: \(droneName) x\(drone.quantity) (category: \(category))")
                    }
                }
            }

            // 打印舰载机详情
            if !fighters.isEmpty {
                Logger.info("=== 舰载机 ===")

                // 获取舰载机名称
                let fighterTypeIds = fighters.map { $0.type_id }
                var fighterNames: [Int: String] = [:]
                for typeId in fighterTypeIds {
                    if let name = ItemInfoMap.typeName(for: typeId) {
                        fighterNames[typeId] = name
                    }
                }

                for fighter in fighters {
                    let fighterName = fighterNames[fighter.type_id] ?? "Unknown Fighter"
                    let category = classifications[fighter.type_id]?.category.rawValue ?? "fighter"
                    Logger.info(
                        "Fighter: \(fighterName) x\(fighter.quantity) (tubeId: \(fighter.tubeId), category: \(category))"
                    )
                }
            }

            // 打印货舱物品详情
            if !cargo.isEmpty {
                Logger.info("=== 货舱物品 ===")
                for cargoItem in cargo {
                    if let itemName = nameToTypeIdMap.first(where: { $0.value == cargoItem.type_id })?
                        .key
                    {
                        let category =
                            classifications[cargoItem.type_id]?.category.rawValue ?? "unknown"
                        Logger.info("Cargo: \(itemName) x\(cargoItem.quantity) (category: \(category))")
                    }
                }
            }

            Logger.info("=== 解析统计 ===")
            Logger.info(
                "EFT转换完成 - 装备: \(items.count), 无人机: \(drones.count), 舰载机: \(fighters.count), 货舱: \(cargo.count)"
            )
            Logger.info(
                "装备分布 - 低槽: \(slotCounters.lowSlot), 中槽: \(slotCounters.medSlot), 高槽: \(slotCounters.hiSlot), 改装件: \(slotCounters.rigSlot), 子系统: \(slotCounters.subSystemSlot), 服务槽: \(slotCounters.serviceSlot)"
            )
            Logger.info("注意：使用装备分类器自动分配槽位和归类，舰载机使用智能tubeId分配")
        }

        return localFitting
    }

    /// 槽位类型枚举
    private enum SlotType {
        case lowSlot
        case medSlot
        case hiSlot
        case rigSlot
        case subSystemSlot
        case serviceSlot
    }

    /// 槽位计数器
    private struct SlotCounters {
        var lowSlot = 0
        var medSlot = 0
        var hiSlot = 0
        var rigSlot = 0
        var subSystemSlot = 0
        var serviceSlot = 0
    }

    /// 根据槽位类型获取对应的flag
    private static func getSlotFlag(slotType: SlotType, slotCounters: inout SlotCounters)
        -> FittingFlag
    {
        switch slotType {
        case .lowSlot:
            let flag = getLoSlotFlag(index: slotCounters.lowSlot)
            slotCounters.lowSlot += 1
            return flag
        case .medSlot:
            let flag = getMedSlotFlag(index: slotCounters.medSlot)
            slotCounters.medSlot += 1
            return flag
        case .hiSlot:
            let flag = getHiSlotFlag(index: slotCounters.hiSlot)
            slotCounters.hiSlot += 1
            return flag
        case .rigSlot:
            let flag = getRigSlotFlag(index: slotCounters.rigSlot)
            slotCounters.rigSlot += 1
            return flag
        case .subSystemSlot:
            let flag = getSubSystemSlotFlag(index: slotCounters.subSystemSlot)
            slotCounters.subSystemSlot += 1
            return flag
        case .serviceSlot:
            let flag = getServiceSlotFlag(index: slotCounters.serviceSlot)
            slotCounters.serviceSlot += 1
            return flag
        }
    }

    /// 获取高槽flag
    private static func getHiSlotFlag(index: Int) -> FittingFlag {
        .slot(.high, index: index)
    }

    /// 获取中槽flag
    private static func getMedSlotFlag(index: Int) -> FittingFlag {
        .slot(.medium, index: index)
    }

    /// 获取低槽flag
    private static func getLoSlotFlag(index: Int) -> FittingFlag {
        .slot(.low, index: index)
    }

    /// 获取改装件槽flag
    private static func getRigSlotFlag(index: Int) -> FittingFlag {
        .slot(.rig, index: index)
    }

    /// 获取子系统槽flag
    private static func getSubSystemSlotFlag(index: Int) -> FittingFlag {
        .slot(.subsystem, index: index)
    }

    /// 获取服务槽flag
    private static func getServiceSlotFlag(index: Int) -> FittingFlag {
        .slot(.service, index: index)
    }

    // MARK: - 批量查询和分类辅助方法

    /// 使用正则表达式检查是否为数量格式（物品名称 x数量）
    private static func isQuantityFormat(line: String) -> Bool {
        // 正则表达式：匹配 "物品名称 x数字" 格式
        // 物品名称可以包含字母、数字、空格、特殊字符等，但不能以x开头
        // x前后可以有空格，数字可以是1位或多位
        let pattern = #"^.+\s+x\s*\d+$"#

        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let range = NSRange(location: 0, length: line.utf16.count)
            return regex.firstMatch(in: line, options: [], range: range) != nil
        } catch {
            Logger.warning("正则表达式错误：\(error)")
            // 如果正则表达式失败，回退到简单的字符串检查
            return line.contains(" x")
                && line.split(separator: " ").last?.allSatisfy(\.isNumber) == true
        }
    }

    /// 从数量格式的行中提取物品名称和数量
    private static func parseQuantityLine(line: String) -> (itemName: String, quantity: Int)? {
        // 正则表达式：捕获物品名称和数量
        let pattern = #"^(.+?)\s+x\s*(\d+)$"#

        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let range = NSRange(location: 0, length: line.utf16.count)

            if let match = regex.firstMatch(in: line, options: [], range: range) {
                let itemNameRange = match.range(at: 1)
                let quantityRange = match.range(at: 2)

                if let itemNameNSRange = Range(itemNameRange, in: line),
                   let quantityNSRange = Range(quantityRange, in: line)
                {
                    let itemName = String(line[itemNameNSRange]).trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    let quantityString = String(line[quantityNSRange])

                    if let quantity = Int(quantityString) {
                        return (itemName: itemName, quantity: quantity)
                    }
                }
            }
        } catch {
            Logger.warning("解析数量行正则表达式错误：\(error)")
        }

        // 如果正则表达式失败，回退到简单的字符串分割
        let parts = line.components(separatedBy: " x")
        if parts.count == 2,
           let quantity = Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
        {
            let itemName = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            return (itemName: itemName, quantity: quantity)
        }

        return nil
    }

    /// 收集EFT文本中的所有物品名称
    private static func collectAllItemNames(lines: [String], startIndex: Int) -> Set<String> {
        var itemNames: Set<String> = []

        for index in startIndex ..< lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)

            // 跳过空行和空槽位标记
            if line.isEmpty || (line.hasPrefix("[") && line.hasSuffix("]")) {
                continue
            }

            // 解析装备行（可能包含弹药）
            if line.contains(",") {
                let parts = line.components(separatedBy: ",").map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                for part in parts {
                    if !part.isEmpty {
                        itemNames.insert(part)
                    }
                }
            } else if isQuantityFormat(line: line) {
                // 使用正则表达式解析数量格式的行
                if let parsed = parseQuantityLine(line: line) {
                    itemNames.insert(parsed.itemName)
                }
            } else {
                // 单个装备名称
                if !line.isEmpty {
                    itemNames.insert(line)
                }
            }
        }

        return itemNames
    }

    /// 批量查询物品名称对应的typeId
    private static func batchQueryTypeIds(itemNames: Set<String>, databaseManager: DatabaseManager)
        throws -> [String: Int]
    {
        guard !itemNames.isEmpty else { return [:] }

        var nameToTypeIdMap: [String: Int] = [:]

        // 将物品名称分批查询，避免SQL语句过长
        let batchSize = 500
        let itemNamesArray = Array(itemNames)

        for i in stride(from: 0, to: itemNamesArray.count, by: batchSize) {
            let endIndex = min(i + batchSize, itemNamesArray.count)
            let batch = Array(itemNamesArray[i ..< endIndex])

            let placeholders = Array(repeating: "?", count: batch.count).joined(separator: ",")
            let langIns = LocalizedText.typeLangNameColumns
                .map { "\($0) IN (\(placeholders))" }
                .joined(separator: " OR ")
            let query = """
                SELECT type_id, \(LocalizedText.typeLangNameColumns.joined(separator: ", "))
                FROM types
                WHERE \(langIns)
            """
            let parameters = Array(repeating: batch, count: 8).flatMap { $0 }

            if case let .success(rows) = databaseManager.executeQuery(query, parameters: parameters) {
                for row in rows {
                    guard let typeId = row["type_id"] as? Int else { continue }
                    let namesText = LocalizedText.from(row: row)
                    for name in batch where namesText.matchesExact(name) {
                        nameToTypeIdMap[name] = typeId
                    }
                }
            }
        }

        // Logger.info("批量查询完成：输入\(itemNames.count)个物品名称，匹配到\(nameToTypeIdMap.count)个typeId")
        return nameToTypeIdMap
    }

    /// 数量物品解析结果
    private struct QuantityItemResult {
        let typeId: Int
        let itemName: String
        let quantity: Int
        let category: EquipmentCategory
    }

    /// 解析数量格式物品并根据分类决定归属
    private static func parseQuantityItemWithClassification(
        line: String,
        nameToTypeIdMap: [String: Int],
        classifications: [Int: EquipmentClassificationResult]
    ) throws -> QuantityItemResult? {
        // 使用正则表达式解析数量格式
        guard let parsed = parseQuantityLine(line: line) else {
            Logger.warning("数量物品行格式错误：\(line)")
            return nil
        }

        let itemName = parsed.itemName
        let quantity = parsed.quantity

        // 验证数量是否合理
        guard quantity > 0 else {
            Logger.warning("数量物品数量无效：\(quantity)")
            return nil
        }

        // 查找物品ID
        guard let typeId = nameToTypeIdMap[itemName] else {
            Logger.warning("未找到数量物品：\(itemName)")
            return nil
        }

        // 获取分类结果
        let category = classifications[typeId]?.category ?? .unknown

        return QuantityItemResult(
            typeId: typeId,
            itemName: itemName,
            quantity: quantity,
            category: category
        )
    }

    /// 基于分类器结果解析装备行，自动分配到正确的槽位
    private static func parseEquipmentLineWithClassification(
        line: String,
        slotCounters: inout SlotCounters,
        nameToTypeIdMap: [String: Int],
        classifications: [Int: EquipmentClassificationResult]
    ) throws -> LocalFittingItem? {
        // 分离装备名称和弹药名称
        let parts = line.components(separatedBy: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let moduleName = parts[0]
        let chargeName = parts.count > 1 ? parts[1] : nil

        // 查找装备ID
        guard let moduleTypeId = nameToTypeIdMap[moduleName] else {
            Logger.warning("未找到装备：\(moduleName)")
            return nil
        }

        // 根据分类结果确定槽位类型和flag
        guard let classification = classifications[moduleTypeId] else {
            Logger.warning("装备 \(moduleName) 未分类，跳过")
            return nil
        }

        let slotType: SlotType
        switch classification.category {
        case .lowSlot:
            slotType = .lowSlot
        case .medSlot:
            slotType = .medSlot
        case .hiSlot:
            slotType = .hiSlot
        case .rig:
            slotType = .rigSlot
        case .subsystem:
            slotType = .subSystemSlot
        default:
            Logger.warning("装备 \(moduleName) 的类型(\(classification.category))不是可安装的装备，跳过")
            return nil
        }

        // 根据分类确定的槽位类型获取flag
        let flag = getSlotFlag(slotType: slotType, slotCounters: &slotCounters)
        guard flag != .invalid else {
            Logger.warning("装备槽位超出支持范围，跳过: \(moduleName)")
            return nil
        }

        // 查找弹药ID（如果有）
        var chargeTypeId: Int? = nil
        if let chargeName = chargeName {
            if let chargeId = nameToTypeIdMap[chargeName] {
                // 验证是否为弹药
                if let chargeClassification = classifications[chargeId],
                   chargeClassification.category == .charge
                {
                    chargeTypeId = chargeId
                } else {
                    Logger.warning("物品 \(chargeName) 不是弹药类型，但仍作为弹药处理")
                    chargeTypeId = chargeId // 即使分类不匹配，也按EFT格式处理
                }
            } else {
                Logger.warning("未找到弹药：\(chargeName)")
            }
        }

        Logger.debug("装备 \(moduleName) 分类为 \(classification.category)，分配到 \(flag)")

        return LocalFittingItem(
            flag: flag,
            quantity: 1,
            type_id: moduleTypeId,
            status: 1, // 默认在线状态
            charge_type_id: chargeTypeId,
            charge_quantity: chargeTypeId != nil ? 1 : nil
        )
    }
}
