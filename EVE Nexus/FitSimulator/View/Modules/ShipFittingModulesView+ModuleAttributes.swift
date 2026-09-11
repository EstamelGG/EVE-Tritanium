import SwiftUI

/// 模块行特殊属性展示机制（自 ShipFittingModulesView+Rows.swift 抽出，便于维护）
/// 每种特殊属性一个方法，Xcode 跳转栏按 MARK 分节定位
extension ShipFittingModulesView {
    /// 模块特殊属性行总入口：按固定顺序展示各特殊属性
    @ViewBuilder
    func moduleSpecialAttributeRows(module: SimModule) -> some View {
        moduleDPSRow(module: module)
        missileMaxRangeRow(module: module)
        probeStrengthRow(module: module)
        energyNeutralizerRow(module: module)
        powerTransferRow(module: module)
        shieldRepairRow(module: module)
        armorRepairRow(module: module)
        hullRepairRow(module: module)
        shieldCapacityBonusRow(module: module)
        armorHPBonusRow(module: module)
        capacitorBonusRow(module: module)
        miningAmountRow(module: module)
        empFieldRangeRow(module: module)
        optimalRangeAndFalloffRow(module: module)
        trackingSpeedRow(module: module)
        rateOfFireRow(module: module)
        warfareBuffRows(module: module)
    }

    // MARK: - 装备DPS/DPH

