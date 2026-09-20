import Foundation

extension FitConvert {
    /// 将本地配置转换为EFT格式的剪贴板文本
    /// - Parameters:
    ///   - localFitting: 本地配置对象
    ///   - databaseManager: 数据库管理器，用于查询物品名称
    ///   - useEnglishNames: 是否使用英文名称（en_name），用于非英文SDE时导出兼容EFT/Pyfa的格式
    /// - Returns: EFT格式的配置文本
    static func localFittingToEFT(
        localFitting: LocalFitting, databaseManager: DatabaseManager,
        useEnglishNames: Bool = false
    ) -> String {
        if AppConfiguration.Fitting.showDebug {
            Logger.info("开始将本地配置转换为EFT格式 - 配置名称: \(localFitting.name)")
        }

        func pickName(name: String?, enName: String?) -> String? {
            if useEnglishNames, let en = enName, !en.isEmpty {
                return en
            }
            return name
        }

        var lines: [String] = []

        // 1. 获取飞船名称（使用标准name字段以保持EFT格式兼容性）
        var shipName = "Unknown Ship"
        if let info = ItemInfoMap.typeInfo(for: localFitting.ship_type_id),
           let name = pickName(name: info.name, enName: info.enName)
        {
            shipName = name
        }

        // 第一行：飞船和配置名称
        let fittingName = localFitting.name.isEmpty ? "Unnamed Fitting" : localFitting.name
        lines.append("[\(shipName), \(fittingName)]")

        // 2. 收集所有需要查询的typeId
        var allTypeIds = localFitting.items.map { $0.type_id }

        // 添加弹药typeId
        let chargeTypeIds = localFitting.items.compactMap { $0.charge_type_id }
        allTypeIds.append(contentsOf: chargeTypeIds)

        // 添加无人机typeId
        if let drones = localFitting.drones {
            allTypeIds.append(contentsOf: drones.map { $0.type_id })
        }

        // 添加舰载机typeId
        if let fighters = localFitting.fighters {
            allTypeIds.append(contentsOf: fighters.map { $0.type_id })
        }

        // 添加货舱物品typeId
        if let cargo = localFitting.cargo {
            allTypeIds.append(contentsOf: cargo.map { $0.type_id })
        }

        // 添加植入体typeId
        if let implants = localFitting.implants {
            allTypeIds.append(contentsOf: implants)
        }

        // 3. 批量查询所有物品名称（使用标准name字段以保持EFT格式兼容性）
        var itemNames: [Int: String] = [:]
        for typeId in allTypeIds {
            guard let info = ItemInfoMap.typeInfo(for: typeId),
                  let name = pickName(name: info.name, enName: info.enName)
            else { continue }
            itemNames[typeId] = name
        }

        // 4. 按槽位分组模块
        let modulesBySlot = groupModulesBySlot(items: localFitting.items)

        // 5. 按顺序添加各槽位模块

        // 低槽模块
        if !modulesBySlot.lowSlots.isEmpty {
            lines.append("") // 空行分隔
            for item in modulesBySlot.lowSlots {
                lines.append(formatModuleLine(item: item, itemNames: itemNames))
            }
        }

        // 中槽模块
        if !modulesBySlot.medSlots.isEmpty {
            lines.append("") // 空行分隔
            for item in modulesBySlot.medSlots {
                lines.append(formatModuleLine(item: item, itemNames: itemNames))
            }
        }

        // 高槽模块
        if !modulesBySlot.hiSlots.isEmpty {
            lines.append("") // 空行分隔
            for item in modulesBySlot.hiSlots {
                lines.append(formatModuleLine(item: item, itemNames: itemNames))
            }
        }

        // 改装件
        if !modulesBySlot.rigs.isEmpty {
            lines.append("") // 空行分隔
            for item in modulesBySlot.rigs {
                lines.append(formatModuleLine(item: item, itemNames: itemNames))
            }
        }

        // 子系统
        if !modulesBySlot.subsystems.isEmpty {
            lines.append("") // 空行分隔
            for item in modulesBySlot.subsystems {
                lines.append(formatModuleLine(item: item, itemNames: itemNames))
            }
        }

        // 服务槽（如果有）
        if !modulesBySlot.services.isEmpty {
            lines.append("") // 空行分隔
            for item in modulesBySlot.services {
                lines.append(formatModuleLine(item: item, itemNames: itemNames))
            }
        }

        // 6. 无人机（两个空行分隔）
        if let drones = localFitting.drones, !drones.isEmpty {
            lines.append("")
            lines.append("")
            for drone in drones {
                if drone.quantity > 0 {
                    let droneName = itemNames[drone.type_id] ?? "Unknown Drone"
                    lines.append("\(droneName) x\(drone.quantity)")
                }
            }
        }

        // 7. 舰载机（如果有）
        if let fighters = localFitting.fighters, !fighters.isEmpty {
            if localFitting.drones?.isEmpty ?? true {
                lines.append("")
                lines.append("")
            }
            for fighter in fighters {
                if fighter.quantity > 0 {
                    let fighterName = itemNames[fighter.type_id] ?? "Unknown Fighter"
                    lines.append("\(fighterName) x\(fighter.quantity)")
                }
            }
        }

        // 8. 货舱物品（排除无人机和舰载机）
        if let cargo = localFitting.cargo, !cargo.isEmpty {
            if (localFitting.drones?.isEmpty ?? true) && (localFitting.fighters?.isEmpty ?? true) {
                lines.append("")
                lines.append("")
            }

            // 使用装备分类器过滤货舱物品，排除无人机和舰载机
            let classifier = EquipmentClassifier(databaseManager: databaseManager)
            let cargoTypeIds = cargo.map { $0.type_id }
            let cargoClassifications = classifier.classifyEquipments(typeIds: cargoTypeIds)

            for cargoItem in cargo {
                if cargoItem.quantity > 0 {
                    // 检查物品类型，排除无人机和舰载机
                    let classification = cargoClassifications[cargoItem.type_id]
                    if classification?.category != .drone && classification?.category != .fighter {
                        let itemName = itemNames[cargoItem.type_id] ?? "Unknown Item"
                        lines.append("\(itemName) x\(cargoItem.quantity)")
                    } else {
                        Logger.debug(
                            "跳过货舱中的无人机/舰载机: \(itemNames[cargoItem.type_id] ?? "Unknown") (类型: \(classification?.category.rawValue ?? "unknown"))"
                        )
                    }
                }
            }
        }

        // 9. 植入体（作为货舱物品导出）
        if let implants = localFitting.implants, !implants.isEmpty {
            // 检查是否需要添加空行分隔
            let needsEmptyLines =
                (localFitting.drones?.isEmpty ?? true) && (localFitting.fighters?.isEmpty ?? true)
                    && (localFitting.cargo?.isEmpty ?? true)
            if needsEmptyLines {
                lines.append("")
                lines.append("")
            }

            for implantTypeId in implants {
                let implantName = itemNames[implantTypeId] ?? "Unknown Implant"
                lines.append("\(implantName) x1")
            }

            if AppConfiguration.Fitting.showDebug {
                Logger.info("导出了 \(implants.count) 个植入体到EFT格式")
            }
        }

        let result = lines.joined(separator: "\n")

        // 统计导出内容
        let implantCount = localFitting.implants?.count ?? 0
        let totalLines = lines.count

        if AppConfiguration.Fitting.showDebug {
            if implantCount > 0 {
                Logger.info("EFT格式转换完成，总行数: \(totalLines)，包含 \(implantCount) 个植入体（作为货舱物品导出）")
            } else {
                Logger.info("EFT格式转换完成，总行数: \(totalLines)")
            }
        }

        return result
    }

