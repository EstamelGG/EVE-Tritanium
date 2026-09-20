import Foundation

/// 解析器
class FitConvert {
    /// 创建一个新的本地配置
    static func createInitialFitting(shipTypeId: Int) -> LocalFitting {
        return LocalFitting(
            description: "",
            fitting_id: UUID(),
            items: [],
            name: "",
            ship_type_id: shipTypeId
        )
    }

    /// 从物品属性中提取所需技能ID
    static func extractRequiredSkills(attributes: [Int: Double]) -> [Int] {
        // 技能属性ID，用于识别所需技能
        let attributeSkills: [Int] = [182, 183, 184, 1285, 1289, 1290]

        var requiredSkills: [Int] = []

        // 遍历所有技能属性ID
        for attributeSkillId in attributeSkills {
            // 如果物品有这个属性，表示需要这个技能
            if let skillValue = attributes[attributeSkillId], skillValue > 0 {
                // 技能ID是属性值的整数部分
                let skillId = Int(skillValue)
                requiredSkills.append(skillId)
            }
        }

        return requiredSkills
    }

    /// 从内存索引加载单个环境效果
    static func loadEnvironmentEffect(
        typeId: Int,
        databaseManager _: DatabaseManager
    ) -> SimEnvironmentEffect? {
        let (attributes, attributesByName) = SDEMemoryStore.typeAttributesFull(for: typeId)
        let typeInfo = SDEMemoryStore.type(for: typeId)

        return SimEnvironmentEffect(
            typeId: typeId,
            name: typeInfo?.name ?? "Unknown Environment",
            attributes: attributes,
            attributesByName: attributesByName,
            effects: SDEMemoryStore.effectIDs(forType: typeId),
            iconFileName: typeInfo?.iconFilename
        )
    }

