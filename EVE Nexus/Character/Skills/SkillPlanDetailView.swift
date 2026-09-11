import Foundation
import SwiftUI
import UniformTypeIdentifiers

private let kShowCompletedSkillsKey = "SkillPlan_ShowCompletedSkills"

/// 技能计划详情中网络请求阶段（与 CharacterAssets 进度条样式一致）
private enum SkillPlanNetworkLoadingPhase: Equatable {
    case fetchingLearnedSkills
    case fetchingAttributes
    case fetchingImplants
    case fetchingInjectorPrices
}

struct SkillPlanDetailView: View {
    @State private var plan: SkillPlan
    let characterId: Int
    @ObservedObject var databaseManager: DatabaseManager
    @Binding var skillPlans: [SkillPlan]
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var characterAttributes: CharacterAttributes?
    @State private var implantBonuses: ImplantAttributes?
    @State private var trainingRates: [Int: Int] = [:] // [skillId: pointsPerHour]
    @State private var injectorCalculation: InjectorCalculation?
    @State private var injectorPrices: InjectorPriceManager.InjectorPrices =
        .init(large: nil, small: nil)
    @State private var isLoadingInjectors = true
    @State private var learnedSkills: [Int: CharacterSkill] = [:] // 添加缓存
    @State private var skillDependencies: [String: Set<String>] = [:] // [skillId_level: Set<依赖它的skillId_level>]
    @AppStorage(kShowCompletedSkillsKey) private var showCompletedSkills = true
    @State private var freshQueueMode = false
    @State private var isFreshQueueTransitioning = false
    @State private var displayedRequiredSkillPoints = 0
    @State private var displayedRequiredTrainingTime: TimeInterval = 0
    @State private var displayedAllSkillPoints = 0
    @State private var showAddSkillSheet = false
    @State private var showAddItemSheet = false
    @State private var showExportSuccessAlert = false
    @State private var networkLoadingPhase: SkillPlanNetworkLoadingPhase?
    @State private var optimalAttributes: SkillTrainingCalculator.OptimalAttributes?
    @State private var attributeComparisons:
        [(name: String, icon: String, current: Int, optimal: Int, diff: Int)] = []
    /// 首次进入：完成 `loadCharacterData`（含注入器）及待添加技能后再展示主列表，避免 Unknown 名称等中间态
    @State private var isInitialLoadComplete = false
    /// 核心数据（已学技能/角色属性）在缓存与强制网络加载均失败时，展示错误占位而非清零的列表
    @State private var isInitialLoadFailed = false
    @State private var cachedCharacterTotalSP: Int?

    init(
        plan: SkillPlan, characterId: Int, databaseManager: DatabaseManager,
        skillPlans: Binding<[SkillPlan]>
    ) {
        _plan = State(initialValue: plan)
        self.characterId = characterId
        self.databaseManager = databaseManager
        _skillPlans = skillPlans
        _learnedSkills = State(initialValue: [:])
    }

    var body: some View {
        // 单一 List：与 CharacterSkillsView 等页面一致，用条件区块切换加载/内容，避免 Group 在两种 List 间切换导致导航栏与内容布局不同步
        List {
            if !isInitialLoadComplete {
                Section {
                    VStack(spacing: 16) {
                        if isInitialLoadFailed {
                            Text(NSLocalizedString("Main_Skills_Plan_Load_Failed", comment: ""))
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)

                            Button(NSLocalizedString("Misc_Retry", comment: "")) {
                                Task {
                                    isInitialLoadFailed = false
                                    await performInitialLoad()
                                }
                            }
                            .buttonStyle(.bordered)
                        } else {
                            ProgressView()
                            Text(initialLoadStatusText)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .listRowBackground(Color.clear)
                }
            } else {
                skillPlanLoadedSections
            }
        }
        .listStyle(.insetGrouped)
        .scrollDisabled(!isInitialLoadComplete)
        .navigationTitle(plan.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                skillPlanToolbarTrailing
            }
        }
        .alert(
            NSLocalizedString("Main_Skills_Plan_Import_Alert_Title", comment: ""),
            isPresented: $showErrorAlert
        ) {
            Button("OK", role: .cancel) {
                // 清理状态
            }
        } message: {
            Text(errorMessage)
        }
        .alert(
            NSLocalizedString("Main_Skills_Plan_Export_Success_Title", comment: "导出成功"),
            isPresented: $showExportSuccessAlert
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(NSLocalizedString("Main_Skills_Plan_Export_Success_Message", comment: "技能计划已复制到剪贴板"))
        }
        .task {
            await performInitialLoad()
        }
        .onChange(of: plan.skills.count) { _, _ in
            // 技能数量变化时重新计算依赖
            calculateSkillDependencies()
        }
        .sheet(isPresented: $showAddSkillSheet) {
            AddSkillSelectorView(
                databaseManager: databaseManager,
                onBatchSkillsSelected: { skills in
                    Task {
                        await addBatchSkillsToPlan(skills: skills)
                    }
                },
                onSkillLevelsRemoved: { skillId, fromLevel, toLevel in
                    removeSkillLevels(skillId: skillId, fromLevel: fromLevel, toLevel: toLevel)
                },
                existingSkillLevels: getExistingSkillLevels(),
                skillDependencies: $skillDependencies
            )
        }
        .sheet(isPresented: $showAddItemSheet) {
            ItemSelectorView(
                databaseManager: databaseManager,
                onSelect: { item in
                    Task {
                        await addItemSkillsToPlan(itemId: item.id, itemName: item.name)
                    }
                }
            )
        }
    }

