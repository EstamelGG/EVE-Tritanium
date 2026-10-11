import SwiftUI

struct ShipFirepowerStatsView: View {
    @ObservedObject var viewModel: FittingEditorViewModel
    @State private var includeSpecialAbilities = false

    init(viewModel: FittingEditorViewModel) {
        self.viewModel = viewModel
    }

    /// 火力专用格式化函数：只有大于100,000时才使用k单位
    private func formatFirepowerValue(_ value: Double) -> String {
        if value == 0 {
            return "0"
        } else if value >= 1_000_000_000 {
            let formattedValue = value / 1_000_000_000
            let numberString =
                formattedValue.truncatingRemainder(dividingBy: 1) == 0
                    ? String(format: "%.0f", formattedValue) : String(format: "%.1f", formattedValue)
            return numberString + "B"
        } else if value >= 10_000_000 {
            let formattedValue = value / 1_000_000
            let numberString =
                formattedValue.truncatingRemainder(dividingBy: 1) == 0
                    ? String(format: "%.0f", formattedValue) : String(format: "%.1f", formattedValue)
            return numberString + "M"
        } else if value >= 1_000_000 {
            let formattedValue = value / 1_000_000
            let numberString =
                formattedValue.truncatingRemainder(dividingBy: 1) == 0
                    ? String(format: "%.0f", formattedValue) : String(format: "%.2f", formattedValue)
            return numberString + "M"
        } else if value >= 100_000 {
            let formattedValue = value / 1000
            let numberString =
                formattedValue.truncatingRemainder(dividingBy: 1) == 0
                    ? String(format: "%.0f", formattedValue) : String(format: "%.1f", formattedValue)
            return numberString + "k"
        } else {
            return value.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", value) : String(format: "%.1f", value)
        }
    }

    /// 投弹伤害结构体
    private struct BombDamage {
        let em: Double
        let explosive: Double
        let kinetic: Double
        let thermal: Double
    }

    /// 一次性查询所有投弹伤害属性
    private func getAllBombDamages(bombTypeIds: [Int]) -> [Int: BombDamage] {
        var bombDamageMap: [Int: BombDamage] = [:]

        // 如果没有投弹类型，直接返回空字典
        guard !bombTypeIds.isEmpty else {
            return bombDamageMap
        }

        // 查询所有投弹伤害属性（内存索引）
        let damageAttrIDs: Set = [114, 116, 117, 118]
        var tempDamages: [Int: [Int: Double]] = [:]

        for typeId in bombTypeIds {
            let attributes = SDEMemoryStore.typeAttributes(for: typeId)
            let damages = attributes.filter { damageAttrIDs.contains($0.key) }
            if !damages.isEmpty {
                tempDamages[typeId] = damages
            }
        }

        // 转换为BombDamage对象
        for (typeId, damages) in tempDamages {
            let bombDamage = BombDamage(
                em: damages[114] ?? 0, // EM伤害
                explosive: damages[116] ?? 0, // 爆炸伤害
                kinetic: damages[117] ?? 0, // 动能伤害
                thermal: damages[118] ?? 0 // 热能伤害
            )
            bombDamageMap[typeId] = bombDamage
        }

        return bombDamageMap
    }

    /// 武器DPS计算结果结构体
    struct WeaponDPSResult {
        let emDamage: Double // 电磁伤害
        let explosiveDamage: Double // 爆炸伤害
        let kineticDamage: Double // 动能伤害
        let thermalDamage: Double // 热能伤害
        let totalDamage: Double // 总伤害
        let dpsWithoutReload: Double // 不考虑装弹的DPS
        let dpsWithReload: Double // 考虑装弹的DPS
        let volleyDamage: Double // 齐射伤害

        // DPS比例而不是伤害比例
        let emDPS: Double // EM伤害DPS
        let explosiveDPS: Double // 爆炸伤害DPS
        let kineticDPS: Double // 动能伤害DPS
        let thermalDPS: Double // 热能伤害DPS
    }

    /// 无人机DPS计算结果结构体
    struct DroneDPSResult {
        let emDamage: Double // 电磁伤害
        let explosiveDamage: Double // 爆炸伤害
        let kineticDamage: Double // 动能伤害
        let thermalDamage: Double // 热能伤害
        let totalDamage: Double // 总伤害
        let dps: Double // DPS
        let volleyDamage: Double // 齐射伤害

        // DPS比例
        let emDPS: Double // EM伤害DPS
        let explosiveDPS: Double // 爆炸伤害DPS
        let kineticDPS: Double // 动能伤害DPS
        let thermalDPS: Double // 热能伤害DPS
    }

    /// 舰载机攻击能力结构体
    private struct FighterAbility {
        let emDamage: Double
        let explosiveDamage: Double
        let kineticDamage: Double
        let thermalDamage: Double
        let damageMultiplier: Double
        let cycleDurationMs: Double

        var totalDamage: Double {
            return (emDamage + explosiveDamage + kineticDamage + thermalDamage) * damageMultiplier
        }