    /// 处理舰载机配置，根据飞船可用的发射筒配置舰载机
    static func processFighters(
        shipTypeId: Int, fighterBayItems: [FittingItem], databaseManager _: DatabaseManager
    ) -> [FighterSquad] {
        // 获取飞船的舰载机槽位信息
        var lightSlotsCount = 0
        var heavySlotsCount = 0
        var supportSlotsCount = 0
        var totalFighterTubes = 0

        // 查询飞船的舰载机槽位数（内存索引）
        let (_, shipAttributesByName) = SDEMemoryStore.typeAttributesFull(for: shipTypeId)
        if let value = shipAttributesByName["fighterLightSlots"] {
            lightSlotsCount = Int(value)
        }
        if let value = shipAttributesByName["fighterHeavySlots"] {
            heavySlotsCount = Int(value)
        }
        if let value = shipAttributesByName["fighterSupportSlots"] {
            supportSlotsCount = Int(value)
        }
        if let value = shipAttributesByName["fighterTubes"] {
            totalFighterTubes = Int(value)
        }

        // 如果飞船不支持舰载机，直接返回空数组
        if totalFighterTubes <= 0 {
            return []
        }

        // 获取所有舰载机的ID列表
        let fighterTypeIds = fighterBayItems.map { $0.type_id }

        // 如果没有舰载机，直接返回空数组
        if fighterTypeIds.isEmpty {
            return []
        }

        // 批量获取舰载机信息（内存索引）
        // 存储舰载机信息
        var fighterInfoMap: [Int: (marketGroupId: Int, name: String, maxSquadSize: Int)] = [:]

        if let maxSizeAttrID = SDEMemoryStore.attributeID(named: "fighterSquadronMaxSize") {
            for typeId in fighterTypeIds {
                guard let typeInfo = SDEMemoryStore.type(for: typeId),
                      let marketGroupId = typeInfo.marketGroupID
                else { continue }

                // 获取最大中队大小，默认为1
                var maxSquadSize = 1
                if let squadSize = SDEMemoryStore.typeAttributeValue(for: typeId, attributeID: maxSizeAttrID),
                   squadSize > 0
                {
                    maxSquadSize = Int(squadSize)
                }

                fighterInfoMap[typeId] = (
                    marketGroupId: marketGroupId, name: typeInfo.name, maxSquadSize: maxSquadSize
                )
            }
        }

        // 按类型分类舰载机
        var heavyFighters: [(typeId: Int, maxSquadSize: Int)] = []
        var supportFighters: [(typeId: Int, maxSquadSize: Int)] = []
        var lightFighters: [(typeId: Int, maxSquadSize: Int)] = []

        for (typeId, info) in fighterInfoMap {
            switch info.marketGroupId {
            case 1310: // 重型舰载机
                heavyFighters.append((typeId: typeId, maxSquadSize: info.maxSquadSize))
                if AppConfiguration.Fitting.showDebug {
                    Logger.info("发现重型舰载机: \(info.name), 最大中队大小: \(info.maxSquadSize)")
                }
            case 2239: // 辅助舰载机
                supportFighters.append((typeId: typeId, maxSquadSize: info.maxSquadSize))
                if AppConfiguration.Fitting.showDebug {
                    Logger.info("发现辅助舰载机: \(info.name), 最大中队大小: \(info.maxSquadSize)")
                }
            case 840: // 轻型舰载机
                lightFighters.append((typeId: typeId, maxSquadSize: info.maxSquadSize))
                if AppConfiguration.Fitting.showDebug {
                    Logger.info("发现轻型舰载机: \(info.name), 最大中队大小: \(info.maxSquadSize)")
                }
            default:
                Logger.warning("未知类型舰载机 marketGroupId: \(info.marketGroupId), typeId: \(typeId)")
            }
        }

        // 对舰载机按typeId排序（升序）
        heavyFighters.sort { $0.typeId < $1.typeId }
        supportFighters.sort { $0.typeId < $1.typeId }
        lightFighters.sort { $0.typeId < $1.typeId }

        // 结果数组
        var fighters: [FighterSquad] = []
        var usedTubes = 0

        // 按优先级添加舰载机（重型 > 辅助 > 轻型）

        // 1. 添加重型舰载机
        if !heavyFighters.isEmpty, heavySlotsCount > 0 {
            let fighter = heavyFighters.first!

            // 计算可添加的数量
            let availableTubes = min(heavySlotsCount, totalFighterTubes - usedTubes)

            for i in 0 ..< availableTubes {
                fighters.append(
                    FighterSquad(
                        type_id: fighter.typeId,
                        quantity: fighter.maxSquadSize,
                        tubeId: 100 + i
                    )
                )
                usedTubes += 1
            }

            if AppConfiguration.Fitting.showDebug {
                Logger.info(
                    "添加重型舰载机: \(fighter.typeId), 数量: \(availableTubes), 中队大小: \(fighter.maxSquadSize)"
                )
            }
        }

        // 2. 添加辅助舰载机
        if !supportFighters.isEmpty, supportSlotsCount > 0, usedTubes < totalFighterTubes {
            let fighter = supportFighters.first!

            // 计算可添加的数量
            let availableTubes = min(supportSlotsCount, totalFighterTubes - usedTubes)

            for i in 0 ..< availableTubes {
                fighters.append(
                    FighterSquad(
                        type_id: fighter.typeId,
                        quantity: fighter.maxSquadSize,
                        tubeId: 200 + i
                    )
                )
                usedTubes += 1
            }

            if AppConfiguration.Fitting.showDebug {
                Logger.info(
                    "添加辅助舰载机: \(fighter.typeId), 数量: \(availableTubes), 中队大小: \(fighter.maxSquadSize)"
                )
            }
        }

        // 3. 添加轻型舰载机
        if !lightFighters.isEmpty, lightSlotsCount > 0, usedTubes < totalFighterTubes {
            let fighter = lightFighters.first!

            // 计算可添加的数量
            let availableTubes = min(lightSlotsCount, totalFighterTubes - usedTubes)

            for i in 0 ..< availableTubes {
                fighters.append(
                    FighterSquad(
                        type_id: fighter.typeId,
                        quantity: fighter.maxSquadSize,
                        tubeId: i
                    )
                )
                usedTubes += 1
            }

            if AppConfiguration.Fitting.showDebug {
                Logger.info(
                    "添加轻型舰载机: \(fighter.typeId), 数量: \(availableTubes), 中队大小: \(fighter.maxSquadSize)"
                )
            }
        }

        if AppConfiguration.Fitting.showDebug {
            Logger.info("舰载机配置完成，总共添加了 \(fighters.count) 个舰载机，使用了 \(usedTubes) 个发射筒")
        }
        return fighters
    }

