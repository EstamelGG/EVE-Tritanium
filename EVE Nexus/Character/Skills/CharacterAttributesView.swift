import SwiftUI

struct CharacterAttributesView: View {
    @Environment(\.timeZone) private var displayTimeZone
    let characterId: Int
    @State private var attributes: CharacterAttributes?
    @State private var isLoading = true
    @State private var implantBonuses: ImplantAttributes?
    @State private var hasBooster = false
    @State private var boosterValue = 0

    var body: some View {
        List {
            Section {
                if let attributes = attributes {
                    AttributeRow(
                        name: NSLocalizedString("Character_Attribute_Perception", comment: ""),
                        icon: "perception", value: attributes.perception
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

                    AttributeRow(
                        name: NSLocalizedString("Character_Attribute_Memory", comment: ""),
                        icon: "memory", value: attributes.memory
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

                    AttributeRow(
                        name: NSLocalizedString("Character_Attribute_Willpower", comment: ""),
                        icon: "willpower", value: attributes.willpower
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

                    AttributeRow(
                        name: NSLocalizedString("Character_Attribute_Intelligence", comment: ""),
                        icon: "intelligence", value: attributes.intelligence
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

                    AttributeRow(
                        name: NSLocalizedString("Character_Attribute_Charisma", comment: ""),
                        icon: "charisma", value: attributes.charisma
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                } else if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    Text(NSLocalizedString("Character_Attributes_Load_Failed", comment: ""))
                        .foregroundColor(.secondary)
                }
            } header: {
                Text(NSLocalizedString("Character_Attributes_Basic", comment: ""))
            } footer: {
                if hasBooster {
                    Text(
                        String(
                            format: NSLocalizedString(
                                "Character_Attributes_Has_Booster", comment: "人物使用了加速器，每个属性+%d"
                            ),
                            boosterValue
                        )
                    )
                }
            }

            if let attributes = attributes {
                Section {
                    if let bonusRemaps = attributes.bonus_remaps {
                        HStack {
                            Text(
                                NSLocalizedString("Character_Attributes_Bonus_Remaps", comment: "")
                            )
                            Spacer()
                            Text("\(bonusRemaps)")
                                .foregroundColor(.secondary)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }

                    if let cooldownDate = attributes.accrued_remap_cooldown_date {
                        HStack {
                            Text(NSLocalizedString("Character_Attributes_Next_Remap", comment: ""))
                            Spacer()
                            Text(formatNextRemapTime(cooldownDate))
                                .foregroundColor(.secondary)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }
                } header: {
                    Text(NSLocalizedString("Character_Attributes_Remap", comment: ""))
                }
            }
        }
        .refreshable {
            await fetchAttributes(forceRefresh: true)
        }
        .navigationTitle(NSLocalizedString("Character_Attributes_Title", comment: ""))
        .onAppear {
            Task {
                await fetchAttributes()
            }
        }
    }

    private func formatNextRemapTime(_ dateString: String) -> String {
        guard let date = FormatUtil.parseUTCDate(dateString) else {
            return NSLocalizedString("Character_Never", comment: "")
        }

        if Date() >= date {
            return NSLocalizedString("Character_Attributes_Ready_Now", comment: "")
        }

        return FormatUtil.formatDateToLocalTime(date)
    }

    private func fetchAttributes(forceRefresh: Bool = false) async {
        isLoading = true
        defer { isLoading = false }

        do {
            // 获取角色属性
            let attrs = try await CharacterSkillsAPI.shared.fetchAttributes(
                characterId: characterId, forceRefresh: forceRefresh
            )

            // 获取植入体加成
            let implants = await SkillTrainingCalculator.getImplantBonuses(
                characterId: characterId, forceRefresh: forceRefresh
            )

            // 检测是否有加速器
            let boosterBonus = SkillTrainingCalculator.detectBoosterBonus(
                currentAttributes: attrs,
                implantBonuses: implants
            )

            await MainActor.run {
                attributes = attrs
                implantBonuses = implants
                hasBooster = boosterBonus > 0
                boosterValue = boosterBonus
            }
        } catch {
            Logger.error("获取角色属性失败: \(error)")
        }
    }
}

struct AttributeRow: View {
    @Environment(\.timeZone) private var displayTimeZone
    let name: String
    let icon: String
    let value: Int

    var body: some View {
        HStack {
            Image(icon)
                .resizable()
                .frame(width: 32, height: 32)
                .cornerRadius(6)
                .drawingGroup()
            Text(name)
            Spacer()
            Text("\(value)")
                .foregroundColor(.secondary)
        }
    }
}
