import SwiftUI

extension OreRefineryCalculatorView {
    // MARK: - 精炼计算核心逻辑

    /// 精炼计算上下文
    func getCurrentRefineryContext() -> RefineryContext {
        return RefineryContext(
            structureID: structure.typeID,
            rigLevel: structureRigs,
            systemSecurity: systemSecurity,
            characterSkills: selectedCharacterSkills,
            structure: structure
        )
    }

    /// 计算精炼加成系数（核心逻辑，可复用）
    func calculateRefineryBonus(
        itemID: Int,
        categoryInfo: ItemCategoryInfo,
        context: RefineryContext
    ) -> Double {
        switch categoryInfo.itemType {
        case .oreAndIce:
            return calculateOreRefineryBonus(
                itemID: itemID,
                structureID: context.structureID,
                rigLevel: context.rigLevel,
                systemSecurity: context.systemSecurity,
                characterSkills: context.characterSkills,
                itemCategoryInfo: categoryInfo
            )
        case .gas:
            return calculateGasRefineryBonus(
                structureID: context.structureID,
                characterSkills: context.characterSkills
            )
        case .other:
            return calculateOtherRefineryBonus(
                characterSkills: context.characterSkills
            )
        case .noOutput:
            return 0.0
        }
    }

    /// 验证物品是否可以精炼
    func validateItemForRefinery(itemID: Int, quantity _: Int64) -> (
        typeMaterials: [DatabaseManager.TypeMaterial]?, categoryInfo: ItemCategoryInfo?,
        processSize: Int
    ) {
        // 1. 检查是否有精炼产出
        guard let typeMaterials = databaseManager.getTypeMaterials(for: itemID),
              !typeMaterials.isEmpty
        else {
            return (nil, nil, 0)
        }

        // 2. 获取物品分类信息
        let itemCategories = getBatchItemCategories(for: [itemID])
        guard let categoryInfo = itemCategories[itemID] else {
            return (typeMaterials, nil, 0)
        }

        // 3. 精炼比例与数量无关，只要有精炼产出就可以计算比例
        let processSize = typeMaterials.first?.process_size ?? 0

        return (typeMaterials, categoryInfo, processSize)
    }

    /// 更新精炼状态（可复用）
    func updateRefineryStatus(itemID: Int, status: RefineryStatus) {
        itemRefineryStatus[itemID] = status

        if case let .canRefine(ratio) = status {
            itemRefineryRatios[itemID] = ratio
        } else {
            itemRefineryRatios[itemID] = 0.0
        }
    }

    /// 计算单个物品的精炼比例（重构后）
    func calculateItemRefineryRatio(itemID: Int, quantity: Int64) -> RefineryStatus {
        let validation = validateItemForRefinery(itemID: itemID, quantity: quantity)

        // 检查验证结果
        if validation.typeMaterials == nil {
            return .noOutput
        }

        if validation.categoryInfo == nil {
            return .unknown
        }

        // 精炼比例与数量无关，只要有精炼产出就可以计算比例
        // 计算精炼比例
        let context = getCurrentRefineryContext()
        let refineryRatio = calculateRefineryBonus(
            itemID: itemID,
            categoryInfo: validation.categoryInfo!,
            context: context
        )

        return .canRefine(ratio: refineryRatio)
    }

    /// 批量计算物品精炼比例（重构后）
    func calculateBatchRefineryRatios() {
        for oreItem in oreItems {
            let status = calculateItemRefineryRatio(
                itemID: oreItem.typeID, quantity: oreItem.quantity
            )
            updateRefineryStatus(itemID: oreItem.typeID, status: status)
        }
    }

    /// 批量获取多个物品的精炼信息（内存索引）
    func getBatchTypeMaterials(for typeIDs: [Int]) -> [Int: [DatabaseManager.TypeMaterial]] {
        guard !typeIDs.isEmpty else { return [:] }

        var result: [Int: [DatabaseManager.TypeMaterial]] = [:]
        for typeID in typeIDs {
            let entries = SDEMemoryStore.materials(for: typeID)
            guard !entries.isEmpty else { continue }

            let materials: [DatabaseManager.TypeMaterial] = entries.map { entry in
                let outputInfo = SDEMemoryStore.type(for: entry.outputMaterial)
                let iconName = outputInfo?.iconFilename ?? ""
                return DatabaseManager.TypeMaterial(
                    process_size: entry.processSize,
                    outputMaterial: entry.outputMaterial,
                    outputQuantity: entry.outputQuantity,
                    outputMaterialName: outputInfo?.name ?? "",
                    outputMaterialIcon: iconName.isEmpty
                        ? IconManager.defaultItemIcon : iconName
                )
            }
            result[typeID] = materials
        }

        Logger.info("批量查询精炼信息: 查询了 \(typeIDs.count) 个物品，找到 \(result.count) 个物品的精炼数据")
        return result
    }