    /// 将模拟器输入数据转为本地配置
    static func simulationInputToLocalFitting(input: SimulationInput) -> LocalFitting {
        // 本地装配沿用原 ID；在线/临时装配保存为本地时生成新 UUID
        let fitId: UUID
        if case let .local(uuid) = input.fittingId {
            fitId = uuid
        } else {
            fitId = UUID()
        }

        // 如果有舰载机，先检查其完整性
        if AppConfiguration.Fitting.showDebug, let fighters = input.fighters {
            Logger.info("检查SimFighterSquad到FighterSquad转换前的数据: 数量 = \(fighters.count)")
            for (index, fighter) in fighters.enumerated() {
                Logger.info(
                    "SimFighterSquad[\(index)]: typeId=\(fighter.typeId), tubeId=\(fighter.tubeId), quantity=\(fighter.quantity)"
                )
            }
        }

        // 从模块数据中恢复装备项
        let items = input.modules.map { module -> LocalFittingItem in
            // 添加调试日志，记录弹药信息
            if AppConfiguration.Fitting.showDebug, let charge = module.charge {
                Logger.info(
                    "转换装备弹药: 装备=\(module.name), 弹药=\(charge.name), 弹药数量=\(charge.chargeQuantity ?? -1)"
                )
            }

            // 构建突变数据（直接存储倍数：+15%就是1.15，-20%是0.8）
            var mutaData: [MutationData]? = nil
            if let mutaplasmidID = module.selectedMutaplasmidID, !module.mutatedAttributes.isEmpty {
                mutaData = module.mutatedAttributes.map { attributeID, multiplier in
                    // 直接存储倍数（不带百分号）
                    MutationData(
                        mutaplasmid_id: mutaplasmidID,
                        attribute_id: attributeID,
                        value: multiplier
                    )
                }
            }

            return LocalFittingItem(
                flag: module.flag ?? .invalid,
                quantity: module.quantity,
                type_id: module.typeId,
                status: module.status,
                charge_type_id: module.charge?.typeId,
                charge_quantity: module.charge?.chargeQuantity,
                muta: mutaData,
                spool_up_full: module.isSpoolUpFull ? nil : false
            )
        }

        // 从无人机数据中恢复无人机列表
        let drones =
            input.drones.isEmpty
                ? nil
                : input.drones.map { drone -> Drone in
                    // 构建突变数据（直接存储倍数：+15%就是1.15，-20%是0.8）
                    var mutaData: [MutationData]? = nil
                    if let mutaplasmidID = drone.selectedMutaplasmidID, !drone.mutatedAttributes.isEmpty {
                        mutaData = drone.mutatedAttributes.map { attributeID, multiplier in
                            // 直接存储倍数（不带百分号）
                            MutationData(
                                mutaplasmid_id: mutaplasmidID,
                                attribute_id: attributeID,
                                value: multiplier
                            )
                        }
                    }

                    return Drone(
                        type_id: drone.typeId,
                        quantity: drone.quantity,
                        active_count: drone.activeCount,
                        muta: mutaData
                    )
                }

        // 从SimFighterSquad转换为FighterSquad
        let fighters = input.fighters?.map { simFighter -> FighterSquad in
            FighterSquad(
                type_id: simFighter.typeId,
                quantity: simFighter.quantity,
                tubeId: simFighter.tubeId
            )
        }

        // 检查转换后的舰载机数据
        if AppConfiguration.Fitting.showDebug, let fighters = fighters {
            Logger.info("检查转换后的FighterSquad数据: 数量 = \(fighters.count)")
            for (index, fighter) in fighters.enumerated() {
                Logger.info(
                    "FighterSquad[\(index)]: type_id=\(fighter.type_id), tubeId=\(fighter.tubeId), quantity=\(fighter.quantity)"
                )
            }
        }

        // 从货舱数据中恢复货舱物品列表
        let cargo =
            input.cargo.items.isEmpty
                ? nil
                : input.cargo.items.map { item -> CargoItem in
                    CargoItem(
                        type_id: item.typeId,
                        quantity: item.quantity
                    )
                }

        // 从植入体数据中提取typeId列表
        let implants =
            input.implants.isEmpty
                ? nil
                : input.implants.map { implant -> Int in
                    implant.typeId
                }

        // 创建并返回LocalFitting
        return LocalFitting(
            description: input.description,
            fitting_id: fitId,
            items: items,
            name: input.name,
            ship_type_id: input.ship.typeId,
            drones: drones,
            fighters: fighters,
            cargo: cargo,
            implants: implants, // 保存植入体typeId列表
            environment_type_id: input.environmentEffects.first?.typeId
        )
    }