        var adjustedDamages: (em: Double, explosive: Double, kinetic: Double, thermal: Double) {
            return (
                em: emDamage * damageMultiplier,
                explosive: explosiveDamage * damageMultiplier,
                kinetic: kineticDamage * damageMultiplier,
                thermal: thermalDamage * damageMultiplier
            )
        }

        func calculateDPS(quantity: Int) -> (
            totalDPS: Double, emDPS: Double, explosiveDPS: Double, kineticDPS: Double,
            thermalDPS: Double
        ) {
            let cycleTime = cycleDurationMs / 1000.0
            guard cycleTime > 0 else {
                return (0, 0, 0, 0, 0)
            }

            let damages = adjustedDamages
            let singleDPS = totalDamage / cycleTime

            return (
                totalDPS: singleDPS * Double(quantity),
                emDPS: (damages.em / cycleTime) * Double(quantity),
                explosiveDPS: (damages.explosive / cycleTime) * Double(quantity),
                kineticDPS: (damages.kinetic / cycleTime) * Double(quantity),
                thermalDPS: (damages.thermal / cycleTime) * Double(quantity)
            )
        }
    }

    /// 从舰载机计算DPS
    private func getFighterDPS(fighter: FighterSquadOutput, bombDamageMap: [Int: BombDamage] = [:])
        -> FighterDPSResult
    {
        // 1. 构建基础攻击能力
        let baseAbility = FighterAbility(
            emDamage: fighter.attributesByName["fighterAbilityAttackMissileDamageEM"] ?? 0,
            explosiveDamage: fighter.attributesByName["fighterAbilityAttackMissileDamageExp"] ?? 0,
            kineticDamage: fighter.attributesByName["fighterAbilityAttackMissileDamageKin"] ?? 0,
            thermalDamage: fighter.attributesByName["fighterAbilityAttackMissileDamageTherm"] ?? 0,
            damageMultiplier: fighter.attributesByName[
                "fighterAbilityAttackMissileDamageMultiplier"
            ] ?? 1.0,
            cycleDurationMs: fighter.attributesByName["fighterAbilityAttackMissileDuration"] ?? 8000
        )

        // 2. 构建导弹特殊能力
        let missileAbility = FighterAbility(
            emDamage: fighter.attributesByName["fighterAbilityMissilesDamageEM"] ?? 0,
            explosiveDamage: fighter.attributesByName["fighterAbilityMissilesDamageExp"] ?? 0,
            kineticDamage: fighter.attributesByName["fighterAbilityMissilesDamageKin"] ?? 0,
            thermalDamage: fighter.attributesByName["fighterAbilityMissilesDamageTherm"] ?? 0,
            damageMultiplier: fighter.attributesByName["fighterAbilityMissilesDamageMultiplier"]
                ?? 1.0,
            cycleDurationMs: fighter.attributesByName["fighterAbilityMissilesDuration"] ?? 40000
        )

        // 3. 构建投弹能力
        var bombAbility = FighterAbility(
            emDamage: 0, explosiveDamage: 0, kineticDamage: 0, thermalDamage: 0,
            damageMultiplier: 1.0,
            cycleDurationMs: fighter.attributesByName["fighterAbilityLaunchBombDuration"] ?? 60000
        )

        // 检查是否有投弹能力并获取投弹伤害
        if let bombTypeId = fighter.attributesByName["fighterAbilityLaunchBombType"],
           bombTypeId > 0,
           let bombDamages = bombDamageMap[Int(bombTypeId)]
        {
            bombAbility = FighterAbility(
                emDamage: bombDamages.em,
                explosiveDamage: bombDamages.explosive,
                kineticDamage: bombDamages.kinetic,
                thermalDamage: bombDamages.thermal,
                damageMultiplier: 1.0,
                cycleDurationMs: fighter.attributesByName["fighterAbilityLaunchBombDuration"]
                    ?? 60000
            )
        }

        // 4. 构建自爆能力（只计算一次伤害，不参与DPS计算）
        let kamikazeAbility = FighterAbility(
            emDamage: fighter.attributesByName["fighterAbilityKamikazeDamageEM"] ?? 0,
            explosiveDamage: fighter.attributesByName["fighterAbilityKamikazeDamageExp"] ?? 0,
            kineticDamage: fighter.attributesByName["fighterAbilityKamikazeDamageKin"] ?? 0,
            thermalDamage: fighter.attributesByName["fighterAbilityKamikazeDamageTherm"] ?? 0,
            damageMultiplier: 1.0,
            cycleDurationMs: 1 // 设置为1ms，表示只执行一次
        )

        // 5. 计算各能力的DPS（自爆能力不参与DPS计算）
        let baseDPS = baseAbility.calculateDPS(quantity: fighter.quantity)
        let missileDPS = missileAbility.calculateDPS(quantity: fighter.quantity)
        let bombDPS = bombAbility.calculateDPS(quantity: fighter.quantity)

        // 6. 合并DPS结果（不包含自爆）
        let specialDPS = (
            totalDPS: missileDPS.totalDPS + bombDPS.totalDPS,
            emDPS: missileDPS.emDPS + bombDPS.emDPS,
            explosiveDPS: missileDPS.explosiveDPS + bombDPS.explosiveDPS,
            kineticDPS: missileDPS.kineticDPS + bombDPS.kineticDPS,
            thermalDPS: missileDPS.thermalDPS + bombDPS.thermalDPS
        )

        // 7. 根据设置决定最终DPS结果
        let finalDPS = (
            totalDPS: baseDPS.totalDPS + (includeSpecialAbilities ? specialDPS.totalDPS : 0),
            emDPS: baseDPS.emDPS + (includeSpecialAbilities ? specialDPS.emDPS : 0),
            explosiveDPS: baseDPS.explosiveDPS
                + (includeSpecialAbilities ? specialDPS.explosiveDPS : 0),
            kineticDPS: baseDPS.kineticDPS + (includeSpecialAbilities ? specialDPS.kineticDPS : 0),
            thermalDPS: baseDPS.thermalDPS + (includeSpecialAbilities ? specialDPS.thermalDPS : 0)
        )

        // 8. 计算总伤害（用于齐射伤害，包含自爆能力）
        let baseDamages = baseAbility.adjustedDamages
        let missileDamages = missileAbility.adjustedDamages
        let bombDamages = bombAbility.adjustedDamages
        let kamikazeDamages = kamikazeAbility.adjustedDamages

        let specialDamages = (
            em: missileDamages.em + bombDamages.em
                + (includeSpecialAbilities ? kamikazeDamages.em : 0),
            explosive: missileDamages.explosive + bombDamages.explosive
                + (includeSpecialAbilities ? kamikazeDamages.explosive : 0),
            kinetic: missileDamages.kinetic + bombDamages.kinetic
                + (includeSpecialAbilities ? kamikazeDamages.kinetic : 0),
            thermal: missileDamages.thermal + bombDamages.thermal
                + (includeSpecialAbilities ? kamikazeDamages.thermal : 0)
        )

        let finalDamages = (
            em: (baseDamages.em + (includeSpecialAbilities ? specialDamages.em : 0))
                * Double(fighter.quantity),
            explosive:
            (baseDamages.explosive + (includeSpecialAbilities ? specialDamages.explosive : 0))
                * Double(fighter.quantity),
            kinetic: (baseDamages.kinetic + (includeSpecialAbilities ? specialDamages.kinetic : 0))
                * Double(fighter.quantity),
            thermal: (baseDamages.thermal + (includeSpecialAbilities ? specialDamages.thermal : 0))
                * Double(fighter.quantity)
        )

        let totalDamage =
            finalDamages.em + finalDamages.explosive + finalDamages.kinetic + finalDamages.thermal

        // 9. 记录日志（包含自爆能力信息）
        let kamikazeTotalDamage = kamikazeAbility.totalDamage * Double(fighter.quantity)
        Logger.info(
            "【舰载机:\(fighter.name) ID: \(fighter.typeId) DPS计算】数量: \(fighter.quantity), 基础DPS: \(baseDPS.totalDPS), 特殊能力DPS: \(specialDPS.totalDPS), 自爆伤害: \(kamikazeTotalDamage), 包含特殊能力: \(includeSpecialAbilities), 最终DPS: \(finalDPS.totalDPS)"
        )

        return FighterDPSResult(
            emDamage: finalDamages.em,
            explosiveDamage: finalDamages.explosive,
            kineticDamage: finalDamages.kinetic,
            thermalDamage: finalDamages.thermal,
            totalDamage: totalDamage,
            dps: finalDPS.totalDPS,
            volleyDamage: totalDamage,
            emDPS: finalDPS.emDPS,
            explosiveDPS: finalDPS.explosiveDPS,
            kineticDPS: finalDPS.kineticDPS,
            thermalDPS: finalDPS.thermalDPS
        )
    }

