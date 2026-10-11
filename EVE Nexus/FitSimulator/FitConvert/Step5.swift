import Foundation

/// Step5 - 推进模块速度修正阶段
/// 处理激活状态的推进模块对maxVelocity的额外修正
class Step5 {
    private let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    /// 处理推进模块的速度修正（突变已在 Step4 缓存前应用）
    /// - Parameter output: 经过Step4计算的输出数据
    /// - Returns: 修正后的输出数据
    func process(output: SimulationOutput) -> SimulationOutput {
        var modifiedOutput = output

        // 查找第一个激活状态的推进模块
        let activePropulsionModule = findFirstActivePropulsionModule(modules: modifiedOutput.modules)

        if let propulsionModule = activePropulsionModule {
            Logger.info("找到激活的推进模块: \(propulsionModule.name) (TypeID: \(propulsionModule.typeId))")

            // 修正飞船的maxVelocity
            modifiedOutput.ship = applyVelocityCorrection(
                ship: modifiedOutput.ship,
                propulsionModule: propulsionModule
            )

            let id = output.originalInput.ship.instanceId
            let before = output.ship.attributes[37] ?? 0
            let after = modifiedOutput.ship.attributes[37] ?? before
            if before != after {
                let source = output.originalInput.modules.first { $0.instanceId == propulsionModule.instanceId }
                let modifier = SimAttributeModifier(sourceTypeID: propulsionModule.typeId,
                                                    sourceName: propulsionModule.name, operation: "Propulsion", value: 0,
                                                    stackingPenalty: false, sourceAttributeId: 20, sourceItemType: .module,
                                                    sourceItemIndex: nil, sourceFlag: source?.flag, effectId: nil, effectCategory: nil,
                                                    sourceInstanceId: propulsionModule.instanceId, targetInstanceId: id)
                var trace = modifiedOutput.attributeTraces[id]?[37]
                    ?? AttributeTrace(baseValue: before, steps: [], finalValue: before)
                trace.steps.append(AttributeTraceStep(modifier: modifier, operation: "Propulsion",
                                                      operand: before == 0 ? 1 : after / before, penalty: 1, before: before, after: after,
                                                      dependencies: [
                                                          AttributeTraceDependency(instanceID: propulsionModule.instanceId, attributeID: 20,
                                                                                   value: propulsionModule.attributesByName["speedFactor"] ?? 0),
                                                          AttributeTraceDependency(instanceID: propulsionModule.instanceId, attributeID: 567,
                                                                                   value: propulsionModule.attributesByName["speedBoostFactor"] ?? 0),
                                                          AttributeTraceDependency(instanceID: id, attributeID: 4,
                                                                                   value: output.ship.attributesByName["mass"] ?? 0),
                                                      ]))
                trace.finalValue = after
                modifiedOutput.attributeTraces[id, default: [:]][37] = trace
            }

            Logger.info("已应用推进模块速度修正")
        } else {
            Logger.info("未找到激活的推进模块，跳过速度修正")
        }

        return modifiedOutput
    }

    /// 查找第一个激活状态的推进模块
    /// - Parameter modules: 模块列表
    /// - Returns: 第一个激活的推进模块，如果没有则返回nil
    private func findFirstActivePropulsionModule(modules: [SimModuleOutput]) -> SimModuleOutput? {
        let propulsionEffectIds = [6730, 6731] // moduleBonusAfterburner, moduleBonusMicrowarpdrive

        for module in modules {
            // 检查模块是否处于激活状态 (status > 1， 0 下线，1 在线，2 激活，3 超载)
            if module.status > 1 {
                // 检查模块是否包含推进效果
                let hasActivePropulsionEffect = module.effects.contains { effectId in
                    propulsionEffectIds.contains(effectId)
                }

                if hasActivePropulsionEffect {
                    return module
                }
            }
        }

        return nil
    }

    /// 应用速度修正到飞船
    /// - Parameters:
    ///   - ship: 飞船数据
    ///   - propulsionModule: 推进模块数据
    /// - Returns: 修正后的飞船数据
    private func applyVelocityCorrection(ship: SimShipOutput, propulsionModule: SimModuleOutput)
        -> SimShipOutput
    {
        var correctedShip = ship

        // 获取当前属性值
        let currentMass = ship.attributesByName["mass"] ?? 0
        let currentMaxVelocity = ship.attributesByName["maxVelocity"] ?? 0

        // 获取推进模块的属性
        let speedFactor = propulsionModule.attributesByName["speedFactor"] ?? 0
        let speedBoostFactor = propulsionModule.attributesByName["speedBoostFactor"] ?? 0

        Logger.info("速度修正前 - 质量: \(currentMass), 最大速度: \(currentMaxVelocity)")
        Logger.info(
            "推进模块属性 - speedFactor: \(speedFactor), speedBoostFactor: \(speedBoostFactor)"
        )

        // 根据propulsionModules.yaml的逻辑计算velocityBoost:
        // velocityBoost += speedBoostFactor (modAdd)
        // velocityBoost *= speedFactor (postMul)
        // velocityBoost /= mass (postDiv)
        // maxVelocity *= (1 + velocityBoost/100) (postPercent)

        // 步骤1: 计算velocityBoost
        var velocityBoost = 0.0
        velocityBoost += speedBoostFactor // modAdd操作
        velocityBoost *= speedFactor // postMul操作

        // 步骤2: 用质量修正velocityBoost
        let correctedVelocityBoost = currentMass > 0 ? velocityBoost / currentMass : 0

        // 步骤3: 计算修正后的maxVelocity
        let velocityMultiplier = 1.0 + (correctedVelocityBoost / 100.0)
        let correctedMaxVelocity = currentMaxVelocity * velocityMultiplier

        // 更新属性值
        correctedShip.attributesByName["maxVelocity"] = correctedMaxVelocity
        if let maxVelocityId = getAttributeId(name: "maxVelocity") {
            correctedShip.attributes[maxVelocityId] = correctedMaxVelocity
        }

        Logger.info(
            "速度修正计算 - velocityBoost: \(velocityBoost), 修正后velocityBoost: \(correctedVelocityBoost)"
        )
        Logger.info("速度修正后 - 速度倍数: \(velocityMultiplier), 最大速度: \(correctedMaxVelocity)")

        return correctedShip
    }

    /// 获取属性ID
    /// - Parameter name: 属性名称
    /// - Returns: 属性ID，如果不存在则返回nil
    private func getAttributeId(name: String) -> Int? {
        // 这里应该从数据库查询属性ID，为了简化先硬编码常用的
        switch name {
        case "maxVelocity":
            return 37
        case "mass":
            return 4
        case "velocityBoost":
            return 5801
        default:
            return nil
        }
    }
}
