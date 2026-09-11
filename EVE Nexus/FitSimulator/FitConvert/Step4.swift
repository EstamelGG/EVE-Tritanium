import Foundation

/// Step4实现 - 递归计算属性最终值
class Step4 {
    private let databaseManager: DatabaseManager
    private let step3: Step3

    // 叠加惩罚因子: 1 / math.exp((1 / 2.67) ** 2)
    private let penaltyFactor: Double = 0.8691199808003974

    /// 需要应用叠加惩罚的操作类型
    private let stackableOperations: [String] = [
        "PreMul", "PreDiv", "PostMul", "PostDiv", "PostPercent",
    ]

    // `damageMultiplierBonusMax`：DPS 修正为 `raw_dps * (1 + bonus)`
    private let damageMultiplierBonusMaxAttributeId = 2734
    private let damageTypeAttributeIds: [Int] = [114, 116, 117, 118]

    /// 递归计算过程中记录的详细信息，用于调试
    private var attributeCalculationProcess: [String: String] = [:]

    /// 属性计算缓存
    private class Cache {
        var ship: [Int: Double] = [:]
        var character: [Int: Double] = [:]
        var modules: [Int: [Int: Double]] = [:]
        var charges: [Int: [Int: Double]] = [:]
        var drones: [Int: [Int: Double]] = [:]
        var fighters: [Int: [Int: Double]] = [:]
        var implants: [Int: [Int: Double]] = [:]
        var skills: [Int: [Int: Double]] = [:]
        var environments: [Int: [Int: Double]] = [:]

        /// 获取物品属性的缓存值
        func getValue(itemType: ItemType, itemIndex: Int, attributeId: Int) -> Double? {
            switch itemType {
            case .ship:
                return ship[attributeId]
            case .character:
                return character[attributeId]
            case .module:
                return modules[itemIndex]?[attributeId]
            case .charge:
                return charges[itemIndex]?[attributeId]
            case .drone:
                return drones[itemIndex]?[attributeId]
            case .fighter:
                return fighters[itemIndex]?[attributeId]
            case .implant:
                return implants[itemIndex]?[attributeId]
            case .skill:
                return skills[itemIndex]?[attributeId]
            case .environment:
                return environments[itemIndex]?[attributeId]
            }
        }

        /// 设置物品属性的缓存值
        func setValue(itemType: ItemType, itemIndex: Int, attributeId: Int, value: Double) {
            switch itemType {
            case .ship:
                ship[attributeId] = value
            case .character:
                character[attributeId] = value
            case .module:
                if modules[itemIndex] == nil {
                    modules[itemIndex] = [:]
                }
                modules[itemIndex]?[attributeId] = value
            case .charge:
                if charges[itemIndex] == nil {
                    charges[itemIndex] = [:]
                }
                charges[itemIndex]?[attributeId] = value
            case .drone:
                if drones[itemIndex] == nil {
                    drones[itemIndex] = [:]
                }
                drones[itemIndex]?[attributeId] = value
            case .fighter:
                if fighters[itemIndex] == nil {
                    fighters[itemIndex] = [:]
                }
                fighters[itemIndex]?[attributeId] = value
            case .implant:
                if implants[itemIndex] == nil {
                    implants[itemIndex] = [:]
                }
                implants[itemIndex]?[attributeId] = value
            case .skill:
                if skills[itemIndex] == nil {
                    skills[itemIndex] = [:]
                }
                skills[itemIndex]?[attributeId] = value
            case .environment:
                if environments[itemIndex] == nil {
                    environments[itemIndex] = [:]
                }
                environments[itemIndex]?[attributeId] = value
            }
        }
    }

    init(databaseManager: DatabaseManager, step3: Step3) {
        self.databaseManager = databaseManager
        self.step3 = step3
    }

    /// 执行Step4处理 - 递归计算属性最终值
    /// - Parameter input: 模拟输入数据
    /// - Returns: 更新后的模拟输出数据
    func process(input: SimulationInput) -> SimulationOutput {
        Logger.info("执行Step4 - 递归计算属性最终值")

        // 清空计算过程
        attributeCalculationProcess = [:]

        // 创建输出对象
        var output = SimulationOutput(from: input)

        // 创建计算缓存
        let cache = Cache()

        // 创建模块实例ID字典，用于快速查询模块状态
        var moduleInstanceMap: [UUID: (module: SimModule, index: Int)] = [:]
        for (index, module) in input.modules.enumerated() {
            moduleInstanceMap[module.instanceId] = (module, index)
        }

        // 计算所有物品的属性值
        calculateValues(input: input, cache: cache, moduleInstanceMap: moduleInstanceMap)

        // 将计算结果更新到输出对象
        updateOutputWithCachedValues(input: input, output: &output, cache: cache)

        // 仅在调试模式下显示日志（不影响计算）
        if AppConfiguration.Fitting.showDebug {
            // 显示关键属性的计算结果
            displayAttributeCalculationResults(input: input, output: output)

            // 展示每个装备的最终属性
            displayAllModuleAttributes(output: output)

            // 展示属性计算过程
            displayAttributeCalculationProcess()
        }

        Logger.info("Step4完成 - 成功计算所有属性的最终值")

        return output
    }

    /// 根据属性ID获取属性名称
    private func getAttributeName(for attributeId: Int) -> String? {
        return SDEMemoryStore.dogmaAttributes[attributeId]?.name
    }

