import Foundation

/// Step3实现 - 将修饰器应用到物品属性上
class Step3 {
    private let databaseManager: DatabaseManager

    /// 需要被豁免叠加惩罚的物品类别ID
    /// 船体(6)、弹药(8)、技能(16)、植入体(20)和子系统(32)
    private let exemptPenaltyCategoryIds: [Int] = [6, 8, 16, 20, 32]

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    /// 执行Step3处理 - 将修饰器应用到物品属性上
    /// - Parameters:
    ///   - input: 模拟输入数据
    ///   - attributeModifiers: 从Step2获取的所有修饰器
    /// - Returns: 更新后的模拟输入数据
    func process(
        input: SimulationInput,
        attributeModifiers: AttributeModifiers
    ) -> SimulationInput {
        Logger.info("执行Step3 - 将修饰器应用到物品属性上")

        // 创建输入数据的可变副本
        var updatedInput = input

        // 初始化技能对象
        initializeSkills(input: &updatedInput)

        // 获取所有修饰器
        let allModifiers = attributeModifiers.allModifiersBySourceType()

        // 1. 处理飞船的修饰器
        if let shipModifiers = allModifiers[updatedInput.ship.typeId] {
            for modifier in shipModifiers {
                // 根据修饰器类型处理
                switch modifier.modifierType {
                case .itemModifier:
                    // 应用到指定物品
                    applyItemModifier(
                        input: &updatedInput,
                        modifier: modifier,
                        sourceInstanceId: updatedInput.ship.instanceId
                    )

                case .locationModifier:
                    // 应用到所有位置上的物品（飞船、模块、弹药等）
                    applyLocationModifier(
                        input: &updatedInput,
                        modifier: modifier,
                        sourceInstanceId: updatedInput.ship.instanceId
                    )

                case let .locationGroupModifier(groupId):
                    // 应用到指定组的物品
                    applyLocationGroupModifier(
                        input: &updatedInput,
                        modifier: modifier,
                        groupId: groupId,
                        sourceInstanceId: updatedInput.ship.instanceId
                    )

                case let .locationRequiredSkillModifier(skillTypeId),
                     let .ownerRequiredSkillModifier(skillTypeId):
                    // 应用到需要特定技能的物品
                    applyRequiredSkillModifier(
                        input: &updatedInput,
                        modifier: modifier,
                        skillTypeId: skillTypeId,
                        sourceInstanceId: updatedInput.ship.instanceId
                    )
                }
            }
        }

        // 2. 处理角色的修饰器
        if let characterModifiers = allModifiers[updatedInput.character.typeId] {
            for modifier in characterModifiers {
                // 根据修饰器类型处理
                switch modifier.modifierType {
                case .itemModifier:
                    // 应用到指定物品
                    applyItemModifier(
                        input: &updatedInput,
                        modifier: modifier,
                        sourceInstanceId: updatedInput.character.instanceId
                    )

                case .locationModifier:
                    // 应用到所有位置上的物品（飞船、模块、弹药等）
                    applyLocationModifier(
                        input: &updatedInput,
                        modifier: modifier,
                        sourceInstanceId: updatedInput.character.instanceId
                    )

                case let .locationGroupModifier(groupId):
                    // 应用到指定组的物品
                    applyLocationGroupModifier(
                        input: &updatedInput,
                        modifier: modifier,
                        groupId: groupId,
                        sourceInstanceId: updatedInput.character.instanceId
                    )

                case let .locationRequiredSkillModifier(skillTypeId),
                     let .ownerRequiredSkillModifier(skillTypeId):
                    // 应用到需要特定技能的物品
                    applyRequiredSkillModifier(
                        input: &updatedInput,
                        modifier: modifier,
                        skillTypeId: skillTypeId,
                        sourceInstanceId: updatedInput.character.instanceId
                    )
                }
            }
        }

        // 3. 处理所有模块的修饰器
        for module in updatedInput.modules {
            if let moduleModifiers = allModifiers[module.typeId] {
                for modifier in moduleModifiers {
                    // 根据修饰器类型处理
                    switch modifier.modifierType {
                    case .itemModifier:
                        // 应用到指定物品
                        applyItemModifier(
                            input: &updatedInput,
                            modifier: modifier,
                            sourceModuleStatus: module.status,
                            currentModuleInstanceId: module.instanceId,
                            sourceInstanceId: module.instanceId
                        )

                    case .locationModifier:
                        // 应用到所有位置上的物品（飞船、模块、弹药等）
                        applyLocationModifier(
                            input: &updatedInput,
                            modifier: modifier,
                            sourceInstanceId: module.instanceId
                        )

                    case let .locationGroupModifier(groupId):
                        // 应用到指定组的物品
                        applyLocationGroupModifier(
                            input: &updatedInput,
                            modifier: modifier,
                            groupId: groupId,
                            sourceInstanceId: module.instanceId
                        )

                    case let .locationRequiredSkillModifier(skillTypeId),
                         let .ownerRequiredSkillModifier(skillTypeId):
                        // 应用到需要特定技能的物品
                        applyRequiredSkillModifier(
                            input: &updatedInput,
                            modifier: modifier,
                            skillTypeId: skillTypeId,
                            sourceInstanceId: module.instanceId
                        )
                    }
                }
            }

            // 处理弹药的修饰器
            if let charge = module.charge, let chargeModifiers = allModifiers[charge.typeId] {
                for modifier in chargeModifiers {
                    // 根据effectId决定sourceInstanceId：
                    // effectId >= 0: 普通修饰器，来源是弹药本身
                    // effectId < 0: dbuff修饰器，来源是模块
                    var sourceInstanceId: UUID
                    if modifier.effectId >= 0 {
                        sourceInstanceId = charge.instanceId
                    } else {
                        sourceInstanceId = module.instanceId
                    }

                    // 根据修饰器类型处理
                    switch modifier.modifierType {
                    case .itemModifier:
                        // 应用到指定物品，传递当前模块的实例ID
                        applyItemModifier(
                            input: &updatedInput,
                            modifier: modifier,
                            sourceModuleStatus: module.status,
                            currentModuleInstanceId: module.instanceId,
                            sourceInstanceId: sourceInstanceId
                        )

                    case .locationModifier:
                        // 应用到所有位置上的物品（飞船、模块、弹药等）
                        applyLocationModifier(
                            input: &updatedInput,
                            modifier: modifier,
                            sourceInstanceId: sourceInstanceId
                        )

                    case let .locationGroupModifier(groupId):
                        // 应用到指定组的物品
                        applyLocationGroupModifier(
                            input: &updatedInput,
                            modifier: modifier,
                            groupId: groupId,
                            sourceInstanceId: sourceInstanceId
                        )

                    case let .locationRequiredSkillModifier(skillTypeId),
                         let .ownerRequiredSkillModifier(skillTypeId):
                        // 应用到需要特定技能的物品
                        applyRequiredSkillModifier(
                            input: &updatedInput,
                            modifier: modifier,
                            skillTypeId: skillTypeId,
                            sourceInstanceId: sourceInstanceId
                        )
                    }
                }
            }
        }

        // 4. 处理所有无人机的修饰器
        for drone in updatedInput.drones {
            if let droneModifiers = allModifiers[drone.typeId] {
                for modifier in droneModifiers {
                    // 根据修饰器类型处理
                    switch modifier.modifierType {
                    case .itemModifier:
                        // 应用到指定物品
                        applyItemModifier(
                            input: &updatedInput,
                            modifier: modifier,
                            sourceInstanceId: drone.instanceId
                        )

                    case .locationModifier:
                        // 应用到所有位置上的物品（飞船、模块、弹药等）
                        applyLocationModifier(
                            input: &updatedInput,
                            modifier: modifier,
                            sourceInstanceId: drone.instanceId
                        )

                    case let .locationGroupModifier(groupId):
                        // 应用到指定组的物品
                        applyLocationGroupModifier(
                            input: &updatedInput,
                            modifier: modifier,
                            groupId: groupId,
                            sourceInstanceId: drone.instanceId
                        )

                    case let .locationRequiredSkillModifier(skillTypeId),
                         let .ownerRequiredSkillModifier(skillTypeId):
                        // 应用到需要特定技能的物品
                        applyRequiredSkillModifier(
                            input: &updatedInput,
                            modifier: modifier,
                            skillTypeId: skillTypeId,
                            sourceInstanceId: drone.instanceId
                        )
                    }
                }
            }
        }

        // 4.5 处理所有舰载机的修饰器
        if let fighters = updatedInput.fighters {
            for fighter in fighters {
                if let fighterModifiers = allModifiers[fighter.typeId] {
                    for modifier in fighterModifiers {
                        // 根据修饰器类型处理
                        switch modifier.modifierType {
                        case .itemModifier:
                            // 应用到指定物品
                            applyItemModifier(
                                input: &updatedInput,
                                modifier: modifier,
                                sourceInstanceId: fighter.instanceId
                            )

                        case .locationModifier:
                            // 应用到所有位置上的物品（飞船、模块、弹药等）
                            applyLocationModifier(
                                input: &updatedInput,
                                modifier: modifier,
                                sourceInstanceId: fighter.instanceId
                            )

                        case let .locationGroupModifier(groupId):
                            // 应用到指定组的物品
                            applyLocationGroupModifier(
                                input: &updatedInput,
                                modifier: modifier,
                                groupId: groupId,
                                sourceInstanceId: fighter.instanceId
                            )

                        case let .locationRequiredSkillModifier(skillTypeId),
                             let .ownerRequiredSkillModifier(skillTypeId):
                            // 应用到需要特定技能的物品
                            applyRequiredSkillModifier(
                                input: &updatedInput,
                                modifier: modifier,
                                skillTypeId: skillTypeId,
                                sourceInstanceId: fighter.instanceId
                            )
                        }
                    }
                }
            }
        }

        // 5. 处理所有植入体的修饰器
        for implant in updatedInput.implants {
            if let implantModifiers = allModifiers[implant.typeId] {
                // 增效剂副作用默认关闭：跳过未启用的副作用修饰器
                let activeModifiers = implantModifiers.filter { modifier in
                    guard SDEMemoryStore.isBoosterSideEffectAttribute(modifier.modifyingAttributeId)
                    else {
                        return true
                    }
                    return implant.enabledSideEffectAttributeIDs.contains(
                        modifier.modifyingAttributeId
                    )
                }
                for modifier in activeModifiers {
                    // 根据修饰器类型处理
                    switch modifier.modifierType {
                    case .itemModifier:
                        // 应用到指定物品
                        applyItemModifier(
                            input: &updatedInput,
                            modifier: modifier,
                            sourceInstanceId: implant.instanceId
                        )

                    case .locationModifier:
                        // 应用到所有位置上的物品（飞船、模块、弹药等）
                        applyLocationModifier(
                            input: &updatedInput,
                            modifier: modifier,
                            sourceInstanceId: implant.instanceId
                        )

                    case let .locationGroupModifier(groupId):
                        // 应用到指定组的物品
                        applyLocationGroupModifier(
                            input: &updatedInput,
                            modifier: modifier,
                            groupId: groupId,
                            sourceInstanceId: implant.instanceId
                        )

                    case let .locationRequiredSkillModifier(skillTypeId),
                         let .ownerRequiredSkillModifier(skillTypeId):
                        // 应用到需要特定技能的物品
                        applyRequiredSkillModifier(
                            input: &updatedInput,
                            modifier: modifier,
                            skillTypeId: skillTypeId,
                            sourceInstanceId: implant.instanceId
                        )
                    }
                }
            }
        }

        // 6. 处理所有环境效果的修饰器
        for effect in updatedInput.environmentEffects {
            if let environmentModifiers = allModifiers[effect.typeId] {
                for modifier in environmentModifiers {
                    switch modifier.modifierType {
                    case .itemModifier:
                        applyItemModifier(
                            input: &updatedInput,
                            modifier: modifier,
                            sourceInstanceId: effect.instanceId
                        )

                    case .locationModifier:
                        applyLocationModifier(
                            input: &updatedInput,
                            modifier: modifier,
                            sourceInstanceId: effect.instanceId
                        )

                    case let .locationGroupModifier(groupId):
                        applyLocationGroupModifier(
                            input: &updatedInput,
                            modifier: modifier,
                            groupId: groupId,
                            sourceInstanceId: effect.instanceId
                        )

                    case let .locationRequiredSkillModifier(skillTypeId),
                         let .ownerRequiredSkillModifier(skillTypeId):
                        applyRequiredSkillModifier(
                            input: &updatedInput,
                            modifier: modifier,
                            skillTypeId: skillTypeId,
                            sourceInstanceId: effect.instanceId
                        )
                    }
                }
            }
        }

        // 7. 处理所有技能的修饰器
        for skill in updatedInput.skills {
            if let skillModifiers = allModifiers[skill.typeId] {
                for modifier in skillModifiers {
                    // 根据修饰器类型处理
                    switch modifier.modifierType {
                    case .itemModifier:
                        // 应用到指定物品
                        applyItemModifier(
                            input: &updatedInput,
                            modifier: modifier,
                            sourceInstanceId: skill.instanceId
                        )

                    case .locationModifier:
                        // 应用到所有位置上的物品（飞船、模块、弹药等）
                        applyLocationModifier(
                            input: &updatedInput,
                            modifier: modifier,
                            sourceInstanceId: skill.instanceId
                        )

                    case let .locationGroupModifier(groupId):
                        // 应用到指定组的物品
                        applyLocationGroupModifier(
                            input: &updatedInput,
                            modifier: modifier,
                            groupId: groupId,
                            sourceInstanceId: skill.instanceId
                        )

                    case let .locationRequiredSkillModifier(skillTypeId),
                         let .ownerRequiredSkillModifier(skillTypeId):
                        // 应用到需要特定技能的物品
                        applyRequiredSkillModifier(
                            input: &updatedInput,
                            modifier: modifier,
                            skillTypeId: skillTypeId,
                            sourceInstanceId: skill.instanceId
                        )
                    }
                }
            }
        }

        Logger.info("Step3完成 - 成功应用修饰器到物品属性上")

        return updatedInput
    }

