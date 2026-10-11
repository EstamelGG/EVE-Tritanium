import SwiftUI

struct SkillPointForLevelView: View {
    @Environment(\.locale) private var displayLocale
    let skillId: Int
    let characterId: Int?
    let databaseManager: DatabaseManager

    @State private var characterAttributes: CharacterAttributes?
    @State private var timeMultiplier: Int = 1
    @State private var skillPrimaryAttr: Int = 0
    @State private var skillSecondaryAttr: Int = 0

    private static let defaultAttributes = CharacterAttributes(
        charisma: 19,
        intelligence: 20,
        memory: 20,
        perception: 20,
        willpower: 20,
        bonus_remaps: 0,
        accrued_remap_cooldown_date: nil,
        last_remap_date: nil
    )

    private var skillPointsPerHour: Double {
        guard skillPrimaryAttr > 0, skillSecondaryAttr > 0 else { return 0 }
        let attributes = characterAttributes ?? Self.defaultAttributes
        return Double(
            SkillTrainingCalculator.calculateTrainingRate(
                primaryAttrId: skillPrimaryAttr,
                secondaryAttrId: skillSecondaryAttr,
                attributes: attributes
            ) ?? 0
        )
    }

    private func skillPoints(for level: Int) -> Int {
        SkillProgressCalculator.baseSkillPoints[level - 1] * timeMultiplier
    }

    var body: some View {
        Section(
            header: Text(NSLocalizedString("Main_Database_Skill_Level_Detail", comment: ""))
                .font(.headline)
        ) {
            ForEach(1 ... 5, id: \.self) { level in
                let requiredSP = skillPoints(for: level)
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(FormatUtil.format(Double(requiredSP))) SP")
                            .font(.body)
                        Text(
                            "\(FormatUtil.formatTrainingDuration(skillPoints: requiredSP, skillPointsPerHour: skillPointsPerHour)) (\(FormatUtil.format(skillPointsPerHour))/h)"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(
                        String.localizedStringWithFormat(
                            NSLocalizedString("Misc_Level_Short", comment: "lv%d"), 0
                        )
                            + " → "
                            + String(
                                format: NSLocalizedString("Misc_Level_Short", comment: "lv%d"),
                                level
                            )
                    )
                    .font(.body)
                    .foregroundColor(.secondary)
                }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        }
        .task {
            if let multiplier = SkillTreeManager.shared.trainingTimeMultiplier(for: skillId) {
                timeMultiplier = Int(multiplier)
            }

            if let attrs = SkillTrainingCalculator.getSkillAttributes(
                skillId: skillId,
                databaseManager: databaseManager
            ) {
                skillPrimaryAttr = attrs.primary
                skillSecondaryAttr = attrs.secondary
            }

            guard let characterId else { return }
            characterAttributes = await loadAttributesFromAPI(characterId: characterId)
            if characterAttributes != nil {
                Logger.debug("从API加载角色属性成功")
            } else {
                Logger.debug("API中未找到角色属性，使用默认值")
            }
        }
    }

    private func loadAttributesFromAPI(characterId: Int) async -> CharacterAttributes? {
        do {
            return try await CharacterSkillsAPI.shared.fetchAttributes(
                characterId: characterId,
                forceRefresh: false
            )
        } catch {
            Logger.error("获取角色属性失败: \(error)")
            return nil
        }
    }
}
