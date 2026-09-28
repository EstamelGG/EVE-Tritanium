import Foundation

// MARK: - EVE 物品 Flag 本地化

enum FlagMapping {
    /// 保存闭包而非翻译结果，查询时才读取当前本地化。
    /// 新增专用名称只需在这里登记；key 保持字面量，便于本地化工具扫描。
    private static let localizedNames: [Int: () -> String] = {
        var names: [Int: () -> String] = [
            4: { NSLocalizedString("Location_Flag_Hangar", comment: "机库") },
            5: { NSLocalizedString("Cargo", comment: "货舱") },
            87: { NSLocalizedString("DroneBay", comment: "无人机舱") },
            89: { NSLocalizedString("Main_KM_Implants", comment: "植入体") },
            90: { NSLocalizedString("ShipHangar", comment: "舰船机库") },
            115: { NSLocalizedString("Location_Flag_CorpSAG1", comment: "公司机库 1") },
            116: { NSLocalizedString("Location_Flag_CorpSAG2", comment: "公司机库 2") },
            117: { NSLocalizedString("Location_Flag_CorpSAG3", comment: "公司机库 3") },
            118: { NSLocalizedString("Location_Flag_CorpSAG4", comment: "公司机库 4") },
            119: { NSLocalizedString("Location_Flag_CorpSAG5", comment: "公司机库 5") },
            120: { NSLocalizedString("Location_Flag_CorpSAG6", comment: "公司机库 6") },
            121: { NSLocalizedString("Location_Flag_CorpSAG7", comment: "公司机库 7") },
            133: { NSLocalizedString("SpecializedFuelBay", comment: "燃料舱") },
            134: { NSLocalizedString("SpecializedAsteroidHold", comment: "小行星舱") },
            135: { NSLocalizedString("SpecializedGasHold", comment: "气云舱") },
            136: { NSLocalizedString("SpecializedMineralHold", comment: "矿物舱") },
            137: { NSLocalizedString("SpecializedSalvageHold", comment: "残骸舱") },
            138: { NSLocalizedString("SpecializedShipHold", comment: "舰船舱") },
            139: { NSLocalizedString("SpecializedSmallShipHold", comment: "小型舰船舱") },
            140: { NSLocalizedString("SpecializedMediumShipHold", comment: "中型舰船舱") },
            141: { NSLocalizedString("SpecializedLargeShipHold", comment: "大型舰船舱") },
            142: { NSLocalizedString("SpecializedIndustrialShipHold", comment: "工业舰船舱") },
            143: { NSLocalizedString("SpecializedAmmoHold", comment: "弹药舱") },
            148: { NSLocalizedString("SpecializedCommandCenterHold", comment: "指挥中心舱") },
            149: { NSLocalizedString("SpecializedPlanetaryCommoditiesHold", comment: "行星商品舱") },
            151: { NSLocalizedString("SpecializedMaterialBay", comment: "材料舱") },
            155: { NSLocalizedString("FleetHangar", comment: "舰队机库") },
            158: { NSLocalizedString("FighterBay", comment: "战斗机舱") },
            172: { NSLocalizedString("Location_Flag_StructureFuel", comment: "建筑燃料舱") },
            177: { NSLocalizedString("Location_Flag_SubSystemBay", comment: "子系统舱") },
            179: { NSLocalizedString("FrigateEscapeBay", comment: "护卫舰逃生舱") },
            180: { NSLocalizedString("Location_Flag_QuantumCoreRoom", comment: "量子芯室") },
            181: { NSLocalizedString("SpecializedIceHold", comment: "冰矿舱") },
            182: { NSLocalizedString("SpecializedAsteroidHold", comment: "小行星舱") },
        ]

        // 连续槽位共用同一个分区标题。
        addSlots(to: &names, ids: SlotFlag.low.ids) {
            NSLocalizedString("Main_KM_Low_Slots", comment: "低槽")
        }
        addSlots(to: &names, ids: SlotFlag.medium.ids) {
            NSLocalizedString("Main_KM_Medium_Slots", comment: "中槽")
        }
        addSlots(to: &names, ids: SlotFlag.high.ids) {
            NSLocalizedString("Main_KM_High_Slots", comment: "高槽")
        }
        addSlots(to: &names, ids: SlotFlag.rig.ids) {
            NSLocalizedString("Main_KM_Rig_Slots", comment: "改装槽")
        }
        addSlots(to: &names, ids: SlotFlag.subsystem.ids) {
            NSLocalizedString("Main_KM_Subsystem_Slots", comment: "子系统")
        }
        addSlots(to: &names, ids: SlotFlag.fighterTube.ids) {
            NSLocalizedString("Main_KM_Fighter_Tubes", comment: "战斗机发射管")
        }
        addSlots(to: &names, ids: SlotFlag.service.ids) {
            NSLocalizedString("Location_Flag_ServiceSlots", comment: "建筑服务槽位")
        }

        return names
    }()

    private static func addSlots(
        to names: inout [Int: () -> String],
        ids: ClosedRange<Int>,
        localizedName: @escaping () -> String
    ) {
        for id in ids {
            precondition(names[id] == nil, "Duplicate flag ID: \(id)")
            names[id] = localizedName
        }
    }

    /// 未配置专用名称的编号统一显示“其他”。
    static func getFlagName(for flagID: Int) -> String {
        localizedNames[flagID]?()
            ?? NSLocalizedString("Flag_Other", comment: "其他")
    }
}
