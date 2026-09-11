import Foundation

// MARK: - 模拟输入数据模型

/// 用于属性模拟的完整输入数据，包含飞船、装备、无人机、货舱、植入体、环境效果和技能等
struct SimulationInput {
    // 元数据
    var fittingId: FittingRef // 装配引用（本地 UUID / 线上 ESI Int）
    var name: String // 配置名称
    var description: String // 配置描述

    // 模拟核心数据
    var ship: SimShip // 当前模拟的飞船
    var character: SimCharacter // 角色属性
    var modules: [SimModule] // 所有已安装装备（含激活状态、弹药）
    var drones: [SimDrone] // 所有携带的无人机
    var cargo: SimCargo // 货舱（容量与物品明细）
    var implants: [SimImplant] // 所有已装备的植入体
    var environmentEffects: [SimEnvironmentEffect] // 当前生效的环境效果（如空间站、星系等）
    var characterSkills: [Int: Int] // 角色技能（技能ID: 等级）
    var skills: [SimSkill] = [] // 技能对象（包含属性和修饰器）
    var fighters: [SimFighterSquad]? // 舰载机中队（如有）

    // 属性计算扩展字段（由Pass1初始化）
    var characterSkillAttributes: [Int: [Int: Double]] = [:] // 技能ID: [属性ID: 值]
    var characterSkillAttributesByName: [Int: [String: Double]] = [:] // 技能ID: [属性名: 值]

    // 效果详情（由Pass2初始化）
    var effectDetails: [Int: EffectDetail] = [:] // 效果ID: 效果详情
    var effectsByTypeId: [Int: [Int]] = [:] // 物品类型ID: [效果ID]

    /// 属性修饰器（由Pass2初始化）
    var attributeModifiers: [Int: [Int: [SimAttributeModifier]]] = [:]

    /// 计算结果（由Pass3初始化）
    var calculatedAttributes: [ItemType: [Int: [Int: Double]]] = [:] // 物品类型: [物品索引: [属性ID: 计算后的值]]

    /// 技能计算结果（由Pass3初始化）
    var characterSkillCalculatedAttributes: [Int: [Int: Double]] = [:] // 技能ID: [属性ID: 计算后的值]

    init(
        // 元数据
        fittingId: FittingRef = .local(UUID()),
        name: String = "",
        description: String = "",
        fighters: [SimFighterSquad]? = nil,

        // 核心数据
        ship: SimShip,
        modules: [SimModule],
        drones: [SimDrone],
        cargo: SimCargo,
        implants: [SimImplant],
        environmentEffects: [SimEnvironmentEffect],
        characterSkills: [Int: Int],
        skills: [SimSkill] = [],

        // 可选的扩展字段
        characterSkillAttributes: [Int: [Int: Double]] = [:],
        characterSkillAttributesByName: [Int: [String: Double]] = [:],
        effectDetails: [Int: EffectDetail] = [:],
        effectsByTypeId: [Int: [Int]] = [:],
        attributeModifiers: [Int: [Int: [SimAttributeModifier]]] = [:],
        calculatedAttributes: [ItemType: [Int: [Int: Double]]] = [:],
        characterSkillCalculatedAttributes: [Int: [Int: Double]] = [:]
    ) {
        self.fittingId = fittingId
        self.name = name
        self.description = description
        self.fighters = fighters
        self.ship = ship
        // 初始化角色对象，类型ID 1373 是EVE中的角色类型
        character = SimCharacter(typeId: 1373)
        self.modules = modules
        self.drones = drones
        self.cargo = cargo
        self.implants = implants
        self.environmentEffects = environmentEffects
        self.characterSkills = characterSkills
        self.skills = skills
        self.characterSkillAttributes = characterSkillAttributes
        self.characterSkillAttributesByName = characterSkillAttributesByName
        self.effectDetails = effectDetails
        self.effectsByTypeId = effectsByTypeId
        self.attributeModifiers = attributeModifiers
        self.calculatedAttributes = calculatedAttributes
        self.characterSkillCalculatedAttributes = characterSkillCalculatedAttributes
    }
}

// MARK: - 物品类型枚举

