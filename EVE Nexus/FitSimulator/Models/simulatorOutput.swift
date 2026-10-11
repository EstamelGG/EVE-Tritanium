import Foundation

// MARK: - 模拟输出数据模型

/// 用于存储属性模拟的计算结果，包含飞船、装备、无人机、植入体、环境效果和技能等的计算后属性
struct SimulationOutput {
    // 元数据 (与输入保持一致)
    var fittingId: FittingRef // 装配引用（本地 UUID / 线上 ESI Int）
    var name: String // 配置名称
    var description: String // 配置描述

    // 模拟核心数据 (使用计算后的属性)
    var ship: SimShipOutput // 当前模拟的飞船
    var modules: [SimModuleOutput] // 所有已安装装备（含激活状态、弹药）
    var drones: [SimDroneOutput] // 所有携带的无人机
    var cargo: SimCargoOutput // 货舱（容量与物品明细）
    var implants: [SimImplantOutput] // 所有已装备的植入体
    var environmentEffects: [SimEnvironmentEffectOutput] // 当前生效的环境效果
    var characterSkills: [Int: Int] // 角色技能（技能ID: 等级）
    var fighters: [FighterSquadOutput]? // 舰载机中队（如有）

    /// 技能计算结果
    var characterSkillCalculatedAttributes: [Int: [Int: Double]] = [:] // 技能ID: [属性ID: 计算后的值]

    var attributeTraces: [UUID: [Int: AttributeTrace]] = [:]

    /// 原始输入数据的引用
    var originalInput: SimulationInput

    /// 从SimulationInput创建SimulationOutput
    /// - Parameter input: 模拟输入数据
    init(from input: SimulationInput) {
        fittingId = input.fittingId
        name = input.name
        description = input.description
        originalInput = input

        // 初始化计算后的飞船数据
        ship = SimShipOutput(from: input.ship)

        // 初始化计算后的模块数据
        modules = input.modules.map { SimModuleOutput(from: $0) }

        // 初始化计算后的无人机数据
        drones = input.drones.map { SimDroneOutput(from: $0) }

        // 初始化计算后的货舱数据
        cargo = SimCargoOutput(from: input.cargo)

        // 初始化计算后的植入体数据
        implants = input.implants.map { SimImplantOutput(from: $0) }

        // 初始化计算后的环境效果数据
        environmentEffects = input.environmentEffects.map {
            SimEnvironmentEffectOutput(from: $0)
        }

        // 复制技能数据
        characterSkills = input.characterSkills

        // 初始化计算后的舰载机数据
        if let fighters = input.fighters {
            self.fighters = fighters.map { FighterSquadOutput(from: $0) }
        } else {
            fighters = nil
        }

        // 复制技能计算属性
        characterSkillCalculatedAttributes = input.characterSkillCalculatedAttributes
    }
}

// MARK: - 输出数据模型

/// 飞船输出数据（基础属性、效果、分组，计算后的属性）
struct SimShipOutput {
    let typeId: Int // 飞船类型ID
    var attributes: [Int: Double] // 计算后的属性值
    var attributesByName: [String: Double] // 计算后的属性值（名称索引）
    let effects: [Int] // 飞船自带效果ID列表
    let groupID: Int // 飞船分组ID
    let name: String // 飞船名称
    let iconFileName: String? // 飞船图标文件名
    let requiredSkills: [Int] // 所需技能ID列表

    // 添加角色属性字段
    var characterAttributes: [Int: Double] = [:] // 角色计算后的属性值
    var characterAttributesByName: [String: Double] = [:] // 角色计算后的属性值（名称索引）

    /// 从SimShip创建SimShipOutput
    init(from ship: SimShip) {
        typeId = ship.typeId
        attributes = ship.baseAttributes
        attributesByName = ship.baseAttributesByName
        effects = ship.effects
        groupID = ship.groupID
        name = ship.name
        iconFileName = ship.iconFileName
        requiredSkills = ship.requiredSkills
        // 角色属性初始化为空字典，将在计算后填充
        characterAttributes = [:]
        characterAttributesByName = [:]
    }
}

