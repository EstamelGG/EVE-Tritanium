import Foundation

extension FitConvert {
    /// 将本地配置转为模拟器输入数据
    static func localFittingToSimulationInput(
        localFitting: LocalFitting,
        databaseManager: DatabaseManager,
        characterSkills: [Int: Int]
    ) -> SimulationInput {
        // 1. 飞船数据
        let shipTypeId = localFitting.ship_type_id
        var shipBaseAttributes: [Int: Double] = [:]
        var shipBaseAttributesByName: [String: Double] = [:]
        var shipEffects: [Int] = []
        var shipGroupID = 0

        // 创建可变的modules数组副本
        var moduleItems = localFitting.items
        // Add the default mode before collecting types, attributes and effects.
        // Otherwise a missing mode can never be found in the original fitting's type map.
        if !moduleItems.contains(where: { $0.flag == .t3dModeSlot0 }),
           let modeId = ModeSwitchingUtils.getDefaultModeId(for: shipTypeId, databaseManager: databaseManager)
        {
            moduleItems.append(LocalFittingItem(flag: .t3dModeSlot0, quantity: 1, type_id: modeId))
        }

        // 收集所有需要查询的typeId（飞船、装备、无人机和弹药）
        var allTypeIds =
            [shipTypeId] + moduleItems.map { $0.type_id }
                + (localFitting.drones?.map { $0.type_id } ?? [])
                + (localFitting.fighters?.map { $0.type_id } ?? [])

        // 添加所有弹药的typeId
        let chargeTypeIds = moduleItems.compactMap { $0.charge_type_id }
        allTypeIds.append(contentsOf: chargeTypeIds)
        allTypeIds = Array(Set(allTypeIds)).sorted()

        // 批量取属性（内存索引）
        var attrMap: [Int: ([Int: Double], [String: Double])] = [:]
        for (typeId, attrs) in SDEMemoryStore.typeAttributes(for: allTypeIds) {
            attrMap[typeId] = (attrs.attributes, attrs.attributesByName)
        }

        // 查询所有效果（飞船、装备、无人机）
        var effectMap: [Int: [Int]] = [:]
        for typeId in allTypeIds {
            effectMap[typeId] = SDEMemoryStore.effectIDs(forType: typeId)
        }

        var typeInfoMap:
            [Int: (
                groupID: Int, capacity: Double, volume: Double, mass: Double, name: String,
                iconFileName: String?
            )] = [:]
        for typeId in allTypeIds {
            guard let info = SDEMemoryStore.type(for: typeId) else { continue }
            typeInfoMap[typeId] = (
                groupID: info.groupID ?? 0,
                capacity: info.capacity,
                volume: info.volume,
                mass: info.mass,
                name: info.name.isEmpty ? "Unknown" : info.name,
                iconFileName: info.iconFilename
            )
        }

        // 设置飞船数据
        if let shipAttr = attrMap[shipTypeId] {
            shipBaseAttributes = shipAttr.0
            shipBaseAttributesByName = shipAttr.1
        }
        shipEffects = effectMap[shipTypeId] ?? []

        // 获取飞船信息
        let shipInfo =
            typeInfoMap[shipTypeId] ?? (
                groupID: 0, capacity: 0, volume: 0, mass: 0, name: "Unknown Ship", iconFileName: nil
            )
        shipGroupID = shipInfo.groupID

        // 将types表中的物理属性添加到baseAttributes和baseAttributesByName中
        // 质量 (mass) - 属性ID 4
        shipBaseAttributes[4] = shipInfo.mass
        shipBaseAttributesByName["mass"] = shipInfo.mass

        // 容量 (capacity) - 属性ID 38
        shipBaseAttributes[38] = shipInfo.capacity
        shipBaseAttributesByName["capacity"] = shipInfo.capacity

        // 体积 (volume) - 属性ID 161
        shipBaseAttributes[161] = shipInfo.volume
        shipBaseAttributesByName["volume"] = shipInfo.volume

        let simShip = SimShip(
            typeId: shipTypeId,
            baseAttributes: shipBaseAttributes,
            baseAttributesByName: shipBaseAttributesByName,
            effects: shipEffects,
            groupID: shipGroupID,
            name: shipInfo.name,
            iconFileName: shipInfo.iconFileName,
            requiredSkills: extractRequiredSkills(attributes: shipBaseAttributes)
        )

        // 2. 装备数据
        var modules: [SimModule] = []
        if !moduleItems.isEmpty {
            // 组装SimModule
            for item in moduleItems {
                let attr = attrMap[item.type_id]?.0 ?? [:]
                let attrName = attrMap[item.type_id]?.1 ?? [:]
                let effects = effectMap[item.type_id] ?? []

                // 获取装备信息
                let moduleInfo =
                    typeInfoMap[item.type_id] ?? (
                        groupID: 0, capacity: 0, volume: 0, mass: 0, name: "Unknown Module",
                        iconFileName: nil
                    )

                // 确保将capacity和volume添加到属性字典中
                var updatedAttr = attr
                var updatedAttrName = attrName

                // 容量 (capacity) - 属性ID 38
                if moduleInfo.capacity > 0 {
                    updatedAttr[38] = moduleInfo.capacity
                    updatedAttrName["capacity"] = moduleInfo.capacity
                }

                // 体积 (volume) - 属性ID 161
                updatedAttr[161] = moduleInfo.volume
                updatedAttrName["volume"] = moduleInfo.volume

                // 获取弹药信息（如有）
                var charge: SimCharge? = nil
                if let chargeTypeId = item.charge_type_id {
                    let chargeAttr = attrMap[chargeTypeId]?.0 ?? [:]
                    let chargeAttrName = attrMap[chargeTypeId]?.1 ?? [:]
                    let chargeEffects = effectMap[chargeTypeId] ?? []

                    // 获取弹药信息
                    let chargeInfo =
                        typeInfoMap[chargeTypeId] ?? (
                            groupID: 0, capacity: 0, volume: 0, mass: 0, name: "Unknown Charge",
                            iconFileName: nil
                        )

                    // 确保volume添加到弹药的属性字典中
                    var updatedChargeAttr = chargeAttr
                    var updatedChargeAttrName = chargeAttrName

                    // 体积 (volume) - 属性ID 161
                    updatedChargeAttr[161] = chargeInfo.volume
                    updatedChargeAttrName["volume"] = chargeInfo.volume

                    charge = SimCharge(
                        typeId: chargeTypeId,
                        attributes: updatedChargeAttr,
                        attributesByName: updatedChargeAttrName,
                        effects: chargeEffects,
                        groupID: chargeInfo.groupID,
                        chargeQuantity: item.charge_quantity,
                        requiredSkills: extractRequiredSkills(attributes: updatedChargeAttr),
                        name: chargeInfo.name,
                        iconFileName: chargeInfo.iconFileName
                    )
                }

                // 加载突变数据（直接使用倍数：1.15表示+15%，0.8表示-20%）
                var selectedMutaplasmidID: Int? = nil
                var mutatedAttributes: [Int: Double] = [:]
                var mutatedTypeId: Int? = nil
                var mutatedName: String? = nil
                var mutatedIconFileName: String? = nil

                if let mutaData = item.muta, !mutaData.isEmpty {
                    // 取第一个突变数据的mutaplasmid_id（所有突变数据应该来自同一个突变质体）
                    selectedMutaplasmidID = mutaData.first?.mutaplasmid_id
                    // 直接使用倍数（value已经是倍数）
                    for mutation in mutaData {
                        mutatedAttributes[mutation.attribute_id] = mutation.value
                    }

                    // 查询突变后的typeID、名称和图标
                    if let mutaplasmidID = selectedMutaplasmidID {
                        if let resultingTypeId = databaseManager.getMutatedTypeID(
                            applicableTypeID: item.type_id,
                            mutaplasmidID: mutaplasmidID
                        ) {
                            mutatedTypeId = resultingTypeId

                            // 查询突变后的名称和图标
                            if let info = ItemInfoMap.typeInfo(for: resultingTypeId) {
                                mutatedName = info.name
                                mutatedIconFileName = info.iconFilename
                            }
                        }
                    }
                }

                let simModule = SimModule(
                    typeId: item.type_id,
                    attributes: updatedAttr,
                    attributesByName: updatedAttrName,
                    effects: effects,
                    groupID: moduleInfo.groupID,
                    status: {
                        // Explicit saved states must round-trip, including online but inactive (1).
                        // Only missing/invalid states use the optimistic installation default.
                        if let status = item.status, (0 ... 3).contains(status) {
                            return status
                        }
                        let maxStatus = getMaxStatus(
                            itemEffects: effects,
                            itemAttributes: updatedAttr,
                            databaseManager: databaseManager
                        )
                        return maxStatus >= 2 ? 2 : (maxStatus == 1 ? 1 : 0)
                    }(),
                    charge: charge,
                    flag: item.flag,
                    quantity: item.quantity,
                    name: moduleInfo.name,
                    iconFileName: moduleInfo.iconFileName,
                    requiredSkills: extractRequiredSkills(attributes: updatedAttr),
                    selectedMutaplasmidID: selectedMutaplasmidID,
                    mutatedAttributes: mutatedAttributes,
                    mutatedTypeId: mutatedTypeId,
                    mutatedName: mutatedName,
                    mutatedIconFileName: mutatedIconFileName,
                    isSpoolUpFull: item.spool_up_full ?? true
                )

                modules.append(simModule)
            }
        }

        // 3. 无人机
        var drones: [SimDrone] = []
        if let droneList = localFitting.drones {
            for drone in droneList {
                let attr = attrMap[drone.type_id]?.0 ?? [:]
                let attrName = attrMap[drone.type_id]?.1 ?? [:]
                let effects = effectMap[drone.type_id] ?? []

                // 获取无人机信息
                let droneInfo =
                    typeInfoMap[drone.type_id] ?? (
                        groupID: 0, capacity: 0, volume: 0, mass: 0, name: "Unknown Drone",
                        iconFileName: nil
                    )

                // 确保volume添加到无人机的属性字典中
                var updatedAttr = attr
                var updatedAttrName = attrName

                // 体积 (volume) - 属性ID 161
                updatedAttr[161] = droneInfo.volume
                updatedAttrName["volume"] = droneInfo.volume

                // 加载突变数据（直接使用倍数：1.15表示+15%，0.8表示-20%）
                var selectedMutaplasmidID: Int? = nil
                var mutatedAttributes: [Int: Double] = [:]
                var mutatedTypeId: Int? = nil
                var mutatedName: String? = nil
                var mutatedIconFileName: String? = nil

                if let mutaData = drone.muta, !mutaData.isEmpty {
                    // 取第一个突变数据的mutaplasmid_id（所有突变数据应该来自同一个突变质体）
                    selectedMutaplasmidID = mutaData.first?.mutaplasmid_id
                    // 直接使用倍数（value已经是倍数）
                    for mutation in mutaData {
                        mutatedAttributes[mutation.attribute_id] = mutation.value
                    }

                    // 查询突变后的typeID、名称和图标
                    if let mutaplasmidID = selectedMutaplasmidID {
                        if let resultingTypeId = databaseManager.getMutatedTypeID(
                            applicableTypeID: drone.type_id,
                            mutaplasmidID: mutaplasmidID
                        ) {
                            mutatedTypeId = resultingTypeId

                            // 查询突变后的名称和图标
                            if let info = ItemInfoMap.typeInfo(for: resultingTypeId) {
                                mutatedName = info.name
                                mutatedIconFileName = info.iconFilename
                            }
                        }
                    }
                }

                var simDrone = SimDrone(
                    typeId: drone.type_id,
                    attributes: updatedAttr,
                    attributesByName: updatedAttrName,
                    effects: effects,
                    quantity: drone.quantity,
                    activeCount: drone.active_count,
                    groupID: droneInfo.groupID,
                    requiredSkills: extractRequiredSkills(attributes: updatedAttr),
                    name: droneInfo.name,
                    iconFileName: droneInfo.iconFileName
                )
                // 设置突变数据
                simDrone.selectedMutaplasmidID = selectedMutaplasmidID
                simDrone.mutatedAttributes = mutatedAttributes
                simDrone.mutatedTypeId = mutatedTypeId
                simDrone.mutatedName = mutatedName
                simDrone.mutatedIconFileName = mutatedIconFileName

                drones.append(simDrone)
            }
        }

        // 4. 货舱
        var cargoItems: [SimCargoItem] = []
        if let cargoList = localFitting.cargo {
            // 收集所有货舱物品的typeId
            let cargoTypeIds = cargoList.map { $0.type_id }

            // 为货舱物品单独查询最新信息
            var cargoItemInfoMap: [Int: (name: String, volume: Double, iconFileName: String?)] = [:]
            for typeId in cargoTypeIds {
                guard let info = ItemInfoMap.typeInfo(for: typeId), !info.name.isEmpty else { continue }
                cargoItemInfoMap[typeId] = (
                    name: info.name, volume: info.volume, iconFileName: info.iconFilename
                )
            }

            for item in cargoList {
                // 首先尝试从专门查询的货舱物品信息中获取
                if let cargoItemInfo = cargoItemInfoMap[item.type_id] {
                    cargoItems.append(
                        SimCargoItem(
                            typeId: item.type_id,
                            quantity: item.quantity,
                            volume: cargoItemInfo.volume,
                            name: cargoItemInfo.name,
                            iconFileName: cargoItemInfo.iconFileName
                        )
                    )
                } else {
                    // 如果专门查询没有结果，再尝试从typeInfoMap获取
                    let itemInfo =
                        typeInfoMap[item.type_id] ?? (
                            groupID: 0, capacity: 0, volume: 0, mass: 0, name: "Unknown Item",
                            iconFileName: nil
                        )

                    cargoItems.append(
                        SimCargoItem(
                            typeId: item.type_id,
                            quantity: item.quantity,
                            volume: itemInfo.volume,
                            name: itemInfo.name,
                            iconFileName: itemInfo.iconFileName
                        )
                    )
                }
            }
        }
        let simCargo = SimCargo(items: cargoItems)

        // 5. 植入体、环境效果
        var implants: [SimImplant] = []
        var environmentEffects: [SimEnvironmentEffect] = []

        if let environmentTypeId = localFitting.environment_type_id,
           let environmentEffect = loadEnvironmentEffect(
               typeId: environmentTypeId,
               databaseManager: databaseManager
           )
        {
            environmentEffects = [environmentEffect]
            if AppConfiguration.Fitting.showDebug {
                Logger.info("加载环境效果: \(environmentEffect.name), typeId: \(environmentTypeId)")
            }
        }

        // 处理植入体数据
        if let implantTypeIds = localFitting.implants, !implantTypeIds.isEmpty {
            if AppConfiguration.Fitting.showDebug {
                Logger.info("开始加载植入体数据，数量: \(implantTypeIds.count)")
            }

            // 批量取植入体属性（内存索引）
            var typeAttributes: [Int: [Int: Double]] = [:]
            var typeAttributesByName: [Int: [String: Double]] = [:]
            var typeNames: [Int: String] = [:]
            var typeIcons: [Int: String] = [:]
            var typeGroupIDs: [Int: Int] = [:]

            for (typeId, attrs) in SDEMemoryStore.typeAttributes(for: implantTypeIds) {
                typeAttributes[typeId] = attrs.attributes
                typeAttributesByName[typeId] = attrs.attributesByName

                // 保存物品名称、图标和分组ID
                if let info = SDEMemoryStore.type(for: typeId) {
                    typeNames[typeId] = info.name
                    typeIcons[typeId] = info.iconFilename
                    if let groupID = info.groupID {
                        typeGroupIDs[typeId] = groupID
                    }
                }
            }

            // 创建植入体对象
            for typeId in implantTypeIds {
                if let attributes = typeAttributes[typeId],
                   let attributesByName = typeAttributesByName[typeId]
                {
                    let effects = SDEMemoryStore.effectIDs(forType: typeId)
                    let name = typeNames[typeId] ?? "Unknown Implant"
                    let iconFileName = typeIcons[typeId]
                    let groupID = typeGroupIDs[typeId] ?? 0

                    // 创建植入体对象
                    let implant = SimImplant(
                        typeId: typeId,
                        attributes: attributes,
                        attributesByName: attributesByName,
                        effects: effects,
                        requiredSkills: extractRequiredSkills(attributes: attributes),
                        groupID: groupID,
                        name: name,
                        iconFileName: iconFileName
                    )

                    implants.append(implant)
                    if AppConfiguration.Fitting.showDebug {
                        Logger.info("加载植入体: \(name), typeId: \(typeId), groupID: \(groupID)")
                    }
                }
            }
        }

        // 6. 组装SimulationInput（带上原始配置元数据）
        if AppConfiguration.Fitting.showDebug {
            Logger.info("localFittingToSimulationInput 完成组装.")
        }

        // 处理舰载机数据，将FighterSquad转换为SimFighterSquad
        if AppConfiguration.Fitting.showDebug {
            Logger.info("开始将FighterSquad转换为SimFighterSquad，原始数量: \(localFitting.fighters?.count ?? 0)")
        }
        // 检查FighterSquad数据完整性
        if AppConfiguration.Fitting.showDebug, let fighters = localFitting.fighters {
            for (index, fighter) in fighters.enumerated() {
                Logger.info(
                    "输入FighterSquad[\(index)]: type_id=\(fighter.type_id), tubeId=\(fighter.tubeId), quantity=\(fighter.quantity)"
                )
            }
        }

        let simFighters: [SimFighterSquad]? = localFitting.fighters?.compactMap { fighter in
            if AppConfiguration.Fitting.showDebug {
                Logger.info(
                    "处理舰载机: typeId=\(fighter.type_id), tubeId=\(fighter.tubeId), quantity=\(fighter.quantity)"
                )
            }
            // 获取舰载机属性和效果
            let attr = attrMap[fighter.type_id]?.0 ?? [:]
            let attrName = attrMap[fighter.type_id]?.1 ?? [:]
            let effects = effectMap[fighter.type_id] ?? []

            // 获取舰载机信息
            let fighterInfo =
                typeInfoMap[fighter.type_id] ?? (
                    groupID: 0, capacity: 0, volume: 0, mass: 0, name: "Unknown Fighter",
                    iconFileName: nil
                )
            if AppConfiguration.Fitting.showDebug {
                Logger.info("舰载机信息: groupID=\(fighterInfo.groupID), name=\(fighterInfo.name)")
            }

            // 确保volume添加到舰载机的属性字典中
            var updatedAttr = attr
            var updatedAttrName = attrName

            // 体积 (volume) - 属性ID 161
            updatedAttr[161] = fighterInfo.volume
            updatedAttrName["volume"] = fighterInfo.volume

            return SimFighterSquad(
                typeId: fighter.type_id,
                attributes: updatedAttr,
                attributesByName: updatedAttrName,
                effects: effects,
                quantity: fighter.quantity,
                tubeId: fighter.tubeId,
                groupID: fighterInfo.groupID,
                requiredSkills: extractRequiredSkills(attributes: updatedAttr),
                name: fighterInfo.name,
                iconFileName: fighterInfo.iconFileName
            )
        }
        if AppConfiguration.Fitting.showDebug {
            Logger.info("完成SimFighterSquad转换，结果数量: \(simFighters?.count ?? 0)")
        }

        return SimulationInput(
            fittingId: .local(localFitting.fitting_id),
            name: localFitting.name,
            description: localFitting.description,
            fighters: simFighters,

            ship: simShip,
            modules: modules,
            drones: drones,
            cargo: simCargo,
            implants: implants,
            environmentEffects: environmentEffects,
            characterSkills: characterSkills
        )
    }
}