/// 物品类型枚举（用于区分不同类型的物品，如飞船、模块、弹药等）
enum ItemType {
    case ship
    case character
    case module
    case charge
    case drone
    case fighter
    case implant
    case skill
    case environment
}

// MARK: - 舰船、装备、无人机、弹药、货舱、植入体、环境效果

/// 角色数据（基础属性、效果）
struct SimCharacter {
    let instanceId: UUID = .init() // 实例唯一标识符
    var typeId: Int = 1373 // 角色类型ID
    var baseAttributes: [Int: Double] = [:] // 属性ID:值，适合高效计算
    var baseAttributesByName: [String: Double] = [:] // 属性名:值，便于可读性和调试

    /// 修饰器（由Step3初始化）
    var attributeModifiers: [Int: [SimAttributeModifier]] = [:] // 属性ID: [修饰器]

    /// 如果需要，可以添加默认值，比如默认设置maxActiveDrones
    init(typeId: Int) {
        self.typeId = typeId
        // 设置maxActiveDrones属性的默认值
        baseAttributes[352] = 0
        baseAttributesByName["maxActiveDrones"] = 0
    }
}

/// 飞船数据（基础属性、效果、分组）
struct SimShip {
    let instanceId: UUID = .init() // 实例唯一标识符
    let typeId: Int // 飞船类型ID
    let baseAttributes: [Int: Double] // 属性ID:值，适合高效计算
    let baseAttributesByName: [String: Double] // 属性名:值，便于可读性和调试
    let effects: [Int] // 飞船自带效果ID列表
    let groupID: Int // 飞船分组ID
    let name: String // 飞船名称
    let iconFileName: String? // 飞船图标文件名
    let requiredSkills: [Int] // 所需技能ID列表

    /// 修饰器（由Step3初始化）
    var attributeModifiers: [Int: [SimAttributeModifier]] = [:] // 属性ID: [修饰器]
}

/// 技能数据（属性、效果、等级）
struct SimSkill {
    let instanceId: UUID = .init() // 实例唯一标识符
    let typeId: Int // 技能类型ID
    let level: Int // 技能等级
    let attributes: [Int: Double] // 属性ID:值
    let attributesByName: [String: Double] // 属性名:值
    let effects: [Int] // 技能效果ID列表
    let groupID: Int // 技能分组ID
    let requiredSkills: [Int] // 所需技能ID列表

    /// 修饰器（由Step3初始化）
    var attributeModifiers: [Int: [SimAttributeModifier]] = [:] // 属性ID: [修饰器]
}

/// 装备/模块数据（含属性、效果、激活状态、弹药）
struct SimModule {
    let instanceId: UUID // 实例唯一标识符
    let typeId: Int // 装备类型ID
    let attributes: [Int: Double] // 属性ID:值
    let attributesByName: [String: Double] // 属性名:值
    let effects: [Int] // 装备效果ID列表
    let groupID: Int // 装备分组ID
    let status: Int // 激活状态（如0未激活，1激活等）
    let charge: SimCharge? // 当前装填的弹药（如有）
    // 原始配置字段
    let flag: FittingFlag? // 装备的槽位标识
    let quantity: Int // 装备数量
    var requiredSkills: [Int] // 所需技能ID列表

    // UI显示字段
    let name: String // 装备名称
    let iconFileName: String? // 装备图标文件名

    /// 修饰器（由Step3初始化）
    var attributeModifiers: [Int: [SimAttributeModifier]] = [:] // 属性ID: [修饰器]

    // 突变相关字段
    var selectedMutaplasmidID: Int? // 选中的突变质体ID
    var mutatedAttributes: [Int: Double] = [:] // 突变后的属性值 (attributeID: 倍数)
    var mutatedTypeId: Int? // 突变后的typeID（用于UI显示）
    var mutatedName: String? // 突变后的名称（用于UI显示）
    var mutatedIconFileName: String? // 突变后的图标文件名（用于UI显示）

    /// 完全预热（Spool up）。为 `false` 时 DPS 按 `damageMultiplierBonusMax = 1` 参与 `(1 + bonus)` 修正。
    var isSpoolUpFull: Bool = true

