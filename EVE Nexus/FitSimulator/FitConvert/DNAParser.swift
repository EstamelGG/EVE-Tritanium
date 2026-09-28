import Foundation

/// DNA解析器 - 用于解析EVE Online的DNA格式装配链接
class DNAParser {
    /// DNA解析结果
    struct DNAResult {
        let shipTypeId: Int
        let subsystems: [Int]
        let modules: [(typeId: Int, quantity: Int, isOffline: Bool)]
        let charges: [(typeId: Int, quantity: Int)]
        let displayName: String
    }

    /// 将飞船与模块编码为 DNA 字符串（与 `parseDNA` 兼容）
    /// - Parameters:
    ///   - shipTypeId: 飞船 `type_id`
    ///   - modules: 模块 `type_id` 与数量（同一 `type_id` 应先合并）
    static func encodeFittingDNA(shipTypeId: Int, modules: [(typeId: Int, quantity: Int)]) -> String {
        var segments: [String] = [String(shipTypeId)]
        for m in modules where m.quantity > 0 {
            segments.append("\(m.typeId);\(m.quantity)")
        }
        return "fitting:" + segments.joined(separator: ":") + ":"
    }

    /// 解析DNA字符串
    /// - Parameters:
    ///   - dnaString: DNA格式的字符串（如：fitting:73792:2048;1:18945;1:...）
    ///   - displayName: 显示名称（从链接文本中提取）
    /// - Returns: 解析结果，如果解析失败则返回nil
    static func parseDNA(_ dnaString: String, displayName: String = "") -> DNAResult? {
        Logger.info("开始解析DNA字符串: \(dnaString)")

        // 移除 "fitting:" 前缀
        guard dnaString.hasPrefix("fitting:") else {
            Logger.warning("DNA字符串格式错误：缺少fitting:前缀")
            return nil
        }

        let cleanDNA = String(dnaString.dropFirst(8)) // 移除 "fitting:"

        // 按冒号分割各个部分
        let parts = cleanDNA.components(separatedBy: ":")
        guard parts.count >= 2 else {
            Logger.warning("DNA字符串格式错误：部分数量不足")
            return nil
        }

        // 解析飞船ID（第一部分）
        guard let shipTypeId = Int(parts[0]) else {
            Logger.warning("DNA字符串格式错误：无法解析飞船ID")
            return nil
        }

        // DNA格式分析：每个冒号分隔的部分都可能包含模块
        // 格式：fitting:shipID:module1;qty1:module2;qty2:...:
        // 我们需要解析所有部分，然后通过数据库查询确定它们的类型

        var allModules: [(typeId: Int, quantity: Int, isOffline: Bool)] = []
        let charges: [(typeId: Int, quantity: Int)] = []

        // 从parts[1]开始解析所有部分，跳过最后的空部分
        for i in 1 ..< parts.count {
            let part = parts[i]
            if part.isEmpty {
                Logger.debug("跳过空部分: parts[\(i)]")
                continue
            }

            // 尝试解析为模块格式 (typeID;quantity)
            if part.contains(";") {
                // 检查是否为离线模块（以下划线结尾）
                var cleanPart = part
                var isOffline = false
                if part.hasSuffix("_") {
                    isOffline = true
                    cleanPart = String(part.dropLast())
                }

                let components = cleanPart.components(separatedBy: ";")
                if components.count >= 2,
                   let typeId = Int(components[0]),
                   let quantity = Int(components[1])
                {
                    allModules.append((typeId: typeId, quantity: quantity, isOffline: isOffline))
                    Logger.debug("解析模块: ID=\(typeId), 数量=\(quantity), 离线=\(isOffline)")
                }
            } else if let typeId = Int(part) {
                // 没有数量信息的模块，默认数量为1
                allModules.append((typeId: typeId, quantity: 1, isOffline: false))
                Logger.debug("解析模块: ID=\(typeId), 数量=1, 离线=false")
            }
        }

        Logger.info(
            "DNA解析完成 - 飞船ID: \(shipTypeId), 模块: \(allModules.count)个, 弹药/无人机: \(charges.count)个"
        )

        return DNAResult(
            shipTypeId: shipTypeId,
            subsystems: [], // 子系统将通过装备分类器识别
            modules: allModules,
            charges: charges,
            displayName: displayName
        )
    }

