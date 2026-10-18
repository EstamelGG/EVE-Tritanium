import Foundation
import SwiftUI

extension FittingEditorViewModel {
    // MARK: - 舰载机相关方法

    /// 根据ID获取数据库物品信息
    func getDatabaseItemInfo(typeId: Int) -> DatabaseListItem? {
        DatabaseListItem(typeID: typeId, databaseManager: databaseManager)
    }

    /// 获取舰载机信息
    func getFighterInfo(typeId: Int) -> (typeId: Int, groupID: Int?)? {
        guard let info = ItemInfoMap.typeInfo(for: typeId) else {
            return nil
        }
        return (typeId: typeId, groupID: info.groupID)
    }

    /// 添加或更新舰载机
    func addOrUpdateFighter(_ fighter: SimFighterSquad, name: String, iconFileName: String?) {
        // 获取舰载机的完整信息（包括属性和效果）
        let fighterInfo = getFighterInfo(typeId: fighter.typeId)

        // 获取舰载机的基础属性
        let (attributes, attributesByName) = loadFighterBaseAttributes(typeId: fighter.typeId)

        // 创建包含完整属性的舰载机对象
        let updatedFighter = SimFighterSquad(
            typeId: fighter.typeId,
            attributes: attributes,
            attributesByName: attributesByName,
            effects: [], // 效果将在属性计算过程中加载
            quantity: fighter.quantity,
            tubeId: fighter.tubeId,
            groupID: fighterInfo?.groupID ?? 0,
            requiredSkills: FitConvert.extractRequiredSkills(attributes: attributes),
            name: name,
            iconFileName: iconFileName
        )

        // 检查是否已存在该发射管中的舰载机
        if let fighters = simulationInput.fighters,
           let index = fighters.firstIndex(where: { $0.tubeId == fighter.tubeId })
        {
            // 更新现有舰载机
            var updatedFighters = fighters
            updatedFighters[index] = updatedFighter
            simulationInput.fighters = updatedFighters
        } else {
            // 添加新舰载机
            var fighters = simulationInput.fighters ?? []
            fighters.append(updatedFighter)
            simulationInput.fighters = fighters
        }

        // 重新计算属性
        calculateAttributes()

        Logger.info("添加/更新舰载机: typeId=\(fighter.typeId), tubeId=\(fighter.tubeId)")
    }

    /// 移除舰载机
    func removeFighter(tubeId: Int) {
        guard let fighters = simulationInput.fighters else { return }

        Logger.info("开始移除舰载机: tubeId=\(tubeId), 当前舰载机数量: \(fighters.count)")

        // 筛选出要保留的舰载机（移除指定tubeId的舰载机）
        let updatedFighters = fighters.filter { $0.tubeId != tubeId }

        Logger.info("过滤后舰载机数量: \(updatedFighters.count)")

        // 如果移除后列表为空，则设置为nil
        if updatedFighters.isEmpty {
            simulationInput.fighters = nil
            Logger.info("所有舰载机都被移除，fighters设置为nil")
        } else {
            simulationInput.fighters = updatedFighters
        }

        Logger.info("开始重新计算属性...")
        // 重新计算属性
        calculateAttributes()

        Logger.info("开始保存配置...")

        Logger.info("舰载机移除完成: tubeId=\(tubeId)")
    }

    // MARK: - 舰载机相关属性