    /// 精炼状态枚举
    func getBatchItemCategories(for typeIDs: [Int]) -> [Int: ItemCategoryInfo] {
        guard !typeIDs.isEmpty else { return [:] }

        // 内存索引获取物品分类/组信息
        var result: [Int: ItemCategoryInfo] = [:]
        for typeID in typeIDs {
            guard let info = SDEMemoryStore.type(for: typeID),
                  let groupID = info.groupID
            else { continue }
            let categoryID = info.categoryID

            // 确定物品类型
            let itemType: RefineryItemType
            if categoryID == 25 {
                itemType = .oreAndIce
            } else if categoryID == 2, groupID == 4168 {
                itemType = .gas
            } else {
                itemType = .other
            }

            result[typeID] = ItemCategoryInfo(
                typeID: typeID,
                categoryID: categoryID,
                groupID: groupID,
                itemType: itemType,
                reprocessingSkillType: nil // 稍后单独查询
            )
        }

        // 对于矿石和冰矿，查询专业技能类型
        let oreAndIceTypeIDs = result.values.filter { $0.itemType == .oreAndIce }.map { $0.typeID }
        if !oreAndIceTypeIDs.isEmpty {
            let skillPlaceholders = String(repeating: "?,", count: oreAndIceTypeIDs.count)
                .dropLast()
            let skillQuery = """
                SELECT type_id, value
                FROM typeAttributes
                WHERE attribute_id = 790 AND type_id IN (\(skillPlaceholders))
            """

            if case let .success(skillRows) = databaseManager.executeQuery(
                skillQuery, parameters: oreAndIceTypeIDs
            ) {
                for row in skillRows {
                    if let typeID = row["type_id"] as? Int,
                       let skillType = row["value"] as? Double
                    {
                        // 更新现有的ItemCategoryInfo
                        if let existingInfo = result[typeID] {
                            result[typeID] = ItemCategoryInfo(
                                typeID: existingInfo.typeID,
                                categoryID: existingInfo.categoryID,
                                groupID: existingInfo.groupID,
                                itemType: existingInfo.itemType,
                                reprocessingSkillType: Int(skillType)
                            )
                        }
                    }
                }
            }
        }

        Logger.info(
            "批量查询物品分类: 查询了 \(typeIDs.count) 个物品，分类结果: 矿石冰矿 \(result.values.filter { $0.itemType == .oreAndIce }.count) 个, 气云 \(result.values.filter { $0.itemType == .gas }.count) 个, 其他 \(result.values.filter { $0.itemType == .other }.count) 个, 无产出 \(result.values.filter { $0.itemType == .noOutput }.count) 个"
        )
        return result
    }

    /// 计算矿石和冰矿的精炼加成系数
    func calculateOreRefineryBonus(
        itemID: Int,
        structureID: Int,
        rigLevel: StructureRigs,
        systemSecurity: SystemSecurity,
        characterSkills: [Int: Int],
        itemCategoryInfo: ItemCategoryInfo
    ) -> Double {
        // 1. 获取插件基础精炼比例
        let baseRigRatio: Double
        switch rigLevel {
        case .none:
            baseRigRatio = 0.5 // 无插件默认50%
        case .t1:
            baseRigRatio = 0.51 // T1插件51%
        case .t2:
            baseRigRatio = 0.53 // T2插件53%
        }

        // 2. 安全等级加成系数
        let securityBonus: Double
        switch systemSecurity {
        case .highSec:
            securityBonus = 1.0
        case .lowSec:
            securityBonus = 1.06
        case .nullSec:
            securityBonus = 1.12
        }

        // 3. 建筑加成
        let structureBonus = getStructureRefineryBonus(structureID: structureID)

        // 4. 植入体加成
        let implantBonus = getImplantRefineryBonus(implantID: implant.typeID)

        // 5. 通用技能加成 (3389 和 3385)
        let generalSkillBonus = calculateGeneralSkillBonus(characterSkills: characterSkills)

        // 6. 专业技能加成
        let specificSkillBonus = calculateSpecificSkillBonus(
            skillType: itemCategoryInfo.reprocessingSkillType,
            characterSkills: characterSkills
        )

        // 计算总加成系数
        let totalBonus =
            baseRigRatio * securityBonus * structureBonus * implantBonus * generalSkillBonus
                * specificSkillBonus

        Logger.debug("精炼加成计算 - 物品ID: \(itemID)")
        Logger.debug("  插件基础比例: \(baseRigRatio)")
        Logger.debug("  安全等级加成: \(securityBonus)")
        Logger.debug("  建筑加成: \(structureBonus)")
        Logger.debug("  植入体加成: \(implantBonus)")
        Logger.debug("  通用技能加成: \(generalSkillBonus)")
        Logger.debug("  专业技能加成: \(specificSkillBonus)")
        Logger.debug("  总加成系数: \(totalBonus)")

        return totalBonus
    }

    /// 获取建筑精炼加成
    func getStructureRefineryBonus(structureID: Int) -> Double {
        let query = "SELECT value FROM typeAttributes WHERE attribute_id = 2722 AND type_id = ?"

        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [structureID]),
           let row = rows.first,
           let value = row["value"] as? Double
        {
            return 1.0 + (value / 100.0) // 转换为百分比加成
        }

