import Foundation

/// 收集参与模拟的类型与效果。属性由 SimulationInput 和 Step3 的技能初始化提供。
class Step1 {
    private let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    func process(input: SimulationInput) -> [Int: [EffectDetail]] {
        var typeInfo: [Int: (name: String, groupId: Int)] = [:]
        func include(_ id: Int, _ name: String, _ groupId: Int) {
            typeInfo[id] = (name, groupId)
        }
        include(input.ship.typeId, input.ship.name, input.ship.groupID)
        include(input.character.typeId, "Character", 0)
        for module in input.modules {
            include(module.typeId, module.name, module.groupID)
            if let charge = module.charge {
                include(charge.typeId, charge.name, charge.groupID)
            }
        }
        for drone in input.drones {
            include(drone.typeId, drone.name, drone.groupID)
        }
        for fighter in input.fighters ?? [] {
            include(fighter.typeId, fighter.name, fighter.groupID)
        }
        for implant in input.implants {
            include(implant.typeId, implant.name, implant.groupID)
        }
        for effect in input.environmentEffects {
            include(effect.typeId, effect.name, 0)
        }
        for id in input.characterSkills.keys where typeInfo[id] == nil {
            let info = SDEMemoryStore.type(for: id)
            include(id, info?.name ?? "Unknown", info?.groupID ?? 0)
        }

        let ids = Array(typeInfo.keys)
        var effects = Dictionary(uniqueKeysWithValues: ids.map { ($0, [EffectDetail]()) })
        collectEffects(ids: ids, effects: &effects, typeInfo: typeInfo)
        collectDbuffCollectionModifiers(ids: ids, effects: &effects, typeInfo: typeInfo)
        return effects
    }

    /// 收集效果
    /// - Parameters:
    ///   - ids: 需要收集效果的ID数组
    ///   - effects: 效果字典（会被修改）
    ///   - typeInfo: 类型信息字典
    private func collectEffects(
        ids: [Int],
        effects: inout [Int: [EffectDetail]],
        typeInfo: [Int: (name: String, groupId: Int)]
    ) {
        // 收集效果信息（内存索引：typeEffects + dogmaEffects）
        for typeId in ids {
            let (typeName, groupId) = typeInfo[typeId] ?? ("Unknown", 0)

            for entry in SDEMemoryStore.typeEffects(forType: typeId) {
                guard let effect = SDEMemoryStore.dogmaEffect(for: entry.effectID) else { continue }

                // 创建效果详情对象
                let effectDetail = EffectDetail(
                    effectId: effect.effectID,
                    effectName: effect.effectName,
                    effectCategory: effect.effectCategory,
                    description: effect.description,

                    typeId: typeId,
                    typeName: typeName,
                    groupId: groupId,

                    isDefault: entry.isDefault,
                    isOffensive: effect.isOffensive,
                    isAssistance: effect.isAssistance,
                    modifierInfo: effect.modifierInfo
                )

                // 添加到对应物品的效果数组
                effects[typeId]?.append(effectDetail)
            }
        }
    }

    /// 收集dbuffCollection表中的修饰器
    /// - Parameters:
    ///   - ids: 需要收集修饰器的ID数组
    ///   - effects: 效果字典（会被修改）
    ///   - typeInfo: 类型信息字典
    private func collectDbuffCollectionModifiers(
        ids: [Int],
        effects: inout [Int: [EffectDetail]],
        typeInfo: [Int: (name: String, groupId: Int)]
    ) {
        if ids.isEmpty {
            return
        }

        // 构建IN查询的占位符
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")

        // 查询dbuffCollection表中的修饰器
        let dbuffQuery = """
            SELECT 
                dbuff_id, 
                type_id, 
                dbuff_name, 
                modifier_info
            FROM dbuffCollection
            WHERE type_id IN (\(placeholders))
        """

        if case let .success(rows) = databaseManager.executeQuery(dbuffQuery, parameters: ids) {
            for row in rows {
                if let dbuffId = row["dbuff_id"] as? Int,
                   let typeId = row["type_id"] as? Int,
                   let dbuffName = row["dbuff_name"] as? String,
                   let modifierInfo = row["modifier_info"] as? String
                {
                    // 从typeInfo获取物品名称和分组ID
                    let (typeName, groupId) = typeInfo[typeId] ?? ("Unknown", 0)

                    // 创建特殊的EffectDetail对象来表示dbuff修饰器
                    // 使用负数的effectId来区分dbuff修饰器和普通效果
                    let effectDetail = EffectDetail(
                        effectId: -dbuffId, // 使用负数来区分dbuff
                        effectName: dbuffName,
                        effectCategory: 1, // dbuff修饰器默认为主动效果
                        description: "DbuffCollection修饰器: \(dbuffName)",

                        typeId: typeId,
                        typeName: typeName,
                        groupId: groupId,

                        isDefault: false,
                        isOffensive: false,
                        isAssistance: false,
                        modifierInfo: modifierInfo
                    )

                    // 添加到对应物品的效果数组
                    effects[typeId]?.append(effectDetail)
                }
            }

            Logger.info("从dbuffCollection表收集了\(rows.count)个额外修饰器")
        } else {
            Logger.warning("查询dbuffCollection表失败")
        }
    }
}