    /// 计算所有舰载机的总DPS
    private func calculateFightersTotalDPS() -> FighterDPSResult {
        var totalEmDamage: Double = 0
        var totalExplosiveDamage: Double = 0
        var totalKineticDamage: Double = 0
        var totalThermalDamage: Double = 0
        var totalDPS: Double = 0
        var totalVolleyDamage: Double = 0
        var totalEmDPS: Double = 0
        var totalExplosiveDPS: Double = 0
        var totalKineticDPS: Double = 0
        var totalThermalDPS: Double = 0

        // 遍历所有舰载机中队计算DPS
        if let fighters = viewModel.simulationOutput?.fighters {
            // 按类型分组，合并相同类型的舰载机数量
            var fighterGroups: [Int: (fighter: FighterSquadOutput, totalQuantity: Int)] = [:]

            for fighter in fighters {
                if let existing = fighterGroups[fighter.typeId] {
                    // 相同类型，累加数量
                    fighterGroups[fighter.typeId] = (
                        existing.fighter, existing.totalQuantity + fighter.quantity
                    )
                } else {
                    // 新类型
                    fighterGroups[fighter.typeId] = (fighter, fighter.quantity)
                }
            }

            // 收集所有投弹类型ID
            var bombTypeIds: Set<Int> = []
            for (_, group) in fighterGroups {
                if let bombTypeId = group.fighter.attributesByName["fighterAbilityLaunchBombType"],
                   bombTypeId > 0
                {
                    bombTypeIds.insert(Int(bombTypeId))
                }
            }

            // 一次性查询所有投弹伤害属性
            let bombDamageMap = getAllBombDamages(bombTypeIds: Array(bombTypeIds))

            // 对每种类型的舰载机计算DPS
            for (_, group) in fighterGroups {
                // 创建一个临时的舰载机对象，使用合并后的数量
                var combinedFighter = group.fighter
                combinedFighter.quantity = group.totalQuantity

                let fighterDPS = getFighterDPS(
                    fighter: combinedFighter, bombDamageMap: bombDamageMap
                )

                // 累加各类伤害
                totalEmDamage += fighterDPS.emDamage
                totalExplosiveDamage += fighterDPS.explosiveDamage
                totalKineticDamage += fighterDPS.kineticDamage
                totalThermalDamage += fighterDPS.thermalDamage

                // 累加DPS和齐射伤害
                totalDPS += fighterDPS.dps
                totalVolleyDamage += fighterDPS.volleyDamage

                // 累加各类型DPS
                totalEmDPS += fighterDPS.emDPS
                totalExplosiveDPS += fighterDPS.explosiveDPS
                totalKineticDPS += fighterDPS.kineticDPS
                totalThermalDPS += fighterDPS.thermalDPS
            }
        }

        // 计算总伤害
        let totalDamage =
            totalEmDamage + totalExplosiveDamage + totalKineticDamage + totalThermalDamage

        return FighterDPSResult(
            emDamage: totalEmDamage,
            explosiveDamage: totalExplosiveDamage,
            kineticDamage: totalKineticDamage,
            thermalDamage: totalThermalDamage,
            totalDamage: totalDamage,
            dps: totalDPS,
            volleyDamage: totalVolleyDamage,
            emDPS: totalEmDPS,
            explosiveDPS: totalExplosiveDPS,
            kineticDPS: totalKineticDPS,
            thermalDPS: totalThermalDPS
        )
    }

