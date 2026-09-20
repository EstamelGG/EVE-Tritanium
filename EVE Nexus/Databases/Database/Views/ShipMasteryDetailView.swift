import SwiftUI

/// 飞船专精详情页：顶部 0-5 等级切换按钮
/// - 专精 0：飞船本身的技能要求（直接复用 SkillRequirementsView）
/// - 专精 1-5：该等级认证列表，认证可折叠展开技能明细（复用 SkillRequirementRow）
struct ShipMasteryDetailView: View {
    let typeID: Int
    @ObservedObject var databaseManager: DatabaseManager

    @AppStorage("currentCharacterId") private var currentCharacterId: Int = 0
    @StateObject private var skillsManager = SharedSkillsManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedLevel = 0
    @State private var characterAttributes: CharacterAttributes?
    @State private var showAddPlanAlert = false
    @State private var planNameText = ""
    @State private var showPlanSavedAlert = false
    @State private var savedPlanName = ""

    /// 专精显示状态（复用 MasteryDisplayHelper，与物品详情页/专精浏览列表同源）
    /// 未登录 / 加载中 / 该船无专精数据时为 nil
    private var masteryDisplayState: MasteryLevelState? {
        MasteryDisplayHelper.state(
            typeID: typeID,
            databaseManager: databaseManager,
            skillsManager: skillsManager
        )
    }

    /// 当前角色的专精等级（未登录/加载中/驾驶技能不满足时为 0）
    private func currentMasteryLevel(from state: MasteryLevelState?) -> Int {
        if case let .level(level) = state ?? .locked {
            return level
        }
        return 0
    }

    /// 该专精等级的认证列表（按名称排序）
    private var levelCerts: [Int] {
        guard let certs = SDEMemoryStore.shipMasteryCerts[typeID]?[selectedLevel],
              !certs.isEmpty
        else { return [] }
        return certs.sorted {
            (SDEMemoryStore.certificateName(for: $0) ?? "") < (SDEMemoryStore.certificateName(for: $1) ?? "")
        }
    }