    /// 初始化技能对象
    private func initializeSkills(input: inout SimulationInput) {
        Logger.info("初始化技能对象...")

        // 清空现有的技能对象
        input.skills = []

        // 获取所有技能ID
        let skillIds = Array(input.characterSkills.keys)
        if skillIds.isEmpty {
            return
        }

        // 从数据库获取所有技能的属性
        let skillAttributes = fetchSkillAttributes(skillIds: skillIds)

        // 遍历所有技能
        for (skillId, skillLevel) in input.characterSkills {
            // 创建新的SimSkill对象
            var attributes: [Int: Double] = [:]
            var attributesByName: [String: Double] = [:]
            var effects: [Int] = []
            var groupID = 0

            // 从数据库获取的属性
            if let attrs = skillAttributes[skillId] {
                attributes = attrs.attributes
                attributesByName = attrs.attributesByName
                groupID = attrs.groupId
            }

            // 设置技能等级属性 (attribute_id=280)，覆盖数据库中的值（如果有）
            attributes[280] = Double(skillLevel)
            attributesByName["skillLevel"] = Double(skillLevel)

            // 从characterSkillAttributes获取其他属性
            if let skillAttrs = input.characterSkillAttributes[skillId] {
                attributes.merge(skillAttrs) { _, new in new }
            }

            // 从characterSkillAttributesByName获取其他属性名称
            if let skillAttrNames = input.characterSkillAttributesByName[skillId] {
                attributesByName.merge(skillAttrNames) { _, new in new }
            }

            // 从effectsByTypeId获取效果
            if let skillEffects = input.effectsByTypeId[skillId] {
                effects = skillEffects
            }

            // 获取技能组ID（如果可能）
            if let categoryId = SDEMemoryStore.type(for: skillId)?.categoryID {
                groupID = categoryId
            }

            // 创建SimSkill对象
            let skill = SimSkill(
                typeId: skillId,
                level: skillLevel,
                attributes: attributes,
                attributesByName: attributesByName,
                effects: effects,
                groupID: groupID,
                requiredSkills: FitConvert.extractRequiredSkills(attributes: attributes)
            )

            // 添加到skills数组
            input.skills.append(skill)
        }

        Logger.info("初始化了\(input.skills.count)个技能对象")
    }