    /// 舰载机DPS计算结果结构体
    struct FighterDPSResult {
        let emDamage: Double // 电磁伤害
        let explosiveDamage: Double // 爆炸伤害
        let kineticDamage: Double // 动能伤害
        let thermalDamage: Double // 热能伤害
        let totalDamage: Double // 总伤害
        let dps: Double // DPS
        let volleyDamage: Double // 齐射伤害

        // DPS比例
        let emDPS: Double // EM伤害DPS
        let explosiveDPS: Double // 爆炸伤害DPS
        let kineticDPS: Double // 动能伤害DPS
        let thermalDPS: Double // 热能伤害DPS
    }

    /// 从模块计算武器DPS
    private func getWeaponDPS(module: SimModuleOutput, ship: SimShipOutput) -> WeaponDPSResult {
        // 检查模块是否处于激活状态
        guard module.status > 1 else {
            return WeaponDPSResult(
                emDamage: 0, explosiveDamage: 0, kineticDamage: 0, thermalDamage: 0,
                totalDamage: 0, dpsWithoutReload: 0, dpsWithReload: 0, volleyDamage: 0,
                emDPS: 0, explosiveDPS: 0, kineticDPS: 0, thermalDPS: 0
            )
        }

        // 获取基础伤害属性，先默认为0
        var emDamage: Double = 0
        var explosiveDamage: Double = 0
        var kineticDamage: Double = 0
        var thermalDamage: Double = 0

        // 如果模块有弹药，优先使用弹药的伤害值
        if let charge = module.charge {
            emDamage = charge.attributesByName["emDamage"] ?? 0
            explosiveDamage = charge.attributesByName["explosiveDamage"] ?? 0
            kineticDamage = charge.attributesByName["kineticDamage"] ?? 0
            thermalDamage = charge.attributesByName["thermalDamage"] ?? 0
        }

        // 如果弹药没有伤害值或者没有弹药，则使用模块自身的伤害值
        if emDamage == 0 && explosiveDamage == 0 && kineticDamage == 0 && thermalDamage == 0 {
            emDamage = module.attributesByName["emDamage"] ?? 0
            explosiveDamage = module.attributesByName["explosiveDamage"] ?? 0
            kineticDamage = module.attributesByName["kineticDamage"] ?? 0
            thermalDamage = module.attributesByName["thermalDamage"] ?? 0
        }

        // 获取伤害乘数
        let damageMultiplier = module.attributesByName["damageMultiplier"] ?? 1.0
        let missileDamageMultiplier =
            ship.characterAttributesByName["missileDamageMultiplier"] ?? 1.0

        // 确定使用哪个倍增系数：如果弹药需要技能3319（导弹类技能），使用导弹伤害倍增器
        let finalDamageMultiplier: Double
        if let charge = module.charge, charge.requiredSkills.contains(3319) {
            finalDamageMultiplier = missileDamageMultiplier
        } else {
            finalDamageMultiplier = damageMultiplier
        }

        // 应用伤害乘数
        emDamage *= finalDamageMultiplier
        explosiveDamage *= finalDamageMultiplier
        kineticDamage *= finalDamageMultiplier
        thermalDamage *= finalDamageMultiplier

        // 计算总伤害
        let totalDamage = emDamage + explosiveDamage + kineticDamage + thermalDamage
        if totalDamage > 0 {
            let multiplierType =
                (module.charge?.requiredSkills.contains(3319) == true) ? "导弹伤害倍增器" : "常规伤害倍增器"
            Logger.info(
                "【武器:\(module.name) ID: \(module.instanceId) DPS计算】使用\(multiplierType): \(finalDamageMultiplier), 电磁伤害: \(emDamage), 爆炸伤害: \(explosiveDamage), 动能伤害: \(kineticDamage), 热能伤害: \(thermalDamage)"
            )
        }
        // 如果没有伤害，直接返回零值
        if totalDamage <= 0 {
            return WeaponDPSResult(
                emDamage: 0, explosiveDamage: 0, kineticDamage: 0, thermalDamage: 0,
                totalDamage: 0, dpsWithoutReload: 0, dpsWithReload: 0, volleyDamage: 0,
                emDPS: 0, explosiveDPS: 0, kineticDPS: 0, thermalDPS: 0
            )
        }

        // 获取武器周期时间（毫秒）
        let speedMs = module.attributesByName["speed"] ?? 0
        let durationMs = module.attributesByName["duration"] ?? 0
        let durationHighisGoodMs = module.attributesByName["durationHighisGood"] ?? 0
        let durationSensorDampeningBurstProjectorMs =
            module.attributesByName["durationSensorDampeningBurstProjector"] ?? 0
        let durationTargetIlluminationBurstProjectorMs =
            module.attributesByName["durationTargetIlluminationBurstProjector"] ?? 0
        let durationECMJammerBurstProjectorMs =
            module.attributesByName["durationECMJammerBurstProjector"] ?? 0
        let durationWeaponDisruptionBurstProjectorMs =
            module.attributesByName["durationWeaponDisruptionBurstProjector"] ?? 0

        // 取最大值作为周期时间
        let cycleDurationMs = max(
            speedMs,
            durationMs,
            durationHighisGoodMs,
            durationSensorDampeningBurstProjectorMs,
            durationTargetIlluminationBurstProjectorMs,
            durationECMJammerBurstProjectorMs,
            durationWeaponDisruptionBurstProjectorMs
        )

        let cycleDuration = cycleDurationMs / 1000.0

        // 齐射伤害就是总伤害
        let volleyDamage = totalDamage

        // 计算不考虑装弹的DPS
        let dpsWithoutReload: Double
        var emDPS: Double = 0
        var explosiveDPS: Double = 0
        var kineticDPS: Double = 0
        var thermalDPS: Double = 0

        if cycleDuration > 0 {
            dpsWithoutReload = totalDamage / cycleDuration

            // 计算各类型伤害的DPS
            emDPS = emDamage / cycleDuration
            explosiveDPS = explosiveDamage / cycleDuration
            kineticDPS = kineticDamage / cycleDuration
            thermalDPS = thermalDamage / cycleDuration
        } else {
            dpsWithoutReload = 0
        }

        let dpsWithReload = FittingWeaponStatistics.dpsIncludingReload(
            volley: totalDamage, cycle: cycleDuration, module: module
        )

        return WeaponDPSResult(
            emDamage: emDamage,
            explosiveDamage: explosiveDamage,
            kineticDamage: kineticDamage,
            thermalDamage: thermalDamage,
            totalDamage: totalDamage,
            dpsWithoutReload: dpsWithoutReload,
            dpsWithReload: dpsWithReload,
            volleyDamage: volleyDamage,
            emDPS: emDPS,
            explosiveDPS: explosiveDPS,
            kineticDPS: kineticDPS,
            thermalDPS: thermalDPS
        )
    }

