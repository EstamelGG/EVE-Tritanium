import SwiftUI

typealias IndustryJob = CharacterIndustryAPI.IndustryJob

/// 全局函数：获取活动类型对应的图标文件名
func getActivityTypeIcon(for activityId: Int) -> String {
    industryActivityIconAsset(for: activityId) + ".png"
}

/// 扩展IndustryJob来包含角色归属信息
struct IndustryJobWithOwner {
    let job: IndustryJob
    let ownerId: Int // 该工业项目归属的角色ID（人物工业为主号；军团工业为 installer_id）
    let isFromCorporation: Bool
}

/// 进度更新 Actor（用于线程安全地更新进度）
actor IndustryProgressActor {
    private var current: Int = 0
    private let total: Int
    private let onUpdate: (Int, Int) -> Void

    init(total: Int, onUpdate: @escaping (Int, Int) -> Void) {
        self.total = total
        self.onUpdate = onUpdate
    }

    func increment() {
        current += 1
        onUpdate(current, total)
    }
}

/// 技能加载进度更新 Actor（用于线程安全地更新技能加载进度）
actor SkillProgressActor {
    private var current: Int = 0
    private let total: Int
    private let onUpdate: (Int, Int) -> Void

    init(total: Int, onUpdate: @escaping (Int, Int) -> Void) {
        self.total = total
        self.onUpdate = onUpdate
    }

    func increment() {
        current += 1
        onUpdate(current, total)
    }
}

struct CharacterSlotDetail {
    let characterId: Int
    let characterName: String
    let manufacturingSlots: Int
    let researchSlots: Int
    let reactionSlots: Int
    let manufacturingRange: Int
    let researchRange: Int
    let reactionRange: Int
    let manufacturingUsed: Int
    let researchUsed: Int
    let reactionUsed: Int
}

struct IndustrySlotCounts: Equatable, Sendable {
    var manufacturing = 0
    var research = 0
    var reaction = 0

    static func used(by activities: some Sequence<Int>) -> Self {
        var counts = Self()
        for activity in activities {
            switch activity {
            case 1: counts.manufacturing += 1
            case 3, 4, 5, 8: counts.research += 1
            case 9: counts.reaction += 1
            default: break
            }
        }
        return counts
    }

    static func skillBonuses(in databaseManager: DatabaseManager) -> [Int: Self] {
        let query = """
        SELECT type_id, attribute_id, value
        FROM typeAttributes
        WHERE attribute_id IN (450, 471, 2661)
        """
        guard case let .success(rows) = databaseManager.executeQuery(query) else { return [:] }
        var bonuses: [Int: Self] = [:]
        for row in rows {
            guard let typeID = row["type_id"] as? Int, let attributeID = row["attribute_id"] as? Int,
                  let value = row["value"] as? Double
            else { continue }
            switch attributeID {
            case 450: bonuses[typeID, default: Self()].manufacturing = Int(value)
            case 471: bonuses[typeID, default: Self()].research = Int(value)
            case 2661: bonuses[typeID, default: Self()].reaction = Int(value)
            default: break
            }
        }
        return bonuses
    }

    static func capacity(for skills: [Int: CharacterSkill], bonuses: [Int: Self]) -> Self {
        var capacity = Self(manufacturing: 1, research: 1, reaction: 1)
        for (id, bonus) in bonuses {
            guard let level = skills[id]?.trained_skill_level else { continue }
            capacity.manufacturing += bonus.manufacturing * level
            capacity.research += bonus.research * level
            capacity.reaction += bonus.reaction * level
        }
        return capacity
    }
}