    /// 按槽位分组模块（私有辅助方法）
    private static func groupModulesBySlot(items: [LocalFittingItem]) -> (
        lowSlots: [LocalFittingItem],
        medSlots: [LocalFittingItem],
        hiSlots: [LocalFittingItem],
        rigs: [LocalFittingItem],
        subsystems: [LocalFittingItem],
        services: [LocalFittingItem]
    ) {
        var lowSlots: [LocalFittingItem] = []
        var medSlots: [LocalFittingItem] = []
        var hiSlots: [LocalFittingItem] = []
        var rigs: [LocalFittingItem] = []
        var subsystems: [LocalFittingItem] = []
        var services: [LocalFittingItem] = []

        for item in items {
            switch item.flag {
            case .loSlot0, .loSlot1, .loSlot2, .loSlot3, .loSlot4, .loSlot5, .loSlot6, .loSlot7:
                lowSlots.append(item)
            case .medSlot0, .medSlot1, .medSlot2, .medSlot3, .medSlot4, .medSlot5, .medSlot6,
                 .medSlot7:
                medSlots.append(item)
            case .hiSlot0, .hiSlot1, .hiSlot2, .hiSlot3, .hiSlot4, .hiSlot5, .hiSlot6, .hiSlot7:
                hiSlots.append(item)
            case .rigSlot0, .rigSlot1, .rigSlot2:
                rigs.append(item)
            case .subSystemSlot0, .subSystemSlot1, .subSystemSlot2, .subSystemSlot3:
                subsystems.append(item)
            case .serviceSlot0, .serviceSlot1, .serviceSlot2, .serviceSlot3, .serviceSlot4,
                 .serviceSlot5, .serviceSlot6, .serviceSlot7:
                services.append(item)
            default:
                break
            }
        }

        // 按槽位索引排序
        lowSlots.sort { getSlotIndex(from: $0.flag) < getSlotIndex(from: $1.flag) }
        medSlots.sort { getSlotIndex(from: $0.flag) < getSlotIndex(from: $1.flag) }
        hiSlots.sort { getSlotIndex(from: $0.flag) < getSlotIndex(from: $1.flag) }
        rigs.sort { getSlotIndex(from: $0.flag) < getSlotIndex(from: $1.flag) }
        subsystems.sort { getSlotIndex(from: $0.flag) < getSlotIndex(from: $1.flag) }
        services.sort { getSlotIndex(from: $0.flag) < getSlotIndex(from: $1.flag) }

        return (lowSlots, medSlots, hiSlots, rigs, subsystems, services)
    }