    /// 从数据库获取技能的所有属性
    private func fetchSkillAttributes(skillIds: [Int]) -> [Int: (
        attributes: [Int: Double], attributesByName: [String: Double], groupId: Int
    )] {
        var result:
            [Int: (attributes: [Int: Double], attributesByName: [String: Double], groupId: Int)] =
            [:]

        if skillIds.isEmpty {
            return result
        }

        // 批量取技能的基本信息和属性（内存索引）
        for typeId in skillIds {
            let (attributes, attributesByName) = SDEMemoryStore.typeAttributesFull(for: typeId)
            let groupId = SDEMemoryStore.type(for: typeId)?.groupID ?? 0
            result[typeId] = (
                attributes: attributes, attributesByName: attributesByName, groupId: groupId
            )
        }

        return result
    }

    /// 应用ItemModifier (作用于特定物品)
    private func applyItemModifier(
        input: inout SimulationInput,
        modifier: AttributeModifier,
        sourceModuleStatus _: Int? = nil,
        currentModuleInstanceId: UUID? = nil,
        sourceInstanceId: UUID? = nil
    ) {
        // 根据domain确定目标物品
        switch modifier.domain {
        case .shipID:
            // 修饰器作用于船体
            addModifierToShip(
                ship: &input.ship,
                modifier: modifier,
                sourceInstanceId: sourceInstanceId
            )

        case .itemID:
            // 修饰器作用于自身，需找到对应物品
            findAndAddModifierToSelf(
                input: &input,
                modifier: modifier,
                sourceInstanceId: sourceInstanceId
            )

        case .charID:
            // 修饰器作用于角色属性
            addModifierToCharacter(
                character: &input.character,
                modifier: modifier,
                sourceInstanceId: sourceInstanceId
            )

        case .otherID:
            // 修饰器作用于关联物品（如模块和弹药之间的关系）
            applyModifierToRelatedItem(
                input: &input,
                modifier: modifier,
                currentModuleInstanceId: currentModuleInstanceId,
                sourceInstanceId: sourceInstanceId
            )

        default:
            // 其他域类型（如targetID等）暂不处理
            break
        }
    }

