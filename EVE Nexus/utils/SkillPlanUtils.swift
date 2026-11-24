import Foundation

/// 技能计划辅助类 - 处理技能添加的共享逻辑
class SkillPlanHelper {
    /// 添加技能及其所有前置依赖
    static func collectSkillsToAdd(
        skillId: Int,
        skillName: String,
        targetLevel: Int,
        databaseManager: DatabaseManager,
        currentSkillLevels: [Int: Int],
        addedSkills: inout Set<Int>,
        skillLevels: inout [Int: Int]
    ) -> [(skillId: Int, skillName: String, level: Int)] {
        Logger.debug(" 开始添加技能到计划 - 技能: \(skillName) (ID: \(skillId)), 等级: \(targetLevel)")

        let currentTargetLevel = currentSkillLevels[skillId] ?? 0

        // 收集要添加的所有技能（用于批量添加）
        var skillsToAdd: [(skillId: Int, skillName: String, level: Int)] = []

        // 只在技能从0级添加时检查前置依赖
        if !addedSkills.contains(skillId) {
            Logger.debug(" 技能未添加，检查前置技能依赖")

            // 获取所有前置技能
            let prerequisites = getAllPrerequisites(
                skillId: skillId,
                requiredLevel: targetLevel,
                databaseManager: databaseManager
            )

            // 收集前置技能
            for prereq in prerequisites {
                let currentLevel = currentSkillLevels[prereq.skillId] ?? 0
                let requiredLevel = prereq.requiredLevel

                if !addedSkills.contains(prereq.skillId) {
                    let prereqSkillName = getSkillName(skillId: prereq.skillId, databaseManager: databaseManager)
                    skillsToAdd.append((skillId: prereq.skillId, skillName: prereqSkillName, level: requiredLevel))
                    addedSkills.insert(prereq.skillId)
                    skillLevels[prereq.skillId] = requiredLevel
                } else if currentLevel < requiredLevel {
                    let prereqSkillName = getSkillName(skillId: prereq.skillId, databaseManager: databaseManager)
                    skillsToAdd.append((skillId: prereq.skillId, skillName: prereqSkillName, level: requiredLevel))
                    skillLevels[prereq.skillId] = requiredLevel
                }
            }

            // 收集目标技能所有等级
            for currentLevel in 1 ... targetLevel {
                skillsToAdd.append((skillId: skillId, skillName: skillName, level: currentLevel))
            }
            addedSkills.insert(skillId)
            skillLevels[skillId] = targetLevel
        } else if currentTargetLevel < targetLevel {
            // 升级技能
            for currentLevel in (currentTargetLevel + 1) ... targetLevel {
                skillsToAdd.append((skillId: skillId, skillName: skillName, level: currentLevel))
            }
            skillLevels[skillId] = targetLevel
        }

        return skillsToAdd
    }