    /// 计算所有武器模块的总DPS
    private func calculateWeaponsTotalDPS() -> WeaponDPSResult {
        var totalEmDamage: Double = 0
        var totalExplosiveDamage: Double = 0
        var totalKineticDamage: Double = 0
        var totalThermalDamage: Double = 0
        var totalVolleyDamage: Double = 0
        var totalDPSWithoutReload: Double = 0
        var totalDPSWithReload: Double = 0
        var totalEmDPS: Double = 0
        var totalExplosiveDPS: Double = 0
        var totalKineticDPS: Double = 0
        var totalThermalDPS: Double = 0

        // 遍历所有模块计算DPS
        if let modules = viewModel.simulationOutput?.modules,
           let ship = viewModel.simulationOutput?.ship
        {
            for module in modules {
                let weaponDPS = getWeaponDPS(module: module, ship: ship)

                // 累加各类伤害
                totalEmDamage += weaponDPS.emDamage
                totalExplosiveDamage += weaponDPS.explosiveDamage
                totalKineticDamage += weaponDPS.kineticDamage
                totalThermalDamage += weaponDPS.thermalDamage

                // 累加DPS和齐射伤害
                totalDPSWithoutReload += weaponDPS.dpsWithoutReload
                totalDPSWithReload += weaponDPS.dpsWithReload
                totalVolleyDamage += weaponDPS.volleyDamage

                // 累加各类型DPS
                totalEmDPS += weaponDPS.emDPS
                totalExplosiveDPS += weaponDPS.explosiveDPS
                totalKineticDPS += weaponDPS.kineticDPS
                totalThermalDPS += weaponDPS.thermalDPS
            }
        }

        // 计算总伤害
        let totalDamage =
            totalEmDamage + totalExplosiveDamage + totalKineticDamage + totalThermalDamage

        return WeaponDPSResult(
            emDamage: totalEmDamage,
            explosiveDamage: totalExplosiveDamage,
            kineticDamage: totalKineticDamage,
            thermalDamage: totalThermalDamage,
            totalDamage: totalDamage,
            dpsWithoutReload: totalDPSWithoutReload,
            dpsWithReload: totalDPSWithReload,
            volleyDamage: totalVolleyDamage,
            emDPS: totalEmDPS,
            explosiveDPS: totalExplosiveDPS,
            kineticDPS: totalKineticDPS,
            thermalDPS: totalThermalDPS
        )
    }

