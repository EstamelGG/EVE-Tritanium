import Foundation

/// Step2实现 - 效果修饰器解析
class Step2 {
    private let databaseManager: DatabaseManager
    /// 以 JSON 内容为键：SDE 内容变化会自然失效，不缓存来源实例和动态值。
    private var parsedModifierCache: [String: [ModifierInfo]] = [:]

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    /// 执行Step2处理 - 解析效果修饰器
    /// - Parameters:
    ///   - itemEffects: 物品效果字典 [物品ID: [效果详情]]
    /// - Returns: 解析后的修饰器信息
    func process(
        itemEffects: [Int: [EffectDetail]]
    ) -> AttributeModifiers {
        Logger.info("执行Step2 - 效果修饰器解析阶段")

        // 创建修饰器容器
        var modifiers = AttributeModifiers()

        // 首先解析所有效果的修饰器信息
        for (typeId, effects) in itemEffects {
            for effect in effects {
                // 解析修饰器信息
                let parsedModifiers = parseModifierInfo(
                    effect: effect,
                    typeId: typeId
                )

                // 将解析的修饰器添加到结果中
                for modifier in parsedModifiers {
                    modifiers.addModifier(modifier)
                }
            }
        }

        Logger.info("Step2完成 - 解析了\(modifiers.count)个修饰器")

        return modifiers
    }

    /// 解析单个效果的修饰器信息
    /// - Parameters:
    ///   - effect: 效果详情
    ///   - typeId: 物品类型ID
    /// - Returns: 解析后的修饰器数组
    private func parseModifierInfo(
        effect: EffectDetail,
        typeId: Int
    ) -> [AttributeModifier] {
        var modifiers: [AttributeModifier] = []

        // 如果没有修饰器信息，则返回空数组
        guard let modifierInfo = effect.modifierInfo else {
            return []
        }

        let parsedModifiers: [ModifierInfo]
        if let cached = parsedModifierCache[modifierInfo] {
            parsedModifiers = cached
        } else {
            guard let data = modifierInfo.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([ModifierInfo].self, from: data)
            else {
                Logger.warning("无法解析修饰器信息: \(effect.effectId) - \(effect.effectName)")
                return []
            }
            parsedModifierCache[modifierInfo] = decoded
            parsedModifiers = decoded
        }

        // 解析每个修饰器
        for modifier in parsedModifiers {
            // 检查必要的字段
            guard let operation = modifier.operation,
                  let modifiedAttributeID = modifier.modifiedAttributeID,
                  let modifyingAttributeID = modifier.modifyingAttributeID,
                  let domain = modifier.domain
            else {
                continue
            }

            // 解析操作类型
            guard let operationType = OperationType(rawValue: operation) else {
                // 跳过未知的操作类型
                continue
            }

            // 如果操作类型为9，则跳过（按要求忽略）
            if operationType == .skillPointsToLevel {
                continue
            }

            // 解析效果类别
            let effectCategory = EffectCategory(rawValue: effect.effectCategory ?? 0) ?? .passive

            // 解析修饰器类型
            guard
                let modifierType = parseModifierType(
                    func: modifier.func,
                    skillTypeID: modifier.skillTypeID,
                    groupID: modifier.groupID
                )
            else {
                continue
            }

            // 解析域（决定目标对象）
            guard let modifierDomain = ModifierDomain(rawValue: domain) else {
                continue
            }

            // 创建修饰器
            let attributeModifier = AttributeModifier(
                effectId: effect.effectId,
                effectName: effect.effectName,
                sourceTypeId: typeId,
                sourceTypeName: effect.typeName,
                sourceGroupId: effect.groupId,
                modifierType: modifierType,
                domain: modifierDomain,
                effectCategory: effectCategory,
                operation: operationType,
                modifiedAttributeId: modifiedAttributeID,
                modifyingAttributeId: modifyingAttributeID
            )

            modifiers.append(attributeModifier)
        }

        return modifiers
    }

    /// 解析修饰器类型
    /// - Parameters:
    ///   - func: 修饰器函数类型
    ///   - skillTypeID: 技能类型ID（如果有）
    ///   - groupID: 组ID（如果有）
    /// - Returns: 修饰器类型（如果可以解析）
    private func parseModifierType(
        func: String?,
        skillTypeID: Int?,
        groupID: Int?
    ) -> ModifierType? {
        guard let funcStr = `func` else {
            return nil
        }

        switch funcStr {
        case "ItemModifier":
            return .itemModifier

        case "LocationModifier":
            return .locationModifier

        case "LocationGroupModifier":
            if let groupID = groupID {
                return .locationGroupModifier(groupID: groupID)
            }
            return nil

        case "LocationRequiredSkillModifier":
            if let skillTypeID = skillTypeID {
                return .locationRequiredSkillModifier(skillTypeID: skillTypeID)
            }
            return nil

        case "OwnerRequiredSkillModifier":
            if let skillTypeID = skillTypeID {
                return .ownerRequiredSkillModifier(skillTypeID: skillTypeID)
            }
            return nil

        case "EffectStopper":
            // 暂不实现EffectStopper
            return nil

        default:
            return nil
        }
    }
}