    /// 计算所有物品的属性值
    private func calculateValues(
        input: SimulationInput,
        cache: Cache,
        moduleInstanceMap: [UUID: (module: SimModule, index: Int)]
    ) {
        // 计算飞船的属性
        calculateItemValues(
            item: input.ship,
            itemType: .ship,
            itemIndex: 0,
            input: input,
            cache: cache,
            moduleInstanceMap: moduleInstanceMap
        )

        // 计算角色的属性
        calculateItemValues(
            item: input.character,
            itemType: .character,
            itemIndex: 0,
            input: input,
            cache: cache,
            moduleInstanceMap: moduleInstanceMap
        )

        // 计算所有模块的属性
        for (index, module) in input.modules.enumerated() {
            calculateItemValues(
                item: module,
                itemType: .module,
                itemIndex: index,
                input: input,
                cache: cache,
                moduleInstanceMap: moduleInstanceMap
            )

            // 计算弹药的属性（如果有）
            if let charge = module.charge {
                calculateItemValues(
                    item: charge,
                    itemType: .charge,
                    itemIndex: index,
                    input: input,
                    cache: cache,
                    moduleInstanceMap: moduleInstanceMap
                )
            }
        }

        // 计算无人机的属性
        for (index, drone) in input.drones.enumerated() {
            calculateItemValues(
                item: drone,
                itemType: .drone,
                itemIndex: index,
                input: input,
                cache: cache,
                moduleInstanceMap: moduleInstanceMap
            )
        }

        // 计算舰载机的属性
        if let fighters = input.fighters {
            for (index, fighter) in fighters.enumerated() {
                calculateItemValues(
                    item: fighter,
                    itemType: .fighter,
                    itemIndex: index,
                    input: input,
                    cache: cache,
                    moduleInstanceMap: moduleInstanceMap
                )
            }
        }

        // 计算植入体的属性
        for (index, implant) in input.implants.enumerated() {
            calculateItemValues(
                item: implant,
                itemType: .implant,
                itemIndex: index,
                input: input,
                cache: cache,
                moduleInstanceMap: moduleInstanceMap
            )
        }

        // 计算技能的属性
        for (index, skill) in input.skills.enumerated() {
            calculateItemValues(
                item: skill,
                itemType: .skill,
                itemIndex: index,
                input: input,
                cache: cache,
                moduleInstanceMap: moduleInstanceMap
            )
        }
    }

    /// 计算单个物品的所有属性值
    private func calculateItemValues(
        item: Any,
        itemType: ItemType,
        itemIndex: Int,
        input: SimulationInput,
        cache: Cache,
        moduleInstanceMap: [UUID: (module: SimModule, index: Int)]
    ) {
        // 获取物品ID、属性和修饰器
        let (typeId, attributes, modifiers) = getItemDetails(item: item)

        // 计算每个属性的值
        for attributeId in Set(attributes.keys).union(Set(modifiers.keys)) {
            calculateAttributeValue(
                typeId: typeId,
                attributeId: attributeId,
                baseValue: attributes[attributeId] ?? 0.0,
                modifiers: modifiers[attributeId] ?? [],
                itemType: itemType,
                itemIndex: itemIndex,
                input: input,
                cache: cache,
                moduleInstanceMap: moduleInstanceMap
            )
        }
    }

    /// 获取物品的详细信息
    private func getItemDetails(item: Any) -> (
        typeId: Int, attributes: [Int: Double], modifiers: [Int: [SimAttributeModifier]]
    ) {
        if let ship = item as? SimShip {
            return (ship.typeId, ship.baseAttributes, ship.attributeModifiers)
        } else if let module = item as? SimModule {
            return (module.typeId, module.attributes, module.attributeModifiers)
        } else if let charge = item as? SimCharge {
            return (charge.typeId, charge.attributes, charge.attributeModifiers)
        } else if let drone = item as? SimDrone {
            return (drone.typeId, drone.attributes, drone.attributeModifiers)
        } else if let fighter = item as? SimFighterSquad {
            return (fighter.typeId, fighter.attributes, fighter.attributeModifiers)
        } else if let implant = item as? SimImplant {
            return (implant.typeId, implant.attributes, implant.attributeModifiers)
        } else if let skill = item as? SimSkill {
            return (skill.typeId, skill.attributes, skill.attributeModifiers)
        } else if let character = item as? SimCharacter {
            return (character.typeId, character.baseAttributes, character.attributeModifiers)
        }

        return (0, [:], [:])
    }

    /// 将计算结果更新到输出对象
    private func updateOutputWithCachedValues(
        input: SimulationInput, output: inout SimulationOutput, cache: Cache
    ) {
        // 更新飞船属性
        for (attributeId, value) in cache.ship {
            output.ship.attributes[attributeId] = value
            if let attrName = getAttributeName(for: attributeId) {
                output.ship.attributesByName[attrName] = value
            }
        }

        // 更新角色属性
        for (attributeId, value) in cache.character {
            // SimulationOutput没有character成员，需要更新到ship中存储角色属性
            // 这里假设ship中有专门存储角色属性的字段，如果没有则需要另外考虑存储位置
            output.ship.characterAttributes[attributeId] = value
            if let attrName = getAttributeName(for: attributeId) {
                output.ship.characterAttributesByName[attrName] = value
            }
        }

        // 更新模块属性
        for (index, _) in input.modules.enumerated() {
            if let moduleAttributes = cache.modules[index] {
                for (attributeId, value) in moduleAttributes {
                    output.modules[index].attributes[attributeId] = value
                    if let attrName = getAttributeName(for: attributeId) {
                        output.modules[index].attributesByName[attrName] = value
                    }
                }
            }

            // 更新弹药属性（如果有）
            if output.modules[index].charge != nil, let chargeAttributes = cache.charges[index] {
                for (attributeId, value) in chargeAttributes {
                    output.modules[index].charge!.attributes[attributeId] = value
                    if let attrName = getAttributeName(for: attributeId) {
                        output.modules[index].charge!.attributesByName[attrName] = value
                    }
                }
            }

            applyDamageMultiplierBonusMaxToModuleIfNeeded(
                &output.modules[index], isSpoolUpFull: input.modules[index].isSpoolUpFull
            )
        }

        // 更新无人机属性
        for (index, _) in input.drones.enumerated() {
            if let droneAttributes = cache.drones[index] {
                for (attributeId, value) in droneAttributes {
                    output.drones[index].attributes[attributeId] = value
                    if let attrName = getAttributeName(for: attributeId) {
                        output.drones[index].attributesByName[attrName] = value
                    }
                }
            }
        }

        // 更新舰载机属性
        if let inputFighters = input.fighters, let outputFighters = output.fighters {
            for (index, _) in inputFighters.enumerated() {
                if index < outputFighters.count, let fighterAttributes = cache.fighters[index] {
                    for (attributeId, value) in fighterAttributes {
                        output.fighters![index].attributes[attributeId] = value
                        if let attrName = getAttributeName(for: attributeId) {
                            output.fighters![index].attributesByName[attrName] = value
                        }
                    }
                }
            }
        }

        // 更新植入体属性
        for (index, _) in input.implants.enumerated() {
            if let implantAttributes = cache.implants[index] {
                for (attributeId, value) in implantAttributes {
                    output.implants[index].attributes[attributeId] = value
                    if let attrName = getAttributeName(for: attributeId) {
                        output.implants[index].attributesByName[attrName] = value
                    }
                }
            }
        }
    }