    /// 从无人机计算DPS
    private func getDroneDPS(drone: SimDroneOutput) -> DroneDPSResult {
        // 仅计算激活的无人机
        guard drone.activeCount > 0 else {
            return DroneDPSResult(
                emDamage: 0, explosiveDamage: 0, kineticDamage: 0, thermalDamage: 0,
                totalDamage: 0, dps: 0, volleyDamage: 0,
                emDPS: 0, explosiveDPS: 0, kineticDPS: 0, thermalDPS: 0
            )
        }

        // 获取无人机伤害属性
        let emDamage = drone.attributesByName["emDamage"] ?? 0
        let explosiveDamage = drone.attributesByName["explosiveDamage"] ?? 0
        let kineticDamage = drone.attributesByName["kineticDamage"] ?? 0
        let thermalDamage = drone.attributesByName["thermalDamage"] ?? 0

        // 获取伤害乘数
        let damageMultiplier = drone.attributesByName["damageMultiplier"] ?? 1.0

        // 应用伤害乘数
        let adjustedEmDamage = emDamage * damageMultiplier
        let adjustedExplosiveDamage = explosiveDamage * damageMultiplier
        let adjustedKineticDamage = kineticDamage * damageMultiplier
        let adjustedThermalDamage = thermalDamage * damageMultiplier

        // 计算单个无人机的总伤害
        let singleDroneTotalDamage =
            adjustedEmDamage + adjustedExplosiveDamage + adjustedKineticDamage
                + adjustedThermalDamage

        // 如果没有伤害，直接返回零值
        if singleDroneTotalDamage <= 0 {
            return DroneDPSResult(
                emDamage: 0, explosiveDamage: 0, kineticDamage: 0, thermalDamage: 0,
                totalDamage: 0, dps: 0, volleyDamage: 0,
                emDPS: 0, explosiveDPS: 0, kineticDPS: 0, thermalDPS: 0
            )
        }

        // 获取无人机攻击周期时间（毫秒）
        let droneAttackCycleTimeMs = drone.attributesByName["speed"] ?? 0

        // 转换为秒
        let droneAttackCycleTime = droneAttackCycleTimeMs / 1000.0

        // 计算单个无人机的DPS
        let singleDroneDPS: Double =
            droneAttackCycleTime > 0 ? singleDroneTotalDamage / droneAttackCycleTime : 0

        // 计算激活无人机的总伤害和DPS
        let totalEmDamage = adjustedEmDamage * Double(drone.activeCount)
        let totalExplosiveDamage = adjustedExplosiveDamage * Double(drone.activeCount)
        let totalKineticDamage = adjustedKineticDamage * Double(drone.activeCount)
        let totalThermalDamage = adjustedThermalDamage * Double(drone.activeCount)
        let totalDamage = singleDroneTotalDamage * Double(drone.activeCount)
        let totalDPS = singleDroneDPS * Double(drone.activeCount)

        // 计算激活无人机的齐射伤害
        let volleyDamage = totalDamage

        // 计算各类型DPS
        let emDPS =
            droneAttackCycleTime > 0
                ? (adjustedEmDamage / droneAttackCycleTime) * Double(drone.activeCount) : 0
        let explosiveDPS =
            droneAttackCycleTime > 0
                ? (adjustedExplosiveDamage / droneAttackCycleTime) * Double(drone.activeCount) : 0
        let kineticDPS =
            droneAttackCycleTime > 0
                ? (adjustedKineticDamage / droneAttackCycleTime) * Double(drone.activeCount) : 0
        let thermalDPS =
            droneAttackCycleTime > 0
                ? (adjustedThermalDamage / droneAttackCycleTime) * Double(drone.activeCount) : 0

        Logger.info(
            "【无人机:\(drone.name) ID: \(drone.typeId) DPS计算】激活数量: \(drone.activeCount), 伤害乘数: \(damageMultiplier), 电磁伤害: \(totalEmDamage), 爆炸伤害: \(totalExplosiveDamage), 动能伤害: \(totalKineticDamage), 热能伤害: \(totalThermalDamage), DPS: \(totalDPS)"
        )

        return DroneDPSResult(
            emDamage: totalEmDamage,
            explosiveDamage: totalExplosiveDamage,
            kineticDamage: totalKineticDamage,
            thermalDamage: totalThermalDamage,
            totalDamage: totalDamage,
            dps: totalDPS,
            volleyDamage: volleyDamage,
            emDPS: emDPS,
            explosiveDPS: explosiveDPS,
            kineticDPS: kineticDPS,
            thermalDPS: thermalDPS
        )
    }