    /// 将模拟器输入数据直接转换为在线配置格式
    /// - Parameter input: 模拟器输入数据
    /// - Returns: 在线配置数据，适用于上传到EVE服务器
    static func simulationInputToCharacterFitting(input: SimulationInput) -> CharacterFitting {
        if AppConfiguration.Fitting.showDebug {
            Logger.info("开始将SimulationInput转换为CharacterFitting - 配置名称: \(input.name)")
        }

        // 创建装备项列表，只包含安装在飞船上的装备（排除货舱、无人机舱等）
        var items: [FittingItem] = []

        // 1. 添加模块装备
        for module in input.modules {
            if let flag = module.flag, flag != .cargo && flag != .droneBay && flag != .fighterBay {
                let item = FittingItem(
                    flag: flag,
                    quantity: module.quantity,
                    type_id: module.typeId
                )
                items.append(item)
                if AppConfiguration.Fitting.showDebug {
                    Logger.debug("添加模块: \(module.name), flag: \(flag), typeId: \(module.typeId)")
                }
            }
        }

        // 2. 添加无人机到无人机舱
        for drone in input.drones {
            let item = FittingItem(
                flag: .droneBay,
                quantity: drone.quantity,
                type_id: drone.typeId
            )
            items.append(item)
            if AppConfiguration.Fitting.showDebug {
                Logger.debug("添加无人机: \(drone.name), 数量: \(drone.quantity)")
            }
        }

        // 3. 添加舰载机到舰载机舱
        if let fighters = input.fighters {
            for fighter in fighters {
                let item = FittingItem(
                    flag: .fighterBay,
                    quantity: fighter.quantity,
                    type_id: fighter.typeId
                )
                items.append(item)
                if AppConfiguration.Fitting.showDebug {
                    Logger.debug("添加舰载机: \(fighter.name), 数量: \(fighter.quantity)")
                }
            }
        }

        // 4. 添加货舱物品
        for cargoItem in input.cargo.items {
            let item = FittingItem(
                flag: .cargo,
                quantity: cargoItem.quantity,
                type_id: cargoItem.typeId
            )
            items.append(item)
            if AppConfiguration.Fitting.showDebug {
                Logger.debug("添加货舱物品: \(cargoItem.name), 数量: \(cargoItem.quantity)")
            }
        }

        // 创建在线配置对象
        let characterFitting = CharacterFitting(
            description: input.description.isEmpty ? nil : input.description,
            fitting_id: 0, // 新上传的配置ID为0
            items: items,
            name: input.name.isEmpty ? "Untitled Fitting" : input.name,
            ship_type_id: input.ship.typeId
        )

        if AppConfiguration.Fitting.showDebug {
            Logger.info("SimulationInput转换完成 - 总装备数: \(items.count), 飞船ID: \(input.ship.typeId)")
        }
        return characterFitting
    }
}
