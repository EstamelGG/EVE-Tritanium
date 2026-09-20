import Foundation
import SwiftUI

/// 专精显示状态（详情页图标 / 专精浏览列表共用）
enum MasteryLevelState: Equatable {
    /// 飞船直接技能要求未全部满足
    case locked
    /// 当前专精等级 0-5
    case level(Int)
}

/// 专精 UI 辅助：由角色技能推导某飞船的显示状态、图标名与背景色
@MainActor
enum MasteryDisplayHelper {
    /// 计算某飞船的专精显示状态
    /// - Returns: 未登录 / 技能加载中 / 该船无专精数据时返回 nil（调用方不显示）
    static func state(
        typeID: Int,
        databaseManager: DatabaseManager,
        skillsManager: SharedSkillsManager
    ) -> MasteryLevelState? {
        guard !skillsManager.isLoading,
              !skillsManager.characterSkills.isEmpty,
              !skillsManager.masteryCertLevels.isEmpty,
              SDEMemoryStore.shipMasteryCerts[typeID] != nil
        else { return nil }

        let canFly = databaseManager.getDirectSkillRequirements(for: typeID)
            .allSatisfy { skillsManager.characterSkills[$0.skillID] ?? 0 >= $0.level }
        guard canFly else { return .locked }

        return .level(
            MasteryEvaluator.masteryLevel(
                typeID: typeID,
                certLevels: skillsManager.masteryCertLevels
            ) ?? 0
        )
    }

    /// 等级图标名：locked / 0-5
    static func iconName(for state: MasteryLevelState) -> String {
        switch state {
        case .locked: return "mastery_level_locked"
        case let .level(level): return "mastery_level_\(level)"
        }
    }

    /// 专精背景色：locked = 红，0-4 级 = 淡蓝，5 级 = 金黄
    static func backdropColor(for state: MasteryLevelState) -> Color {
        switch state {
        case .locked:
            return Color(red: 0x77 / 255.0, green: 0x2E / 255.0, blue: 0x2D / 255.0)
        case let .level(level) where level >= 5:
            return Color(red: 0x61 / 255.0, green: 0x54 / 255.0, blue: 0x37 / 255.0)
        case .level:
            return Color(red: 0x2B / 255.0, green: 0x3C / 255.0, blue: 0x57 / 255.0)
        }
    }

    /// 专精等级符号（下标 = 等级）
    static let levelSymbols = ["0", "I", "II", "III", "IV", "V"]

    /// 筛选项标题：nil = 全部，-1 = 不达标，-2 = 达标，0-5 = 专精等级
    static func filterTitle(_ filter: Int?) -> String {
        switch filter {
        case nil:
            return NSLocalizedString("Mastery_Filter_All", comment: "全部")
        case -1:
            return NSLocalizedString("Mastery_Filter_Locked", comment: "不达标")
        case -2:
            return NSLocalizedString("Mastery_Filter_Qualified", comment: "达标")
        case let level?:
            return "\(NSLocalizedString("Mastery_Detail_Title", comment: "专精")) \(levelSymbols[level])"
        }
    }

    /// 筛选匹配：-1 = 不达标（开不了），-2 = 达标（非不达标，含专精 0-5），0-5 = 对应专精等级
    static func matchesFilter(_ filter: Int, state: MasteryLevelState?) -> Bool {
        switch filter {
        case -1: return state == .locked
        case -2: return state != nil && state != .locked
        default: return state == .level(filter)
        }
    }
}

/// 飞船专精（Mastery）两步法计算器
///
/// 第一步：由角色技能字典计算认证满足矩阵（每个角色只需计算一次，约 4500 次整数比较）
/// 第二步：纯字典查表得出某物品的当前专精等级（每船几十次查找，不碰技能数据）
///
/// 静态数据来自 `SDEMemoryStore.certificateSkills` / `SDEMemoryStore.shipMasteryCerts`
enum MasteryEvaluator {
    /// 计算认证满足矩阵：certificateID → 该认证可达的最高等级（0-5）
    ///
    /// 判定规则：认证 N 级（对应 tierLevels 下标 N-1）要求该档位下所有技能
    /// 的档位值 ≤ 角色训练等级；档位值为 0 表示该档不要求此技能，直接跳过；
    /// 未训练的技能按 0 级处理。从 5 级往 1 级试探，第一个达标即最高等级。
    static func certificateLevels(characterSkills: [Int: Int]) -> [Int: Int] {
        var levels: [Int: Int] = [:]
        levels.reserveCapacity(SDEMemoryStore.certificateSkills.count)

        for (certificateID, requirements) in SDEMemoryStore.certificateSkills {
            var highest = 0

            tierLoop: for tier in stride(from: 5, through: 1, by: -1) {
                for requirement in requirements {
                    let requiredLevel = requirement.tierLevels[tier - 1]
                    if requiredLevel == 0 {
                        continue
                    } // 该档不要求此技能
                    let trainedLevel = characterSkills[requirement.skillID] ?? 0
                    if trainedLevel < requiredLevel {
                        continue tierLoop
                    }
                }
                highest = tier
                break tierLoop
            }

            levels[certificateID] = highest
        }
        return levels
    }

    /// 查表得出物品当前专精等级
    ///
    /// 判定规则：专精 N 级要求该等级认证列表中的每个认证都达到 N 级（certLevels >= N）。
    /// 数据本身累积嵌套（专精 N 列表包含专精 N-1 列表），从 5 往 1 找第一个达标等级即可。
    /// - Returns: 0-5（0 = 无专精）；该物品无专精数据时返回 nil
    static func masteryLevel(typeID: Int, certLevels: [Int: Int]) -> Int? {
        guard let levelCerts = SDEMemoryStore.shipMasteryCerts[typeID] else { return nil }

        for level in stride(from: 5, through: 1, by: -1) {
            guard let certs = levelCerts[level], !certs.isEmpty else { continue }
            if certs.allSatisfy({ (certLevels[$0] ?? 0) >= level }) {
                return level
            }
        }
        return 0
    }
}
