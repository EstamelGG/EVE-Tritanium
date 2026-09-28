import Foundation

/// Inventory 槽位身份；接口可识别的范围与装配界面支持的范围分开处理。
enum SlotFlag: String, CaseIterable {
    case high = "HiSlots"
    case medium = "MedSlots"
    case low = "LoSlots"
    case rig = "RigSlots"
    case subsystem = "SubSystemSlots"
    case service = "ServiceSlots"
    case fighterTube = "FighterTubes"

    private var definition: (ids: ClosedRange<Int>, prefix: String) {
        switch self {
        case .high: return (27 ... 34, "HiSlot")
        case .medium: return (19 ... 26, "MedSlot")
        case .low: return (11 ... 18, "LoSlot")
        case .rig: return (92 ... 99, "RigSlot")
        case .subsystem: return (125 ... 132, "SubSystemSlot")
        case .service: return (164 ... 171, "ServiceSlot")
        case .fighterTube: return (159 ... 163, "FighterTube")
        }
    }

    var ids: ClosedRange<Int> {
        definition.ids
    }

    /// Fittings API 的槽位子集；战斗机发射管不属于 FittingFlag。
    var fittingCount: Int {
        switch self {
        case .rig: return 3
        case .subsystem: return 4
        case .fighterTube: return 0
        default: return ids.count
        }
    }

    var fittingIDs: [Int] {
        Array(ids.prefix(fittingCount))
    }

    var acceptsCharge: Bool {
        self == .high || self == .medium || self == .low
    }

    func id(at index: Int) -> Int? {
        guard index >= 0, index < ids.count else { return nil }
        return ids.lowerBound + index
    }

    func name(at index: Int) -> String? {
        guard id(at: index) != nil else { return nil }
        return "\(definition.prefix)\(index)"
    }

    static func location(for id: Int) -> (slot: SlotFlag, index: Int)? {
        guard let slot = allCases.first(where: { $0.ids.contains(id) }) else { return nil }
        return (slot, id - slot.ids.lowerBound)
    }

    /// 精确识别名称和历史别名，避免将 HiSlot99 等无效值归入有效槽位。
    static func location(for name: String) -> (slot: SlotFlag, index: Int)? {
        for slot in allCases {
            for index in 0 ..< slot.ids.count {
                if name == slot.name(at: index)
                    || (slot == .service && name == "StructureServiceSlot\(index)")
                    || (slot == .subsystem && name == "SubSystem\(index)")
                {
                    return (slot, index)
                }
            }
        }
        return nil
    }

    static func assetGroup(for name: String) -> String {
        location(for: name)?.slot.rawValue ?? name
    }
}

extension FittingFlag {
    var slot: SlotFlag? {
        SlotFlag.location(for: rawValue)?.slot
    }

    var slotIndex: Int? {
        self == .t3dModeSlot0 ? 0 : SlotFlag.location(for: rawValue)?.index
    }

    static func slot(_ slot: SlotFlag, index: Int) -> FittingFlag {
        guard index >= 0, index < slot.fittingCount,
              let name = slot.name(at: index) else { return .invalid }
        return FittingFlag(rawValue: name) ?? .invalid
    }

    static func fromInventorySlot(_ id: Int) -> FittingFlag? {
        guard let location = SlotFlag.location(for: id) else { return nil }
        let flag = slot(location.slot, index: location.index)
        return flag == .invalid ? nil : flag
    }

    var inventorySlotID: Int? {
        guard let location = SlotFlag.location(for: rawValue) else { return nil }
        return location.slot.id(at: location.index)
    }
}