    @ViewBuilder
    private var skillPlanToolbarTrailing: some View {
        if isInitialLoadComplete {
            HStack(spacing: 16) {
                Button {
                    Task {
                        await importSkillsFromClipboard()
                    }
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }

                if isEnglishLanguage() {
                    Button {
                        Task {
                            await exportSkillPlan(useEnglishNames: true)
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                } else {
                    Menu {
                        Button {
                            Task {
                                await exportSkillPlan(useEnglishNames: false)
                            }
                        } label: {
                            Label(NSLocalizedString("Main_Skills_Plan_Export_Localized", comment: "导出当前语言"), systemImage: "doc.text")
                        }

                        Button {
                            Task {
                                await exportSkillPlan(useEnglishNames: true)
                            }
                        } label: {
                            Label(NSLocalizedString("Main_Skills_Plan_Export_English", comment: "导出英文"), systemImage: "doc.text")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }

                Menu {
                    Button {
                        showAddSkillSheet = true
                    } label: {
                        Label(NSLocalizedString("Main_Skills_Plan_Add_Skill", comment: "添加技能"), systemImage: "plus")
                    }

                    Divider()

                    Button {
                        showAddItemSheet = true
                    } label: {
                        Label(NSLocalizedString("Main_Skills_Plan_Add_Item", comment: "添加物品"), systemImage: "cube.box")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }

    /// 数据就绪后的列表区块（嵌入同一 `List`，与加载占位共用容器）
    @ViewBuilder
    private var skillPlanLoadedSections: some View {
        skillPlanNetworkLoadingSection

        Section(header: Text(NSLocalizedString("Main_Skills_Points", comment: "技能点数"))) {
            HStack(spacing: 12) {
                Toggle(isOn: freshQueueToggleBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("Main_Skills_Plan_Fresh_Queue", comment: ""))
                        Text(freshQueueDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .animation(.easeInOut(duration: 0.25), value: freshQueueMode)
                    }
                }
                .disabled(isFreshQueueTransitioning)
            }

            HStack {
                Text(NSLocalizedString("Main_Skills_To_Learn", comment: "需要学习"))
                Spacer()
                Text("\(FormatUtil.format(Double(displayedRequiredSkillPoints))) SP")
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.35), value: displayedRequiredSkillPoints)
            }

            HStack {
                Text(NSLocalizedString("Main_Skills_Required_Time", comment: "需要时间"))
                Spacer()
                Text(FormatUtil.formatCompactDuration(displayedRequiredTrainingTime))
                    .foregroundColor(.secondary)
                    .contentTransition(.interpolate)
                    .animation(.easeInOut(duration: 0.35), value: displayedRequiredTrainingTime)
            }

            HStack {
                Text(NSLocalizedString("Main_Skills_All_Points", comment: "全部点数"))
                Spacer()
                Text("\(FormatUtil.format(Double(displayedAllSkillPoints))) SP")
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.35), value: displayedAllSkillPoints)
            }
        }

        // 添加注入器需求部分
        if !plan.skills.isEmpty && !isLoadingInjectors && (freshQueueMode || filteredSkills.count > 0) {
            if let calculation = injectorCalculation,
               calculation.largeInjectorCount + calculation.smallInjectorCount > 0
            {
                Section(
                    header: Text(
                        NSLocalizedString("Main_Skills_Required_Injectors", comment: "")
                    )
                ) {
                    // 大型注入器
                    if let largeInfo = getInjectorInfo(
                        typeId: SkillInjectorCalculator.largeInjectorTypeId
                    ),
                        calculation.largeInjectorCount > 0
                    {
                        injectorItemView(
                            info: largeInfo, count: calculation.largeInjectorCount,
                            typeId: SkillInjectorCalculator.largeInjectorTypeId
                        )
                    }

                    // 小型注入器
                    if let smallInfo = getInjectorInfo(
                        typeId: SkillInjectorCalculator.smallInjectorTypeId
                    ),
                        calculation.smallInjectorCount > 0
                    {
                        injectorItemView(
                            info: smallInfo, count: calculation.smallInjectorCount,
                            typeId: SkillInjectorCalculator.smallInjectorTypeId
                        )
                    }

                    // 总计所需技能点和预计价格
                    injectorSummaryView(calculation: calculation)
                }
            }
        }

        optimalAttributesSection

        Section(
            header: HStack {
                Text(skillPlanHeaderText)
                Spacer()
                Button {
                    showCompletedSkills.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(
                            systemName: showCompletedSkills
                                ? "checkmark.circle.fill" : "circle"
                        )
                        Text(NSLocalizedString("Main_Skills_Plan_Show_Completed_Short", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        ) {
            if plan.skills.isEmpty {
                // 队列为空
                Text(NSLocalizedString("Main_Skills_Plan_Empty", comment: ""))
                    .foregroundColor(.secondary)
            } else if filteredSkills.count == 0 {
                // 队列不为空，但所有技能都已完成（且不显示已完成技能）
                Text(NSLocalizedString("Main_Skills_Plan_All_Completed", comment: ""))
                    .foregroundColor(.green)
            } else {
                ForEach(filteredSkills) { skill in
                    skillRowView(skill)
                        .contextMenu {
                            // 只有无后置依赖的技能才能删除
                            if !hasPostDependencies(skillId: skill.skillID, level: skill.targetLevel) {
                                Button(role: .destructive) {
                                    if let index = plan.skills.firstIndex(where: { $0.id == skill.id }) {
                                        deleteSkill(at: IndexSet(integer: index))
                                    }
                                } label: {
                                    Label(NSLocalizedString("Misc_Delete", comment: ""), systemImage: "trash")
                                }
                            } else {
                                Text(NSLocalizedString("Main_Skills_Plan_Has_Dependencies", comment: "此技能被其他技能依赖，无法删除"))
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                }
                .onDelete { indexSet in
                    // 检查是否所有要删除的技能都没有后置依赖
                    let skillsToDelete = indexSet.map { filteredSkills[$0] }
                    let hasAnyDependencies = skillsToDelete.contains { skill in
                        hasPostDependencies(skillId: skill.skillID, level: skill.targetLevel)
                    }

                    if !hasAnyDependencies {
                        deleteSkill(at: indexSet)
                    } else {
                        errorMessage = NSLocalizedString("Main_Skills_Plan_Cannot_Delete_Has_Dependencies", comment: "")
                        showErrorAlert = true
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }
        }

        // 清空队列按钮 - 单独section
        if !plan.skills.isEmpty {
            Section {
                Button {
                    clearAllSkills()
                } label: {
                    HStack {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                        Text(NSLocalizedString("Main_Skills_Plan_Clear_All", comment: "清空队列"))
                            .foregroundColor(.red)
                        Spacer()
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }
        }
    }

    @ViewBuilder
    private var optimalAttributesSection: some View {
        if shouldShowOptimalAttributesSection(freshQueue: freshQueueMode), !attributeComparisons.isEmpty {
            Section {
                ForEach(attributeComparisons, id: \.name) { attr in
                    HStack {
                        Image(attr.icon)
                            .resizable()
                            .frame(width: 32, height: 32)
                            .cornerRadius(4)
                        Text(attr.name)
                        Spacer()
                        if attr.diff != 0 {
                            Text("+\(attr.diff)")
                                .foregroundColor(.green)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }

                if let optimal = optimalAttributes {
                    VStack(alignment: .leading, spacing: 4) {
                        let savedTime = optimal.currentTrainingTime - optimal.totalTrainingTime
                        if savedTime > 0 {
                            Text(
                                String(
                                    format: NSLocalizedString(
                                        "Main_Skills_Optimal_Attributes_Time_Saved_With_Total", comment: ""
                                    ),
                                    FormatUtil.formatCompactDuration(savedTime, rounding: .ceil),
                                    FormatUtil.formatCompactDuration(optimal.totalTrainingTime, rounding: .ceil)
                                )
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        } else {
                            Text(
                                NSLocalizedString(
                                    "Main_Skills_Optimal_Attributes_Already_Optimal", comment: ""
                                )
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }

                        if !freshQueueMode,
                           let attrs = characterAttributes,
                           let implants = implantBonuses,
                           SkillTrainingCalculator.detectBoosterBonus(
                               currentAttributes: attrs,
                               implantBonuses: implants
                           ) > 0
                        {
                            Text(
                                NSLocalizedString(
                                    "Main_Skills_Optimal_Attributes_Note", comment: ""
                                )
                            )
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                OptimalAttributesSectionHeader()
            }
        }
    }

    private var allSkillsCompleted: Bool {
        !plan.skills.isEmpty && plan.skills.allSatisfy(\.isCompleted)
    }

    private var freshQueueToggleBinding: Binding<Bool> {
        Binding(
            get: { freshQueueMode },
            set: { newValue in
                guard newValue != freshQueueMode, !isFreshQueueTransitioning else { return }
                Task { await transitionFreshQueueMode(to: newValue) }
            }
        )
    }

    private var freshQueueDescription: String {
        freshQueueMode
            ? NSLocalizedString("Main_Skills_Plan_Fresh_Queue_Description", comment: "")
            : NSLocalizedString("Main_Skills_Plan_Fresh_Queue_Description_Current", comment: "")
    }

    private func shouldShowOptimalAttributesSection(freshQueue: Bool) -> Bool {
        guard !plan.skills.isEmpty else { return false }
        return freshQueue || !allSkillsCompleted
    }

    private func attributesBaselineForOptimal(freshQueue _: Bool) -> CharacterAttributes? {
        characterAttributes
    }

    private func requiredSkillPoints(freshQueue: Bool) -> Int {
        freshQueue ? freshQueueTotalSkillPoints() : plan.totalSkillPoints
    }

    private func requiredTrainingTime(freshQueue: Bool) -> TimeInterval {
        freshQueue ? freshQueueTotalTrainingTime() : plan.totalTrainingTime
    }

    private func allSkillPoints(freshQueue: Bool) -> Int {
        freshQueue ? freshQueueTotalSkillPoints() : calculateAllSkillPoints()
    }

    @MainActor
    private func syncDisplayedMetrics(freshQueue: Bool, animated: Bool) {
        let sp = requiredSkillPoints(freshQueue: freshQueue)
        let time = requiredTrainingTime(freshQueue: freshQueue)
        let all = allSkillPoints(freshQueue: freshQueue)

        if animated {
            withAnimation(.easeInOut(duration: 0.35)) {
                displayedRequiredSkillPoints = sp
                displayedRequiredTrainingTime = time
                displayedAllSkillPoints = all
            }
        } else {
            displayedRequiredSkillPoints = sp
            displayedRequiredTrainingTime = time
            displayedAllSkillPoints = all
        }
    }

    private func transitionFreshQueueMode(to newValue: Bool) async {
        await MainActor.run { isFreshQueueTransitioning = true }
        await recalculatePlanMetrics(freshQueue: newValue, animated: true)
        await MainActor.run {
            freshQueueMode = newValue
            isFreshQueueTransitioning = false
        }
    }

    private static func freshQueueBaselineAttributes() -> CharacterAttributes {
        CharacterAttributes(
            charisma: 19,
            intelligence: 20,
            memory: 20,
            perception: 20,
            willpower: 20,
            bonus_remaps: nil,
            accrued_remap_cooldown_date: nil,
            last_remap_date: nil
        )
    }

    private func skillRequiredSPFromZero(_ skill: PlannedSkill) -> Int {
        let timeMultiplier = getSkillTimeMultiplier(skill.skillID)
        let startSP = (getBaseSkillPointsForLevel(skill.targetLevel - 1) ?? 0) * timeMultiplier
        let endSP = (getBaseSkillPointsForLevel(skill.targetLevel) ?? 0) * timeMultiplier
        return endSP - startSP
    }

    private func freshQueueTotalSkillPoints() -> Int {
        plan.skills.reduce(0) { $0 + skillRequiredSPFromZero($1) }
    }

    private func trainingTime(forSkill skill: PlannedSkill, requiredSP: Int, attributes: CharacterAttributes) -> TimeInterval {
        guard let (primary, secondary) = SkillTrainingCalculator.getSkillAttributes(
            skillId: skill.skillID, databaseManager: databaseManager
        ),
            let rate = SkillTrainingCalculator.calculateTrainingRate(
                primaryAttrId: primary,
                secondaryAttrId: secondary,
                attributes: attributes
            ),
            rate > 0
        else {
            return 0
        }
        return Double(requiredSP) / Double(rate) * 3600
    }

    private func freshQueueTotalTrainingTime() -> TimeInterval {
        let attributes = Self.freshQueueBaselineAttributes()
        return plan.skills.reduce(0) { total, skill in
            total + trainingTime(
                forSkill: skill,
                requiredSP: skillRequiredSPFromZero(skill),
                attributes: attributes
            )
        }
    }

    private func updateAttributeComparisons(freshQueue: Bool) {
        guard let attrs = attributesBaselineForOptimal(freshQueue: freshQueue),
              let optimal = optimalAttributes
        else {
            attributeComparisons = []
            return
        }

        let minAttr = 17
        var comparisons: [(name: String, icon: String, current: Int, optimal: Int, diff: Int)] = []

        let attributes = [
            (
                NSLocalizedString("Character_Attribute_Perception", comment: ""), "perception",
                attrs.perception, optimal.perception, optimal.perception - minAttr
            ),
            (
                NSLocalizedString("Character_Attribute_Memory", comment: ""), "memory",
                attrs.memory, optimal.memory, optimal.memory - minAttr
            ),
            (
                NSLocalizedString("Character_Attribute_Willpower", comment: ""), "willpower",
                attrs.willpower, optimal.willpower, optimal.willpower - minAttr
            ),
            (
                NSLocalizedString("Character_Attribute_Intelligence", comment: ""), "intelligence",
                attrs.intelligence, optimal.intelligence, optimal.intelligence - minAttr
            ),
            (
                NSLocalizedString("Character_Attribute_Charisma", comment: ""), "charisma",
                attrs.charisma, optimal.charisma, optimal.charisma - minAttr
            ),
        ]

        for attr in attributes where attr.4 > 0 {
            comparisons.append(attr)
        }
        attributeComparisons = comparisons
    }

    private func persistPlan(_ updatedPlan: SkillPlan) {
        let saved = SkillPlanFileManager.shared.saveSkillPlan(
            characterId: characterId, plan: updatedPlan, databaseManager: databaseManager
        )
        plan = saved
        if let index = skillPlans.firstIndex(where: { $0.id == saved.id }) {
            skillPlans[index] = saved
        }
    }

    private func updateOptimalAttributes(freshQueue: Bool) async {
        guard shouldShowOptimalAttributesSection(freshQueue: freshQueue),
              let baselineAttrs = attributesBaselineForOptimal(freshQueue: freshQueue)
        else {
            await MainActor.run {
                optimalAttributes = nil
                attributeComparisons = []
            }
            return
        }

        let queueInfo = plan.skills.compactMap {
            skill -> (skillId: Int, remainingSP: Int, startDate: Date?, finishDate: Date?)? in
            if !freshQueue, skill.isCompleted { return nil }

            let remainingSP: Int
            if freshQueue {
                remainingSP = skillRequiredSPFromZero(skill)
            } else {
                let spRange = getSkillPointRange(skill)
                remainingSP = spRange.end - spRange.start
            }
            guard remainingSP > 0 else { return nil }
            return (skillId: skill.skillID, remainingSP: remainingSP, startDate: nil, finishDate: nil)
        }

        guard !queueInfo.isEmpty else {
            await MainActor.run {
                optimalAttributes = nil
                attributeComparisons = []
            }
            return
        }

        let optimal = await SkillTrainingCalculator.calculateOptimalAttributes(
            skillQueue: queueInfo,
            databaseManager: databaseManager,
            currentAttributes: baselineAttrs,
            characterId: characterId,
            implantBonuses: implantBonuses ?? ImplantAttributes()
        )

        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.35)) {
                optimalAttributes = optimal
                updateAttributeComparisons(freshQueue: freshQueue)
            }
        }
    }

    private var initialLoadStatusText: String {
        if let phase = networkLoadingPhase {
            return skillPlanLoadingPhaseText(phase)
        }
        return NSLocalizedString("Main_Skills_Plan_Loading_Placeholder", comment: "")
    }

    private func performInitialLoad() async {
        await loadCharacterData()

        // 计划非空时，已学技能或角色属性仍缺失说明缓存与强制网络加载均失败：
        // 不进入主列表，展示错误占位，避免出现“需要学习 0 / 全部 0 秒”的假数据
        if !plan.skills.isEmpty, learnedSkills.isEmpty || characterAttributes == nil {
            await MainActor.run { isInitialLoadFailed = true }
            return
        }

        calculateSkillDependencies()
        await loadInjectorPricesIfNeeded()
        await MainActor.run {
            isLoadingInjectors = false
            isInitialLoadComplete = true
        }
    }

    private var filteredSkills: [PlannedSkill] {
        showCompletedSkills ? plan.skills : plan.skills.filter { !$0.isCompleted }
    }

    /// 技能计划标题文本
    private var skillPlanHeaderText: String {
        let totalCount = plan.skills.count

        if showCompletedSkills {
            // 显示已完成：只显示总数
            return "\(NSLocalizedString("Main_Skills_Plan", comment: ""))(\(totalCount))"
        } else {
            // 不显示已完成：显示 未完成/总数
            let uncompletedCount = plan.skills.filter { !$0.isCompleted }.count
            return "\(NSLocalizedString("Main_Skills_Plan", comment: ""))(\(uncompletedCount)/\(totalCount))"
        }
    }

    @ViewBuilder
    private var skillPlanNetworkLoadingSection: some View {
        if let phase = networkLoadingPhase {
            Section {
                HStack {
                    Spacer()
                    Text(skillPlanLoadingPhaseText(phase))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
    }

    private func skillPlanLoadingPhaseText(_ phase: SkillPlanNetworkLoadingPhase) -> String {
        switch phase {
        case .fetchingLearnedSkills:
            return NSLocalizedString("Main_Skills_Plan_Loading_Fetching_Skills", comment: "")
        case .fetchingAttributes:
            return NSLocalizedString("Main_Skills_Plan_Loading_Fetching_Attributes", comment: "")
        case .fetchingImplants:
            return NSLocalizedString("Main_Skills_Plan_Loading_Fetching_Implants", comment: "")
        case .fetchingInjectorPrices:
            return NSLocalizedString("Main_Skills_Plan_Loading_Fetching_Injector_Prices", comment: "")
        }
    }

    private func setNetworkLoadingPhase(_ phase: SkillPlanNetworkLoadingPhase?) async {
        await MainActor.run {
            networkLoadingPhase = phase
        }
    }

    /// 依次请求：已学技能 → 角色属性 → 植入体（仅缓存缺失时拉属性/植入体）。
    /// - Returns: 若本次请求了 `fetchCharacterSkillsAndQueue`，返回其 `total_sp + unallocated_sp`，供注入器计算复用，避免重复 ESI。
    private func refreshSkillPlanNetworkCaches(skillIds: [Int]) async -> Int? {
        var spForInjector: Int?

        if learnedSkills.isEmpty {
            await setNetworkLoadingPhase(.fetchingLearnedSkills)
            var (learned, sp) = await getLearnedSkills(skillIds: skillIds)
            // 缓存优先加载未取到数据时强制走一次网络刷新，确保进入页面即有已学技能数据
            if learned.isEmpty, !skillIds.isEmpty {
                Logger.error("技能计划：缓存优先加载已学技能失败，强制网络重试 - 角色ID: \(characterId)")
                let retried = await getLearnedSkills(skillIds: skillIds, forceRefresh: true)
                if !retried.learned.isEmpty {
                    learned = retried.learned
                    sp = retried.characterTotalSP
                }
            }
            learnedSkills = learned
            spForInjector = sp
        } else {
            let missingSkillIds = skillIds.filter { !learnedSkills.keys.contains($0) }
            if !missingSkillIds.isEmpty {
                await setNetworkLoadingPhase(.fetchingLearnedSkills)
                let (newSkills, sp) = await getLearnedSkills(skillIds: missingSkillIds)
                learnedSkills.merge(newSkills) { current, _ in current }
                spForInjector = sp
            } else if let cached = CharacterSkillsAPI.shared.loadSkillsFromCacheIfAvailable(
                characterId: characterId
            ) {
                // 未再走 fetchCharacterSkillsAndQueue 时仍从合并缓存取 total_sp，供注入器计算，避免再走 fetchCharacterSkills 触发额外读盘/可能写盘
                spForInjector = cached.total_sp + cached.unallocated_sp
            }
        }

        if characterAttributes == nil {
            await setNetworkLoadingPhase(.fetchingAttributes)
            characterAttributes = try? await CharacterSkillsAPI.shared.fetchAttributes(
                characterId: characterId
            )
            // 属性缺失会导致所有技能显示 0 秒，失败时强制网络重试一次
            if characterAttributes == nil {
                characterAttributes = try? await CharacterSkillsAPI.shared.fetchAttributes(
                    characterId: characterId, forceRefresh: true
                )
            }
        }
        if implantBonuses == nil {
            await setNetworkLoadingPhase(.fetchingImplants)
            implantBonuses = await SkillTrainingCalculator.getImplantBonuses(characterId: characterId)
        }
        if cachedCharacterTotalSP == nil, let sp = spForInjector {
            cachedCharacterTotalSP = sp
        } else if cachedCharacterTotalSP == nil,
                  let cached = CharacterSkillsAPI.shared.loadSkillsFromCacheIfAvailable(
                      characterId: characterId
                  )
        {
            cachedCharacterTotalSP = cached.total_sp + cached.unallocated_sp
        }
        await setNetworkLoadingPhase(nil)
        return spForInjector
    }

    private func skillRowView(_ skill: PlannedSkill) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 2) {
                Text(skill.skillName)
                    .lineLimit(1)
                Spacer()
                Text(
                    String(
                        format: NSLocalizedString("Misc_Level_Short", comment: ""),
                        skill.targetLevel
                    )
                )
                .foregroundColor(.secondary)
                .font(.caption)
                .padding(.trailing, 2)
                SkillLevelIndicator(
                    currentLevel: skill.targetLevel - 1, // 计划中的当前等级
                    trainingLevel: skill.targetLevel, // 计划中的目标等级
                    isTraining: false
                )
                .padding(.trailing, 2)
            }
            .contextMenu {
                Button {
                    UIPasteboard.general.string = skill.skillName
                } label: {
                    Label(NSLocalizedString("Misc_Copy", comment: ""), systemImage: "doc.on.doc")
                }
            }

            let spRange = getSkillPointRange(skill)
            HStack(spacing: 4) {
                if let rate = trainingRates[skill.skillID] {
                    Text(
                        "\(FormatUtil.format(Double(spRange.start)))/\(FormatUtil.format(Double(spRange.end))) SP (\(FormatUtil.format(Double(rate)))/h)"
                    )
                } else {
                    Text(
                        "\(FormatUtil.format(Double(spRange.start)))/\(FormatUtil.format(Double(spRange.end))) SP"
                    )
                }
                Spacer()
                if skill.isCompleted {
                    Text(NSLocalizedString("Main_Skills_Completed", comment: ""))
                        .foregroundColor(.green)
                } else {
                    Text(FormatUtil.formatCompactDuration(skill.trainingTime))
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.top, 2)
        }
        .padding(.vertical, 2)
    }

    private func importSkillsFromClipboard() async {
        // 检查剪贴板是否为空
        guard let clipboardString = UIPasteboard.general.string, !clipboardString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await MainActor.run {
                errorMessage = NSLocalizedString("Main_Market_Clipboard_Empty", comment: "剪贴板为空")
                showErrorAlert = true
            }
            return
        }

        Logger.debug("从剪贴板读取内容: \(clipboardString)")
        let result = SkillPlanReaderTool.parseSkillPlan(
            from: clipboardString, databaseManager: databaseManager
        )

        // 继续处理成功解析的技能
        if !result.skills.isEmpty {
            Logger.debug("解析技能计划结果: \(result.skills)")

            // 将解析结果转换为待添加技能
            let parsedSkills = result.skills.compactMap { skillString -> (skillId: Int, level: Int)? in
                let components = skillString.split(separator: ":")
                guard components.count == 2,
                      let typeId = Int(components[0]),
                      let targetLevel = Int(components[1])
                else {
                    return nil
                }
                return (skillId: typeId, level: targetLevel)
            }

            var updatedPlan = plan
            let validSkills = parsedSkills.compactMap { skill -> PlannedSkill? in
                if updatedPlan.skills.contains(where: {
                    $0.skillID == skill.skillId && $0.targetLevel == skill.level
                }) {
                    return nil
                }

                let skillName = SkillTreeManager.shared.getSkillName(for: skill.skillId)
                    ?? "Unknown Skill (\(skill.skillId))"
                let learnedSkill = learnedSkills[skill.skillId]
                let currentLevel = learnedSkill?.trained_skill_level ?? 0
                let isCompleted = skill.level <= currentLevel

                return createPlannedSkill(
                    typeId: skill.skillId,
                    skillName: skillName,
                    targetLevel: skill.level,
                    isCompleted: isCompleted
                )
            }

            if !validSkills.isEmpty {
                updatedPlan = updatePlanWithSkills(updatedPlan, skills: updatedPlan.skills + validSkills)
                await MainActor.run {
                    persistPlan(updatedPlan)
                }
                await loadCharacterData()
            }

            // 构建提示消息
            var message = String(
                format: NSLocalizedString("Main_Skills_Plan_Import_Success", comment: ""),
                validSkills.count
            )

            if result.hasErrors {
                message += "\n\n"

                if !result.parseErrors.isEmpty {
                    message +=
                        NSLocalizedString("Main_Skills_Plan_Import_Parse_Failed", comment: "")
                        + "\n" + result.parseErrors.joined(separator: "\n")
                }

                if !result.notFoundSkills.isEmpty {
                    if !result.parseErrors.isEmpty {
                        message += "\n\n"
                    }
                    message +=
                        NSLocalizedString("Main_Skills_Plan_Import_Not_Found", comment: "")
                        + "\n" + result.notFoundSkills.joined(separator: "\n")
                }

                // 导入完成，显示结果
            }

            await MainActor.run {
                errorMessage = message
                showErrorAlert = true
            }
        } else if result.hasErrors {
            // 如果没有成功导入任何技能，但有错误
            var message = ""

            if !result.parseErrors.isEmpty {
                message +=
                    NSLocalizedString("Main_Skills_Plan_Import_Parse_Failed", comment: "")
                    + "\n" + result.parseErrors.joined(separator: "\n")
            }

            if !result.notFoundSkills.isEmpty {
                if !message.isEmpty {
                    message += "\n\n"
                }
                message +=
                    NSLocalizedString("Main_Skills_Plan_Import_Not_Found", comment: "") + "\n"
                    + result.notFoundSkills.joined(separator: "\n")
            }

            await MainActor.run {
                errorMessage = message
                showErrorAlert = true
            }
        }
    }

    /// - Parameter forceRefresh: true 时跳过磁盘缓存，直接请求网络（用于缓存优先加载失败后的强制重试）
    /// - Returns: 已学技能映射，以及本次 ESI 响应中的角色总技能点（`total_sp + unallocated_sp`），失败时为 `nil`
    private func getLearnedSkills(skillIds: [Int], forceRefresh: Bool = false) async -> (learned: [Int: CharacterSkill], characterTotalSP: Int?) {
        do {
            let (skillsResponse, queue) = try await CharacterSkillsAPI.shared.fetchCharacterSkillsAndQueue(
                characterId: characterId,
                forceRefresh: forceRefresh
            )

            let totalSP = skillsResponse.total_sp + skillsResponse.unallocated_sp

            // 合并队列中已完成的部分
            let baseSkills = Dictionary(uniqueKeysWithValues: skillsResponse.skillsMap.map { ($0.key, $0.value.trained_skill_level) })
            let mergedLevels = CharacterSkillsUtils.mergeCompletedQueueIntoSkills(
                baseSkills: baseSkills,
                queue: queue
            )

            // 使用合并后的等级构建技能信息（仅返回请求的技能ID）
            var result: [Int: CharacterSkill] = [:]
            for skillId in skillIds {
                let mergedLevel = mergedLevels[skillId] ?? skillsResponse.skillsMap[skillId]?.trained_skill_level ?? 0
                let skill = skillsResponse.skillsMap[skillId]
                result[skillId] = CharacterSkill(
                    active_skill_level: mergedLevel,
                    skill_id: skillId,
                    skillpoints_in_skill: skill?.skillpoints_in_skill ?? 0,
                    trained_skill_level: mergedLevel
                )
            }
            return (result, totalSP)
        } catch {
            Logger.error("获取技能数据失败: \(error)")
            return ([:], nil)
        }
    }

    private func loadCharacterData() async {
        let skillIds = plan.skills.map { $0.skillID }

        _ = await refreshSkillPlanNetworkCaches(skillIds: skillIds)

        var updatedSkills = plan.skills
        if !skillIds.isEmpty {
            let nameDict = loadSkillNames(skillIds: skillIds)
            updatedSkills = updatedSkills.map { skill in
                if let name = nameDict[skill.skillID] {
                    return PlannedSkill(
                        id: skill.id,
                        skillID: skill.skillID,
                        skillName: name,
                        currentLevel: skill.currentLevel,
                        targetLevel: skill.targetLevel,
                        trainingTime: skill.trainingTime,
                        requiredSP: skill.requiredSP,
                        prerequisites: skill.prerequisites,
                        currentSkillPoints: skill.currentSkillPoints,
                        isCompleted: skill.isCompleted
                    )
                }
                return skill
            }
        }

        if let attrs = characterAttributes {
            for skill in updatedSkills {
                if let (primary, secondary) = SkillTrainingCalculator.getSkillAttributes(
                    skillId: skill.skillID, databaseManager: databaseManager
                ),
                    let rate = SkillTrainingCalculator.calculateTrainingRate(
                        primaryAttrId: primary,
                        secondaryAttrId: secondary,
                        attributes: attrs
                    )
                {
                    trainingRates[skill.skillID] = rate
                }
            }
        }

        // 更新计划中的技能
        let finalSkills = updatedSkills.map { skill in
            // 获取已学习的技能信息
            let learnedSkill = learnedSkills[skill.skillID]
            let currentLevel = learnedSkill?.trained_skill_level ?? 0

            // 如果目标等级小于等于当前等级，说明已完成
            let isCompleted = skill.targetLevel <= currentLevel

            return createPlannedSkill(
                typeId: skill.skillID,
                skillName: skill.skillName,
                targetLevel: skill.targetLevel,
                isCompleted: isCompleted
            )
        }

        let updatedPlan = updatePlanWithSkills(plan, skills: finalSkills)

        // 在主线程更新状态
        await MainActor.run {
            // 更新当前视图的计划
            plan = updatedPlan

            // 更新父视图中的计划列表
            if let index = skillPlans.firstIndex(where: { $0.id == plan.id }) {
                skillPlans[index] = updatedPlan
            }
        }

        await recalculatePlanMetrics()
    }

    private func getSkillTimeMultiplier(_ skillId: Int) -> Int {
        Int(SkillTreeManager.shared.trainingTimeMultiplier(for: skillId) ?? 1)
    }

    private func getBaseSkillPointsForLevel(_ level: Int) -> Int? {
        switch level {
        case 1: return 250
        case 2: return 1415
        case 3: return 8000
        case 4: return 45255
        case 5: return 256_000
        default: return nil
        }
    }

    private func calculateSkillDetails(_ skill: PlannedSkill) -> (
        startSP: Int, endSP: Int, requiredSP: Int, trainingTime: TimeInterval
    ) {
        // 获取训练速度
        let trainingRate = trainingRates[skill.skillID] ?? 0

        // 获取技能的训练倍增系数
        let timeMultiplier = getSkillTimeMultiplier(skill.skillID)

        // 获取起始和目标等级的技能点数
        let startSP = (getBaseSkillPointsForLevel(skill.currentLevel) ?? 0) * timeMultiplier
        let endSP = (getBaseSkillPointsForLevel(skill.targetLevel) ?? 0) * timeMultiplier

        // 计算需要训练的技能点数
        let requiredSP = endSP - startSP

        // 计算训练时间（如果有训练速度）
        let trainingTime: TimeInterval =
            trainingRate > 0 ? Double(requiredSP) / Double(trainingRate) * 3600 : 0 // 转换为秒

        return (startSP, endSP, requiredSP, trainingTime)
    }

    private func calculateSkillRequirements(_ skill: PlannedSkill) -> (
        requiredSP: Int, trainingTime: TimeInterval
    ) {
        let details = calculateSkillDetails(skill)
        return (details.requiredSP, details.trainingTime)
    }

    private func getSkillPointRange(_ skill: PlannedSkill) -> (start: Int, end: Int) {
        let timeMultiplier = getSkillTimeMultiplier(skill.skillID)
        // 使用目标等级-1作为起始等级，目标等级作为结束等级
        let startLevel = skill.targetLevel - 1
        let endLevel = skill.targetLevel

        // 使用缓存的技能数据
        let actualSkillPoints = learnedSkills[skill.skillID]?.skillpoints_in_skill ?? 0
        let actualLevel = learnedSkills[skill.skillID]?.trained_skill_level ?? 0

        // 如果实际等级等于计划的起始等级，使用实际技能点数作为起始点
        let startSP =
            (actualLevel == startLevel)
                ? actualSkillPoints : (getBaseSkillPointsForLevel(startLevel) ?? 0) * timeMultiplier
        let endSP = (getBaseSkillPointsForLevel(endLevel) ?? 0) * timeMultiplier
        return (startSP, endSP)
    }

    private func deleteSkill(at offsets: IndexSet) {
        var updatedPlan = plan
        updatedPlan.skills.remove(atOffsets: offsets)

        // 使用通用函数更新计划
        updatedPlan = updatePlanWithSkills(updatedPlan, skills: updatedPlan.skills)

        persistPlan(updatedPlan)

        // 重新计算依赖关系
        calculateSkillDependencies()

        // 重新计算注入器需求
        Task { await recalculatePlanMetrics() }
    }

    /// 移除技能的某些等级（从技能选择器降级时调用）
    private func removeSkillLevels(skillId: Int, fromLevel: Int, toLevel: Int) {
        var updatedPlan = plan

        // 移除指定范围的技能等级
        updatedPlan.skills.removeAll { skill in
            skill.skillID == skillId && skill.targetLevel >= fromLevel && skill.targetLevel <= toLevel
        }

        // 使用通用函数更新计划
        updatedPlan = updatePlanWithSkills(updatedPlan, skills: updatedPlan.skills)

        persistPlan(updatedPlan)

        // 重新计算依赖关系（移除后其他技能可能可以降级）
        calculateSkillDependencies()

        // 重新计算注入器需求
        Task { await recalculatePlanMetrics() }
    }

    private func injectorItemView(info: InjectorInfo, count: Int, typeId: Int) -> some View {
        NavigationLink {
            ShowItemInfo(
                databaseManager: databaseManager,
                itemID: typeId
            )
        } label: {
            HStack {
                IconManager.shared.loadImage(for: info.iconFilename)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
                Text(info.name)
                Spacer()
                Text("\(count)")
                    .foregroundColor(.secondary)
            }
        }
    }

    private func injectorSummaryView(calculation: InjectorCalculation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(
                String(
                    format: NSLocalizedString("Main_Skills_Total_Required_SP", comment: ""),
                    FormatUtil.format(Double(calculation.totalSkillPoints))
                )
            )
            if let totalCost = totalInjectorCost {
                Text(
                    String(
                        format: NSLocalizedString("Main_Skills_Total_Injector_Cost", comment: ""),
                        FormatUtil.formatISK(totalCost)
                    )
                )
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }

    private struct InjectorInfo {
        let name: String
        let iconFilename: String
    }

    private func getInjectorInfo(typeId: Int) -> InjectorInfo? {
        guard let info = ItemInfoMap.typeInfo(for: typeId),
              !info.name.isEmpty
        else { return nil }
        return InjectorInfo(name: info.name, iconFilename: info.iconFilename)
    }

    private var totalInjectorCost: Double? {
        guard let calculation = injectorCalculation else {
            Logger.debug("计算总价失败 - 没有注入器计算结果")
            return nil
        }

        return InjectorPriceManager.shared.calculateTotalCost(
            calculation: calculation,
            prices: injectorPrices
        )
    }

    private func recalculatePlanMetrics(freshQueue: Bool? = nil, animated: Bool = false) async {
        let mode = freshQueue ?? freshQueueMode
        await MainActor.run {
            injectorCalculation = SkillInjectorCalculator.calculate(
                requiredSkillPoints: requiredSkillPoints(freshQueue: mode),
                characterTotalSP: mode ? 0 : (cachedCharacterTotalSP ?? 0)
            )
        }
        await updateOptimalAttributes(freshQueue: mode)
        await MainActor.run {
            syncDisplayedMetrics(freshQueue: mode, animated: animated)
        }
    }

    private func loadInjectorPricesIfNeeded() async {
        guard injectorPrices.large == nil || injectorPrices.small == nil else { return }
        await setNetworkLoadingPhase(.fetchingInjectorPrices)
        let prices = await InjectorPriceManager.shared.loadInjectorPrices()
        await MainActor.run {
            injectorPrices = prices
            networkLoadingPhase = nil
        }
    }

    /// 添加新的通用函数
    private func updatePlanWithSkills(_ currentPlan: SkillPlan, skills: [PlannedSkill]) -> SkillPlan {
        var updatedPlan = currentPlan
        updatedPlan.skills = skills

        // 更新计划的总训练时间和总技能点
        updatedPlan.totalTrainingTime = updatedPlan.skills.reduce(0) {
            $0 + ($1.isCompleted ? 0 : $1.trainingTime)
        }
        updatedPlan.totalSkillPoints = updatedPlan.skills.reduce(0) { total, skill in
            if skill.isCompleted {
                return total
            }
            let spRange = getSkillPointRange(skill)
            return total + (spRange.end - spRange.start)
        }

        return updatedPlan
    }

    private func createPlannedSkill(
        typeId: Int,
        skillName: String,
        targetLevel: Int,
        isCompleted: Bool
    ) -> PlannedSkill {
        let skill = PlannedSkill(
            id: UUID(),
            skillID: typeId,
            skillName: skillName,
            currentLevel: targetLevel - 1, // 计划中的当前等级始终是目标等级-1
            targetLevel: targetLevel,
            trainingTime: 0,
            requiredSP: 0,
            prerequisites: [],
            currentSkillPoints: getBaseSkillPointsForLevel(targetLevel - 1) ?? 0, // 使用计划等级的基础点数
            isCompleted: isCompleted
        )

        // 计算训练时间和所需技能点
        let (requiredSP, trainingTime) = calculateSkillRequirements(skill)

        return PlannedSkill(
            id: skill.id,
            skillID: skill.skillID,
            skillName: skill.skillName,
            currentLevel: skill.currentLevel,
            targetLevel: skill.targetLevel,
            trainingTime: trainingTime,
            requiredSP: requiredSP,
            prerequisites: skill.prerequisites,
            currentSkillPoints: skill.currentSkillPoints,
            isCompleted: isCompleted
        )
    }

    private func calculateAllSkillPoints() -> Int {
        // 计算所有技能点数，不考虑已学会的技能
        return plan.skills.reduce(0) { total, skill in
            let spRange = getSkillPointRange(skill)
            return total + (spRange.end - spRange.start)
        }
    }

    /// 清空所有技能
    private func clearAllSkills() {
        var updatedPlan = plan
        updatedPlan.skills = []

        // 使用通用函数更新计划
        updatedPlan = updatePlanWithSkills(updatedPlan, skills: [])

        persistPlan(updatedPlan)

        // 重新计算依赖关系
        calculateSkillDependencies()

        // 重新计算注入器需求
        Task { await recalculatePlanMetrics() }
    }

    /// 批量添加技能到计划（从 AddSkillSelectorView 回调）
    private func addBatchSkillsToPlan(skills: [(skillId: Int, skillName: String, level: Int)]) async {
        // 加载所有相关技能的数据
        let skillIds = Array(Set(skills.map { $0.skillId }))
        await ensureSkillsDataLoaded(skillIds: skillIds)

        // 批量添加技能
        addSkillLevelsToPlan(skills)
    }

    /// 确保技能数据已加载
    private func ensureSkillsDataLoaded(skillIds: [Int]) async {
        _ = await refreshSkillPlanNetworkCaches(skillIds: skillIds)

        if let attrs = characterAttributes {
            for skillId in skillIds {
                if trainingRates[skillId] != nil {
                    continue
                }
                if let (primary, secondary) = SkillTrainingCalculator.getSkillAttributes(
                    skillId: skillId, databaseManager: databaseManager
                ),
                    let rate = SkillTrainingCalculator.calculateTrainingRate(
                        primaryAttrId: primary,
                        secondaryAttrId: secondary,
                        attributes: attrs
                    )
                {
                    trainingRates[skillId] = rate
                }
            }
        }
    }

    /// 批量添加技能等级到计划（内部使用）
    private func addSkillLevelsToPlan(_ skillsToAdd: [(skillId: Int, skillName: String, level: Int)]) {
        var updatedSkills = plan.skills
        var skillNamesToLoad: Set<Int> = []

        // 收集需要加载名称的技能ID
        for skill in skillsToAdd where skill.skillName.isEmpty {
            skillNamesToLoad.insert(skill.skillId)
        }

        // 批量加载技能名称
        let skillNamesDict = skillNamesToLoad.isEmpty ? [:] : loadSkillNames(skillIds: Array(skillNamesToLoad))

        // 先收集每个技能已存在的最高等级
        var existingMaxLevels: [Int: Int] = [:] // [skillId: maxLevel]
        for skill in updatedSkills {
            let currentMax = existingMaxLevels[skill.skillID] ?? 0
            existingMaxLevels[skill.skillID] = max(currentMax, skill.targetLevel)
        }

        // 收集要添加的新技能等级
        var newSkills: [PlannedSkill] = []
        var skillsToAddSet: Set<String> = [] // 用于去重，格式: "skillId_level"

        for skill in skillsToAdd {
            let skillName = skill.skillName.isEmpty ? (skillNamesDict[skill.skillId] ?? "Unknown Skill (\(skill.skillId))") : skill.skillName
            let key = "\(skill.skillId)_\(skill.level)"

            // 如果该技能等级已在待添加列表中，跳过
            if skillsToAddSet.contains(key) {
                continue
            }

            // 如果该技能的该等级已存在于计划中，跳过
            if updatedSkills.contains(where: { $0.skillID == skill.skillId && $0.targetLevel == skill.level }) {
                Logger.debug("  [=] 技能等级已存在: \(skillName) 等级 \(skill.level)")
                continue
            }

            // 如果已存在更高等级，跳过
            if let existingMax = existingMaxLevels[skill.skillId], existingMax >= skill.level {
                Logger.debug("  [=] 已存在更高或相同等级: \(skillName) (已有等级 \(existingMax) >= \(skill.level))")
                continue
            }

            // 检查技能是否已完成
            let learnedSkill = learnedSkills[skill.skillId]
            let currentLevel = learnedSkill?.trained_skill_level ?? 0
            let isCompleted = skill.level <= currentLevel

            // 创建新技能
            let newSkill = createPlannedSkill(
                typeId: skill.skillId,
                skillName: skillName,
                targetLevel: skill.level,
                isCompleted: isCompleted
            )

            newSkills.append(newSkill)
            skillsToAddSet.insert(key)
            // 更新记录的最高等级
            let currentMax = existingMaxLevels[skill.skillId] ?? 0
            existingMaxLevels[skill.skillId] = max(currentMax, skill.level)
        }

        // 如果有新技能要添加
        if !newSkills.isEmpty {
            // 将新技能添加到计划中
            updatedSkills.append(contentsOf: newSkills)

            let updatedPlan = updatePlanWithSkills(plan, skills: updatedSkills)

            persistPlan(updatedPlan)

            // 重新计算依赖关系
            calculateSkillDependencies()

            // 重新计算注入器需求
            Task { await recalculatePlanMetrics() }

            Logger.debug("  [*] 批量添加完成，共添加 \(newSkills.count) 个技能等级")
        } else {
            Logger.debug("  [*] 没有新技能需要添加")
        }
    }

    /// 添加物品的所有技能依赖到计划
    private func addItemSkillsToPlan(itemId: Int, itemName: String) async {
        Logger.debug(" 开始添加物品技能依赖到计划 - 物品: \(itemName) (ID: \(itemId))")

        // 获取物品的所有技能依赖
        let requirements = SkillTreeManager.shared.getDeduplicatedSkillRequirements(
            for: itemId,
            databaseManager: databaseManager
        )

        guard !requirements.isEmpty else {
            Logger.debug("[-] 物品 \(itemName) 没有技能依赖")
            return
        }

        Logger.debug(" 物品需要 \(requirements.count) 个技能:")
        for requirement in requirements {
            if let skillName = SkillTreeManager.shared.getSkillName(for: requirement.skillID) {
                Logger.debug("  - \(skillName) (ID: \(requirement.skillID)) 等级: \(requirement.level)")
            }
        }

        // 获取所有需要添加的技能ID（用于批量加载数据）
        let skillIds = requirements.map { $0.skillID }

        // 批量加载技能名称
        let skillNamesDict = loadSkillNames(skillIds: skillIds)

        // 收集所有需要添加的技能（包括前置技能）
        var skillsToAdd: [(skillId: Int, skillName: String, level: Int)] = []
        var allSkillIds: Set<Int> = []

        for requirement in requirements {
            let skillName = skillNamesDict[requirement.skillID] ?? "Unknown Skill (\(requirement.skillID))"

            // 收集前置技能
            let prerequisites = getAllPrerequisitesForSkill(skillId: requirement.skillID, requiredLevel: requirement.level)
            for prereq in prerequisites {
                skillsToAdd.append((skillId: prereq.skillId, skillName: "", level: prereq.requiredLevel))
                allSkillIds.insert(prereq.skillId)
            }

            // 收集目标技能的所有等级（从1到目标等级）
            for currentLevel in 1 ... requirement.level {
                skillsToAdd.append((skillId: requirement.skillID, skillName: skillName, level: currentLevel))
                allSkillIds.insert(requirement.skillID)
            }
        }

        // 加载所有相关技能的数据
        await ensureSkillsDataLoaded(skillIds: Array(allSkillIds))

        // 批量添加所有技能
        addSkillLevelsToPlan(skillsToAdd)

        Logger.debug(" 物品技能依赖添加完成")
    }

    /// 获取技能的所有前置要求（递归，包括所有等级，从1级开始）
    private func getAllPrerequisitesForSkill(
        skillId: Int,
        requiredLevel _: Int
    ) -> [(skillId: Int, requiredLevel: Int)] {
        var depthCache: [Int: Int] = [:]
        func skillDepth(for id: Int) -> Int {
            if let cached = depthCache[id] { return cached }
            let directReqs = SkillTreeManager.shared.directSkillRequirements(for: id)
            let depth: Int
            if directReqs.isEmpty {
                depth = 0
            } else {
                depth = 1 + (directReqs.map { skillDepth(for: $0.skillID) }.max() ?? 0)
            }
            depthCache[id] = depth
            return depth
        }

        let skillLevels = SkillTreeManager.shared.prerequisiteMaxLevels(for: skillId)
        var allPrerequisites: [(skillId: Int, requiredLevel: Int)] = []
        for (prereqSkillId, maxLevel) in skillLevels {
            for level in 1 ... maxLevel {
                allPrerequisites.append((skillId: prereqSkillId, requiredLevel: level))
            }
        }

        return allPrerequisites.sorted { first, second in
            let depth1 = skillDepth(for: first.skillId)
            let depth2 = skillDepth(for: second.skillId)

            if depth1 != depth2 {
                return depth1 < depth2
            } else if first.skillId == second.skillId {
                return first.requiredLevel < second.requiredLevel
            } else {
                return first.skillId < second.skillId
            }
        }
    }

    /// 批量加载技能名称
    private func loadSkillNames(skillIds: [Int]) -> [Int: String] {
        guard !skillIds.isEmpty else { return [:] }
        var skillNames: [Int: String] = [:]
        for skillId in skillIds {
            if let name = ItemInfoMap.typeName(for: skillId) {
                skillNames[skillId] = name
            }
        }
        return skillNames
    }

    /// 获取计划中已有技能的最高等级
    private func getExistingSkillLevels() -> [Int: Int] {
        var skillLevels: [Int: Int] = [:]
        for skill in plan.skills {
            let currentMax = skillLevels[skill.skillID] ?? 0
            skillLevels[skill.skillID] = max(currentMax, skill.targetLevel)
        }
        return skillLevels
    }

    /// 计算技能的后置依赖关系
    private func calculateSkillDependencies() {
        var dependencies: [String: Set<String>] = [:]

        for skill in plan.skills {
            let skillKey = "\(skill.skillID)_\(skill.targetLevel)"

            // 1. 该技能的低等级被高等级依赖
            // 例如：Amarr Destroyer 3 依赖 Amarr Destroyer 2, 1
            if skill.targetLevel > 1 {
                for lowerLevel in 1 ..< skill.targetLevel {
                    let lowerKey = "\(skill.skillID)_\(lowerLevel)"
                    dependencies[lowerKey, default: []].insert(skillKey)
                }
            }

            // 2. 该技能依赖的前置技能
            for (prereqId, level) in SkillTreeManager.shared.prerequisiteMaxLevels(for: skill.skillID) {
                let prereqKey = "\(prereqId)_\(level)"
                dependencies[prereqKey, default: []].insert(skillKey)
            }
        }

        skillDependencies = dependencies
    }

    /// 检查技能等级是否有后置依赖
    private func hasPostDependencies(skillId: Int, level: Int) -> Bool {
        let key = "\(skillId)_\(level)"
        return !(skillDependencies[key]?.isEmpty ?? true)
    }

    /// 判断当前数据库语言是否为英文
    private func isEnglishLanguage() -> Bool {
        let dbLanguage = UserDefaults.standard.string(forKey: "selectedDatabaseLanguage") ?? "en"
        return dbLanguage == "en"
    }

    /// 导出技能计划
    private func exportSkillPlan(useEnglishNames: Bool) async {
        guard !plan.skills.isEmpty else {
            await MainActor.run {
                errorMessage = NSLocalizedString("Main_Skills_Plan_Export_Empty", comment: "技能计划为空，无法导出")
                showErrorAlert = true
            }
            return
        }

        // 获取所有技能ID
        let skillIds = plan.skills.map { $0.skillID }

        var skillNamesDict: [Int: String] = [:]
        for skillId in skillIds {
            guard let info = ItemInfoMap.typeInfo(for: skillId) else { continue }
            let skillName = useEnglishNames ? info.enName : info.name
            if !skillName.isEmpty {
                skillNamesDict[skillId] = skillName
            }
        }

        // 构建导出文本
        var exportLines: [String] = []
        for skill in plan.skills {
            if let skillName = skillNamesDict[skill.skillID] {
                exportLines.append("\(skillName) \(skill.targetLevel)")
            } else {
                // 如果找不到技能名称，使用ID作为后备
                exportLines.append("Unknown Skill (\(skill.skillID)) \(skill.targetLevel)")
            }
        }

        let exportText = exportLines.joined(separator: "\n")

        // 复制到剪贴板
        await MainActor.run {
            UIPasteboard.general.string = exportText
            showExportSuccessAlert = true
        }

        Logger.debug("导出技能计划完成，共 \(exportLines.count) 个技能")
    }
}