    /// 若模块存在 `damageMultiplierBonusMax`（2734），将各伤害类型数值乘以 `(1 + bonus)`。
    /// 未完全预热时按 `bonus = 1` 参与计算（见装配「完全预热」开关）。
    private func applyDamageMultiplierBonusMaxToModuleIfNeeded(
        _ module: inout SimModuleOutput, isSpoolUpFull: Bool
    ) {
        let rawBonus =
            module.attributes[damageMultiplierBonusMaxAttributeId]
                ?? module.attributesByName["damageMultiplierBonusMax"]
        guard let rawBonus else { return }
        let effectiveBonus = isSpoolUpFull ? rawBonus : 0
        let factor = 1.0 + effectiveBonus
        for attributeId in damageTypeAttributeIds {
            if var v = module.attributes[attributeId] {
                v *= factor
                module.attributes[attributeId] = v
                if let attrName = getAttributeName(for: attributeId) {
                    module.attributesByName[attrName] = v
                }
            }
        }
        if var charge = module.charge {
            for attributeId in damageTypeAttributeIds {
                if var v = charge.attributes[attributeId] {
                    v *= factor
                    charge.attributes[attributeId] = v
                    if let attrName = getAttributeName(for: attributeId) {
                        charge.attributesByName[attrName] = v
                    }
                }
            }
            module.charge = charge
        }
    }

    /// 计算单个属性的值
    private func calculateAttributeValue(
        typeId: Int,
        attributeId: Int,
        baseValue: Double,
        modifiers: [SimAttributeModifier],
        itemType: ItemType,
        itemIndex: Int,
        input: SimulationInput,
        cache: Cache,
        moduleInstanceMap: [UUID: (module: SimModule, index: Int)]
    ) {
        // 检查缓存中是否已有计算结果
        if cache.getValue(itemType: itemType, itemIndex: itemIndex, attributeId: attributeId) != nil {
            return
        }

        // 当前属性值，初始为基础值
        var currentValue = baseValue

        // 获取当前物品的instanceId用于生成唯一的计算过程键
        let instanceId = getInstanceId(itemType: itemType, itemIndex: itemIndex, input: input)
        let instanceIdShort = String(instanceId.uuidString.prefix(8))

        // 记录计算过程（仅在调试模式下）
        let attrName = getAttributeName(for: attributeId) ?? "未知属性"
        var process: String?
        if AppConfiguration.Fitting.showDebug {
            process =
                "[AttributeCalc] TypeID：\(typeId)，实例ID：\(instanceIdShort)，属性：\(attrName)(ID: \(attributeId))，基础值：\(baseValue)"
        }

        // 如果没有修饰器，直接缓存基础值
        if modifiers.isEmpty {
            cache.setValue(
                itemType: itemType, itemIndex: itemIndex, attributeId: attributeId, value: baseValue
            )
            if AppConfiguration.Fitting.showDebug, var processValue = process {
                processValue += "\n  无修饰器，最终值：\(baseValue)"
                attributeCalculationProcess["\(instanceIdShort):\(attributeId)"] = processValue
            }
            return
        }

        // 按操作类型分组处理修饰器
        let operationTypes = [
            "PreAssign", "PreMul", "PreDiv", "ModAdd", "ModSub",
            "PostMul", "PostDiv", "PostPercent", "PostAssign",
        ]

        for operation in operationTypes {
            // 获取当前操作类型的所有修饰器
            let operationModifiers = modifiers.filter { $0.operation == operation }
            if operationModifiers.isEmpty {
                continue
            }

            // 应用操作类型的修饰器
            let operationResult = applyOperator(
                operation: operation,
                modifiers: operationModifiers,
                currentValue: currentValue,
                attributeId: attributeId,
                itemType: itemType,
                input: input,
                cache: cache,
                moduleInstanceMap: moduleInstanceMap
            )

            currentValue = operationResult.newValue
            if AppConfiguration.Fitting.showDebug, var processValue = process {
                processValue += operationResult.process
                process = processValue
            }
        }

        // 缓存计算结果
        cache.setValue(
            itemType: itemType, itemIndex: itemIndex, attributeId: attributeId, value: currentValue
        )

        // 记录最终结果（仅在调试模式下）
        if AppConfiguration.Fitting.showDebug, var processValue = process {
            if !processValue.contains("最终值") {
                processValue += "\n  最终值: \(currentValue)"
            }
            // 存储计算过程，使用instanceId作为键的一部分
            attributeCalculationProcess["\(instanceIdShort):\(attributeId)"] = processValue
        }
    }

    /// 获取物品的instanceId
    private func getInstanceId(itemType: ItemType, itemIndex: Int, input: SimulationInput) -> UUID {
        switch itemType {
        case .ship:
            return input.ship.instanceId
        case .character:
            return input.character.instanceId
        case .module:
            return input.modules[itemIndex].instanceId
        case .charge:
            return input.modules[itemIndex].charge?.instanceId ?? UUID()
        case .drone:
            return input.drones[itemIndex].instanceId
        case .fighter:
            return input.fighters?[itemIndex].instanceId ?? UUID()
        case .implant:
            return input.implants[itemIndex].instanceId
        case .skill:
            return input.skills[itemIndex].instanceId
        case .environment:
            return input.environmentEffects[itemIndex].instanceId
        }
    }