// MARK: - 修饰器信息模型

/// 从JSON解析的修饰器信息
struct ModifierInfo: Decodable {
    let domain: String?
    let `func`: String?
    let groupID: Int?
    let modifiedAttributeID: Int?
    let modifyingAttributeID: Int?
    let operation: Int?
    let skillTypeID: Int?
}

/// 修饰域（确定效果目标）
enum ModifierDomain: String {
    case shipID // 作用于所在的飞船
    case itemID // 作用于物品自身
    case charID // 作用于角色属性
    case otherID // 作用于关联物品
    case structureID // 作用于结构
    case targetID // 作用于目标
    case target // 作用于目标
}

/// 修饰器类型
enum ModifierType {
    case itemModifier // 修改单个指定物品的属性
    case locationModifier // 修改所有位置上物品的属性
    case locationGroupModifier(groupID: Int) // 修改特定组物品的属性
    case locationRequiredSkillModifier(skillTypeID: Int) // 修改需要特定技能的物品属性
    case ownerRequiredSkillModifier(skillTypeID: Int) // 修改需要特定技能的物品属性（作用对象不同）
}

/// 操作类型（修饰行为）
enum OperationType: Int {
    case preAssign = -1 // 直接赋值（优先级最高）
    case preMul = 0 // 前置乘法
    case preDiv = 1 // 前置除法
    case modAdd = 2 // 加法
    case modSub = 3 // 减法
    case postMul = 4 // 后置乘法
    case postDiv = 5 // 后置除法
    case postPercent = 6 // 后置百分比
    case postAssign = 7 // 后置赋值
    case skillPointsToLevel = 9 // 技能点到等级（忽略）

    /// 是否受叠加惩罚影响
    var isStackable: Bool {
        switch self {
        case .preMul, .preDiv, .postMul, .postDiv, .postPercent:
            return true
        case .preAssign, .modAdd, .modSub, .postAssign, .skillPointsToLevel:
            return false
        }
    }

    /// 将操作类型转换为字符串
    func toString() -> String {
        switch self {
        case .preAssign:
            return "PreAssign"
        case .preMul:
            return "PreMul"
        case .preDiv:
            return "PreDiv"
        case .modAdd:
            return "ModAdd"
        case .modSub:
            return "ModSub"
        case .postMul:
            return "PostMul"
        case .postDiv:
            return "PostDiv"
        case .postPercent:
            return "PostPercent"
        case .postAssign:
            return "PostAssign"
        case .skillPointsToLevel:
            return "SkillPointsToLevel"
        }
    }
}

/// 单个属性修饰器
struct AttributeModifier {
    let effectId: Int // 效果ID
    let effectName: String // 效果名称
    let sourceTypeId: Int // 源物品类型ID
    let sourceTypeName: String // 源物品类型名称
    let sourceGroupId: Int // 源物品组ID
    let modifierType: ModifierType // 修饰器类型
    let domain: ModifierDomain // 修饰域
    let effectCategory: EffectCategory // 效果类别
    let operation: OperationType // 操作类型
    let modifiedAttributeId: Int // 被修改的属性ID
    let modifyingAttributeId: Int // 修改源的属性ID
}

/// 属性修饰器容器
struct AttributeModifiers {
    /// 按照效果ID存储的修饰器
    private var modifiersByEffectId: [Int: [AttributeModifier]] = [:]

    /// 按照源物品类型ID存储的修饰器
    var modifiersBySourceTypeId: [Int: [AttributeModifier]] = [:]

    /// 添加修饰器
    mutating func addModifier(_ modifier: AttributeModifier) {
        // 按效果ID存储
        if modifiersByEffectId[modifier.effectId] == nil {
            modifiersByEffectId[modifier.effectId] = []
        }
        modifiersByEffectId[modifier.effectId]?.append(modifier)

        // 按源物品类型ID存储
        if modifiersBySourceTypeId[modifier.sourceTypeId] == nil {
            modifiersBySourceTypeId[modifier.sourceTypeId] = []
        }
        modifiersBySourceTypeId[modifier.sourceTypeId]?.append(modifier)
    }

    /// 获取所有按源物品类型组织的修饰器
    func allModifiersBySourceType() -> [Int: [AttributeModifier]] {
        return modifiersBySourceTypeId
    }

    /// 修饰器总数
    var count: Int {
        return modifiersByEffectId.values.reduce(0) { $0 + $1.count }
    }
}