/// 装备/模块输出数据（含属性、效果、激活状态、弹药）
struct SimModuleOutput {
    let instanceId: UUID // 实例唯一标识符
    let typeId: Int // 装备类型ID
    var attributes: [Int: Double] // 计算后的属性值
    var attributesByName: [String: Double] // 计算后的属性值（名称索引）
    let effects: [Int] // 装备效果ID列表
    let groupID: Int // 装备分组ID
    let status: Int // 激活状态（如0未激活，1激活等）
    var charge: SimChargeOutput? // 当前装填的弹药（如有）
    let flag: FittingFlag? // 装备的槽位标识
    let quantity: Int // 装备数量
    let name: String // 装备名称
    let iconFileName: String? // 装备图标文件名
    let requiredSkills: [Int] // 所需技能ID列表

    // 突变后的显示信息（用于UI显示）
    let mutatedTypeId: Int? // 突变后的typeID
    let mutatedName: String? // 突变后的名称
    let mutatedIconFileName: String? // 突变后的图标文件名

    /// 从SimModule创建SimModuleOutput
    init(from module: SimModule) {
        instanceId = module.instanceId
        typeId = module.typeId
        attributes = module.attributes
        attributesByName = module.attributesByName
        effects = module.effects
        groupID = module.groupID
        status = module.status
        if let charge = module.charge {
            self.charge = SimChargeOutput(from: charge)
        } else {
            charge = nil
        }
        flag = module.flag
        quantity = module.quantity
        // 优先使用突变后的名称和图标
        name = module.mutatedName ?? module.name
        iconFileName = module.mutatedIconFileName ?? module.iconFileName
        requiredSkills = module.requiredSkills
        mutatedTypeId = module.mutatedTypeId
        mutatedName = module.mutatedName
        mutatedIconFileName = module.mutatedIconFileName
    }
}

/// 弹药输出数据（属性、效果、分组）
struct SimChargeOutput {
    let instanceId: UUID // 实例唯一标识符
    let typeId: Int // 弹药类型ID
    var attributes: [Int: Double] // 计算后的属性值
    var attributesByName: [String: Double] // 计算后的属性值（名称索引）
    let effects: [Int] // 弹药效果ID列表
    let groupID: Int // 弹药分组ID
    let chargeQuantity: Int? // 弹药数量（可选）
    let name: String // 弹药名称
    let iconFileName: String? // 弹药图标文件名
    let requiredSkills: [Int] // 所需技能ID列表

    /// 从SimCharge创建SimChargeOutput
    init(from charge: SimCharge) {
        instanceId = charge.instanceId
        typeId = charge.typeId
        attributes = charge.attributes
        attributesByName = charge.attributesByName
        effects = charge.effects
        groupID = charge.groupID
        chargeQuantity = charge.chargeQuantity
        name = charge.name
        iconFileName = charge.iconFileName
        requiredSkills = charge.requiredSkills
    }
}

/// 无人机输出数据（属性、效果、数量、激活数）
struct SimDroneOutput {
    let instanceId: UUID // 实例唯一标识符
    let typeId: Int // 无人机类型ID
    var attributes: [Int: Double] // 计算后的属性值
    var attributesByName: [String: Double] // 计算后的属性值（名称索引）
    let effects: [Int] // 无人机效果ID列表
    let quantity: Int // 携带数量
    let activeCount: Int // 激活数量
    let groupID: Int // 无人机分组ID
    let name: String // 无人机名称
    let iconFileName: String? // 无人机图标文件名
    let requiredSkills: [Int] // 所需技能ID列表

    // 突变后的显示信息（用于UI显示）
    let mutatedTypeId: Int? // 突变后的typeID
    let mutatedName: String? // 突变后的名称
    let mutatedIconFileName: String? // 突变后的图标文件名