    /// 应用操作类型的修饰器
    private func applyOperator(
        operation: String,
        modifiers: [SimAttributeModifier],
        currentValue: Double,
        attributeId: Int,
        itemType: ItemType,
        input: SimulationInput,
        cache: Cache,
        moduleInstanceMap: [UUID: (module: SimModule, index: Int)]
    ) -> (newValue: Double, process: String) {
        var newValue = currentValue
        var process = AppConfiguration.Fitting.showDebug ? "\n  \(operation): \(currentValue)" : ""

        // 如果没有修饰器，直接返回
        if modifiers.isEmpty {
            if AppConfiguration.Fitting.showDebug {
                process += "\n    无修饰器应用"
            }
            return (newValue, process)
        }

        // 过滤出符合当前状态要求的修饰器
        let validModifiers = modifiers.filter { modifier in
            // 如果没有effectCategory，默认认为是有效的
            guard let effectCategory = modifier.effectCategory else {
                return true
            }

            // 获取修饰器来源的实例ID
            guard let sourceInstanceId = modifier.sourceInstanceId else {
                return true
            }

            // 直接从字典中查找模块
            if let (module, _) = moduleInstanceMap[sourceInstanceId] {
                // 获取该效果类别所需的最低状态
                let requiredStatus = getRequiredStatusForEffect(effectCategory: effectCategory)
                // 检查模块当前状态是否满足效果要求
                return module.status >= requiredStatus
            }

            // 如果在字典中找不到对应模块，默认允许应用
            return true
        }

        // 如果过滤后没有有效修饰器，直接返回
        if validModifiers.isEmpty {
            if AppConfiguration.Fitting.showDebug {
                process += "\n    没有符合当前状态的修饰器"
            }
            return (newValue, process)
        }

        // 对 dbuff 修饰器进行去重处理（只保留强度最高的）
        let finalModifiers = deduplicateDbuffModifiers(
            modifiers: validModifiers,
            input: input,
            cache: cache,
            moduleInstanceMap: moduleInstanceMap
        )

        switch operation {
        case "PreAssign", "PostAssign":
            // 直接赋值，取最大或最小值（根据属性是否highIsGood）
            let isHighGood = step3.isAttributeHighGood(attributeId: attributeId)
            var bestValue: Double?
            var bestSource = ""

            for modifier in finalModifiers {
                // 获取修饰源的值
                let sourceValue = getSourceAttributeValue(
                    modifier: modifier,
                    input: input,
                    cache: cache,
                    moduleInstanceMap: moduleInstanceMap
                )

                let sourceName = modifier.sourceName
                let sourceAttrName = getAttributeName(for: modifier.sourceAttributeId) ?? "未知属性"

                if bestValue == nil {
                    bestValue = sourceValue
                    bestSource =
                        "\(sourceName)的\(sourceAttrName)(\(modifier.sourceAttributeId)): \(sourceValue)"
                } else if isHighGood, sourceValue > bestValue! {
                    bestValue = sourceValue
                    bestSource =
                        "\(sourceName)的\(sourceAttrName)(\(modifier.sourceAttributeId)): \(sourceValue)"
                } else if !isHighGood, sourceValue < bestValue! {
                    bestValue = sourceValue
                    bestSource =
                        "\(sourceName)的\(sourceAttrName)(\(modifier.sourceAttributeId)): \(sourceValue)"
                }
            }

            if let value = bestValue {
                newValue = value
                if AppConfiguration.Fitting.showDebug {
                    process += "\n    直接赋值为\(bestSource)"
                }
            }

        case "PreMul", "PostMul", "PreDiv", "PostDiv", "PostPercent":
            // 乘法、除法和百分比修饰器

            // 分为三组：非叠加惩罚、正值叠加惩罚、负值叠加惩罚
            var nonStackingValues: [(value: Double, source: String)] = []
            var positiveStackingValues: [(value: Double, source: String)] = []
            var negativeStackingValues: [(value: Double, source: String)] = []

            // 收集所有值并分组
            for modifier in finalModifiers {
                let sourceValue = getSourceAttributeValue(
                    modifier: modifier,
                    input: input,
                    cache: cache,
                    moduleInstanceMap: moduleInstanceMap
                )

                // 转换值
                let transformedValue: Double
                switch operation {
                case "PreMul", "PostMul":
                    transformedValue = sourceValue - 1.0
                case "PreDiv", "PostDiv":
                    transformedValue = 1.0 / sourceValue - 1.0
                case "PostPercent":
                    transformedValue = sourceValue / 100.0
                default:
                    transformedValue = sourceValue
                }

                let sourceName = modifier.sourceName
                let sourceAttrName = getAttributeName(for: modifier.sourceAttributeId) ?? "未知属性"
                let source = "\(sourceName)的\(sourceAttrName)(\(modifier.sourceAttributeId))"

                if modifier.stackingPenalty, stackableOperations.contains(operation) {
                    if transformedValue < 0 {
                        negativeStackingValues.append((transformedValue, source))
                    } else {
                        positiveStackingValues.append((transformedValue, source))
                    }
                } else {
                    nonStackingValues.append((transformedValue, source))
                }
            }

            // 应用非叠加惩罚的修饰器
            for (value, source) in nonStackingValues {
                newValue *= (1.0 + value)
                if AppConfiguration.Fitting.showDebug {
                    process += "\n    * (1 + \(value)) [\(source)] = \(newValue)"
                }
            }

            // 按绝对值从大到小排序
            positiveStackingValues.sort { abs($0.value) > abs($1.value) }
            negativeStackingValues.sort { abs($0.value) > abs($1.value) }

            // 应用正值叠加惩罚
            if AppConfiguration.Fitting.showDebug, !positiveStackingValues.isEmpty {
                process += "\n    正值叠加惩罚:"
            }

            for (index, (value, source)) in positiveStackingValues.enumerated() {
                let penalty = pow(penaltyFactor, Double(index * index))
                let penalizedValue = value * penalty
                newValue *= (1.0 + penalizedValue)
                if AppConfiguration.Fitting.showDebug {
                    process +=
                        "\n    * (1 + \(value) * \(penalty)) [\(source), 第\(index + 1)级惩罚] = \(newValue)"
                }
            }

            // 应用负值叠加惩罚
            if AppConfiguration.Fitting.showDebug, !negativeStackingValues.isEmpty {
                process += "\n    负值叠加惩罚:"
            }

            for (index, (value, source)) in negativeStackingValues.enumerated() {
                let penalty = pow(penaltyFactor, Double(index * index))
                let penalizedValue = value * penalty
                newValue *= (1.0 + penalizedValue)
                if AppConfiguration.Fitting.showDebug {
                    process +=
                        "\n    * (1 + \(value) * \(penalty)) [\(source), 第\(index + 1)级惩罚] = \(newValue)"
                }
            }

        case "ModAdd", "ModSub":
            // 加减法修饰器
            for modifier in finalModifiers {
                let sourceValue = getSourceAttributeValue(
                    modifier: modifier,
                    input: input,
                    cache: cache,
                    moduleInstanceMap: moduleInstanceMap
                )

                let value = operation == "ModAdd" ? sourceValue : -sourceValue

                // 跃迁干扰状态(104)只统计负贡献（跃迁稳定点数：船体固有值/跃迁核心稳定器/泰坦加成）；
                // 正贡献（如激活旗舰模块使自身无法跃迁）属于战术状态叠加，不计入船体固有属性
                if itemType == .ship, attributeId == 104, value > 0 {
                    continue
                }

                newValue += value

                if AppConfiguration.Fitting.showDebug {
                    let sourceName = modifier.sourceName
                    let sourceAttrName = getAttributeName(for: modifier.sourceAttributeId) ?? "未知属性"
                    let operationSymbol = operation == "ModAdd" ? "+" : "-"

                    process += " \(operationSymbol) \(sourceValue) (\(sourceName)的\(sourceAttrName))"
                }
            }

            if AppConfiguration.Fitting.showDebug {
                process += " = \(newValue)"
            }

        default:
            break
        }

        return (newValue, process)
    }