    /// 舰载机属性计算结果
    var fighterAttributes:
        (
            light: (used: Int, total: Int), heavy: (used: Int, total: Int),
            support: (used: Int, total: Int)
        )
    {
        // 获取各类型舰载机槽位数量
        let lightTotal = Int(simulationInput.ship.baseAttributesByName["fighterLightSlots"] ?? 0)
        let heavyTotal = Int(simulationInput.ship.baseAttributesByName["fighterHeavySlots"] ?? 0)
        let supportTotal = Int(
            simulationInput.ship.baseAttributesByName["fighterSupportSlots"] ?? 0
        )

        // 获取飞船总的舰载机管数
        let totalFighterTubes = Int(simulationInput.ship.baseAttributesByName["fighterTubes"] ?? 0)

        // 初始化使用数量
        var lightUsed = 0
        var heavyUsed = 0
        var supportUsed = 0

        // 自动检查和清理超额的舰载机
        if let fighters = simulationInput.fighters, totalFighterTubes > 0 {
            var validFighters: [SimFighterSquad] = []
            var currentCount = 0

            for fighter in fighters {
                // 修改此处，直接使用tubeId而不是进行可选绑定
                let tubeId = fighter.tubeId
                // 如果超过总管数限制，跳过该舰载机
                if currentCount >= totalFighterTubes {
                    continue
                }

                validFighters.append(fighter)
                currentCount += 1

                // 统计各类型舰载机数量
                if tubeId >= 0, tubeId < 100 {
                    // 轻型舰载机
                    lightUsed += 1
                } else if tubeId >= 100, tubeId < 200 {
                    // 重型舰载机
                    heavyUsed += 1
                } else if tubeId >= 200 {
                    // 辅助舰载机
                    supportUsed += 1
                }
            }

            // 如果有舰载机被移除，更新simulationInput
            if fighters.count != validFighters.count {
                Logger.info("自动移除了 \(fighters.count - validFighters.count) 个超额舰载机")
                simulationInput.fighters = validFighters.isEmpty ? nil : validFighters
            }
        } else {
            // 统计舰载机数量（无需清理的情况）
            if let fighters = simulationInput.fighters {
                for fighter in fighters {
                    // 修改此处，直接使用tubeId而不是进行可选绑定
                    let tubeId = fighter.tubeId
                    if tubeId >= 0, tubeId < 100 {
                        // 轻型舰载机
                        lightUsed += 1
                    } else if tubeId >= 100, tubeId < 200 {
                        // 重型舰载机
                        heavyUsed += 1
                    } else if tubeId >= 200 {
                        // 辅助舰载机
                        supportUsed += 1
                    }
                }
            }
        }

        return (
            light: (used: lightUsed, total: lightTotal),
            heavy: (used: heavyUsed, total: heavyTotal),
            support: (used: supportUsed, total: supportTotal)
        )
    }

    /// 更新舰载机数量
    func updateFighterQuantity(tubeId: Int, quantity: Int) {
        guard let fighters = simulationInput.fighters,
              let index = fighters.firstIndex(where: { $0.tubeId == tubeId })
        else { return }

        // 获取现有舰载机
        let fighter = fighters[index]

        // 如果数量没有变化，直接返回
        if fighter.quantity == quantity {
            return
        }

        // 创建更新后的舰载机对象
        let updatedFighter = SimFighterSquad(
            typeId: fighter.typeId,
            attributes: fighter.attributes,
            attributesByName: fighter.attributesByName,
            effects: fighter.effects,
            quantity: quantity,
            tubeId: fighter.tubeId,
            groupID: fighter.groupID,
            requiredSkills: fighter.requiredSkills,
            name: fighter.name,
            iconFileName: fighter.iconFileName
        )

        // 更新舰载机列表
        var updatedFighters = fighters
        updatedFighters[index] = updatedFighter
        simulationInput.fighters = updatedFighters

        // 仅记录日志，不重新计算属性和保存配置
        // 这部分会在舰载机设置页面关闭时执行
        Logger.info("更新舰载机数量: typeId=\(fighter.typeId), tubeId=\(fighter.tubeId), 数量=\(quantity)")
    }

    /// 加载舰载机的基础属性
    func loadFighterBaseAttributes(typeId: Int) -> ([Int: Double], [String: Double]) {
        // 查询舰载机的基础属性（内存索引；name 缺失时跳过，与旧 LEFT JOIN 行为一致）
        SDEMemoryStore.typeAttributesFull(for: typeId)
    }
}