    /// 应用LocationModifier (作用于所有物品)
    private func applyLocationModifier(
        input: inout SimulationInput,
        modifier: AttributeModifier,
        sourceInstanceId: UUID? = nil
    ) {
        // 应用到船体
        addModifierToShip(
            ship: &input.ship,
            modifier: modifier,
            sourceInstanceId: sourceInstanceId
        )

        // 应用到角色
        addModifierToCharacter(
            character: &input.character,
            modifier: modifier,
            sourceInstanceId: sourceInstanceId
        )

        // 应用到所有模块
        for i in 0 ..< input.modules.count {
            addModifierToModule(
                module: &input.modules[i],
                modifier: modifier,
                sourceInstanceId: sourceInstanceId
            )

            // 应用到模块中的弹药（如果有）
            if let charge = input.modules[i].charge {
                // 创建带有修饰器的新弹药，传入模块状态
                let modifiedCharge = addModifierToCharge(
                    charge: charge,
                    modifier: modifier,
                    moduleStatus: input.modules[i].status,
                    sourceInstanceId: sourceInstanceId
                )

                // 创建包含新弹药的新模块
                input.modules[i] = createModuleWithUpdatedCharge(
                    originalModule: input.modules[i],
                    updatedCharge: modifiedCharge
                )
            }
        }

        // 应用到所有无人机
        for i in 0 ..< input.drones.count {
            addModifierToDrone(
                drone: &input.drones[i],
                modifier: modifier,
                sourceInstanceId: sourceInstanceId
            )
        }

        // 应用到所有舰载机
        if let fighters = input.fighters {
            for i in 0 ..< fighters.count {
                addModifierToFighter(
                    fighter: &input.fighters![i],
                    modifier: modifier,
                    sourceInstanceId: sourceInstanceId
                )
            }
        }

        // 应用到所有植入体
        for i in 0 ..< input.implants.count {
            addModifierToImplant(
                implant: &input.implants[i],
                modifier: modifier,
                sourceInstanceId: sourceInstanceId
            )
        }

        // 应用到所有技能
        for i in 0 ..< input.skills.count {
            addModifierToSkill(
                skill: &input.skills[i],
                modifier: modifier,
                sourceInstanceId: sourceInstanceId
            )
        }
    }

    /// 应用LocationGroupModifier (作用于特定组的物品)
    private func applyLocationGroupModifier(
        input: inout SimulationInput,
        modifier: AttributeModifier,
        groupId: Int,
        sourceInstanceId: UUID? = nil
    ) {
        // 检查船体是否属于指定组
        if input.ship.groupID == groupId {
            addModifierToShip(
                ship: &input.ship,
                modifier: modifier,
                sourceInstanceId: sourceInstanceId
            )
        }

        // 检查模块是否属于指定组
        for i in 0 ..< input.modules.count {
            if input.modules[i].groupID == groupId {
                addModifierToModule(
                    module: &input.modules[i],
                    modifier: modifier,
                    sourceInstanceId: sourceInstanceId
                )
            }

            // 检查弹药是否属于指定组
            if let charge = input.modules[i].charge, charge.groupID == groupId {
                // 创建带有修饰器的新弹药，传入模块状态
                let modifiedCharge = addModifierToCharge(
                    charge: charge,
                    modifier: modifier,
                    moduleStatus: input.modules[i].status,
                    sourceInstanceId: sourceInstanceId
                )

                // 创建包含新弹药的新模块
                input.modules[i] = createModuleWithUpdatedCharge(
                    originalModule: input.modules[i],
                    updatedCharge: modifiedCharge
                )
            }
        }

        // 检查无人机是否属于指定组
        for i in 0 ..< input.drones.count {
            if input.drones[i].groupID == groupId {
                addModifierToDrone(
                    drone: &input.drones[i],
                    modifier: modifier,
                    sourceInstanceId: sourceInstanceId
                )
            }
        }

        // 检查舰载机是否属于指定组
        if let fighters = input.fighters {
            for i in 0 ..< fighters.count {
                if fighters[i].groupID == groupId {
                    addModifierToFighter(
                        fighter: &input.fighters![i],
                        modifier: modifier,
                        sourceInstanceId: sourceInstanceId
                    )
                }
            }
        }

        // 检查植入体是否属于指定组（如果有groupID属性）
        for i in 0 ..< input.implants.count {
            // 植入体可能没有groupID属性，这里假设有
            if let implantGroupId = getImplantGroupId(implant: input.implants[i]),
               implantGroupId == groupId
            {
                addModifierToImplant(
                    implant: &input.implants[i],
                    modifier: modifier,
                    sourceInstanceId: sourceInstanceId
                )
            }
        }

        // 检查技能是否属于指定组
        for i in 0 ..< input.skills.count {
            if input.skills[i].groupID == groupId {
                addModifierToSkill(
                    skill: &input.skills[i],
                    modifier: modifier,
                    sourceInstanceId: sourceInstanceId
                )
            }
        }
    }