    /// 根据缓存或递归计算获取单个源属性的值。
    /// 通用模式：查 cache → 取 baseValue → 递归 calculateAttributeValue → 再查 cache → 返回默认值。
    /// 适用于 ship/character/module/charge/drone/fighter/implant/skill（environment 段逻辑不同，不使用本 helper）。
    private func getSourceAttributeValueFromCache(
        sourceAttributeId: Int,
        itemType: ItemType,
        itemIndex: Int,
        typeId: Int,
        baseValue: Double?,
        modifiers: [SimAttributeModifier],
        input: SimulationInput,
        cache: Cache,
        moduleInstanceMap: [UUID: (module: SimModule, index: Int)]
    ) -> Double {
        // 查 cache
        if let value = cache.getValue(
            itemType: itemType, itemIndex: itemIndex, attributeId: sourceAttributeId
        ) {
            return value
        }

        // 取 baseValue → 递归 calculateAttributeValue → 再查 cache
        if let baseValue = baseValue {
            calculateAttributeValue(
                typeId: typeId,
                attributeId: sourceAttributeId,
                baseValue: baseValue,
                modifiers: modifiers,
                itemType: itemType,
                itemIndex: itemIndex,
                input: input,
                cache: cache,
                moduleInstanceMap: moduleInstanceMap
            )
            if let value = cache.getValue(
                itemType: itemType, itemIndex: itemIndex, attributeId: sourceAttributeId
            ) {
                return value
            }
        }

        // 如果没有找到属性，使用默认值
        return SDEMemoryStore.dogmaAttributes[sourceAttributeId]?.defaultValue ?? 0.0
    }