    /// 计算所有无人机的总DPS
    private func calculateDronesTotalDPS() -> DroneDPSResult {
        var totalEmDamage: Double = 0
        var totalExplosiveDamage: Double = 0
        var totalKineticDamage: Double = 0
        var totalThermalDamage: Double = 0
        var totalDPS: Double = 0
        var totalVolleyDamage: Double = 0
        var totalEmDPS: Double = 0
        var totalExplosiveDPS: Double = 0
        var totalKineticDPS: Double = 0
        var totalThermalDPS: Double = 0

        // 遍历所有无人机计算DPS
        if let drones = viewModel.simulationOutput?.drones {
            for drone in drones {
                let droneDPS = getDroneDPS(drone: drone)

                // 累加各类伤害
                totalEmDamage += droneDPS.emDamage
                totalExplosiveDamage += droneDPS.explosiveDamage
                totalKineticDamage += droneDPS.kineticDamage
                totalThermalDamage += droneDPS.thermalDamage

                // 累加DPS和齐射伤害
                totalDPS += droneDPS.dps
                totalVolleyDamage += droneDPS.volleyDamage

                // 累加各类型DPS
                totalEmDPS += droneDPS.emDPS
                totalExplosiveDPS += droneDPS.explosiveDPS
                totalKineticDPS += droneDPS.kineticDPS
                totalThermalDPS += droneDPS.thermalDPS
            }
        }

        // 计算总伤害
        let totalDamage =
            totalEmDamage + totalExplosiveDamage + totalKineticDamage + totalThermalDamage

        return DroneDPSResult(
            emDamage: totalEmDamage,
            explosiveDamage: totalExplosiveDamage,
            kineticDamage: totalKineticDamage,
            thermalDamage: totalThermalDamage,
            totalDamage: totalDamage,
            dps: totalDPS,
            volleyDamage: totalVolleyDamage,
            emDPS: totalEmDPS,
            explosiveDPS: totalExplosiveDPS,
            kineticDPS: totalKineticDPS,
            thermalDPS: totalThermalDPS
        )
    }

    /// 计算火力数据
    private func calculateFirepowerData() -> FirepowerData {
        // 计算武器DPS
        let weaponDPS = calculateWeaponsTotalDPS()

        // 计算无人机DPS
        let droneDPSResult = calculateDronesTotalDPS()

        // 计算舰载机DPS
        let fighterDPSResult = calculateFightersTotalDPS()

        // 合并无人机和舰载机的DPS
        let combinedDroneDPS = droneDPSResult.dps + fighterDPSResult.dps
        let combinedDroneVolley = droneDPSResult.volleyDamage + fighterDPSResult.volleyDamage

        // 合并无人机和舰载机的各类型DPS
        let combinedEmDPS = droneDPSResult.emDPS + fighterDPSResult.emDPS
        let combinedThermalDPS = droneDPSResult.thermalDPS + fighterDPSResult.thermalDPS
        let combinedKineticDPS = droneDPSResult.kineticDPS + fighterDPSResult.kineticDPS
        let combinedExplosiveDPS = droneDPSResult.explosiveDPS + fighterDPSResult.explosiveDPS

        // 合并武器和无人机(包含舰载机)DPS
        let totalDPS = weaponDPS.dpsWithoutReload + combinedDroneDPS
        let totalVolley = weaponDPS.volleyDamage + combinedDroneVolley

        // 计算综合伤害比例（武器和无人机(包含舰载机)的加权平均）
        let totalEmDPS = weaponDPS.emDPS + combinedEmDPS
        let totalThermalDPS = weaponDPS.thermalDPS + combinedThermalDPS
        let totalKineticDPS = weaponDPS.kineticDPS + combinedKineticDPS
        let totalExplosiveDPS = weaponDPS.explosiveDPS + combinedExplosiveDPS

        // 计算总伤害比例
        let emRatio = totalDPS > 0 ? totalEmDPS / totalDPS : 0
        let thermalRatio = totalDPS > 0 ? totalThermalDPS / totalDPS : 0
        let kineticRatio = totalDPS > 0 ? totalKineticDPS / totalDPS : 0
        let explosiveRatio = totalDPS > 0 ? totalExplosiveDPS / totalDPS : 0

        return FirepowerData(
            weaponVolley: weaponDPS.volleyDamage,
            weaponDPS: weaponDPS.dpsWithoutReload,
            droneVolley: combinedDroneVolley,
            droneDPS: combinedDroneDPS,
            totalVolley: totalVolley,
            totalDPS: totalDPS,
            emRatio: emRatio,
            thermalRatio: thermalRatio,
            kineticRatio: kineticRatio,
            explosiveRatio: explosiveRatio
        )
    }