    /// 获取植入体的分组ID
    private func getImplantGroupId(implant: SimImplant) -> Int? {
        // 直接从SimImplant对象中获取groupID
        return implant.groupID
    }

    /// 应用RequiredSkillModifier (作用于需要特定技能的物品)
    private func applyRequiredSkillModifier(
        input: inout SimulationInput,
        modifier: AttributeModifier,
        skillTypeId: Int,
        sourceInstanceId: UUID? = nil
    ) {
        // 获取实际的技能ID（处理-1特殊情况）
        let actualSkillTypeId = skillTypeId == -1 ? modifier.sourceTypeId : skillTypeId

        // 检查船体是否需要该技能
        if input.ship.requiredSkills.contains(actualSkillTypeId) {
            addModifierToShip(
                ship: &input.ship,
                modifier: modifier,
                sourceInstanceId: sourceInstanceId
            )
        }

        // 检查模块是否需要该技能
        for i in 0 ..< input.modules.count {
            if input.modules[i].requiredSkills.contains(actualSkillTypeId) {
                addModifierToModule(
                    module: &input.modules[i],
                    modifier: modifier,
                    sourceInstanceId: sourceInstanceId
                )
            }

            // 检查弹药是否需要该技能
            if let charge = input.modules[i].charge,
               charge.requiredSkills.contains(actualSkillTypeId)
            {
                // 创建带有修饰器的新弹药，传入模块状态
                let modifiedCharge = addModifierToCharge(
                    charge: charge,
                    modifier: modifier,
                    moduleStatus: input.modules[i].status,
                    sourceInstanceId: sourceInstanceId
                )

                // 创建包含新弹药的新模块
                input.modules[i] = createModuleWithUpdatedCharge(
                    originalModule: input.modules[i],
                    updatedCharge: modifiedCharge
                )
            }
        }

        // 检查无人机是否需要该技能
        for i in 0 ..< input.drones.count {
            if input.drones[i].requiredSkills.contains(actualSkillTypeId) {
                addModifierToDrone(
                    drone: &input.drones[i],
                    modifier: modifier,
                    sourceInstanceId: sourceInstanceId
                )
            }
        }

        // 检查舰载机是否需要该技能
        if let fighters = input.fighters {
            for i in 0 ..< fighters.count {
                if fighters[i].requiredSkills.contains(actualSkillTypeId) {
                    addModifierToFighter(
                        fighter: &input.fighters![i],
                        modifier: modifier,
                        sourceInstanceId: sourceInstanceId
                    )
                }
            }
        }

        // 检查植入体是否需要该技能
        for i in 0 ..< input.implants.count {
            if input.implants[i].requiredSkills.contains(actualSkillTypeId) {
                addModifierToImplant(
                    implant: &input.implants[i],
                    modifier: modifier,
                    sourceInstanceId: sourceInstanceId
                )
            }
        }

        // 检查技能是否需要该技能（技能可能有前置技能要求）
        for i in 0 ..< input.skills.count {
            if input.skills[i].requiredSkills.contains(actualSkillTypeId) {
                addModifierToSkill(
                    skill: &input.skills[i],
                    modifier: modifier,
                    sourceInstanceId: sourceInstanceId
                )
            }
        }
    }