    /// 获取修饰源的属性值
    private func getSourceAttributeValue(
        modifier: SimAttributeModifier,
        input: SimulationInput,
        cache: Cache,
        moduleInstanceMap: [UUID: (module: SimModule, index: Int)]
    ) -> Double {
        let sourceAttributeId = modifier.sourceAttributeId

        // 必须有sourceInstanceId才能进行查找
        guard let sourceInstanceId = modifier.sourceInstanceId else {
            // 如果没有sourceInstanceId，使用默认值
            return SDEMemoryStore.dogmaAttributes[sourceAttributeId]?.defaultValue ?? 0.0
        }

        // 在飞船中查找
        if input.ship.instanceId == sourceInstanceId {
            return getSourceAttributeValueFromCache(
                sourceAttributeId: sourceAttributeId,
                itemType: .ship,
                itemIndex: 0,
                typeId: input.ship.typeId,
                baseValue: input.ship.baseAttributes[sourceAttributeId],
                modifiers: input.ship.attributeModifiers[sourceAttributeId] ?? [],
                input: input,
                cache: cache,
                moduleInstanceMap: moduleInstanceMap
            )
        }

        // 在角色中查找
        if input.character.instanceId == sourceInstanceId {
            return getSourceAttributeValueFromCache(
                sourceAttributeId: sourceAttributeId,
                itemType: .character,
                itemIndex: 0,
                typeId: input.character.typeId,
                baseValue: input.character.baseAttributes[sourceAttributeId],
                modifiers: input.character.attributeModifiers[sourceAttributeId] ?? [],
                input: input,
                cache: cache,
                moduleInstanceMap: moduleInstanceMap
            )
        }

        // 在模块中查找（使用字典快速访问）
        if let (module, moduleIndex) = moduleInstanceMap[sourceInstanceId] {
            return getSourceAttributeValueFromCache(
                sourceAttributeId: sourceAttributeId,
                itemType: .module,
                itemIndex: moduleIndex,
                typeId: module.typeId,
                baseValue: module.attributes[sourceAttributeId],
                modifiers: module.attributeModifiers[sourceAttributeId] ?? [],
                input: input,
                cache: cache,
                moduleInstanceMap: moduleInstanceMap
            )
        }

        // 在弹药中查找
        for (index, module) in input.modules.enumerated() {
            if let charge = module.charge, charge.instanceId == sourceInstanceId {
                return getSourceAttributeValueFromCache(
                    sourceAttributeId: sourceAttributeId,
                    itemType: .charge,
                    itemIndex: index,
                    typeId: charge.typeId,
                    baseValue: charge.attributes[sourceAttributeId],
                    modifiers: charge.attributeModifiers[sourceAttributeId] ?? [],
                    input: input,
                    cache: cache,
                    moduleInstanceMap: moduleInstanceMap
                )
            }
        }

        // 在无人机中查找
        for (index, drone) in input.drones.enumerated() {
            if drone.instanceId == sourceInstanceId {
                return getSourceAttributeValueFromCache(
                    sourceAttributeId: sourceAttributeId,
                    itemType: .drone,
                    itemIndex: index,
                    typeId: drone.typeId,
                    baseValue: drone.attributes[sourceAttributeId],
                    modifiers: drone.attributeModifiers[sourceAttributeId] ?? [],
                    input: input,
                    cache: cache,
                    moduleInstanceMap: moduleInstanceMap
                )
            }
        }

        // 在舰载机中查找
        if let fighters = input.fighters {
            for (index, fighter) in fighters.enumerated() {
                if fighter.instanceId == sourceInstanceId {
                    return getSourceAttributeValueFromCache(
                        sourceAttributeId: sourceAttributeId,
                        itemType: .fighter,
                        itemIndex: index,
                        typeId: fighter.typeId,
                        baseValue: fighter.attributes[sourceAttributeId],
                        modifiers: fighter.attributeModifiers[sourceAttributeId] ?? [],
                        input: input,
                        cache: cache,
                        moduleInstanceMap: moduleInstanceMap
                    )
                }
            }
        }

        // 在植入体中查找
        for (index, implant) in input.implants.enumerated() {
            if implant.instanceId == sourceInstanceId {
                return getSourceAttributeValueFromCache(
                    sourceAttributeId: sourceAttributeId,
                    itemType: .implant,
                    itemIndex: index,
                    typeId: implant.typeId,
                    baseValue: implant.attributes[sourceAttributeId],
                    modifiers: implant.attributeModifiers[sourceAttributeId] ?? [],
                    input: input,
                    cache: cache,
                    moduleInstanceMap: moduleInstanceMap
                )
            }
        }

        // 在环境效果中查找
        for (index, environment) in input.environmentEffects.enumerated() {
            if environment.instanceId == sourceInstanceId {
                if let value = cache.getValue(
                    itemType: .environment, itemIndex: index, attributeId: sourceAttributeId
                ) {
                    return value
                }

                if let baseValue = environment.attributes[sourceAttributeId] {
                    cache.setValue(
                        itemType: .environment,
                        itemIndex: index,
                        attributeId: sourceAttributeId,
                        value: baseValue
                    )
                    return baseValue
                }

                return SDEMemoryStore.dogmaAttributes[sourceAttributeId]?.defaultValue ?? 0.0
            }
        }

        // 在技能中查找
        for (index, skill) in input.skills.enumerated() {
            if skill.instanceId == sourceInstanceId {
                return getSourceAttributeValueFromCache(
                    sourceAttributeId: sourceAttributeId,
                    itemType: .skill,
                    itemIndex: index,
                    typeId: skill.typeId,
                    baseValue: skill.attributes[sourceAttributeId],
                    modifiers: skill.attributeModifiers[sourceAttributeId] ?? [],
                    input: input,
                    cache: cache,
                    moduleInstanceMap: moduleInstanceMap
                )
            }
        }

        // 如果没有找到对应的实例或属性，使用默认值
        return SDEMemoryStore.dogmaAttributes[sourceAttributeId]?.defaultValue ?? 0.0
    }

    /// 显示属性计算结果，用于调试和验证
    private func displayAttributeCalculationResults(
        input: SimulationInput, output: SimulationOutput
    ) {
        Logger.info("===== 属性计算结果 =====")

        // 显示飞船的关键属性计算结果
        Logger.info("【飞船】\(input.ship.name) (TypeID: \(input.ship.typeId))")

        // 显示惯性调整属性(70)的计算过程和结果
        if let baseValue = input.ship.baseAttributes[70],
           let finalValue = output.ship.attributes[70]
        {
            Logger.info("  惯性调整(ID: 70):")
            Logger.info("    基础值: \(baseValue)")
            Logger.info("    最终值: \(finalValue)")

            // 计算改进百分比（对于惯性调整，越小越好）
            let improvementPercent = ((baseValue - finalValue) / baseValue * 100)
            Logger.info("    改进百分比: \(improvementPercent)%")
        }

        // 显示其他关键属性的计算结果
        let keyAttributes = [
            (11, "装配CPU输出"),
            (48, "CPU输出"),
            (263, "护盾HP"),
            (265, "船体HP"),
            (9, "装配能量栅格输出"),
            (30, "能量栅格输出"),
        ]

        for (attrId, attrName) in keyAttributes {
            if let baseValue = input.ship.baseAttributes[attrId],
               let finalValue = output.ship.attributes[attrId]
            {
                Logger.info("  \(attrName)(ID: \(attrId)):")
                Logger.info("    基础值: \(baseValue)")
                Logger.info("    最终值: \(finalValue)")

                // 计算改进百分比（对于越大越好的属性）
                let improvementPercent = ((finalValue - baseValue) / baseValue * 100)
                Logger.info("    改进百分比: \(improvementPercent)%")
            }
        }

        Logger.info("===== 属性计算结果结束 =====")
    }