    var body: some View {
        if viewModel.simulationOutput?.ship != nil {
            let firepowerData = calculateFirepowerData()

            Section {
                VStack(spacing: 2) {
                    // 标题行：伤害类型图标
                    HStack {
                        Text("")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Icon(image: "gunSlot").frame(maxWidth: .infinity)
                        Icon(image: "drone_band").frame(maxWidth: .infinity)
                        Icon(image: "turret_volley").frame(maxWidth: .infinity)
                    }
                    Divider()
                        .padding(.vertical, 2)

                    // DPS行
                    HStack {
                        Text(NSLocalizedString("Fitting_dps", comment: "DPS"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(formatFirepowerValue(firepowerData.weaponDPS)).fixedSize()
                            .frame(maxWidth: .infinity)
                        Text(formatFirepowerValue(firepowerData.droneDPS)).fixedSize()
                            .frame(maxWidth: .infinity)
                        Text(formatFirepowerValue(firepowerData.totalDPS)).fixedSize()
                            .frame(maxWidth: .infinity)
                    }

                    // 单次伤害行
                    HStack {
                        Text(NSLocalizedString("Fitting_volley", comment: "单次伤害"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(formatFirepowerValue(firepowerData.weaponVolley)).fixedSize()
                            .frame(maxWidth: .infinity)
                        Text(formatFirepowerValue(firepowerData.droneVolley)).fixedSize()
                            .frame(maxWidth: .infinity)
                        Text(formatFirepowerValue(firepowerData.totalVolley)).fixedSize()
                            .frame(maxWidth: .infinity)
                    }

                    Divider()
                        .padding(.vertical, 2)

                    // 伤害分布行
                    HStack {
                        Text(NSLocalizedString("Fitting_damage_profile", comment: "伤害分布"))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // EM伤害比例
                        DamageRatioView(ratio: firepowerData.emRatio, damageType: "em")

                        // 热能伤害比例
                        DamageRatioView(ratio: firepowerData.thermalRatio, damageType: "th")

                        // 动能伤害比例
                        DamageRatioView(ratio: firepowerData.kineticRatio, damageType: "ki")

                        // 爆炸伤害比例
                        DamageRatioView(ratio: firepowerData.explosiveRatio, damageType: "ex")
                    }
                }
                .font(.caption)
                .lineLimit(1)
            } header: {
                HStack {
                    Text(NSLocalizedString("Fitting_stat_firepower", comment: ""))
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .font(.system(size: 18))

                    Spacer()

                    // 如果有舰载机，显示特殊能力切换按钮
                    if let fighters = viewModel.simulationOutput?.fighters, !fighters.isEmpty {
                        Button(action: {
                            includeSpecialAbilities.toggle()
                        }) {
                            Text(
                                includeSpecialAbilities
                                    ? NSLocalizedString(
                                        "Fitting_Fighter_With_Special_Abilities", comment: ""
                                    )
                                    : NSLocalizedString(
                                        "Fitting_Fighter_Without_Special_Abilities", comment: ""
                                    )
                            )
                            .font(.caption)
                            .foregroundColor(.blue)
                        }
                    }
                }
            }
        }
    }
}

/// 火力数据结构
struct FirepowerData {
    let weaponVolley: Double
    let weaponDPS: Double
    let droneVolley: Double
    let droneDPS: Double
    let totalVolley: Double
    let totalDPS: Double
    let emRatio: Double
    let thermalRatio: Double
    let kineticRatio: Double
    let explosiveRatio: Double
}

/// 伤害比例视图
struct DamageRatioView: View {
    let ratio: Double
    let damageType: String

    private func formatPercentage(_ value: Double) -> String {
        return FormatUtil.formatForUI(value * 100) + "%"
    }

    var body: some View {
        HStack(spacing: 4) {
            // 伤害类型图标
            IconManager.shared.loadImage(for: damageType)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)

            // 伤害比例文本
            Text(formatPercentage(ratio))
                .font(.caption)
        }
        .frame(maxWidth: .infinity)
    }
}