    /// 自定义初始化器，允许指定instanceId
    init(
        instanceId: UUID = UUID(),
        typeId: Int,
        attributes: [Int: Double],
        attributesByName: [String: Double],
        effects: [Int],
        groupID: Int,
        status: Int,
        charge: SimCharge? = nil,
        flag: FittingFlag? = nil,
        quantity: Int,
        name: String,
        iconFileName: String? = nil,
        requiredSkills: [Int],
        attributeModifiers: [Int: [SimAttributeModifier]] = [:],
        selectedMutaplasmidID: Int? = nil,
        mutatedAttributes: [Int: Double] = [:],
        mutatedTypeId: Int? = nil,
        mutatedName: String? = nil,
        mutatedIconFileName: String? = nil,
        isSpoolUpFull: Bool = true
    ) {
        self.instanceId = instanceId
        self.typeId = typeId
        self.attributes = attributes
        self.attributesByName = attributesByName
        self.effects = effects
        self.groupID = groupID
        self.status = status
        self.charge = charge
        self.flag = flag
        self.quantity = quantity
        self.name = name
        self.iconFileName = iconFileName
        self.requiredSkills = requiredSkills
        self.attributeModifiers = attributeModifiers
        self.selectedMutaplasmidID = selectedMutaplasmidID
        self.mutatedAttributes = mutatedAttributes
        self.mutatedTypeId = mutatedTypeId
        self.mutatedName = mutatedName
        self.mutatedIconFileName = mutatedIconFileName
        self.isSpoolUpFull = isSpoolUpFull
    }

    /// 返回仅替换激活状态的副本（保留其余全部字段）
    func withStatus(_ newStatus: Int) -> SimModule {
        SimModule(
            instanceId: instanceId,
            typeId: typeId,
            attributes: attributes,
            attributesByName: attributesByName,
            effects: effects,
            groupID: groupID,
            status: newStatus,
            charge: charge,
            flag: flag,
            quantity: quantity,
            name: name,
            iconFileName: iconFileName,
            requiredSkills: requiredSkills,
            attributeModifiers: attributeModifiers,
            selectedMutaplasmidID: selectedMutaplasmidID,
            mutatedAttributes: mutatedAttributes,
            mutatedTypeId: mutatedTypeId,
            mutatedName: mutatedName,
            mutatedIconFileName: mutatedIconFileName,
            isSpoolUpFull: isSpoolUpFull
        )
    }
}

/// 弹药数据（属性、效果、分组）
struct SimCharge {
    let instanceId: UUID = .init() // 实例唯一标识符
    let typeId: Int // 弹药类型ID
    let attributes: [Int: Double] // 属性ID:值
    let attributesByName: [String: Double] // 属性名:值
    let effects: [Int] // 弹药效果ID列表
    let groupID: Int // 弹药分组ID
    let chargeQuantity: Int? // 弹药数量（可选）
    let requiredSkills: [Int] // 所需技能ID列表

    // UI显示字段
    let name: String // 弹药名称
    let iconFileName: String? // 弹药图标文件名

    /// 修饰器（由Step3初始化）
    var attributeModifiers: [Int: [SimAttributeModifier]] = [:] // 属性ID: [修饰器]
}

/// 无人机数据（属性、效果、数量、激活数）
struct SimDrone {
    let instanceId: UUID = .init() // 实例唯一标识符
    let typeId: Int // 无人机类型ID
    let attributes: [Int: Double] // 属性ID:值
    let attributesByName: [String: Double] // 属性名:值
    let effects: [Int] // 无人机效果ID列表
    let quantity: Int // 携带数量
    let activeCount: Int // 激活数量
    let groupID: Int // 无人机分组ID
    let requiredSkills: [Int] // 所需技能ID列表

    // UI显示字段
    let name: String // 无人机名称
    let iconFileName: String? // 无人机图标文件名

    /// 修饰器（由Step3初始化）
    var attributeModifiers: [Int: [SimAttributeModifier]] = [:] // 属性ID: [修饰器]

    // 突变相关字段
    var selectedMutaplasmidID: Int? // 选中的突变质体ID
    var mutatedAttributes: [Int: Double] = [:] // 突变后的属性值 (attributeID: 倍数)
    var mutatedTypeId: Int? // 突变后的typeID（用于UI显示）
    var mutatedName: String? // 突变后的名称（用于UI显示）
    var mutatedIconFileName: String? // 突变后的图标文件名（用于UI显示）
}