    /// 格式化模块行（包含弹药信息）（私有辅助方法）
    private static func formatModuleLine(item: LocalFittingItem, itemNames: [Int: String]) -> String {
        let moduleName = itemNames[item.type_id] ?? "Unknown Module"

        if let chargeTypeId = item.charge_type_id {
            let chargeName = itemNames[chargeTypeId] ?? "Unknown Charge"
            return "\(moduleName), \(chargeName)"
        } else {
            return moduleName
        }
    }

    /// 从槽位标识获取槽位索引（私有辅助方法）
    private static func getSlotIndex(from flag: FittingFlag) -> Int {
        switch flag {
        case .loSlot0, .medSlot0, .hiSlot0, .rigSlot0, .subSystemSlot0, .serviceSlot0:
            return 0
        case .loSlot1, .medSlot1, .hiSlot1, .rigSlot1, .subSystemSlot1, .serviceSlot1:
            return 1
        case .loSlot2, .medSlot2, .hiSlot2, .rigSlot2, .subSystemSlot2, .serviceSlot2:
            return 2
        case .loSlot3, .medSlot3, .hiSlot3, .subSystemSlot3, .serviceSlot3:
            return 3
        case .loSlot4, .medSlot4, .hiSlot4, .serviceSlot4:
            return 4
        case .loSlot5, .medSlot5, .hiSlot5, .serviceSlot5:
            return 5
        case .loSlot6, .medSlot6, .hiSlot6, .serviceSlot6:
            return 6
        case .loSlot7, .medSlot7, .hiSlot7, .serviceSlot7:
            return 7
        default:
            return 999
        }
    }
}