    /// 查找并将修饰器添加到自身物品
    private func findAndAddModifierToSelf(
        input: inout SimulationInput,
        modifier: AttributeModifier,
        sourceInstanceId: UUID? = nil
    ) {
        // 如果没有提供源实例ID，无法进行精确匹配，直接返回
        guard let sourceId = sourceInstanceId else {
            Logger.warning("缺少源实例ID，无法应用自身修饰器")
            return
        }

        // 检查船体
        if input.ship.instanceId == sourceId {
            addModifierToShip(
                ship: &input.ship,
                modifier: modifier,
                sourceInstanceId: sourceInstanceId
            )
            return // 找到目标后直接返回
        }

        // 检查角色
        if input.character.instanceId == sourceId {
            addModifierToCharacter(
                character: &input.character,
                modifier: modifier,
                sourceInstanceId: sourceInstanceId
            )
            return // 找到目标后直接返回
        }

        // 检查模块和弹药（保持在同一循环中）
        for i in 0 ..< input.modules.count {
            // 检查模块
            if input.modules[i].instanceId == sourceId {
                addModifierToModule(
                    module: &input.modules[i],
                    modifier: modifier,
                    sourceInstanceId: sourceInstanceId
                )

                // 同时处理该模块的弹药（如果有）
                if let charge = input.modules[i].charge {
                    let modifiedCharge = addModifierToCharge(
                        charge: charge,
                        modifier: modifier,
                        moduleStatus: input.modules[i].status,
                        sourceInstanceId: sourceInstanceId
                    )

                    input.modules[i] = createModuleWithUpdatedCharge(
                        originalModule: input.modules[i],
                        updatedCharge: modifiedCharge
                    )
                }

                return // 处理完模块和其弹药后返回
            }

            // 只有当目标是弹药本身时才单独处理弹药
            if let charge = input.modules[i].charge, charge.instanceId == sourceId {
                // 创建带有修饰器的新弹药
                let modifiedCharge = addModifierToCharge(
                    charge: charge,
                    modifier: modifier,
                    moduleStatus: input.modules[i].status,
                    sourceInstanceId: sourceInstanceId
                )

                // 创建包含新弹药的新模块
                input.modules[i] = createModuleWithUpdatedCharge(
                    originalModule: input.modules[i],
                    updatedCharge: modifiedCharge
                )
                return // 找到目标后直接返回
            }
        }

        // 检查无人机
        for i in 0 ..< input.drones.count {
            if input.drones[i].instanceId == sourceId {
                addModifierToDrone(
                    drone: &input.drones[i],
                    modifier: modifier,
                    sourceInstanceId: sourceInstanceId
                )
                return // 找到目标后直接返回
            }
        }

        // 检查舰载机
        if let fighters = input.fighters {
            for i in 0 ..< fighters.count {
                if fighters[i].instanceId == sourceId {
                    addModifierToFighter(
                        fighter: &input.fighters![i],
                        modifier: modifier,
                        sourceInstanceId: sourceInstanceId
                    )
                    return // 找到目标后直接返回
                }
            }
        }

        // 检查植入体
        for i in 0 ..< input.implants.count {
            if input.implants[i].instanceId == sourceId {
                addModifierToImplant(
                    implant: &input.implants[i],
                    modifier: modifier,
                    sourceInstanceId: sourceInstanceId
                )
                return // 找到目标后直接返回
            }
        }

        // 检查技能
        for i in 0 ..< input.skills.count {
            if input.skills[i].instanceId == sourceId {
                addModifierToSkill(
                    skill: &input.skills[i],
                    modifier: modifier,
                    sourceInstanceId: sourceInstanceId
                )
                return // 找到目标后直接返回
            }
        }

        // 如果没有找到匹配的物品，记录警告
        Logger.warning("未找到实例ID为 \(sourceId) 的物品来应用自身修饰器")
    }

    /// 将修饰器应用到相关联物品（如模块和弹药）
    private func applyModifierToRelatedItem(
        input: inout SimulationInput,
        modifier: AttributeModifier,
        currentModuleInstanceId: UUID? = nil,
        sourceInstanceId: UUID? = nil
    ) {
        let sourceTypeId = modifier.sourceTypeId

        // 如果提供了当前模块实例ID，优先进行精确匹配
        if let moduleInstanceId = currentModuleInstanceId {
            // 找到对应的模块
            if let moduleIndex = input.modules.firstIndex(where: {
                $0.instanceId == moduleInstanceId
            }) {
                let module = input.modules[moduleIndex]

                // 如果源是模块，目标是弹药
                if module.typeId == sourceTypeId, let charge = module.charge {
                    // 创建带有修饰器的新弹药，传入模块状态
                    let modifiedCharge = addModifierToCharge(
                        charge: charge,
                        modifier: modifier,
                        moduleStatus: module.status,
                        sourceInstanceId: sourceInstanceId
                    )

                    // 创建包含新弹药的新模块
                    input.modules[moduleIndex] = createModuleWithUpdatedCharge(
                        originalModule: module,
                        updatedCharge: modifiedCharge
                    )
                    return // 精确匹配后直接返回
                }

                // 如果源是弹药，目标是模块
                if let charge = module.charge, charge.typeId == sourceTypeId {
                    addModifierToModule(
                        module: &input.modules[moduleIndex],
                        modifier: modifier,
                        sourceInstanceId: sourceInstanceId
                    )
                    return // 精确匹配后直接返回
                }
            }
        }

        // 如果没有提供实例ID或精确匹配失败，回退到原有逻辑（兼容性）
        // 检查每个模块和其弹药
        for i in 0 ..< input.modules.count {
            // 如果源是模块，目标是弹药
            if input.modules[i].typeId == sourceTypeId, let charge = input.modules[i].charge {
                // 创建带有修饰器的新弹药，传入模块状态
                let modifiedCharge = addModifierToCharge(
                    charge: charge,
                    modifier: modifier,
                    moduleStatus: input.modules[i].status,
                    sourceInstanceId: sourceInstanceId
                )

                // 创建包含新弹药的新模块
                input.modules[i] = createModuleWithUpdatedCharge(
                    originalModule: input.modules[i],
                    updatedCharge: modifiedCharge
                )
                // 不返回，继续检查其他模块的弹药
            }

            // 如果源是弹药，目标是模块
            if let charge = input.modules[i].charge, charge.typeId == sourceTypeId {
                addModifierToModule(
                    module: &input.modules[i],
                    modifier: modifier,
                    sourceInstanceId: sourceInstanceId
                )
                // 不返回，继续检查其他弹药
            }
        }
    }

    // MARK: - 添加修饰器到具体物品

