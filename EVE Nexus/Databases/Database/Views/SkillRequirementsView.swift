import SwiftUI

/// 单个技能要求行
struct SkillRequirementRow: View {
    let skillID: Int
    let level: Int
    let timeMultiplier: Double?
    @ObservedObject var databaseManager: DatabaseManager
    let currentLevel: Int?
    let trainingLevel: Int?
    let characterAttributes: CharacterAttributes?
    let skillAttributes: (primary: Int, secondary: Int)?

    private func skillPoints(at level: Int) -> Int {
        SkillTreeManager.skillPoints(level: level, multiplier: timeMultiplier) ?? 0
    }

    private var currentSP: Int {
        let cl = normalizedCurrentLevel
        return cl > 0 ? skillPoints(at: cl) : 0
    }

    private var requiredSP: Int {
        skillPoints(at: level)
    }

    private var missingSP: Int {
        max(0, requiredSP - currentSP)
    }

    private var estimatedTrainingTime: TimeInterval? {
        guard let attributes = characterAttributes,
              let skillAttrs = skillAttributes,
              missingSP > 0,
              normalizedCurrentLevel < level,
              let pointsPerHour = SkillTrainingCalculator.calculateTrainingRate(
                  primaryAttrId: skillAttrs.primary,
                  secondaryAttrId: skillAttrs.secondary,
                  attributes: attributes
              ),
              pointsPerHour > 0
        else { return nil }
        return Double(missingSP) / Double(pointsPerHour) * 3600
    }

    private var normalizedCurrentLevel: Int {
        guard let cl = currentLevel, cl >= 0 else { return 0 }
        return min(cl, 5)
    }

    /// 第二行左侧：SP 进度
    private var spLineText: Text? {
        if currentLevel == nil {
            return Text(NSLocalizedString("Misc_Loading", comment: ""))
        } else if let cl = currentLevel, cl == -2 {
            if requiredSP > 0 {
                return Text("\(FormatUtil.format(Double(requiredSP))) SP")
            }
            return nil
        } else {
            return Text("\(FormatUtil.format(Double(currentSP)))/\(FormatUtil.format(Double(requiredSP))) SP")
        }
    }