    /// 显示每个装备的最终属性，格式为id：value
    private func displayAllModuleAttributes(output: SimulationOutput) {
        Logger.info("===== 所有装备的最终属性 =====")

        // 遍历所有装备
        for (index, module) in output.modules.enumerated() {
            let slotName = module.flag?.rawValue ?? "未知槽位"
            // 显示instanceId的前8位以便区分相同typeId的装备
            let instanceIdShort = String(module.instanceId.uuidString.prefix(8))
            Logger.info(
                "\n【装备 \(index + 1)】\(module.name) (TypeID: \(module.typeId), 槽位: \(slotName), 实例ID: \(instanceIdShort))"
            )

            // 按属性ID排序
            let sortedAttributeIds = module.attributes.keys.sorted()

            for attrId in sortedAttributeIds {
                if let value = module.attributes[attrId],
                   let attrName = getAttributeName(for: attrId)
                {
                    Logger.info("  \(attrId): \(value) (\(attrName))")
                }
            }

            // 如果有弹药，也显示弹药的属性
            if let charge = module.charge {
                let chargeInstanceIdShort = String(charge.instanceId.uuidString.prefix(8))
                Logger.info(
                    "\n  【弹药】\(charge.name) (TypeID: \(charge.typeId), 实例ID: \(chargeInstanceIdShort))"
                )

                // 按属性ID排序
                let sortedChargeAttributeIds = charge.attributes.keys.sorted()

                for attrId in sortedChargeAttributeIds {
                    if let value = charge.attributes[attrId],
                       let attrName = getAttributeName(for: attrId)
                    {
                        Logger.info("    \(attrId): \(value) (\(attrName))")
                    }
                }
            }
        }

        // 显示无人机属性
        if !output.drones.isEmpty {
            Logger.info("\n===== 所有无人机的最终属性 =====")

            for (index, drone) in output.drones.enumerated() {
                let droneInstanceIdShort = String(drone.instanceId.uuidString.prefix(8))
                Logger.info(
                    "\n【无人机 \(index + 1)】\(drone.name) (TypeID: \(drone.typeId), 数量: \(drone.quantity), 实例ID: \(droneInstanceIdShort))"
                )

                // 按属性ID排序
                let sortedAttributeIds = drone.attributes.keys.sorted()

                for attrId in sortedAttributeIds {
                    if let value = drone.attributes[attrId],
                       let attrName = getAttributeName(for: attrId)
                    {
                        Logger.info("  \(attrId): \(value) (\(attrName))")
                    }
                }
            }
        }

        // 显示舰载机属性
        if let fighters = output.fighters, !fighters.isEmpty {
            Logger.info("\n===== 所有舰载机的最终属性 =====")

            for (index, fighter) in fighters.enumerated() {
                let fighterInstanceIdShort = String(fighter.instanceId.uuidString.prefix(8))
                Logger.info(
                    "\n【舰载机 \(index + 1)】\(fighter.name) (TypeID: \(fighter.typeId), 数量: \(fighter.quantity), 发射管: \(fighter.tubeId), 实例ID: \(fighterInstanceIdShort))"
                )

                // 按属性ID排序
                let sortedAttributeIds = fighter.attributes.keys.sorted()

                for attrId in sortedAttributeIds {
                    if let value = fighter.attributes[attrId],
                       let attrName = getAttributeName(for: attrId)
                    {
                        Logger.info("  \(attrId): \(value) (\(attrName))")
                    }
                }
            }
        }

        Logger.info("\n===== 装备属性展示结束 =====")
    }

    /// 显示属性计算过程
    private func displayAttributeCalculationProcess() {
        Logger.info("\n===== 属性计算过程 =====")

        // 按照物品类型和属性ID对计算过程进行排序
        let sortedKeys = attributeCalculationProcess.keys.sorted()

        // 输出所有计算过程
        for key in sortedKeys {
            if let process = attributeCalculationProcess[key] {
                Logger.info("\n\(process)")
            }
        }

        Logger.info("\n===== 属性计算过程结束 =====")
    }

    /// 根据效果类别获取所需的模块状态
    private func getRequiredStatusForEffect(effectCategory: Int) -> Int {
        switch effectCategory {
        case 0: // passive
            return 0 // 离线状态就可以生效
        case 1: // active
            return 2 // 需要启动状态
        case 4: // online
            return 1 // 需要在线状态
        case 5: // overload
            return 3 // 需要超载状态
        default:
            return 0 // 默认离线状态就可以生效
        }
    }