    /// 添加修饰器到船体
    private func addModifierToShip(
        ship: inout SimShip,
        modifier: AttributeModifier,
        sourceInstanceId: UUID? = nil
    ) {
        let attributeId = modifier.modifiedAttributeId

        // 检查船体是否有该属性，如果没有则不添加修饰器
        if !ship.baseAttributes.keys.contains(attributeId) {
            return
        }

        let simModifier = createSimAttributeModifier(
            modifier: modifier,
            sourceInstanceId: sourceInstanceId,
            targetInstanceId: ship.instanceId
        )

        if ship.attributeModifiers[attributeId] == nil {
            ship.attributeModifiers[attributeId] = []
        }

        ship.attributeModifiers[attributeId]!.append(simModifier)
    }

    /// 添加修饰器到模块
    private func addModifierToModule(
        module: inout SimModule,
        modifier: AttributeModifier,
        sourceInstanceId: UUID? = nil
    ) {
        let attributeId = modifier.modifiedAttributeId

        // 检查模块是否有该属性，如果没有则不添加修饰器
        if !module.attributes.keys.contains(attributeId), modifier.operation.rawValue != 7 { // 赋值类的，不关心是否存在此属性
            if AppConfiguration.Fitting.showDebug {
                Logger.info(
                    "模块 \(module.name)[\(module.instanceId)] 不含有该属性 \(attributeId)，不添加效果 \(modifier.effectName) 的修饰器 \(modifier.modifierType)"
                )
            }
            return
        }

        let simModifier = createSimAttributeModifier(
            modifier: modifier,
            sourceInstanceId: sourceInstanceId,
            targetInstanceId: module.instanceId
        )

        if module.attributeModifiers[attributeId] == nil {
            module.attributeModifiers[attributeId] = []
        }

        module.attributeModifiers[attributeId]!.append(simModifier)
    }

    /// 添加修饰器到弹药（返回新的弹药对象）
    private func addModifierToCharge(
        charge: SimCharge,
        modifier: AttributeModifier,
        moduleStatus _: Int = 2,
        sourceInstanceId: UUID? = nil
    ) -> SimCharge {
        let attributeId = modifier.modifiedAttributeId

        // 检查弹药是否有该属性，如果没有则返回原始弹药对象
        if !charge.attributes.keys.contains(attributeId) {
            return charge
        }

        // 注意：状态检查逻辑已移至Step4中处理
        // 这里不再过滤修饰器，而是收集所有可能的修饰器，让Step4根据当前状态决定应用哪些

        let simModifier = createSimAttributeModifier(
            modifier: modifier,
            sourceInstanceId: sourceInstanceId,
            targetInstanceId: charge.instanceId
        )

        // 创建修饰器字典的副本
        var updatedModifiers = charge.attributeModifiers

        // 添加新的修饰器
        if updatedModifiers[attributeId] == nil {
            updatedModifiers[attributeId] = []
        }
        updatedModifiers[attributeId]!.append(simModifier)

        // 创建一个新的SimCharge对象，包含更新后的修饰器
        return SimCharge(
            typeId: charge.typeId,
            attributes: charge.attributes,
            attributesByName: charge.attributesByName,
            effects: charge.effects,
            groupID: charge.groupID,
            chargeQuantity: charge.chargeQuantity,
            requiredSkills: charge.requiredSkills,
            name: charge.name,
            iconFileName: charge.iconFileName,
            attributeModifiers: updatedModifiers
        )
    }

    /// 创建一个包含更新后弹药的新模块
    private func createModuleWithUpdatedCharge(originalModule: SimModule, updatedCharge: SimCharge)
        -> SimModule
    {
        return SimModule(
            instanceId: originalModule.instanceId, // 保留原模块的instanceId
            typeId: originalModule.typeId,
            attributes: originalModule.attributes,
            attributesByName: originalModule.attributesByName,
            effects: originalModule.effects,
            groupID: originalModule.groupID,
            status: originalModule.status,
            charge: updatedCharge,
            flag: originalModule.flag,
            quantity: originalModule.quantity,
            name: originalModule.name,
            iconFileName: originalModule.iconFileName,
            requiredSkills: originalModule.requiredSkills,
            attributeModifiers: originalModule.attributeModifiers,
            isSpoolUpFull: originalModule.isSpoolUpFull
        )
    }

    /// 添加修饰器到无人机
    private func addModifierToDrone(
        drone: inout SimDrone,
        modifier: AttributeModifier,
        sourceInstanceId: UUID? = nil
    ) {
        let attributeId = modifier.modifiedAttributeId

        // 检查无人机是否有该属性，如果没有则不添加修饰器
        if !drone.attributes.keys.contains(attributeId) {
            return
        }

        let simModifier = createSimAttributeModifier(
            modifier: modifier,
            sourceInstanceId: sourceInstanceId,
            targetInstanceId: drone.instanceId
        )

        if drone.attributeModifiers[attributeId] == nil {
            drone.attributeModifiers[attributeId] = []
        }

        drone.attributeModifiers[attributeId]!.append(simModifier)
    }

    /// 添加修饰器到舰载机
    private func addModifierToFighter(
        fighter: inout SimFighterSquad,
        modifier: AttributeModifier,
        sourceInstanceId: UUID? = nil
    ) {
        let attributeId = modifier.modifiedAttributeId

        // 检查舰载机是否有该属性，如果没有则不添加修饰器
        if !fighter.attributes.keys.contains(attributeId) {
            return
        }

        let simModifier = createSimAttributeModifier(
            modifier: modifier,
            sourceInstanceId: sourceInstanceId,
            targetInstanceId: fighter.instanceId
        )

        if fighter.attributeModifiers[attributeId] == nil {
            fighter.attributeModifiers[attributeId] = []
        }

        fighter.attributeModifiers[attributeId]!.append(simModifier)
    }