    /// 装备DPS/DPH行：DPS = 总伤害/周期（不含装填），DPH = 单发总伤害；非武器或未激活时不显示
    @ViewBuilder
    private func moduleDPSRow(module: SimModule) -> some View {
        let damage = calculateModuleDamage(module: module)
        if damage.dps > 0 {
            HStack(spacing: 4) {
                IconManager.shared.loadImage(for: "dps")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)

                (Text("DPS: ")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    + Text(String(format: "%.1f", damage.dps))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    + Text(" / DPH: ")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    + Text(String(format: "%.1f", damage.dph))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary))
                    .lineLimit(1)
            }
        }
    }

    /// 计算单模块伤害（dps 不含装填，dph 为单发总伤害）
    /// 精简自 ShipFirepowerStatsView.getWeaponDPS：伤害优先取弹药四维、全 0 回落模块自身；
    /// 弹药需要技能 3319（导弹类）时用船的导弹伤害倍增器，否则用模块常规倍增器
    private func calculateModuleDamage(module: SimModule) -> (dps: Double, dph: Double) {
        // 仅激活状态（status > 1）参与计算，与火力统计页一致
        guard module.status > 1 else { return (0, 0) }

        var emDamage = module.charge?.attributesByName["emDamage"] ?? 0
        var explosiveDamage = module.charge?.attributesByName["explosiveDamage"] ?? 0
        var kineticDamage = module.charge?.attributesByName["kineticDamage"] ?? 0
        var thermalDamage = module.charge?.attributesByName["thermalDamage"] ?? 0

        if emDamage == 0, explosiveDamage == 0, kineticDamage == 0, thermalDamage == 0 {
            emDamage = module.attributesByName["emDamage"] ?? 0
            explosiveDamage = module.attributesByName["explosiveDamage"] ?? 0
            kineticDamage = module.attributesByName["kineticDamage"] ?? 0
            thermalDamage = module.attributesByName["thermalDamage"] ?? 0
        }

        let finalDamageMultiplier: Double
        if module.charge?.requiredSkills.contains(3319) == true {
            finalDamageMultiplier =
                viewModel.simulationOutput?.ship.characterAttributesByName["missileDamageMultiplier"] ?? 1.0
        } else {
            finalDamageMultiplier = module.attributesByName["damageMultiplier"] ?? 1.0
        }

        let totalDamage =
            (emDamage + explosiveDamage + kineticDamage + thermalDamage) * finalDamageMultiplier
        guard totalDamage > 0 else { return (0, 0) }

        let cycleDuration = calculateCycleDuration(module: module)
        guard cycleDuration > 0 else { return (0, totalDamage) }

        return (totalDamage / cycleDuration, totalDamage)
    }

    // MARK: - 导弹最大射程

    @ViewBuilder
    private func missileMaxRangeRow(module: SimModule) -> some View {
        if let charge = module.charge {
            let maxFlightTime = charge.attributesByName["explosionDelay"] ?? 0
            let maxFlightSpeed = charge.attributesByName["maxVelocity"] ?? 0
            let maxMissileRange = maxFlightTime * maxFlightSpeed / 1000
            if maxMissileRange > 0 { // 导弹最大射程，需除以1000
                HStack(spacing: 4) {
                    IconManager.shared.loadImage(for: "target_range")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)

                    HStack(spacing: 0) {
                        Text(
                            "\(NSLocalizedString("Module_Attribute_MaxRange", comment: "")): "
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                        Text("\(formatDistance(maxMissileRange))")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - 扫描探针强度

    @ViewBuilder
    private func probeStrengthRow(module: SimModule) -> some View {
        if let charge = module.charge {
            let baseSensorStrength = charge.attributesByName["baseSensorStrength"] ?? 0
            if baseSensorStrength > 0, charge.groupID == 479 { // 扫描探针强度
                HStack(spacing: 4) {
                    IconManager.shared.loadImage(for: "probes")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)

                    HStack(spacing: 0) {
                        Text(
                            "\(NSLocalizedString("Module_Attribute_ProbeStrength", comment: "")): "
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                        Text("\(formatNumber(baseSensorStrength, digits: 2))")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - 能量中和

    @ViewBuilder
    private func energyNeutralizerRow(module: SimModule) -> some View {
        let energyNeutralizerAmount =
            module.attributesByName["energyNeutralizerAmount"] ?? 0
        if energyNeutralizerAmount > 0 {
            HStack(spacing: 4) {
                IconManager.shared.loadImage(for: "neut")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)

                HStack(spacing: 0) {
                    Text(
                        "\(NSLocalizedString("Module_Attribute_energyNeutralizerAmount", comment: "")): "
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    Text("\(formatNumber(energyNeutralizerAmount, digits: 2)) GJ")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - 吸电 / 传电

    @ViewBuilder
    private func powerTransferRow(module: SimModule) -> some View {
        let powerTransferAmount = module.attributesByName["powerTransferAmount"] ?? 0
        if powerTransferAmount > 0 {
            HStack(spacing: 4) {
                IconManager.shared.loadImage(
                    for: module.groupID == 68 ? "neut_nos" : "cap_trans"
                )
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)

                HStack(spacing: 0) { // 68 为吸电
                    Text(
                        "\(module.groupID == 68 ? NSLocalizedString("Module_Attribute_powerTransferAmount_nos", comment: "") : NSLocalizedString("Module_Attribute_powerTransferAmount", comment: "")): "
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    Text("\(formatNumber(powerTransferAmount, digits: 2)) GJ")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - 护盾维修

    @ViewBuilder
    private func shieldRepairRow(module: SimModule) -> some View {
        let isRemote = isRemoteEquip(module: module)
        let shieldBonus = module.attributesByName["shieldBonus"] ?? 0
        if shieldBonus > 0 {
            HStack(spacing: 4) {
                IconManager.shared.loadImage(
                    for: !isRemote ? "shield_glow" : "shield_trans"
                )
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)

                HStack(spacing: 0) {
                    Text(
                        "\(!isRemote ? NSLocalizedString("Module_Attribute_shieldBonus", comment: "") : NSLocalizedString("Module_Attribute_trans_shieldBonus", comment: "")): "
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    Text("\(formatNumber(shieldBonus, digits: 2)) HP")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - 装甲维修

    @ViewBuilder
    private func armorRepairRow(module: SimModule) -> some View {
        let isRemote = isRemoteEquip(module: module)
        let armorDamageAmount = module.attributesByName["armorDamageAmount"] ?? 0
        if armorDamageAmount > 0 {
            HStack(spacing: 4) {
                IconManager.shared.loadImage(
                    for: !isRemote ? "armor_repairer_i" : "armor_trans"
                )
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)

                HStack(spacing: 0) {
                    Text(
                        "\(!isRemote ? NSLocalizedString("Module_Attribute_armorBonus", comment: "") : NSLocalizedString("Module_Attribute_trans_armorBonus", comment: "")): "
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    Text("\(formatNumber(armorDamageAmount, digits: 2)) HP")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - 结构维修

    @ViewBuilder
    private func hullRepairRow(module: SimModule) -> some View {
        let isRemote = isRemoteEquip(module: module)
        let structureDamageAmount =
            module.attributesByName["structureDamageAmount"] ?? 0
        if structureDamageAmount > 0 {
            HStack(spacing: 4) {
                IconManager.shared.loadImage(
                    for: !isRemote ? "hull_repairer_i" : "hull_trans"
                )
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)

                HStack(spacing: 0) {
                    Text(
                        "\(!isRemote ? NSLocalizedString("Module_Attribute_hullBonus", comment: "") : NSLocalizedString("Module_Attribute_trans_hullBonus", comment: "")): "
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    Text("\(formatNumber(structureDamageAmount, digits: 2)) HP")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - 护盾盾扩加成

    @ViewBuilder
    private func shieldCapacityBonusRow(module: SimModule) -> some View {
        let capacityBonus = module.attributesByName["capacityBonus"] ?? 0
        if capacityBonus > 0 {
            HStack(spacing: 4) {
                IconManager.shared.loadImage(for: "shield")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)

                HStack(spacing: 0) {
                    Text(
                        "\(NSLocalizedString("Module_Attribute_shieldHPBonus", comment: "")): "
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    Text("+\(formatNumber(capacityBonus, digits: 2)) HP")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - 钢版加成

    @ViewBuilder
    private func armorHPBonusRow(module: SimModule) -> some View {
        let armorHPBonusAdd = module.attributesByName["armorHPBonusAdd"] ?? 0
        if armorHPBonusAdd > 0 {
            HStack(spacing: 4) {
                IconManager.shared.loadImage(for: "armor")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)

                HStack(spacing: 0) {
                    Text(
                        "\(NSLocalizedString("Module_Attribute_armorHPBonus", comment: "")): "
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    Text("+\(formatNumber(armorHPBonusAdd, digits: 2)) HP")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - 电容量加成

    @ViewBuilder
    private func capacitorBonusRow(module: SimModule) -> some View {
        let capacitorBonus = module.attributesByName["capacitorBonus"] ?? 0
        if capacitorBonus > 0 {
            HStack(spacing: 4) {
                IconManager.shared.loadImage(for: "cap_add")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)

                HStack(spacing: 0) {
                    Text(
                        "\(NSLocalizedString("Module_Attribute_capBonus", comment: "")): "
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    Text("+\(formatNumber(capacitorBonus, digits: 2)) GJ")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - 开采量

    @ViewBuilder
    private func miningAmountRow(module: SimModule) -> some View {
        let miningAmount = module.attributesByName["miningAmount"] ?? 0
        let miningWasteProbability =
            module.attributesByName["miningWasteProbability"] ?? 0
        if miningAmount > 0 {
            HStack(spacing: 4) {
                IconManager.shared.loadImage(for: "miner")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)

                HStack(spacing: 0) {
                    Text(
                        "\(NSLocalizedString("Module_Attribute_miningAmount", comment: "")): "
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    Text(
                        "\(formatNumber(miningAmount, digits: 2)) m³ + \(FormatUtil.formatPercentFrom100(miningWasteProbability, fractionDigits: 2))"
                    )
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - 立体炸弹范围

    @ViewBuilder
    private func empFieldRangeRow(module: SimModule) -> some View {
        let empFieldRange = module.attributesByName["empFieldRange"] ?? 0
        if empFieldRange > 0 {
            HStack(spacing: 4) {
                IconManager.shared.loadImage(for: "target_range")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)

                HStack(spacing: 0) {
                    Text(
                        "\(NSLocalizedString("Module_Attribute_empFieldRange", comment: "")): "
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    Text("\(formatDistance(empFieldRange))")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - 最佳射程与失准

    @ViewBuilder
    private func optimalRangeAndFalloffRow(module: SimModule) -> some View {
        let maxRange = module.attributesByName["maxRange"] ?? 0
        let falloff = module.attributesByName["falloff"] ?? 0
        if maxRange > 0 || falloff > 0 {
            HStack(spacing: 4) {
                if maxRange > 0 {
                    // 有maxRange时使用maxRange图标
                    IconManager.shared.loadImage(for: "target_range")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                } else {
                    // 只有falloff时使用falloff图标
                    IconManager.shared.loadImage(for: "falloff_mod")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                }

                HStack(spacing: 0) {
                    if maxRange > 0 && falloff > 0 {
                        Text(
                            "\(NSLocalizedString("Module_Attribute_Range", comment: ""))+\(NSLocalizedString("Module_Attribute_Falloff", comment: "")): "
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                        Text("\(formatDistance(maxRange)) + \(formatDistance(falloff))")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    } else if maxRange > 0 {
                        Text(
                            "\(NSLocalizedString("Module_Attribute_Range", comment: "")): "
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                        Text("\(formatDistance(maxRange))")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    } else {
                        Text(
                            "\(NSLocalizedString("Module_Attribute_Falloff", comment: "")): "
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                        Text("\(formatDistance(falloff))")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - 跟踪速度

    @ViewBuilder
    private func trackingSpeedRow(module: SimModule) -> some View {
        let trackingSpeed = module.attributesByName["trackingSpeed"] ?? 0
        if trackingSpeed > 0 {
            HStack(spacing: 4) {
                IconManager.shared.loadImage(for: "tracking")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)

                HStack(spacing: 0) {
                    Text(
                        "\(NSLocalizedString("Module_Attribute_Tracking", comment: "")): "
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    Text("\(formatNumber(trackingSpeed))")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - 射击速度

    @ViewBuilder
    private func rateOfFireRow(module: SimModule) -> some View {
        let cycleDuration = calculateCycleDuration(module: module)
        if cycleDuration > 0 {
            HStack(spacing: 4) {
                IconManager.shared.loadImage(for: "turret_volley")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)

                HStack(spacing: 0) {
                    Text(
                        "\(NSLocalizedString("Module_Attribute_Rate_of_Fire", comment: "")): "
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    Text("\(formatCycleDuration(cycleDuration))s")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - 指挥脉冲波加成

    /// 统一从模块的 warfareBuff{n}ID/Value 对解析
    /// EVE 机制：弹药的强度基数经弹药效果 chargeBonusWarfareCharge（otherID 修饰器）乘入模块的 Value，
    /// 技能/脑插/舰船加成也作用于模块 Value，因此模块计算后的 Value 即最终强度（如 8.48%）；
    /// ID 由管线从弹药 assign 到模块（弹药未装载时无 ID，不显示）
    /// buff 名称按来源 typeID 精确查询（dbuffCollection.type_id 场景隔离：弹药/泰坦/天气）
    @ViewBuilder
    private func warfareBuffRows(module: SimModule) -> some View {
        let warfareBuffItems: [(buffID: Int, value: Double, icon: String?, sourceTypeID: Int)] =
            SDEMemoryStore.parseWarfareBuffPairs(module.attributesByName).map { pair in
                (
                    pair.buffID,
                    pair.value,
                    module.charge?.iconFileName ?? module.iconFileName,
                    module.charge?.typeId ?? module.typeId
                )
            }

        ForEach(warfareBuffItems, id: \.buffID) { buffID, multiplier, icon, sourceTypeID in
            if let buffInfo = SDEMemoryStore.warfareBuff(for: buffID, typeID: sourceTypeID) {
                warfareBuffRow(
                    name: buffInfo.displayName,
                    iconFileName: icon,
                    multiplier: multiplier
                )
            }
        }
    }

    // MARK: - 辅助函数

    func isRemoteEquip(module: SimModule) -> Bool {
        let maxRange = module.attributesByName["maxRange"] ?? 0
        return maxRange > 0
    }

    /// 格式化距离显示（自动选择合适的单位：m或km）
    /// 大于1000km时显示完整数字，不使用k km缩写
    func formatDistance(_ distance: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.numberStyle = .decimal

        if distance >= 1000 {
            // 大于等于1km时，使用km单位，保留2位小数
            let value = distance / 1000.0
            formatter.maximumFractionDigits = 2
            let formattedValue = formatter.string(from: NSNumber(value: value)) ?? "0"
            return "\(formattedValue) km"
        } else {
            // 小于1km时，使用m单位
            formatter.maximumFractionDigits = 0
            let formattedValue = formatter.string(from: NSNumber(value: distance)) ?? "0"
            return "\(formattedValue) m"
        }
    }

    /// 格式化跟踪速度（最多5位小数，去掉末尾的0）
    func formatNumber(_ number: Double, digits: Int = 5) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = digits
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "0"
    }

    /// 计算射击周期时间（参考ShipFirepowerStatsView的方法）
    func calculateCycleDuration(module: SimModule) -> Double {
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

        // 转换为秒
        return cycleDurationMs / 1000.0
    }

    /// 格式化射击周期时间
    func formatCycleDuration(_ duration: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: duration)) ?? "0"
    }

    /// 指挥脉冲波加成行：弹药图标 + 本地化 buff 名称 + 百分比（复用共享的 WarfareBuffRow 内嵌样式）
    private func warfareBuffRow(
        name: String,
        iconFileName: String?,
        multiplier: Double
    ) -> some View {
        WarfareBuffRow(
            name: name,
            iconFileName: iconFileName,
            multiplier: multiplier,
            font: .caption,
            iconSize: 20,
            fractionDigits: 2,
            isInline: true
        )
    }
}