    /// 对 dbuff 修饰器进行去重处理（根据 aggregateMode 选择保留策略）
    private func deduplicateDbuffModifiers(
        modifiers: [SimAttributeModifier],
        input: SimulationInput,
        cache: Cache,
        moduleInstanceMap: [UUID: (module: SimModule, index: Int)]
    ) -> [SimAttributeModifier] {
        // 分离 dbuff 修饰器和普通修饰器
        var dbuffModifiers: [SimAttributeModifier] = []
        var normalModifiers: [SimAttributeModifier] = []

        for modifier in modifiers {
            if let effectId = modifier.effectId, effectId < 0 {
                dbuffModifiers.append(modifier)
            } else {
                normalModifiers.append(modifier)
            }
        }

        // 如果没有 dbuff 修饰器，直接返回原始列表
        if dbuffModifiers.isEmpty {
            return modifiers
        }

        if AppConfiguration.Fitting.showDebug {
            Logger.info("发现 \(dbuffModifiers.count) 个 dbuff 修饰器，开始去重处理")
        }

        // 按 effectId 分组 dbuff 修饰器
        var dbuffGroups: [Int: [SimAttributeModifier]] = [:]
        for modifier in dbuffModifiers {
            if let effectId = modifier.effectId {
                if dbuffGroups[effectId] == nil {
                    dbuffGroups[effectId] = []
                }
                dbuffGroups[effectId]!.append(modifier)
            }
        }

        // 获取所有 dbuff_id 的 aggregateMode
        let dbuffIds = Array(dbuffGroups.keys.map { abs($0) }) // 转换为正数的 dbuff_id
        let aggregateModes = getAggregateModes(for: dbuffIds)

        // 对每组 dbuff 修饰器进行去重，根据 aggregateMode 选择保留策略
        var deduplicatedDbuffModifiers: [SimAttributeModifier] = []

        for (effectId, groupModifiers) in dbuffGroups {
            if groupModifiers.count == 1 {
                // 如果只有一个修饰器，直接添加
                deduplicatedDbuffModifiers.append(groupModifiers[0])
                if AppConfiguration.Fitting.showDebug {
                    Logger.info("效果ID \(effectId): 只有1个修饰器，直接保留")
                }
            } else {
                // 如果有多个修饰器，根据 aggregateMode 选择保留策略
                let dbuffId = abs(effectId) // 转换为正数的 dbuff_id
                let aggregateMode = aggregateModes[dbuffId] ?? "Default" // 默认为 Default 模式

                var selectedModifier: SimAttributeModifier?
                var selectedValue = 0.0
                var strengthDetails: [(modifier: SimAttributeModifier, strength: Double)] = []

                // 收集所有修饰器的强度值
                for modifier in groupModifiers {
                    let strengthValue = getSourceAttributeValue(
                        modifier: modifier,
                        input: input,
                        cache: cache,
                        moduleInstanceMap: moduleInstanceMap
                    )
                    strengthDetails.append((modifier: modifier, strength: strengthValue))
                }

                // 根据 aggregateMode 选择保留策略
                switch aggregateMode.lowercased() {
                case "maximum":
                    // 取较大的修饰器
                    for detail in strengthDetails {
                        if selectedModifier == nil || detail.strength > selectedValue {
                            selectedModifier = detail.modifier
                            selectedValue = detail.strength
                        }
                    }
                    if AppConfiguration.Fitting.showDebug {
                        Logger.info("效果ID \(effectId): 使用 Maximum 模式，保留数值较大的修饰器")
                    }

                case "minimum":
                    // 取较小的修饰器
                    for detail in strengthDetails {
                        if selectedModifier == nil || detail.strength < selectedValue {
                            selectedModifier = detail.modifier
                            selectedValue = detail.strength
                        }
                    }
                    if AppConfiguration.Fitting.showDebug {
                        Logger.info("效果ID \(effectId): 使用 Minimum 模式，保留数值较小的修饰器")
                    }

                default:
                    // 默认情况：取绝对值最大的修饰器
                    for detail in strengthDetails {
                        if selectedModifier == nil || abs(detail.strength) > abs(selectedValue) {
                            selectedModifier = detail.modifier
                            selectedValue = detail.strength
                        }
                    }
                    if AppConfiguration.Fitting.showDebug {
                        Logger.info("效果ID \(effectId): 使用 Default 模式，保留绝对值最大的修饰器")
                    }
                }

                if let selected = selectedModifier {
                    deduplicatedDbuffModifiers.append(selected)

                    if AppConfiguration.Fitting.showDebug {
                        // 记录详细的去重信息
                        let removedCount = groupModifiers.count - 1
                        Logger.info(
                            "效果ID \(effectId): 发现 \(groupModifiers.count) 个相同的 dbuff 修饰器，聚合模式: \(aggregateMode)"
                        )

                        // 显示所有修饰器的强度
                        for (index, detail) in strengthDetails.enumerated() {
                            let isSelected =
                                detail.modifier.sourceInstanceId == selected.sourceInstanceId
                            let status = isSelected ? "【保留】" : "【移除】"
                            let sourceName = detail.modifier.sourceName
                            Logger.info(
                                "  \(index + 1). \(status) \(sourceName) - 强度: \(detail.strength)"
                            )
                        }

                        if removedCount > 0 {
                            Logger.info("  结果: 保留选中的修饰器 (\(selectedValue))，移除了 \(removedCount) 个其他的")
                        }
                    }
                } else {
                    if AppConfiguration.Fitting.showDebug {
                        Logger.warning("效果ID \(effectId): 无法确定要保留的修饰器，跳过该组")
                    }
                }
            }
        }

        if AppConfiguration.Fitting.showDebug {
            let totalDbuffBefore = dbuffModifiers.count
            let totalDbuffAfter = deduplicatedDbuffModifiers.count
            let removedDbuffCount = totalDbuffBefore - totalDbuffAfter

            if removedDbuffCount > 0 {
                Logger.info(
                    "Dbuff去重完成: 原有 \(totalDbuffBefore) 个，去重后 \(totalDbuffAfter) 个，移除了 \(removedDbuffCount) 个重复的"
                )
            } else {
                Logger.info("Dbuff去重完成: 没有发现重复的 dbuff 修饰器")
            }
        }

        // 合并普通修饰器和去重后的 dbuff 修饰器
        return normalModifiers + deduplicatedDbuffModifiers
    }

    /// 从 dbuffCollection 表获取 aggregateMode
    private func getAggregateModes(for dbuffIds: [Int]) -> [Int: String] {
        var aggregateModes: [Int: String] = [:]

        if dbuffIds.isEmpty {
            return aggregateModes
        }

        // 构建IN查询的占位符
        let placeholders = Array(repeating: "?", count: dbuffIds.count).joined(separator: ",")

        let query = """
            SELECT dbuff_id, aggregateMode 
            FROM dbuffCollection 
            WHERE dbuff_id IN (\(placeholders))
        """

        if case let .success(rows) = databaseManager.executeQuery(query, parameters: dbuffIds) {
            for row in rows {
                if let dbuffId = row["dbuff_id"] as? Int,
                   let aggregateMode = row["aggregateMode"] as? String
                {
                    aggregateModes[dbuffId] = aggregateMode
                    if AppConfiguration.Fitting.showDebug {
                        Logger.info("获取到 dbuff_id \(dbuffId) 的聚合模式: \(aggregateMode)")
                    }
                }
            }
        } else {
            if AppConfiguration.Fitting.showDebug {
                Logger.warning("查询 dbuffCollection 表的 aggregateMode 失败")
            }
        }

        return aggregateModes
    }
}