    /// 添加修饰器到植入体
    private func addModifierToImplant(
        implant: inout SimImplant,
        modifier: AttributeModifier,
        sourceInstanceId: UUID? = nil
    ) {
        let attributeId = modifier.modifiedAttributeId

        // 检查植入体是否有该属性，如果没有则不添加修饰器
        if !implant.attributes.keys.contains(attributeId) {
            return
        }

        let simModifier = createSimAttributeModifier(
            modifier: modifier,
            sourceInstanceId: sourceInstanceId,
            targetInstanceId: implant.instanceId
        )

        if implant.attributeModifiers[attributeId] == nil {
            implant.attributeModifiers[attributeId] = []
        }

        implant.attributeModifiers[attributeId]!.append(simModifier)
    }

    /// 创建一个SimAttributeModifier对象
    private func createSimAttributeModifier(
        modifier: AttributeModifier,
        sourceInstanceId: UUID? = nil,
        targetInstanceId: UUID? = nil
    ) -> SimAttributeModifier {
        // 确定是否需要应用叠加惩罚
        // 从缓存获取属性信息
        let attributeStackable = isAttributeStackable(attributeId: modifier.modifiedAttributeId)

        // 对于dbuff效果（effectId < 0），强制应用叠加惩罚
        let isDbuffEffect = (modifier.effectId) < 0
        let categoryExemptFromPenalty =
            isDbuffEffect
                ? false
                : isCategoryExemptFromPenalty(
                    categoryId: getSourceCategoryId(typeId: modifier.sourceTypeId)
                )

        // 如果属性可叠加或者类别豁免，则不应用叠加惩罚
        // 但dbuff效果例外，总是应用叠加惩罚
        let applyStackingPenalty =
            !attributeStackable && !categoryExemptFromPenalty && modifier.operation.isStackable

        // 创建一个SimAttributeModifier
        return SimAttributeModifier(
            sourceTypeID: modifier.sourceTypeId,
            sourceName: modifier.sourceTypeName,
            operation: modifier.operation.toString(),
            value: 0, // 值需要从物品属性中获取，在Pass4中计算
            stackingPenalty: applyStackingPenalty,
            sourceAttributeId: modifier.modifyingAttributeId,
            sourceItemType: nil,
            sourceItemIndex: nil, // 需要查找源物品索引，这里暂时留空
            sourceFlag: nil, // 需要查找源物品Flag，这里暂时留空
            effectId: modifier.effectId,
            effectCategory: Int(modifier.effectCategory.rawValue),
            sourceInstanceId: sourceInstanceId,
            targetInstanceId: targetInstanceId
        )
    }

    // MARK: - 辅助方法

    /// 判断属性是否可叠加
    private func isAttributeStackable(attributeId: Int) -> Bool {
        return SDEMemoryStore.dogmaAttributes[attributeId]?.stackable ?? false
    }

    /// 判断类别是否豁免叠加惩罚
    private func isCategoryExemptFromPenalty(categoryId: Int) -> Bool {
        return exemptPenaltyCategoryIds.contains(categoryId)
    }

    /// 获取物品类别ID（从 SDEMemoryStore 内存缓存获取）
    private func getSourceCategoryId(typeId: Int) -> Int {
        return SDEMemoryStore.type(for: typeId)?.categoryID ?? 0
    }

    /// 添加修饰器到技能
    private func addModifierToSkill(
        skill: inout SimSkill,
        modifier: AttributeModifier,
        sourceInstanceId: UUID? = nil
    ) {
        let attributeId = modifier.modifiedAttributeId

        // 检查技能是否有该属性，如果没有则不添加修饰器
        if !skill.attributes.keys.contains(attributeId) {
            return
        }

        let simModifier = createSimAttributeModifier(
            modifier: modifier,
            sourceInstanceId: sourceInstanceId,
            targetInstanceId: skill.instanceId
        )

        if skill.attributeModifiers[attributeId] == nil {
            skill.attributeModifiers[attributeId] = []
        }

        skill.attributeModifiers[attributeId]!.append(simModifier)
    }

    /// 判断属性是否为"高值更好"类型
    func isAttributeHighGood(attributeId: Int) -> Bool {
        return SDEMemoryStore.dogmaAttributes[attributeId]?.highIsGood ?? true
    }

    /// 添加修饰器到角色
    private func addModifierToCharacter(
        character: inout SimCharacter,
        modifier: AttributeModifier,
        sourceInstanceId: UUID? = nil
    ) {
        let attributeId = modifier.modifiedAttributeId

        // 确保角色属性字典中有该属性（如果没有则初始化为默认值）
        if !character.baseAttributes.keys.contains(attributeId) {
            // 从 SDEMemoryStore 获取属性的默认值，如果没有则使用0
            let attrInfo = SDEMemoryStore.dogmaAttributes[attributeId]
            let defaultValue = attrInfo?.defaultValue ?? 0.0
            character.baseAttributes[attributeId] = defaultValue

            // 也添加到属性名称字典中
            let attributeName = attrInfo?.name ?? "attribute_\(attributeId)"
            character.baseAttributesByName[attributeName] = defaultValue
        }

        let simModifier = createSimAttributeModifier(
            modifier: modifier,
            sourceInstanceId: sourceInstanceId,
            targetInstanceId: character.instanceId
        )

        if character.attributeModifiers[attributeId] == nil {
            character.attributeModifiers[attributeId] = []
        }

        character.attributeModifiers[attributeId]!.append(simModifier)

        if AppConfiguration.Fitting.showDebug {
            Logger.info("添加修饰器到角色属性: \(attributeId), 修饰器: \(modifier.effectName)")
        }
    }
}
