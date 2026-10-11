import Foundation
import SwiftUI

/// 植入体属性加成
struct ImplantAttributes {
    var charismaBonus: Int = 0
    var intelligenceBonus: Int = 0
    var memoryBonus: Int = 0
    var perceptionBonus: Int = 0
    var willpowerBonus: Int = 0
}

struct CharacterSkillsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var displayLocale
    @Environment(\.timeZone) private var displayTimeZone
    let characterId: Int
    let databaseManager: DatabaseManager
    @State private var skillQueue: [SkillQueueItem] = []
    @State private var skillNames: [Int: String] = [:]
    @State private var isRefreshing = false
    @State private var isLoading = true
    @State private var isLoadingInjectors = true
    @State private var skillIcon: Image?
    @State private var injectorCalculation: InjectorCalculation?
    @State private var injectorPrices: InjectorPriceManager.InjectorPrices =
        .init(large: nil, small: nil)
    @State private var characterAttributes: CharacterAttributes?
    @State private var implantBonuses: ImplantAttributes?
    @State private var trainingRates: [Int: Int] = [:] // [skillId: pointsPerHour]
    @State private var optimalAttributes: OptimalAttributeAllocation?
    @State private var attributeComparisons:
        [(name: String, icon: String, current: Int, optimal: Int, diff: Int)] = []
    @State private var isDataReady = false
    @State private var hasInitialized = false // 追踪是否已执行初始化
    @State private var currentLoadTask: Task<Void, Never>? // 追踪当前加载任务
    @State private var skillListUpdateTrigger: Int = 0 // 用于触发技能列表更新
    @State private var cachedCharacterTotalSP: Int = 0 // 缓存的角色总技能点数
    @State private var detectedBoosterBonus: Int = 0 // 加速器属性加成（加载时算一次）

    private func updateAttributeComparisons() {
        guard let attrs = characterAttributes,
              let optimal = optimalAttributes,
              implantBonuses != nil
        else {
            attributeComparisons = []
            return
        }

        let minAttr = 17 // 基础属性值

        // 只添加需要分配点数的属性
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

        // 只添加有分配点数的属性
        for attr in attributes {
            if attr.4 > 0 { // 只显示分配了点数的属性
                comparisons.append(attr)
            }
        }

        attributeComparisons = comparisons
    }

    private var activeSkills: [SkillQueueItem] {
        let now = Date()

        // 检查队列是否暂停
        let isPaused = isQueuePaused

        // 根据队列状态过滤技能
        let filteredQueue =
            skillQueue
                .filter { skill in
                    // 如果队列暂停，显示所有技能
                    if isPaused {
                        return true
                    }

                    // 如果队列在训练，过滤掉已完成的技能
                    guard let startDate = skill.start_date,
                          let finishDate = skill.finish_date
                    else {
                        return false
                    }

                    // 只显示未完成的技能（正在训练或等待训练）
                    return finishDate > now || startDate > now
                }
                .sorted { $0.queue_position < $1.queue_position }

        // 动态确定当前正在训练的技能
        var activeQueue = filteredQueue

        // 找到第一个应该正在训练的技能（开始时间已到但未完成）
        if let currentTrainingSkill = activeQueue.first(where: { skill in
            guard let startDate = skill.start_date,
                  let finishDate = skill.finish_date
            else {
                return false
            }
            return now >= startDate && now < finishDate
        }) {
            // 将正在训练的技能移到第一位
            if let trainingIndex = activeQueue.firstIndex(where: {
                $0.skill_id == currentTrainingSkill.skill_id
            }) {
                let trainingSkill = activeQueue.remove(at: trainingIndex)
                activeQueue.insert(trainingSkill, at: 0)
            }
        }

        return activeQueue
    }

    private var isQueuePaused: Bool {
        guard let firstSkill = skillQueue.first,
              firstSkill.start_date != nil,
              firstSkill.finish_date != nil
        else {
            return true
        }
        return false
    }

    /// 动态判断技能是否正在训练
    private func isSkillCurrentlyTraining(_ item: SkillQueueItem) -> Bool {
        let now = Date()
        guard let startDate = item.start_date,
              let finishDate = item.finish_date
        else {
            return false
        }
        return now >= startDate && now < finishDate
    }

    /// 计算活跃技能列表的总剩余时间
    private func calculateTotalRemainingTime(for skills: [SkillQueueItem]) -> TimeInterval? {
        guard let lastSkill = skills.last,
              let finishDate = lastSkill.finish_date,
              finishDate.timeIntervalSinceNow > 0
        else {
            return nil
        }
        return finishDate.timeIntervalSinceNow
    }

    /// 触发技能列表更新
    private func triggerSkillListUpdate() {
        // 使用延迟避免频繁触发
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            skillListUpdateTrigger += 1
        }
    }

    /// 计算注入器总价值
    private var totalInjectorCost: Double? {
        guard let calculation = injectorCalculation else {
            return nil
        }

        return InjectorPriceManager.shared.calculateTotalCost(
            calculation: calculation,
            prices: injectorPrices
        )
    }

    var body: some View {
        List {
            if isLoading || !isDataReady {
                CharacterSkillsSkeleton()
            } else {
                // 第一个列表 - 属性和技能目录导航
                navigationSection

                // 第二个列表 - 技能队列
                skillQueueSection

                // 第三个列表 - 注入器需求
                injectorSection

                // 第四个列表 - 属性对比
                attributeComparisonSection
            }
        }
        .navigationTitle(NSLocalizedString("Main_Skills", comment: ""))
        .refreshable {
            currentLoadTask?.cancel()
            let task = Task {
                guard !isRefreshing else { return }
                await refreshSkillQueue()
            }
            currentLoadTask = task
            await task.value
        }
        .onAppear {
            loadInitialDataIfNeeded()
        }
        .onDisappear {
            currentLoadTask?.cancel()
        }
    }

    private var navigationSection: some View {
        Section {
            NavigationLink {
                CharacterAttributesView(characterId: characterId)
            } label: {
                HStack {
                    Image("attributes")
                        .resizable()
                        .frame(width: 36, height: 36)
                        .cornerRadius(6)
                        .drawingGroup()
                    Text(NSLocalizedString("Main_Skills_Attribute", comment: ""))
                }
            }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

            NavigationLink {
                SkillCategoryView(characterId: characterId, databaseManager: databaseManager)
            } label: {
                HStack {
                    Image("skills")
                        .resizable()
                        .frame(width: 36, height: 36)
                        .cornerRadius(6)
                        .drawingGroup()
                    Text(NSLocalizedString("Main_Skills_Category", comment: ""))
                }
            }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

            NavigationLink {
                SkillPlanView(characterId: characterId, databaseManager: databaseManager)
            } label: {
                HStack {
                    Image("notegroup")
                        .resizable()
                        .frame(width: 32, height: 36)
                        .foregroundColor(.blue)
                    Text(NSLocalizedString("Main_Skills_Plan", comment: ""))
                }
            }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        } header: {
            Text(NSLocalizedString("Main_Skills_Categories", comment: ""))
        }
    }

    @ViewBuilder
    private var skillQueueSection: some View {
        let currentActiveSkills = activeSkills // 根据触发器重新计算
        // 从同一份可见队列一次性计算等级，避免每行重复筛选、排序整个队列。
        let currentLevels = currentActiveSkills.reduce(into: [Int: Int]()) { levels, item in
            let level = item.finished_level - 1
            levels[item.skill_id] = min(levels[item.skill_id] ?? level, level)
        }

        Section {
            if skillQueue.isEmpty {
                Text(NSLocalizedString("Main_Skills_Queue_Empty", comment: ""))
                    .foregroundColor(.secondary)
            } else if currentActiveSkills.isEmpty {
                Text(NSLocalizedString("Main_Skills_Queue_All_Completed", comment: "所有技能已完成"))
                    .foregroundColor(.secondary)
            } else {
                ForEach(currentActiveSkills) { item in
                    NavigationLink {
                        ShowItemInfo(
                            databaseManager: databaseManager,
                            itemID: item.skill_id
                        )
                    } label: {
                        skillQueueItemView(item, currentLevel: currentLevels[item.skill_id] ?? 0)
                    }
                }
            }
        } header: {
            skillQueueHeaderView(activeSkills: currentActiveSkills)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        .id(skillListUpdateTrigger) // 当触发器改变时重新计算
    }

    @ViewBuilder
    private var injectorSection: some View {
        if !skillQueue.isEmpty, !isLoadingInjectors, let calculation = injectorCalculation,
           calculation.largeInjectorCount + calculation.smallInjectorCount > 0
        {
            Section {
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

                // 总计所需技能点和预计价格（使用实时更新）
                dynamicInjectorSummaryView(calculation: calculation)
            } header: {
                Text(NSLocalizedString("Main_Skills_Required_Injectors", comment: ""))
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        }
    }

    @ViewBuilder
    private var attributeComparisonSection: some View {
        if !attributeComparisons.isEmpty {
            Section {
                ForEach(attributeComparisons, id: \.name) { attr in
                    attributeComparisonItemView(attr)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

                if let optimal = optimalAttributes {
                    VStack(alignment: .leading, spacing: 4) {
                        if optimal.savedTime > 0 {
                            Text(
                                String(
                                    format: NSLocalizedString(
                                        "Main_Skills_Optimal_Attributes_Time_Saved", comment: ""
                                    ),
                                    FormatUtil.formatCompactDuration(optimal.savedTime, rounding: .ceil)
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

                        // 只在检测到加速器时显示注释信息
                        if detectedBoosterBonus > 0 {
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

    @ViewBuilder
    private func skillQueueHeaderView(activeSkills: [SkillQueueItem]) -> some View {
        if skillQueue.isEmpty {
            Text(String.localizedStringWithFormat(NSLocalizedString("Main_Skills_Queue_Count", comment: ""), 0))
        } else if isQueuePaused {
            Text(
                String(
                    format: NSLocalizedString("Main_Skills_Queue_Count_Paused", comment: ""),
                    activeSkills.count
                )
            )
        } else if let totalTime = calculateTotalRemainingTime(for: activeSkills) {
            Text(
                String(
                    format: NSLocalizedString("Main_Skills_Queue_Count_Time", comment: ""),
                    activeSkills.count,
                    FormatUtil.formatCompactDuration(totalTime, rounding: .ceil)
                )
            )
            .fontDesign(.monospaced)
        } else {
            Text(
                String(
                    format: NSLocalizedString("Main_Skills_Queue_Count", comment: ""),
                    activeSkills.count
                )
            )
        }
    }

    private func skillQueueItemView(_ item: SkillQueueItem, currentLevel: Int) -> some View {
        HStack(spacing: 8) {
            if let icon = skillIcon {
                icon
                    .resizable()
                    .frame(width: 36, height: 36)
                    .cornerRadius(6)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 2) {
                    Text(
                        skillNames[item.skill_id]
                            ?? NSLocalizedString("Main_Database_Loading", comment: "")
                    )
                    .lineLimit(1)
                    Spacer()
                    Text(
                        String(
                            format: NSLocalizedString("Misc_Level_Short", comment: ""),
                            item.finished_level
                        )
                    )
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .padding(.trailing, 2)
                    SkillLevelIndicator(
                        currentLevel: currentLevel,
                        trainingLevel: item.finished_level,
                        isTraining: isSkillCurrentlyTraining(item)
                    )
                    .padding(.trailing, 4)
                }

                if let progress = calculateProgress(item) {
                    skillProgressView(item: item, progress: progress)
                }
            }
        }
        .contextMenu {
            if let skillName = skillNames[item.skill_id] {
                Button {
                    UIPasteboard.general.string = skillName
                } label: {
                    Label(NSLocalizedString("Misc_Copy", comment: ""), systemImage: "doc.on.doc")
                }
            }
        }
    }

    private func skillProgressView(item: SkillQueueItem, progress: ProgressInfo) -> some View {
        VStack(spacing: 2) {
            if isSkillCurrentlyTraining(item) {
                // 正在训练的技能使用实时更新
                TimelineView(.periodic(from: Date(), by: 1.0)) { timeline in
                    let now = timeline.date
                    let realtimeProgress = calculateRealtimeProgress(item, at: now)
                    let displayedSkillPoints = Int(realtimeProgress.current)
                    VStack(spacing: 2) {
                        HStack(spacing: 2) {
                            Text(
                                String(
                                    format: NSLocalizedString(
                                        "Main_Skills_Points_Progress", comment: ""
                                    ),
                                    FormatUtil.formatInteger(displayedSkillPoints),
                                    FormatUtil.formatInteger(realtimeProgress.total)
                                )
                            )
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(displayedSkillPoints)))
                            .animation(
                                reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.78),
                                value: displayedSkillPoints
                            )

                            if let rate = trainingRates[item.skill_id] {
                                Text("(\(FormatUtil.formatInteger(rate))/h)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            // 实时倒计时
                            if let finishDate = item.finish_date {
                                let remainingTime = finishDate.timeIntervalSince(now)
                                if remainingTime > 0 {
                                    Text(
                                        String(
                                            format: NSLocalizedString(
                                                "Main_Skills_Time_Required", comment: ""
                                            ),
                                            FormatUtil.formatCompactDuration(remainingTime, rounding: .ceil)
                                        )
                                    )
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                } else {
                                    Text(NSLocalizedString("Main_Skills_Completed", comment: "完成"))
                                        .font(.caption)
                                        .foregroundColor(.green)
                                        .onAppear {
                                            // 技能完成时触发列表更新
                                            triggerSkillListUpdate()
                                        }
                                }
                            }
                        }

                        PulsingProgressBar(
                            progress: realtimeProgress.percentage,
                            color: .blue,
                            height: 4,
                            cornerRadius: 2
                        )
                        .padding(.top, 1)
                    }
                }
            } else {
                // 非训练技能使用静态显示
                HStack(spacing: 2) {
                    Text(
                        String(
                            format: NSLocalizedString("Main_Skills_Points_Progress", comment: ""),
                            FormatUtil.formatInteger(Int(progress.current)),
                            FormatUtil.formatInteger(progress.total)
                        )
                    )
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)

                    if let rate = trainingRates[item.skill_id] {
                        Text("(\(FormatUtil.formatInteger(rate))/h)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    skillTimeView(item: item, progress: progress)
                }
            }
        }
    }

    private func calculateRealtimeProgress(_ item: SkillQueueItem, at currentTime: Date)
        -> ProgressInfo
    {
        guard let levelEndSp = item.level_end_sp,
              let trainingStartSp = item.training_start_sp,
              let levelStartSp = item.level_start_sp,
              let startDate = item.start_date,
              let finishDate = item.finish_date
        else {
            return ProgressInfo(current: 0, total: 0, percentage: 0)
        }

        var currentSP = Double(trainingStartSp)

        if currentTime < startDate {
            // 还未开始训练
            currentSP = Double(trainingStartSp)
        } else if currentTime > finishDate {
            // 已完成训练
            currentSP = Double(levelEndSp)
        } else {
            // 正在训练中，使用时间比例和训练速度计算当前进度
            if let rate = trainingRates[item.skill_id] {
                let trainedTime = currentTime.timeIntervalSince(startDate)
                let trainedHours = trainedTime / 3600.0
                let trainedSP = Double(rate) * trainedHours
                currentSP = Double(trainingStartSp) + trainedSP

                // 确保不超过目标值
                currentSP = min(currentSP, Double(levelEndSp))
            } else {
                // 如果没有训练速度数据，使用时间比例
                let totalTrainingTime = finishDate.timeIntervalSince(startDate)
                let trainedTime = currentTime.timeIntervalSince(startDate)
                let timeProgress = trainedTime / totalTrainingTime

                let remainingSP = levelEndSp - trainingStartSp
                let trainedSP = Double(remainingSP) * timeProgress
                currentSP = Double(trainingStartSp) + trainedSP
            }
        }

        // 计算当前等级的进度
        let levelTotalSP = levelEndSp - levelStartSp
        let levelCurrentSP = currentSP - Double(levelStartSp)

        return ProgressInfo(
            current: currentSP,
            total: levelEndSp,
            percentage: levelCurrentSP / Double(levelTotalSP)
        )
    }

    @ViewBuilder
    private func skillTimeView(item: SkillQueueItem, progress: ProgressInfo) -> some View {
        if isSkillCurrentlyTraining(item) {
            if let remainingTime = item.remainingTime {
                Text(
                    String(
                        format: NSLocalizedString("Main_Skills_Time_Required", comment: ""),
                        FormatUtil.formatCompactDuration(remainingTime, rounding: .ceil)
                    )
                )
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
            }
        } else if let startDate = item.start_date,
                  let finishDate = item.finish_date
        {
            // 如果有服务器时间，使用服务器时间
            let trainingTime = finishDate.timeIntervalSince(startDate)
            Text(
                String(
                    format: NSLocalizedString("Main_Skills_Time_Required", comment: ""),
                    FormatUtil.formatCompactDuration(trainingTime, rounding: .ceil)
                )
            )
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(.secondary)
        } else if isQueuePaused {
            // 如果队列暂停且没有服务器时间，才使用计算的时间
            if let rate = trainingRates[item.skill_id] {
                let remainingSP = progress.total - Int(progress.current)
                let trainingTimeHours = Double(remainingSP) / Double(rate)
                let trainingTime = trainingTimeHours * 3600 // 转换为秒

                Text(
                    String(
                        format: NSLocalizedString("Main_Skills_Time_Required", comment: ""),
                        FormatUtil.formatCompactDuration(trainingTime, rounding: .ceil)
                    )
                )
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
            }
        }
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

                VStack(alignment: .leading, spacing: 2) {
                    Text(info.name)

                    // 显示每个注入器在当前技能情况下的实际注入量
                    let isLarge = typeId == SkillInjectorCalculator.largeInjectorTypeId
                    let actualSP = SkillInjectorCalculator.getInjectorSkillPoints(
                        isLarge: isLarge,
                        characterTotalSP: cachedCharacterTotalSP
                    )
                    Text(
                        String(
                            format: NSLocalizedString(
                                "Main_Skills_Injector_Actual_SP", comment: "每个+%@ SP"
                            ),
                            FormatUtil.format(Double(actualSP))
                        )
                    )
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                }

                Spacer()
                Text("\(count)")
                    .foregroundColor(.secondary)
            }
        }
    }

    private func dynamicInjectorSummaryView(calculation: InjectorCalculation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(
                String(
                    format: NSLocalizedString("Main_Skills_Total_Required_SP", comment: ""),
                    FormatUtil.format(Double(calculation.totalSkillPoints))
                )
            )
            .fontDesign(.monospaced)
            if let totalCost = totalInjectorCost {
                Text(
                    String(
                        format: NSLocalizedString(
                            "Main_Skills_Total_Injector_Cost", comment: ""
                        ),
                        FormatUtil.formatISK(totalCost)
                    )
                )
                .font(.system(.caption, design: .monospaced))
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }

    private func attributeComparisonItemView(
        _ attr: (name: String, icon: String, current: Int, optimal: Int, diff: Int)
    ) -> some View {
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
    }

    private func loadInitialDataIfNeeded() {
        guard !hasInitialized else { return }

        hasInitialized = true

        Task {
            await loadSkillQueue()
        }
    }

    private func loadSkillQueue(forceRefresh: Bool = false) async {
        // 仅在没有已有数据时显示加载状态；刷新时保留现有数据，避免列表闪烁
        let hasExistingData = isDataReady
        if !hasExistingData {
            isLoading = true
            isDataReady = false
        }

        do {
            var loadedAttributes: CharacterAttributes?
            var loadedImplants: ImplantAttributes?
            var loadedQueue: [SkillQueueItem] = []
            var loadedSkills: CharacterSkillsResponse?

            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    loadedAttributes = try await CharacterSkillsAPI.shared.fetchAttributes(
                        characterId: characterId
                    )
                }

                group.addTask {
                    loadedImplants = await SkillTrainingCalculator.getImplantBonuses(
                        characterId: characterId
                    )
                }

                // 技能快照 + 队列一次读盘/拉取，避免注入器计算再次读 bundle
                group.addTask {
                    let pair = try await CharacterSkillsAPI.shared.fetchCharacterSkillsAndQueue(
                        characterId: characterId,
                        forceRefresh: forceRefresh
                    )
                    loadedSkills = pair.skills
                    loadedQueue = pair.queue
                }

                try await group.waitForAll()
            }

            guard let attributes = loadedAttributes,
                  let implants = loadedImplants
            else {
                throw NSError(
                    domain: "CharacterSkillsView", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "加载数据失败"]
                )
            }

            let skillIds = loadedQueue.map { $0.skill_id }
            let skillAttrsMap = SkillTrainingCalculator.loadSkillAttributes(
                skillIds: skillIds,
                databaseManager: databaseManager
            )

            var names: [Int: String] = [:]
            for skillId in skillIds {
                if let name = ItemInfoMap.typeName(for: skillId) {
                    names[skillId] = name
                }
            }

            var rates: [Int: Int] = [:]
            for skillId in skillIds {
                guard let attrs = skillAttrsMap[skillId],
                      let rate = SkillTrainingCalculator.calculateTrainingRate(
                          primaryAttrId: attrs.primary,
                          secondaryAttrId: attrs.secondary,
                          attributes: attributes
                      )
                else { continue }
                rates[skillId] = rate
            }

            let booster = SkillTrainingCalculator.detectBoosterBonus(
                currentAttributes: attributes,
                implantBonuses: implants
            )

            let totalSPFromSkills = loadedSkills.map { $0.total_sp + $0.unallocated_sp }

            // 基础数据就绪后立即显示列表（不等待耗时的最优属性计算和注入器价格）
            await MainActor.run {
                self.characterAttributes = attributes
                self.implantBonuses = implants
                self.detectedBoosterBonus = booster
                self.skillQueue = loadedQueue
                self.skillNames = names
                self.trainingRates = rates
                self.isLoading = false
                self.isDataReady = true
            }

            // 最优属性分配使用回溯算法枚举所有分配组合，可能较耗时，放到独立任务不阻塞列表
            Task {
                let queueInfo = loadedQueue.compactMap {
                    item -> (skillId: Int, remainingSP: Int, startDate: Date?, finishDate: Date?)? in
                    guard let levelEndSp = item.level_end_sp,
                          let trainingStartSp = item.training_start_sp
                    else {
                        return nil
                    }
                    return (
                        skillId: item.skill_id,
                        remainingSP: levelEndSp - trainingStartSp,
                        startDate: item.start_date,
                        finishDate: item.finish_date
                    )
                }

                let optimal = await SkillTrainingCalculator.calculateOptimalAttributes(
                    skillQueue: queueInfo,
                    databaseManager: databaseManager,
                    currentAttributes: attributes,
                    characterId: characterId,
                    implantBonuses: implants,
                    skillAttributes: skillAttrsMap,
                    boosterBonus: booster
                ).map { result in
                    OptimalAttributeAllocation(
                        charisma: result.charisma,
                        intelligence: result.intelligence,
                        memory: result.memory,
                        perception: result.perception,
                        willpower: result.willpower,
                        totalTrainingTime: result.totalTrainingTime,
                        currentTrainingTime: result.currentTrainingTime
                    )
                }

                await MainActor.run {
                    self.optimalAttributes = optimal
                    updateAttributeComparisons()
                }
            }

            Task {
                await calculateInjectors(characterTotalSP: totalSPFromSkills)
            }

        } catch {
            Logger.error("加载技能数据失败: \(error)")
            await MainActor.run {
                self.isLoading = false
                self.isDataReady = true
            }
        }
    }

    private func refreshSkillQueue() async {
        guard !Task.isCancelled else { return }

        await MainActor.run {
            isRefreshing = true
        }

        await loadSkillQueue(forceRefresh: true)

        if !Task.isCancelled {
            await MainActor.run {
                isRefreshing = false
            }
        }

        // 添加延迟以防止快速连续刷新
        if !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
        }
    }

    /// 计算注入器需求并加载价格
    /// - Parameter characterTotalSP: 已有总技能点时传入，避免再读技能快照
    private func calculateInjectors(characterTotalSP: Int? = nil) async {
        isLoadingInjectors = true
        defer { isLoadingInjectors = false }

        // 计算队列中所需的总技能点数
        var totalRequiredSP = 0
        for item in skillQueue {
            if let endSP = item.level_end_sp,
               let startSP = item.training_start_sp
            {
                if item.isCurrentlyTraining {
                    // 对于正在训练的技能，从当前训练进度开始计算
                    if let finishDate = item.finish_date,
                       let startDate = item.start_date
                    {
                        let now = Date()
                        let totalTrainingTime = finishDate.timeIntervalSince(startDate)
                        let trainedTime = now.timeIntervalSince(startDate)
                        let progress = trainedTime / totalTrainingTime
                        let totalSP = endSP - startSP
                        let trainedSP = Int(Double(totalSP) * progress)
                        let remainingSP = totalSP - trainedSP
                        totalRequiredSP += remainingSP
                    }
                } else {
                    let requiredSP = endSP - startSP
                    totalRequiredSP += requiredSP
                }
            }
        }

        let resolvedTotalSP = if let characterTotalSP {
            characterTotalSP
        } else {
            await getCharacterTotalSP()
        }

        await MainActor.run {
            cachedCharacterTotalSP = resolvedTotalSP
        }

        injectorCalculation = SkillInjectorCalculator.calculate(
            requiredSkillPoints: totalRequiredSP,
            characterTotalSP: resolvedTotalSP
        )

        await loadInjectorPrices()
    }

    /// 获取角色总技能点数
    private func getCharacterTotalSP() async -> Int {
        do {
            // 直接调用API获取技能数据
            let skillsInfo = try await CharacterSkillsAPI.shared.fetchCharacterSkills(
                characterId: characterId,
                forceRefresh: false
            )
            let characterTotalSP = skillsInfo.total_sp + skillsInfo.unallocated_sp
            Logger.debug(
                "从API获取角色总技能点: \(characterTotalSP) (已分配: \(skillsInfo.total_sp), 未分配: \(skillsInfo.unallocated_sp))"
            )
            return characterTotalSP
        } catch {
            Logger.error("获取技能点数据失败: \(error)")
            return 0
        }
    }

    func loadInjectorPrices() async {
        let prices = await InjectorPriceManager.shared.loadInjectorPrices()

        await MainActor.run {
            injectorPrices = prices
        }
    }

    private struct InjectorInfo {
        let name: String
        let iconFilename: String
    }

    private func getInjectorInfo(typeId: Int) -> InjectorInfo? {
        guard let info = ItemInfoMap.typeInfo(for: typeId), !info.name.isEmpty else {
            return nil
        }
        return InjectorInfo(name: info.name, iconFilename: info.iconFilename)
    }

    private struct ProgressInfo {
        let current: Double
        let total: Int
        let percentage: Double
    }

    private func calculateProgress(_ item: SkillQueueItem) -> ProgressInfo? {
        // 1. 检查必要数据，增加 level_start_sp 的检查
        guard let levelEndSp = item.level_end_sp,
              let trainingStartSp = item.training_start_sp,
              let levelStartSp = item.level_start_sp
        else {
            return nil
        }

        var currentSP = Double(trainingStartSp)

        // 2. 计算实时进度
        if let startDate = item.start_date,
           let finishDate = item.finish_date
        {
            let now = Date()

            if now < startDate {
                // 2.1 还未开始训练
                currentSP = Double(trainingStartSp)
            } else if now > finishDate {
                // 2.2 已完成训练
                currentSP = Double(levelEndSp)
            } else {
                // 2.3 正在训练中，使用时间比例计算当前进度
                let totalTrainingTime = finishDate.timeIntervalSince(startDate)
                let trainedTime = now.timeIntervalSince(startDate)
                let timeProgress = trainedTime / totalTrainingTime

                let remainingSP = levelEndSp - trainingStartSp
                let trainedSP = Double(remainingSP) * timeProgress
                currentSP = Double(trainingStartSp) + trainedSP
            }
        }

        // 3. 修改进度计算逻辑，只计算当前等级的进度
        let levelTotalSP = levelEndSp - levelStartSp // 该等级需要的总技能点
        let levelCurrentSP = currentSP - Double(levelStartSp) // 在该等级已获得的技能点

        return ProgressInfo(
            current: currentSP,
            total: levelEndSp,
            percentage: levelCurrentSP / Double(levelTotalSP) // 计算该等级的实际进度
        )
    }

    private struct OptimalAttributeAllocation {
        let charisma: Int
        let intelligence: Int
        let memory: Int
        let perception: Int
        let willpower: Int
        let totalTrainingTime: TimeInterval
        let currentTrainingTime: TimeInterval

        var savedTime: TimeInterval {
            currentTrainingTime - totalTrainingTime
        }
    }
}