        return 1.0 // 默认无加成
    }

    /// 获取植入体精炼加成
    func getImplantRefineryBonus(implantID: Int) -> Double {
        if implantID == 0 {
            return 1.0
        } // 无植入体

        let query = "SELECT value FROM typeAttributes WHERE attribute_id = 379 AND type_id = ?"

        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [implantID]),
           let row = rows.first,
           let value = row["value"] as? Double
        {
            return 1.0 + (value / 100.0) // 转换为百分比加成
        }

        return 1.0 // 默认无加成
    }

    /// 计算通用技能加成 (3389 和 3385)
    func calculateGeneralSkillBonus(characterSkills: [Int: Int]) -> Double {
        let skillIDs = [3389, 3385] // 通用精炼技能
        var totalBonus = 1.0

        for skillID in skillIDs {
            let skillLevel = characterSkills[skillID] ?? 0
            let skillBonus = getSkillRefineryBonus(skillID: skillID, skillLevel: skillLevel)
            totalBonus *= skillBonus
        }

        return totalBonus
    }

    /// 计算专业技能加成
    func calculateSpecificSkillBonus(skillType: Int?, characterSkills: [Int: Int]) -> Double {
        guard let skillType = skillType else {
            return 1.0
        }

        let skillLevel = characterSkills[skillType] ?? 0
        return getSkillRefineryBonus(skillID: skillType, skillLevel: skillLevel)
    }

    /// 获取技能精炼加成
    func getSkillRefineryBonus(skillID: Int, skillLevel: Int) -> Double {
        let query = "SELECT value FROM typeAttributes WHERE attribute_id = 379 AND type_id = ?"

        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [skillID]),
           let row = rows.first,
           let value = row["value"] as? Double
        {
            return 1.0 + ((value * Double(skillLevel)) / 100.0) // 技能等级 * 每级加成
        }

        return 1.0 // 默认无加成
    }

    /// 计算压缩气云的精炼加成系数
    func calculateGasRefineryBonus(
        structureID: Int,
        characterSkills: [Int: Int]
    ) -> Double {
        // 1. 基础加成 80%
        let baseBonus = 0.8

        // 2. 技能62452加成
        let skillID = 62452
        let skillLevel = characterSkills[skillID] ?? 0
        let skillBonus = getGasSkillBonus(skillID: skillID, skillLevel: skillLevel)

        // 3. 建筑加成
        let structureBonus = getGasStructureBonus(structureID: structureID)

        // 直接相加：基础加成 + 技能加成 + 建筑加成
        let totalBonus = baseBonus + skillBonus + structureBonus

        Logger.debug("气云精炼加成计算:")
        Logger.debug("  基础加成: \(baseBonus)")
        Logger.debug("  技能加成: \(skillBonus)")
        Logger.debug("  建筑加成: \(structureBonus)")
        Logger.debug("  总加成: \(totalBonus)")

        return totalBonus
    }

    /// 获取气云技能加成
    func getGasSkillBonus(skillID: Int, skillLevel: Int) -> Double {
        let query = "SELECT value FROM typeAttributes WHERE attribute_id = 3260 AND type_id = ?"

        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [skillID]),
           let row = rows.first,
           let value = row["value"] as? Double
        {
            return (value * Double(skillLevel)) / 100.0 // 技能等级 * 每级加成
        }

        return 0.0 // 默认无加成
    }

    /// 获取气云建筑加成
    func getGasStructureBonus(structureID: Int) -> Double {
        let query = "SELECT value FROM typeAttributes WHERE attribute_id = 3261 AND type_id = ?"

        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [structureID]),
           let row = rows.first,
           let value = row["value"] as? Double
        {
            return value // 直接返回加成值（如0.1表示10%）
        }

        return 0.0 // 默认无加成
    }

    /// 计算其他物品的精炼加成系数
    func calculateOtherRefineryBonus(
        characterSkills: [Int: Int]
    ) -> Double {
        // 1. 基础比例 50%
        let baseRatio = 0.5

        // 2. 技能12196加成
        let skillID = 12196
        let skillLevel = characterSkills[skillID] ?? 0
        let skillBonus = getOtherSkillBonus(skillID: skillID, skillLevel: skillLevel)

        // 相乘：基础比例 * 技能加成
        let totalBonus = baseRatio * skillBonus

        Logger.debug("其他物品精炼加成计算:")
        Logger.debug("  基础比例: \(baseRatio)")
        Logger.debug("  技能加成: \(skillBonus)")
        Logger.debug("  总加成: \(totalBonus)")

        return totalBonus
    }

    /// 获取其他物品技能加成
    func getOtherSkillBonus(skillID: Int, skillLevel: Int) -> Double {
        let query = "SELECT value FROM typeAttributes WHERE attribute_id = 379 AND type_id = ?"

        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [skillID]),
           let row = rows.first,
           let value = row["value"] as? Double
        {
            return 1.0 + ((value * Double(skillLevel)) / 100.0) // 技能等级 * 每级加成
        }

        return 1.0 // 默认无加成
    }
}
