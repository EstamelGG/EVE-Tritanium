import SwiftUI

/// 将装配技能保存到新技能计划
enum AddFittingSkillsToPlanSheet {
    /// 保存装配所需全部技能到新计划（含已满足和未满足的技能，生成完整队列）
    /// - Parameters:
    ///   - requiredSkills: 装配所需的全部技能（含飞船、装备、弹药、无人机、货舱、舰载机）
    ///   - characterId: 角色ID
    ///   - planName: 计划名称
    ///   - databaseManager: 数据库管理器
    /// - Returns: 保存的计划名称，空名称返回 nil；保存失败时抛出错误。
    static func saveMissingSkillsToPlan(
        missingSkills: [(skillID: Int, requiredLevel: Int, currentLevel: Int, skillName: String)],
        characterId: Int,
        planName: String,
        databaseManager: DatabaseManager
    ) async throws -> String? {
        let name = SkillPlanNaming.normalized(planName)
        guard !name.isEmpty else { return nil }

        var skillsToAdd: [(skillId: Int, skillName: String, level: Int)] = []
        var addedSkills: Set<Int> = []
        var skillLevels: [Int: Int] = [:]
        let currentSkillLevels = await getCurrentSkillLevels(characterId: characterId)

        for item in missingSkills {
            let collected = SkillPlanHelper.collectSkillsToAdd(
                skillId: item.skillID,
                skillName: item.skillName,
                targetLevel: item.requiredLevel,
                databaseManager: databaseManager,
                currentSkillLevels: currentSkillLevels,
                addedSkills: &addedSkills,
                skillLevels: &skillLevels
            )
            skillsToAdd.append(contentsOf: collected)
        }

        // 待训练技能（保存时统一修正队列）
        var plannedSkills = skillsToAdd.map { skill -> PlannedSkill in
            let skillName = skill.skillName
            return PlannedSkill(
                id: UUID(),
                skillID: skill.skillId,
                skillName: skillName,
                targetLevel: skill.level
            )
        }

        // 已满足的技能也加入队列（作为完整清单）
        let completedSkills = missingSkills
            .filter { $0.currentLevel >= $0.requiredLevel }
            .sorted { $0.skillID < $1.skillID }
        for item in completedSkills {
            plannedSkills.insert(
                PlannedSkill(
                    id: UUID(),
                    skillID: item.skillID,
                    skillName: item.skillName,
                    targetLevel: item.requiredLevel
                ),
                at: 0
            )
        }

        let newPlan = SkillPlan(
            id: UUID(),
            name: name,
            skills: plannedSkills,
            lastUpdated: Date()
        )

        let savedPlan = try SkillPlanFileManager.shared.saveSkillPlan(
            characterId: characterId, plan: newPlan, databaseManager: databaseManager
        )
        return savedPlan.name
    }

    private static func getCurrentSkillLevels(characterId: Int) async -> [Int: Int] {
        guard characterId != 0 else { return [:] }
        do {
            let (response, queue) = try await CharacterSkillsAPI.shared.fetchCharacterSkillsAndQueue(
                characterId: characterId,
                forceRefresh: false
            )
            let baseSkills = Dictionary(uniqueKeysWithValues: response.skillsMap.map { ($0.key, $0.value.trained_skill_level) })
            return CharacterSkillsUtils.mergeCompletedQueueIntoSkills(baseSkills: baseSkills, queue: queue)
        } catch {
            Logger.error("加载角色技能失败: \(error)")
            return [:]
        }
    }
}
