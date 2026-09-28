import SwiftUI

enum FittingSlotType: String, CaseIterable {
    case subSystemSlots = "SubSystemSlots"
    case hiSlots = "HiSlots"
    case medSlots = "MedSlots"
    case loSlots = "LoSlots"
    case rigSlots = "RigSlots"
    case t3dModeSlot = "T3DModeSlot"

    var localizedName: String {
        switch self {
        case .subSystemSlots:
            return NSLocalizedString("Location_Flag_SubSystemSlots", comment: "")
        case .hiSlots:
            return NSLocalizedString("Location_Flag_HiSlots", comment: "")
        case .medSlots:
            return NSLocalizedString("Location_Flag_MedSlots", comment: "")
        case .loSlots:
            return NSLocalizedString("Location_Flag_LoSlots", comment: "")
        case .rigSlots:
            return NSLocalizedString("Location_Flag_RigSlots", comment: "")
        case .t3dModeSlot:
            return NSLocalizedString("Location_Flag_T3DModeSlot", comment: "")
        }
    }

    var slot: SlotFlag? {
        switch self {
        case .hiSlots: return .high
        case .medSlots: return .medium
        case .loSlots: return .low
        case .rigSlots: return .rig
        case .subSystemSlots: return .subsystem
        case .t3dModeSlot: return nil
        }
    }

    var flags: [FittingFlag] {
        guard let slot else { return [.t3dModeSlot0] }
        return (0 ..< slot.fittingCount).map { .slot(slot, index: $0) }
    }

    /// 获取指定索引的槽位flag标识
    func getSlotFlag(index: Int) -> FittingFlag {
        guard index >= 0, index < flags.count else { return .invalid }
        return flags[index]
    }
}

/// 装备分组数据结构
struct ModuleGroup: Identifiable {
    /// 稳定标识（用于折叠/展开动画时的行匹配）：模块组为 "typeId-mutationKey"，空槽位组为 "empty"
    let id: String
    let typeId: Int
    let name: String
    let iconFileName: String?
    var modules: [SimModule]
    let emptySlots: [FittingFlag]

    var totalCount: Int {
        return modules.count + emptySlots.count
    }
}

class SlotState: ObservableObject, Identifiable {
    var id: String {
        slotFlag?.rawValue ?? "none"
    }

    @Published var slotFlag: FittingFlag?
}

/// 保留FittingFlag的Identifiable扩展
extension FittingFlag: Identifiable {
    public var id: String {
        rawValue
    }
}