    /// 将DNA解析结果转换为LocalFitting
    /// - Parameters:
    ///   - dnaResult: DNA解析结果
    ///   - databaseManager: 数据库管理器
    /// - Returns: LocalFitting对象
    static func dnaResultToLocalFitting(_ dnaResult: DNAResult, databaseManager: DatabaseManager)
        -> LocalFitting?
    {
        Logger.info("开始将DNA结果转换为LocalFitting")

        // 创建装备分类器
        let classifier = EquipmentClassifier(databaseManager: databaseManager)

        // 收集所有typeId进行分类
        var allTypeIds: [Int] = [dnaResult.shipTypeId]
        allTypeIds.append(contentsOf: dnaResult.subsystems)
        allTypeIds.append(contentsOf: dnaResult.modules.map { $0.typeId })
        allTypeIds.append(contentsOf: dnaResult.charges.map { $0.typeId })

        let classifications = classifier.classifyEquipments(typeIds: allTypeIds)

        // 创建装备项列表
        var items: [LocalFittingItem] = []
        var drones: [Drone] = []
        var cargo: [CargoItem] = []

        // 槽位计数器
        var slotCounters = SlotCounters()

        // 处理子系统
        for subsystemId in dnaResult.subsystems {
            let flag = getSubSystemSlotFlag(index: slotCounters.subSystemSlot)
            slotCounters.subSystemSlot += 1
            guard flag != .invalid else {
                Logger.warning("子系统槽位超出支持范围，跳过: \(subsystemId)")
                continue
            }

            items.append(
                LocalFittingItem(
                    flag: flag,
                    quantity: 1,
                    type_id: subsystemId,
                    status: 1
                )
            )
        }

        // 处理所有模块，使用装备分类器来确定槽位类型，而不是依赖DNA中的位置
        // 这样更准确，因为装备的槽位类型由其effect_id和category_id决定

        for module in dnaResult.modules {
            // 根据装备分类器确定槽位类型
            guard let classification = classifications[module.typeId] else {
                Logger.warning("模块 \(module.typeId) 未分类，跳过")
                continue
            }

            // 如果数量大于1，需要为每个装备创建单独的槽位
            for _ in 0 ..< module.quantity {
                let currentFlag: FittingFlag
                switch classification.category {
                case .hiSlot:
                    currentFlag = getHiSlotFlag(index: slotCounters.hiSlot)
                    slotCounters.hiSlot += 1
                case .medSlot:
                    currentFlag = getMedSlotFlag(index: slotCounters.medSlot)
                    slotCounters.medSlot += 1
                case .lowSlot:
                    currentFlag = getLoSlotFlag(index: slotCounters.lowSlot)
                    slotCounters.lowSlot += 1
                case .rig:
                    currentFlag = getRigSlotFlag(index: slotCounters.rigSlot)
                    slotCounters.rigSlot += 1
                case .subsystem:
                    currentFlag = getSubSystemSlotFlag(index: slotCounters.subSystemSlot)
                    slotCounters.subSystemSlot += 1
                default:
                    Logger.warning("模块 \(module.typeId) 的类型(\(classification.category))不是可安装的装备，跳过")
                    continue
                }

                guard currentFlag != .invalid else {
                    Logger.warning("装备槽位超出支持范围，跳过: \(module.typeId)")
                    continue
                }

                items.append(
                    LocalFittingItem(
                        flag: currentFlag,
                        quantity: 1, // 每个槽位只能装一个装备
                        type_id: module.typeId,
                        status: module.isOffline ? 0 : 1
                    )
                )

                Logger.debug("创建装备项: \(module.typeId) -> \(currentFlag)")
            }
        }

        // 处理弹药和无人机
        for charge in dnaResult.charges {
            guard let classification = classifications[charge.typeId] else {
                Logger.warning("弹药/无人机 \(charge.typeId) 未分类，跳过")
                continue
            }

            switch classification.category {
            case .drone:
                drones.append(
                    Drone(
                        type_id: charge.typeId,
                        quantity: charge.quantity,
                        active_count: 0,
                        muta: nil
                    )
                )
            case .charge:
                // 弹药需要分配给对应的模块，这里先作为货舱物品处理
                cargo.append(
                    CargoItem(
                        type_id: charge.typeId,
                        quantity: charge.quantity
                    )
                )
            default:
                // 其他物品作为货舱物品
                cargo.append(
                    CargoItem(
                        type_id: charge.typeId,
                        quantity: charge.quantity
                    )
                )
            }
        }

        // 创建LocalFitting对象
        let localFitting = LocalFitting(
            description: NSLocalizedString("DNA_Fitting_Link_Default_Description", comment: ""),
            fitting_id: UUID(), // 全局唯一，避免时间戳碰撞互相覆盖
            items: items,
            name: dnaResult.displayName.isEmpty
                ? NSLocalizedString("DNA_Fitting_Link_Default_Name", comment: "")
                : dnaResult.displayName,
            ship_type_id: dnaResult.shipTypeId,
            drones: drones.isEmpty ? nil : drones,
            fighters: nil,
            cargo: cargo.isEmpty ? nil : cargo,
            implants: nil,
            environment_type_id: nil
        )

        Logger.info("DNA转换完成 - 装备: \(items.count), 无人机: \(drones.count), 货舱: \(cargo.count)")
        return localFitting
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
}