    /// 第三行：预计训练时间（左）+ 未注入提示（右）
    @ViewBuilder
    private var statusLine: some View {
        let cl = currentLevel
        let isUnmet = (cl ?? -2) >= 0 && (cl ?? -2) < level
        let showNotInjected = cl == -1
        let time: TimeInterval? = (isUnmet || showNotInjected) ? estimatedTrainingTime : nil

        if showNotInjected || (time ?? 0) > 0 {
            HStack(spacing: 4) {
                if let time, time > 0 {
                    Text("\(FormatUtil.formatCompactDuration(time))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if showNotInjected {
                    Text(NSLocalizedString("Misc_Skill_Not_Injected", comment: ""))
                        .font(.caption)
                        .foregroundColor(.red.opacity(0.8))
                }
            }
        }
    }

    var body: some View {
        if let skillName = SkillTreeManager.shared.getSkillName(for: skillID) {
            NavigationLink {
                ItemInfoMap.getItemInfoView(
                    itemID: skillID,
                    databaseManager: databaseManager
                )
            } label: {
                HStack(spacing: 12) {
                    // 左侧：状态图标
                    statusIcon

                    // 右侧：三行文本
                    VStack(alignment: .leading, spacing: 2) {
                        // 第一行：技能名（左）+ 等级方块（右）
                        HStack {
                            Text(skillName)
                                .font(.body)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 8)
                            SkillLevelIndicator(
                                currentLevel: currentLevel ?? 0,
                                trainingLevel: trainingLevel ?? 0,
                                isTraining: trainingLevel.map { $0 > max(currentLevel ?? 0, 0) } ?? false,
                                requiredLevel: level
                            )
                        }

                        // 第二行：SP（左）+ 等级数字（右）
                        HStack(spacing: 4) {
                            if let sp = spLineText {
                                sp
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .layoutPriority(0)
                            }
                            Spacer(minLength: 4)
                            if let cl = currentLevel, cl >= -1 {
                                Text("\(normalizedCurrentLevel)/\(level)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .layoutPriority(1)
                            } else if let cl = currentLevel, cl == -2 {
                                // 无激活角色：仅显示所需等级
                                Text("Lv.\(level)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .layoutPriority(1)
                            }
                        }

                        // 第三行：预计训练时间 / 未注入提示
                        statusLine
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if currentLevel == nil {
            ProgressView()
                .frame(width: 32, height: 32)
                .scaleEffect(0.8)
        } else if let currentLevel, currentLevel == -2 {
            Image("skill")
                .resizable()
                .frame(width: 32, height: 32)
                .clipShape(Circle())
        } else if let currentLevel, currentLevel == -1 {
            Image(systemName: "xmark.circle.fill")
                .frame(width: 32, height: 32)
                .foregroundColor(.red)
        } else if let currentLevel, currentLevel >= level {
            Image(systemName: "checkmark.circle.fill")
                .frame(width: 32, height: 32)
                .foregroundColor(.green)
        } else {
            Image(systemName: "circle")
                .frame(width: 32, height: 32)
                .foregroundColor(.primary)
        }
    }
}

/// 技能要求组显示组件
struct SkillRequirementsView: View {
    let typeID: Int
    let groupName: String
    @ObservedObject var databaseManager: DatabaseManager
    @AppStorage("currentCharacterId") private var currentCharacterId: Int = 0
    @StateObject private var skillsManager = SharedSkillsManager.shared
    @State private var characterAttributes: CharacterAttributes?

    private var requirements: [(skillID: Int, level: Int, timeMultiplier: Double?)] {
        // 未满足的技能排在前面，确保用户先看到缺失项；满足组内按原规则（等级降序）
        let characterSkills = skillsManager.characterSkills
        return SkillTreeManager.shared
            .getDeduplicatedSkillRequirements(
                for: typeID,
                databaseManager: databaseManager
            )
            .sorted { lhs, rhs in
                let lhsUnmet = (characterSkills[lhs.skillID] ?? 0) < lhs.level
                let rhsUnmet = (characterSkills[rhs.skillID] ?? 0) < rhs.level
                if lhsUnmet != rhsUnmet {
                    return lhsUnmet
                }
                if lhs.level == rhs.level {
                    return lhs.skillID > rhs.skillID
                }
                return lhs.level > rhs.level
            }
    }

    /// 未达标技能的训练主/副属性（供行内预计训练时间使用）
    private func unmetSkillAttributes(
        for requirements: [(skillID: Int, level: Int, timeMultiplier: Double?)]
    ) -> [Int: (primary: Int, secondary: Int)] {
        let unmetSkillIDs = requirements.compactMap { requirement -> Int? in
            guard let currentLevel = skillsManager.getSkillLevel(for: requirement.skillID),
                  currentLevel != -2,
                  currentLevel < requirement.level
            else { return nil }
            return requirement.skillID
        }
        guard !unmetSkillIDs.isEmpty else { return [:] }
        return SkillTreeManager.shared.trainingAttributes(forSkillIDs: unmetSkillIDs)
    }

    var body: some View {
        // requirements 底层含 SQL 查询，单次渲染只求值一次
        let requirements = self.requirements
        if !requirements.isEmpty {
            let unmetAttrs = unmetSkillAttributes(for: requirements)
            let stats = SkillRequirementStats(
                requirements: requirements,
                characterSkills: skillsManager.characterSkills,
                hasCharacter: currentCharacterId != 0,
                attributes: characterAttributes
            )

            Section(
                header: HStack {
                    Text(groupName)
                        .font(.headline)
                    if currentCharacterId != 0 && stats.missingPoints > 0 && stats.trainingTime > 0 {
                        Spacer()
                        Text("(\(FormatUtil.formatCompactDuration(stats.trainingTime)))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                },
                footer: Text(stats.footerText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            ) {
                ForEach(requirements, id: \.skillID) { requirement in
                    let curLevel = skillsManager.getSkillLevel(for: requirement.skillID)
                    let trainLevel = skillsManager.getTrainingTargetLevel(for: requirement.skillID)
                    SkillRequirementRow(
                        skillID: requirement.skillID,
                        level: requirement.level,
                        timeMultiplier: requirement.timeMultiplier,
                        databaseManager: databaseManager,
                        currentLevel: curLevel,
                        trainingLevel: trainLevel,
                        characterAttributes: characterAttributes,
                        skillAttributes: unmetAttrs[requirement.skillID]
                    )
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }
            .onAppear {
                skillsManager.loadAttributes(
                    characterId: currentCharacterId,
                    into: $characterAttributes
                )
            }
        }
    }
}