/// 货舱内单个物品及数量
struct SimCargoItem {
    let typeId: Int // 物品类型ID
    let quantity: Int // 物品数量
    let volume: Double // 物品体积

    // UI显示字段
    let name: String // 物品名称
    let iconFileName: String? // 物品图标文件名
}

/// 货舱数据（物品明细）
struct SimCargo {
    let items: [SimCargoItem] // 货舱内所有物品及数量
}

/// 植入体数据（属性、效果）
struct SimImplant {
    let instanceId: UUID = .init() // 实例唯一标识符
    let typeId: Int // 植入体类型ID
    let attributes: [Int: Double] // 属性ID:值
    let attributesByName: [String: Double] // 属性名:值
    let effects: [Int] // 植入体效果ID列表
    let requiredSkills: [Int] // 所需技能ID列表
    let groupID: Int // 植入体分组ID

    // UI显示字段
    let name: String // 植入体名称
    let iconFileName: String? // 植入体图标文件名

    /// 修饰器（由Step3初始化）
    var attributeModifiers: [Int: [SimAttributeModifier]] = [:] // 属性ID: [修饰器]

    /// 已启用的增效剂副作用惩罚属性 ID（默认空 = 全部副作用关闭）
    var enabledSideEffectAttributeIDs: Set<Int> = []
}

/// 环境效果（如空间站、星系、信号场等带来的加成）
struct SimEnvironmentEffect {
    let instanceId: UUID = .init() // 实例唯一标识符
    let typeId: Int // 环境效果类型ID
    let name: String // 环境效果名称
    let attributes: [Int: Double] // 属性ID:值
    let attributesByName: [String: Double] // 属性名:值
    let effects: [Int] // 效果ID列表

    /// UI显示字段
    let iconFileName: String? // 环境效果图标文件名
}

// MARK: - 属性修饰器与结果

/// 属性修饰器，记录每一步属性变化的来源和方式
struct SimAttributeModifier {
    let sourceTypeID: Int? // 来源类型ID（如装备、技能、环境等）
    let sourceName: String // 来源名称
    let operation: String // 操作类型（加法、乘法等）
    let value: Double // 修饰值
    let stackingPenalty: Bool // 是否有叠加惩罚
    let sourceAttributeId: Int // 来源属性ID
    let sourceItemType: ItemType? // 来源物品类型（飞船、模块、弹药等）
    let sourceItemIndex: Int? // 来源物品索引
    let sourceFlag: FittingFlag? // 来源模块的槽位标识
    let effectId: Int? // 来源效果ID
    let effectCategory: Int? // 效果类别（用于确定需要的状态级别）

    let sourceInstanceId: UUID? // 来源物品实例ID
    let targetInstanceId: UUID? // 目标物品实例ID
}

// MARK: - 效果详情模型

/// 效果详情模型 - 用于存储批量查询的效果信息
struct EffectDetail {
    let effectId: Int
    let effectName: String
    let effectCategory: Int?
    let description: String?

    let typeId: Int
    let typeName: String
    let groupId: Int

    let isDefault: Bool
    let isOffensive: Bool
    let isAssistance: Bool
    let modifierInfo: String?
}

/// 舰载机中队数据（属性、效果、数量、发射管ID）
struct SimFighterSquad {
    let instanceId: UUID = .init() // 实例唯一标识符
    let typeId: Int // 舰载机类型ID
    let attributes: [Int: Double] // 属性ID:值
    let attributesByName: [String: Double] // 属性名:值
    let effects: [Int] // 舰载机效果ID列表
    let quantity: Int // 舰载机数量
    let tubeId: Int // 舰载机发射管ID
    let groupID: Int // 舰载机分组ID
    let requiredSkills: [Int] // 所需技能ID列表

    // UI显示字段
    let name: String // 舰载机名称
    let iconFileName: String? // 舰载机图标文件名

    /// 修饰器（由Step3初始化）
    var attributeModifiers: [Int: [SimAttributeModifier]] = [:] // 属性ID: [修饰器]
}