    /// 用修正后的队列重建计划技能列表，保留已有条目的身份和名称。
    static func rebuildSkills(
        corrected: [(skillId: Int, level: Int)],
        existing: [PlannedSkill]
    ) -> [PlannedSkill] {
        let lookup = Dictionary(
            existing.map { ("\($0.skillID)_\($0.targetLevel)", $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return corrected.map { skill in
            let key = "\(skill.skillId)_\(skill.level)"
            if let existingSkill = lookup[key] {
                return existingSkill
            }
            let skillName = SkillTreeManager.shared.getSkillName(for: skill.skillId)
                ?? "Unknown Skill (\(skill.skillId))"
            return PlannedSkill(
                id: UUID(),
                skillID: skill.skillId,
                skillName: skillName,
                targetLevel: skill.level
            )
        }
    }

    /// 获取前置技能（按依赖深度排序）
    private static func getAllPrerequisites(
        skillId: Int,
        requiredLevel _: Int,
        databaseManager: DatabaseManager
    ) -> [(skillId: Int, requiredLevel: Int)] {
        let requirements = SkillTreeManager.shared.getDeduplicatedSkillRequirements(
            for: skillId, databaseManager: databaseManager
        )

        // 计算每个技能的依赖深度
        var skillDepths: [Int: Int] = [:]
        for requirement in requirements {
            let depth = calculateSkillDepth(skillId: requirement.skillID, databaseManager: databaseManager)
            skillDepths[requirement.skillID] = depth
        }

        var allPrerequisites: [(skillId: Int, requiredLevel: Int)] = []
        for requirement in requirements {
            for level in 1 ... requirement.level {
                allPrerequisites.append((skillId: requirement.skillID, requiredLevel: level))
            }
        }

        // 按深度排序（深度小的先=最底层的前置优先）
        return allPrerequisites.sorted { first, second in
            let depth1 = skillDepths[first.skillId] ?? 0
            let depth2 = skillDepths[second.skillId] ?? 0

            if depth1 != depth2 {
                return depth1 < depth2 // 深度小的优先（最底层优先）
            } else if first.skillId == second.skillId {
                return first.requiredLevel < second.requiredLevel // 同一技能，等级从低到高
            } else {
                return first.skillId < second.skillId // 同深度，按 ID 排序
            }
        }
    }

    /// 计算技能的依赖深度（递归）
    private static func calculateSkillDepth(skillId: Int, databaseManager: DatabaseManager) -> Int {
        let directReqs = SkillTreeManager.shared.getDeduplicatedSkillRequirements(
            for: skillId, databaseManager: databaseManager
        )

        if directReqs.isEmpty {
            return 0 // 没有前置，深度为0
        }

        // 深度 = 1 + 所有前置技能的最大深度
        let maxPrereqDepth = directReqs.map { req in
            calculateSkillDepth(skillId: req.skillID, databaseManager: databaseManager)
        }.max() ?? 0

        return 1 + maxPrereqDepth
    }

    /// 获取技能名称
    private static func getSkillName(skillId: Int, databaseManager _: DatabaseManager) -> String {
        if let name = SkillTreeManager.shared.getSkillName(for: skillId) {
            return name
        }
        return ItemInfoMap.typeName(for: skillId) ?? "Unknown Skill (\(skillId))"
    }
}

// MARK: - 技能队列修正工具类

/// 技能队列修正工具类：补齐前置依赖、等级依赖并去重（使用内存技能树，无 SQL）
class SkillQueueCorrector {
    private var depthCache: [Int: Int] = [:]

    /// 修正技能队列：补齐前置依赖、等级依赖并去重
    /// - Parameter inputSkills: 输入的技能ID+目标等级列表（按用户输入顺序）
    /// - Returns: 修正后的完整技能队列（包含所有前置依赖，按正确顺序排列，无重复）
    func correctSkillQueue(inputSkills: [(skillId: Int, level: Int)]) -> [(skillId: Int, level: Int)] {
        depthCache.removeAll()
        var result: [(skillId: Int, level: Int)] = []
        var addedSkills: Set<String> = []

        Logger.debug("[队列修正] 开始修正技能队列，输入 \(inputSkills.count) 个技能")

        for inputSkill in inputSkills {
            let skillsToAdd = getSkillsWithPrerequisites(skillId: inputSkill.skillId, targetLevel: inputSkill.level)

            for skill in skillsToAdd {
                let key = "\(skill.skillId)_\(skill.level)"
                if !addedSkills.contains(key) {
                    result.append(skill)
                    addedSkills.insert(key)
                }
            }
        }

        Logger.debug("[队列修正] 修正完成，输出 \(result.count) 个技能等级")
        return result
    }

    // MARK: - Private Methods

    private func getSkillsWithPrerequisites(skillId: Int, targetLevel: Int) -> [(skillId: Int, level: Int)] {
        var allSkills: [(skillId: Int, level: Int)] = []
        allSkills.append(contentsOf: getAllPrerequisitesForSkill(skillId: skillId))

        let targetSkillDepth = skillDepth(for: skillId)
        for level in 1 ... targetLevel {
            allSkills.append((skillId: skillId, level: level))
        }

        allSkills.sort { first, second in
            let depth1 = first.skillId == skillId ? targetSkillDepth : skillDepth(for: first.skillId)
            let depth2 = second.skillId == skillId ? targetSkillDepth : skillDepth(for: second.skillId)

            if depth1 != depth2 {
                return depth1 < depth2
            } else if first.skillId == second.skillId {
                return first.level < second.level
            } else {
                return first.skillId < second.skillId
            }
        }

        return allSkills
    }

    private func getAllPrerequisitesForSkill(skillId: Int) -> [(skillId: Int, level: Int)] {
        let skillLevels = SkillTreeManager.shared.prerequisiteMaxLevels(for: skillId)

        var skillDepths: [Int: Int] = [:]
        for prereqSkillId in skillLevels.keys {
            skillDepths[prereqSkillId] = skillDepth(for: prereqSkillId)
        }

        var allPrerequisites: [(skillId: Int, level: Int)] = []
        for (prereqSkillId, maxLevel) in skillLevels {
            for level in 1 ... maxLevel {
                allPrerequisites.append((skillId: prereqSkillId, level: level))
            }
        }

        return allPrerequisites.sorted { first, second in
            let depth1 = skillDepths[first.skillId] ?? 0
            let depth2 = skillDepths[second.skillId] ?? 0

            if depth1 != depth2 {
                return depth1 < depth2
            } else if first.skillId == second.skillId {
                return first.level < second.level
            } else {
                return first.skillId < second.skillId
            }
        }
    }

    private func skillDepth(for skillId: Int) -> Int {
        if let cached = depthCache[skillId] {
            return cached
        }

        let directReqs = SkillTreeManager.shared.directSkillRequirements(for: skillId)
        guard !directReqs.isEmpty else {
            depthCache[skillId] = 0
            return 0
        }

        let depth = 1 + (directReqs.map { skillDepth(for: $0.skillID) }.max() ?? 0)
        depthCache[skillId] = depth
        return depth
    }
}