    var body: some View {
        // masteryDisplayState 底层含 SQL 查询，单次渲染只求值一次
        let masteryState = masteryDisplayState
        let currentLevel = currentMasteryLevel(from: masteryState)

        List {
            Section {
                HStack(spacing: 8) {
                    ForEach(0 ..< 6, id: \.self) { level in
                        masteryTabButton(for: level, masteryState: masteryState)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            if selectedLevel == 0 {
                SkillRequirementsView(
                    typeID: typeID,
                    groupName: NSLocalizedString("Mastery_Skill_Req_Header", comment: "技能要求"),
                    databaseManager: databaseManager
                )
            } else if !levelCerts.isEmpty {
                // 该等级去重后的技能要求 → 共享统计（SP 总量/缺口/训练时间）
                let certReqs = dedupedRequirements
                let stats = SkillRequirementStats(
                    requirements: certReqs.map {
                        (
                            skillID: $0.key,
                            level: $0.value,
                            timeMultiplier: SkillTreeManager.shared.trainingTimeMultiplier(for: $0.key)
                        )
                    },
                    characterSkills: skillsManager.characterSkills,
                    hasCharacter: currentCharacterId != 0,
                    attributes: characterAttributes
                )
                let timeText = stats.trainingTime > 0
                    ? FormatUtil.formatCompactDuration(stats.trainingTime) : nil

                Section(
                    header: HStack {
                        Text("\(NSLocalizedString("Mastery_Detail_Title", comment: "专精")) \(MasteryDisplayHelper.levelSymbols[selectedLevel])")
                            .font(.headline)
                        Spacer()
                        if let timeText {
                            Text(timeText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    },
                    footer: Text(certReqs.isEmpty ? "" : stats.footerText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                ) {
                    ForEach(levelCerts, id: \.self) { certificateID in
                        MasteryCertRow(
                            certificateID: certificateID,
                            requiredLevel: selectedLevel,
                            databaseManager: databaseManager,
                            characterAttributes: characterAttributes
                        )
                    }
                    .listRowInsets(itemSectionRowInsets)
                }
            }

            // 第二个 section：添加到技能计划
            Section {
                Button {
                    planNameText = defaultPlanName
                    showAddPlanAlert = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text(NSLocalizedString("Fitting_Add_To_Skill_Plan", comment: "添加到技能计划"))
                    }
                }
            }
            .listRowInsets(itemSectionRowInsets)
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Mastery_Detail_Title", comment: "专精"))
        .alert(
            NSLocalizedString("Fitting_Add_To_Skill_Plan", comment: "添加到技能计划"),
            isPresented: $showAddPlanAlert
        ) {
            TextField(
                NSLocalizedString("Main_Skills_Plan_Name", comment: "计划名称"),
                text: $planNameText
            )
            Button(NSLocalizedString("Main_EVE_Mail_Cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("Misc_Save", comment: "保存")) {
                addToSkillPlan()
            }
        } message: {
            Text(
                String.localizedStringWithFormat(
                    NSLocalizedString("Mastery_Plan_Skills_Count", comment: "专精技能共 %d 项"),
                    planRequirements.count
                )
            )
        }
        .alert(
            NSLocalizedString("Fitting_Add_To_Skill_Plan_Success", comment: ""),
            isPresented: $showPlanSavedAlert
        ) {
            Button(NSLocalizedString("Misc_Done", comment: "")) {}
        } message: {
            Text(
                String.localizedStringWithFormat(
                    NSLocalizedString("Fitting_Add_To_Skill_Plan_Saved_Message", comment: ""),
                    savedPlanName
                )
            )
        }
        .onAppear {
            skillsManager.loadAttributes(
                characterId: currentCharacterId,
                into: $characterAttributes
            )
            selectedLevel = currentLevel
        }
    }

    // MARK: - 等级切换按钮

    private func masteryTabButton(for level: Int, masteryState: MasteryLevelState?) -> some View {
        let isSelected = selectedLevel == level
        // 等级 5 按钮描边金色（提亮版）
        let tint: Color = level == 5
            ? Color(red: 0xD6 / 255.0, green: 0xBC / 255.0, blue: 0x6E / 255.0)
            : .blue
        // 已达到该等级：等级 0 = 可驾驶（非 locked），1-5 = 当前专精等级 ≥ level
        let isReached: Bool
        if case let .level(current) = masteryState ?? .locked {
            isReached = level == 0 ? true : current >= level
        } else {
            isReached = false
        }
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedLevel = level
            }
        } label: {
            VStack(spacing: 4) {
                Image("mastery_level_\(level)")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)

                // 已达到该等级：绿色对勾；未达到：空心圆（专精 0 = 驾驶技能未满足也是未达到）
                if isReached {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "circle")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.45))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            // 浅色模式：非 5 级蓝底 / 5 级金底（实色）；深色模式：系统底色；选中时叠白提亮
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(buttonBackground(for: level))
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.18))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? tint : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    /// 按钮底色：非 5 级蓝 / 5 级金（浅色 #395172/#69614c，深色用降低亮度的暗色调）
    private func buttonBackground(for level: Int) -> Color {
        if colorScheme == .light {
            return level == 5
                ? Color(red: 0x69 / 255.0, green: 0x61 / 255.0, blue: 0x4C / 255.0)
                : Color(red: 0x39 / 255.0, green: 0x51 / 255.0, blue: 0x72 / 255.0)
        }
        return level == 5
            ? Color(red: 0x45 / 255.0, green: 0x3C / 255.0, blue: 0x2C / 255.0)
            : Color(red: 0x21 / 255.0, green: 0x2B / 255.0, blue: 0x3E / 255.0)
    }

    // MARK: - Footer 统计

    /// 该专精等级去重后的技能要求（同一技能在多个认证中出现时取最高要求）
    private var dedupedRequirements: [Int: Int] {
        var required: [Int: Int] = [:]
        for certificateID in levelCerts {
            for requirement in SDEMemoryStore.certificateSkills[certificateID] ?? [] {
                let level = requirement.tierLevels[selectedLevel - 1]
                guard level > 0 else { continue }
                required[requirement.skillID] = max(required[requirement.skillID] ?? 0, level)
            }
        }
        return required
    }

    // MARK: - 添加到技能计划

    /// 默认计划名：飞船名-专精X（本地化格式）
    private var defaultPlanName: String {
        let shipName = SDEMemoryStore.type(for: typeID)?.name ?? ""
        return String(
            format: NSLocalizedString("Mastery_Plan_Name_Format", comment: "飞船名-专精x"),
            shipName,
            MasteryDisplayHelper.levelSymbols[selectedLevel]
        )
    }

    /// 所选等级的全部技能要求（专精 0 = 飞船直接技能要求，1-5 = 专精技能 + 船体技能要求，同技能取最高）
    private var planRequirements: [(skillID: Int, requiredLevel: Int, currentLevel: Int, skillName: String)] {
        let pairs: [(skillID: Int, level: Int)]
        if selectedLevel == 0 {
            pairs = databaseManager.getDirectSkillRequirements(for: typeID)
        } else {
            // 专精 1-5 的认证技能不含船体本身（专精 0）的技能要求，导出计划时需合并
            var required = dedupedRequirements
            for requirement in databaseManager.getDirectSkillRequirements(for: typeID) {
                required[requirement.skillID] = max(required[requirement.skillID] ?? 0, requirement.level)
            }
            pairs = required.map { (skillID: $0.key, level: $0.value) }
        }

        return pairs.map {
            (
                skillID: $0.skillID,
                requiredLevel: $0.level,
                currentLevel: skillsManager.characterSkills[$0.skillID] ?? 0,
                skillName: SkillTreeManager.shared.getSkillName(for: $0.skillID) ?? ""
            )
        }
    }

    /// 创建技能计划（复用装配技能计划流程：自动补前置链并生成完整队列）
    private func addToSkillPlan() {
        let name = planNameText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let requirements = planRequirements
        Task {
            if let saved = await AddFittingSkillsToPlanSheet.saveMissingSkillsToPlan(
                missingSkills: requirements,
                characterId: currentCharacterId,
                planName: name,
                databaseManager: databaseManager
            ) {
                await MainActor.run {
                    savedPlanName = saved
                    showPlanSavedAlert = true
                }
            }
        }
    }
}

/// 单个认证行：折叠展开该认证在所需等级下的全部技能要求
struct MasteryCertRow: View {
    let certificateID: Int
    /// 所需认证等级 = 专精等级（1-5）
    let requiredLevel: Int
    @ObservedObject var databaseManager: DatabaseManager
    @ObservedObject var skillsManager = SharedSkillsManager.shared
    let characterAttributes: CharacterAttributes?

    @State private var isExpanded = false

    private var certificateName: String {
        SDEMemoryStore.certificateName(for: certificateID) ?? "Certificate \(certificateID)"
    }

    /// 该认证在 requiredLevel 档位下的技能要求（档位值 0 表示不要求，跳过）
    /// 未满足的技能排在前面，确保用户先看到缺失项
    private var requirements: [(skillID: Int, level: Int)] {
        let characterSkills = skillsManager.characterSkills
        return (SDEMemoryStore.certificateSkills[certificateID] ?? [])
            .compactMap { requirement in
                let level = requirement.tierLevels[requiredLevel - 1]
                return level > 0 ? (skillID: requirement.skillID, level: level) : nil
            }
            .sorted { lhs, rhs in
                let lhsUnmet = (characterSkills[lhs.skillID] ?? 0) < lhs.level
                let rhsUnmet = (characterSkills[rhs.skillID] ?? 0) < rhs.level
                if lhsUnmet != rhsUnmet {
                    return lhsUnmet
                }
                return lhs.skillID < rhs.skillID
            }
    }

    /// 该认证当前达标状态
    private var isCertMet: Bool {
        (skillsManager.masteryCertLevels[certificateID] ?? 0) >= requiredLevel
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(requirements, id: \.skillID) { requirement in
                SkillRequirementRow(
                    skillID: requirement.skillID,
                    level: requirement.level,
                    timeMultiplier: SkillTreeManager.shared.trainingTimeMultiplier(
                        for: requirement.skillID
                    ),
                    databaseManager: databaseManager,
                    currentLevel: skillsManager.getSkillLevel(for: requirement.skillID),
                    trainingLevel: skillsManager.getTrainingTargetLevel(for: requirement.skillID),
                    characterAttributes: characterAttributes,
                    skillAttributes: SkillTreeManager.shared.trainingAttributes(
                        for: requirement.skillID
                    )
                )
            }
        } label: {
            HStack {
                Image("skill_lv_\(requiredLevel)")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
                Text(certificateName)
                    .foregroundColor(.primary)
                Spacer()
                if !skillsManager.masteryCertLevels.isEmpty {
                    Image(systemName: isCertMet ? "checkmark.circle.fill" : "circle")
                        .frame(width: 20, height: 20)
                        .foregroundColor(isCertMet ? .green : .secondary)
                }
            }
            .contentShape(Rectangle())
        }
    }
}