    /// 从SimDrone创建SimDroneOutput
    init(from drone: SimDrone) {
        instanceId = drone.instanceId
        typeId = drone.typeId
        attributes = drone.attributes
        attributesByName = drone.attributesByName
        effects = drone.effects
        quantity = drone.quantity
        activeCount = drone.activeCount
        groupID = drone.groupID
        // 优先使用突变后的名称和图标
        name = drone.mutatedName ?? drone.name
        iconFileName = drone.mutatedIconFileName ?? drone.iconFileName
        requiredSkills = drone.requiredSkills
        mutatedTypeId = drone.mutatedTypeId
        mutatedName = drone.mutatedName
        mutatedIconFileName = drone.mutatedIconFileName
    }
}

/// 货舱输出数据（物品明细）
struct SimCargoOutput {
    let items: [SimCargoItemOutput] // 货舱内所有物品及数量

    /// 从SimCargo创建SimCargoOutput
    init(from cargo: SimCargo) {
        items = cargo.items.map { SimCargoItemOutput(from: $0) }
    }
}

/// 货舱内单个物品输出数据
struct SimCargoItemOutput {
    let typeId: Int // 物品类型ID
    let quantity: Int // 物品数量
    let volume: Double // 物品体积
    let name: String // 物品名称
    let iconFileName: String? // 物品图标文件名

    /// 从SimCargoItem创建SimCargoItemOutput
    init(from item: SimCargoItem) {
        typeId = item.typeId
        quantity = item.quantity
        volume = item.volume
        name = item.name
        iconFileName = item.iconFileName
    }
}

/// 植入体输出数据（属性、效果）
struct SimImplantOutput {
    let instanceId: UUID // 实例唯一标识符
    let typeId: Int // 植入体类型ID
    var attributes: [Int: Double] // 计算后的属性值
    var attributesByName: [String: Double] // 计算后的属性值（名称索引）
    let effects: [Int] // 植入体效果ID列表
    let name: String // 植入体名称
    let iconFileName: String? // 植入体图标文件名
    let requiredSkills: [Int] // 所需技能ID列表
    let groupID: Int // 植入体分组ID

    /// 从SimImplant创建SimImplantOutput
    init(from implant: SimImplant) {
        instanceId = implant.instanceId
        typeId = implant.typeId
        attributes = implant.attributes
        attributesByName = implant.attributesByName
        effects = implant.effects
        name = implant.name
        iconFileName = implant.iconFileName
        requiredSkills = implant.requiredSkills
        groupID = implant.groupID
    }
}

/// 环境效果输出数据（如空间站、星系、信号场等带来的加成）
struct SimEnvironmentEffectOutput {
    let typeId: Int // 环境效果类型ID
    let name: String // 环境效果名称
    var attributes: [Int: Double] // 计算后的属性值
    var attributesByName: [String: Double] // 计算后的属性值（名称索引）
    let effects: [Int] // 效果ID列表
    let iconFileName: String? // 环境效果图标文件名

    /// 从SimEnvironmentEffect创建SimEnvironmentEffectOutput
    init(from effect: SimEnvironmentEffect) {
        typeId = effect.typeId
        name = effect.name
        attributes = effect.attributes
        attributesByName = effect.attributesByName
        effects = effect.effects
        iconFileName = effect.iconFileName
    }
}

/// 舰载机中队输出数据
struct FighterSquadOutput {
    var typeId: Int // 舰载机类型ID
    var quantity: Int // 数量
    var tubeId: Int // 舰载机发射管ID
    var attributes: [Int: Double] // 计算后的属性值
    var attributesByName: [String: Double] // 计算后的属性值（名称索引）
    var effects: [Int] // 舰载机效果ID列表
    var groupID: Int // 舰载机分组ID
    var instanceId: UUID // 实例唯一标识符
    var name: String // 舰载机名称
    var iconFileName: String? // 舰载机图标文件名
    var requiredSkills: [Int] // 所需技能ID列表

    /// 从SimFighterSquad创建FighterSquadOutput
    init(from fighter: SimFighterSquad) {
        typeId = fighter.typeId
        quantity = fighter.quantity
        tubeId = fighter.tubeId
        attributes = fighter.attributes
        attributesByName = fighter.attributesByName
        effects = fighter.effects
        groupID = fighter.groupID
        instanceId = fighter.instanceId
        name = fighter.name
        iconFileName = fighter.iconFileName
        requiredSkills = fighter.requiredSkills
    }
}
