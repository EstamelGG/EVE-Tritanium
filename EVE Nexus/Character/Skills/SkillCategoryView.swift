import SwiftUI

/// 技能筛选条件
enum SkillFilter: String, CaseIterable {
    case all
    case completed
    case notInjected
    case trainable

    var localized: String {
        switch self {
        case .all:
            return NSLocalizedString("Misc_All", comment: "全部")
        case .completed:
            return NSLocalizedString("Main_Skills_Completed", comment: "已完成")
        case .notInjected:
            return NSLocalizedString("Main_Skills_Not_Injected", comment: "未吸收")
        case .trainable:
            return NSLocalizedString("Main_Skills_Trainable", comment: "可训练")
        }
    }
}

/// 技能组模型
struct SkillGroup: Identifiable {
    let id: Int // groupID
    let name: String // group_name
    var skills: [CharacterSkill]
    let totalSkillsInGroup: Int // 该组中的总技能数
    let maxTotalSkillPoints: Int // 该组所有技能满级时的总点数
    let learnedTotalSkillPoints: Int // 该组已学技能的总点数

    var totalSkillPoints: Int {
        skills.reduce(0) { $0 + $1.skillpoints_in_skill }
    }
}

/// 技能目录视图模型
@MainActor
class SkillCategoryViewModel: ObservableObject {
    @Published var skillGroups: [SkillGroup] = []
    @Published var isLoading = true
    @Published var searchText = ""
    @Published var selectedFilter: SkillFilter = .all
    @Published var isRefreshing = false // 添加下拉刷新状态

    private let characterId: Int
    private let databaseManager: DatabaseManager
    private let characterDatabaseManager: CharacterDatabaseManager

    /// 修改 allSkillsDict 的类型
    var allSkillsDict:
        [Int: (
            names: LocalizedText,
            groupID: Int,
            timeMultiplier: Double,
            currentSkillPoints: Int,
            currentLevel: Int,
            trainingRate: Int?
        )] = [:]

    /// 添加一个数组来存储所有技能组
    private var allSkillGroups: [SkillGroup] = []

    /// 存储技能队列
    private var skillQueue: [SkillQueueItem] = []

    /// 获取指定技能组中在队列中的技能数量（仅未完成的，按技能ID去重）
    func getQueueCount(for group: SkillGroup) -> Int {
        let groupSkillIds = allSkillsDict.filter { $0.value.groupID == group.id }.keys
        return groupSkillIds.filter { hasActiveQueueItem($0) }.count
    }

    /// 整个分类的队列待训练点数，扣除已获得的 SP，避免与绿色部分重复。
    func getQueueSkillPoints(for group: SkillGroup) -> Int {
        var targetLevels: [Int: Int] = [:]
        let now = Date()
        for item in skillQueue {
            guard let info = allSkillsDict[item.skill_id], info.groupID == group.id,
                  (1 ... 5).contains(item.finished_level),
                  item.finish_date.map({ $0 > now }) ?? true else { continue }
            targetLevels[item.skill_id] = max(targetLevels[item.skill_id] ?? 0, item.finished_level)
        }
        return targetLevels.reduce(0) { total, item in
            guard let info = allSkillsDict[item.key],
                  let targetSP = SkillTreeManager.skillPoints(level: item.value, multiplier: info.timeMultiplier)
            else { return total }
            return total + max(0, targetSP - info.currentSkillPoints)
        }
    }

    /// 检查技能是否有未完成的队列项（用于"队列中"section，排除已全部完成的技能）
    /// 已完成：finish_date <= now
    func hasActiveQueueItem(_ skillId: Int) -> Bool {
        let now = Date()
        return skillQueue.contains { item in
            guard item.skill_id == skillId else { return false }
            if let finishDate = item.finish_date {
                return finishDate > now
            }
            return true // 无 finish_date 视为暂停，仍算在队列中
        }
    }

    /// 检查技能是否正在训练
    func isSkillCurrentlyTraining(_ skillId: Int) -> Bool {
        return skillQueue.first { $0.skill_id == skillId && $0.isCurrentlyTraining } != nil
    }

    /// 使用完整分类判断，避免筛选隐藏正在训练的技能后丢失标签。
    func isGroupCurrentlyTraining(_ group: SkillGroup) -> Bool {
        skillQueue.contains {
            $0.isCurrentlyTraining && allSkillsDict[$0.skill_id]?.groupID == group.id
        }
    }

    /// 获取技能在队列中的等级集合（排除正在训练的等级）
    func getQueuedLevels(for skillId: Int) -> Set<Int> {
        return Set(skillQueue.filter {
            $0.skill_id == skillId && !$0.isCurrentlyTraining
        }.map { $0.finished_level })
    }

    /// 获取技能正在训练的等级（如果正在训练）
    func getTrainingLevel(for skillId: Int) -> Int? {
        return skillQueue.first { $0.skill_id == skillId && $0.isCurrentlyTraining }?.finished_level
    }

    init(
        characterId: Int, databaseManager: DatabaseManager,
        characterDatabaseManager: CharacterDatabaseManager
    ) {
        self.characterId = characterId
        self.databaseManager = databaseManager
        self.characterDatabaseManager = characterDatabaseManager

        // 在初始化时就开始加载数据
        Task {
            await loadSkills()
        }
    }

    func loadSkills(forceRefresh: Bool = false) async {
        if forceRefresh {
            isRefreshing = true
        } else if allSkillsDict.isEmpty {
            // 已有数据时不显示全屏加载，避免从子页面返回时列表被替换导致滚动位置丢失
            isLoading = true
        }

        defer {
            isLoading = false
            isRefreshing = false
        }

        do {
            // 1. 一次调用获取技能数据和技能队列（API 内部并行请求）
            let (skillsResponse, queue) = try await CharacterSkillsAPI.shared.fetchCharacterSkillsAndQueue(
                characterId: characterId,
                forceRefresh: forceRefresh
            )

            // 合并队列中已完成的部分到技能等级，解决刚训练完的技能无法参与计算的问题
            let baseSkills = Dictionary(uniqueKeysWithValues: skillsResponse.skillsMap.map { ($0.key, $0.value.trained_skill_level) })
            let mergedSkillLevels = CharacterSkillsUtils.mergeCompletedQueueIntoSkills(
                baseSkills: baseSkills,
                queue: queue
            )

            // 使用已学习技能的查找字典（mergedSkillLevels 用于等级显示和计算）
            let learnedSkills = skillsResponse.skillsMap

            let skillsQuery = """
                SELECT 
                    t.type_id,
                    t.groupID,
                    t.group_name
                FROM types t
                WHERE t.published = 1 and t.categoryID = 16
            """

            guard case let .success(skillRows) = databaseManager.executeQuery(skillsQuery) else {
                return
            }

            // 3. 合并所有技能信息并计算技能组总数
            var groupDict: [Int: (name: String, skills: [Int])] = [:]
            for row in skillRows {
                guard let typeId = row["type_id"] as? Int,
                      let groupId = row["groupID"] as? Int,
                      let groupName = row["group_name"] as? String,
                      let type = SDEMemoryStore.type(for: typeId)
                else {
                    continue
                }

                // 保存技能组信息
                if groupDict[groupId] == nil {
                    groupDict[groupId] = (name: groupName, skills: [])
                }
                groupDict[groupId]?.skills.append(typeId)

                let timeMultiplier = SkillTreeManager.shared.trainingTimeMultiplier(for: typeId) ?? 1.0
                let learnedSkill = learnedSkills[typeId]
                // 使用合并后的等级（含队列中已完成的），确保刚训练完的技能正确参与计算
                let currentLevel = mergedSkillLevels[typeId] ?? learnedSkill?.trained_skill_level ?? -1

                allSkillsDict[typeId] = (
                    names: type.names,
                    groupID: groupId,
                    timeMultiplier: timeMultiplier,
                    currentSkillPoints: learnedSkill?.skillpoints_in_skill ?? 0,
                    currentLevel: currentLevel,
                    trainingRate: nil
                )
            }

            // 获取角色属性
            do {
                let attributes = try await CharacterSkillsAPI.shared.fetchAttributes(
                    characterId: characterId
                )

                // 计算每个技能的训练速度
                for (typeId, _) in allSkillsDict {
                    if let (primary, secondary) = SkillTrainingCalculator.getSkillAttributes(
                        skillId: typeId, databaseManager: databaseManager
                    ) {
                        let trainingRate = SkillTrainingCalculator.calculateTrainingRate(
                            primaryAttrId: primary,
                            secondaryAttrId: secondary,
                            attributes: attributes
                        )
                        allSkillsDict[typeId]?.trainingRate = trainingRate
                    }
                }
            } catch {
                Logger.error("获取角色属性失败: \(error)")
            }

            // 5. 按技能组组织数据
            var groups: [SkillGroup] = []
            for (groupId, groupInfo) in groupDict {
                // 获取该组所有技能
                let groupSkills = allSkillsDict.filter { $0.value.groupID == groupId }

                // 转换为 CharacterSkill 数组，包含所有技能
                let allSkills = groupSkills.map { typeId, info in
                    CharacterSkill(
                        active_skill_level: info.currentLevel,
                        skill_id: typeId,
                        skillpoints_in_skill: info.currentSkillPoints,
                        trained_skill_level: info.currentLevel
                    )
                }

                // 计算该组所有已发布技能满级时的总点数（包括未注入的技能）
                let maxTotalSP = groupSkills.reduce(0) { total, item in
                    let maxSP = Int(256_000 * item.value.timeMultiplier)
                    return total + maxSP
                }

                // 计算该组已学技能的总点数
                let learnedTotalSP = groupSkills.reduce(0) { total, item in
                    total + item.value.currentSkillPoints
                }

                if !allSkills.isEmpty {
                    groups.append(
                        SkillGroup(
                            id: groupId,
                            name: groupInfo.name,
                            skills: allSkills,
                            totalSkillsInGroup: groupSkills.count,
                            maxTotalSkillPoints: maxTotalSP,
                            learnedTotalSkillPoints: learnedTotalSP
                        )
                    )
                }
            }

            // 技能队列已在步骤1中并行加载
            await MainActor.run {
                self.skillQueue = queue
            }

            await MainActor.run {
                self.allSkillGroups = groups
                self.updateFilteredGroups()
            }

        } catch {
            Logger.error("加载技能数据失败: \(error)")
        }
    }

    /// 修改过滤方法
    func updateFilteredGroups() {
        if searchText.isEmpty {
            // 根据筛选条件过滤技能组
            skillGroups = allSkillGroups.map { group in
                // 根据筛选条件过滤技能
                let filteredSkills = group.skills.filter { skill in
                    switch selectedFilter {
                    case .all:
                        return true // 显示所有技能
                    case .completed:
                        return skill.trained_skill_level == 5
                    case .notInjected:
                        return skill.trained_skill_level == -1
                    case .trainable:
                        return skill.trained_skill_level >= 0 && skill.trained_skill_level < 5
                    }
                }

                // 只返回包含过滤后技能的组
                return SkillGroup(
                    id: group.id,
                    name: group.name,
                    skills: filteredSkills,
                    totalSkillsInGroup: group.totalSkillsInGroup,
                    maxTotalSkillPoints: group.maxTotalSkillPoints,
                    learnedTotalSkillPoints: group.learnedTotalSkillPoints
                )
            }.filter { !$0.skills.isEmpty } // 移除空组
        } else {
            // 搜索逻辑保持不变
            skillGroups = []
        }
    }

    /// 修改搜索功能
    var filteredSkills:
        [(
            typeId: Int, name: String, timeMultiplier: Double, currentSkillPoints: Int?,
            currentLevel: Int?, trainingRate: Int?
        )]
    {
        if searchText.isEmpty {
            return []
        } else {
            // 根据当前筛选条件过滤技能
            let filteredByLevel = allSkillsDict.filter { _, info in
                switch selectedFilter {
                case .all:
                    return true
                case .completed:
                    return info.currentLevel == 5
                case .notInjected:
                    return info.currentLevel == -1
                case .trainable:
                    return info.currentLevel >= 0 && info.currentLevel < 5
                }
            }

            // 在过滤后的技能中搜索
            return filteredByLevel
                .filter { _, info in
                    info.names.matchesSearch(searchText)
                }
                .map { typeId, info in
                    (
                        typeId: typeId,
                        name: info.names.resolved(),
                        timeMultiplier: info.timeMultiplier,
                        currentSkillPoints: info.currentSkillPoints,
                        currentLevel: info.currentLevel,
                        trainingRate: info.trainingRate
                    )
                }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }
}

/// 通用技能单元格视图
struct SkillCellView: View {
    @Environment(\.locale) private var displayLocale
    let skill:
        (
            typeId: Int,
            name: String,
            timeMultiplier: Double,
            currentSkillPoints: Int?,
            currentLevel: Int?,
            trainingRate: Int?
        )
    let viewModel: SkillCategoryViewModel?
    let showsQueueStatus: Bool

    init(
        skill: (
            typeId: Int, name: String, timeMultiplier: Double, currentSkillPoints: Int?,
            currentLevel: Int?, trainingRate: Int?
        ),
        viewModel: SkillCategoryViewModel? = nil,
        showsQueueStatus: Bool = true
    ) {
        self.skill = skill
        self.viewModel = viewModel
        self.showsQueueStatus = showsQueueStatus
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 2) {
                Text(skill.name)
                    .lineLimit(1)
                if skill.timeMultiplier >= 1 {
                    Text("(×\(String(format: "%.0f", skill.timeMultiplier)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                // 处理技能等级显示
                if let currentLevel = skill.currentLevel, currentLevel >= 0 {
                    Text(
                        String(
                            format: NSLocalizedString("Misc_Level_Short", comment: ""),
                            currentLevel
                        )
                    )
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .padding(.trailing, 2)

                    // 检查是否正在训练
                    let isTraining = viewModel?.isSkillCurrentlyTraining(skill.typeId) ?? false
                    let trainingLevel = viewModel?.getTrainingLevel(for: skill.typeId) ?? currentLevel
                    let queuedLevels = viewModel?.getQueuedLevels(for: skill.typeId) ?? []

                    SkillLevelIndicator(
                        currentLevel: currentLevel,
                        trainingLevel: trainingLevel,
                        isTraining: isTraining,
                        queuedLevels: queuedLevels
                    )
                    .padding(.trailing, 4)
                } else {
                    Text(NSLocalizedString("Main_Skills_Not_Injected", comment: ""))
                        .foregroundColor(.secondary)
                        .font(.caption)
                        .padding(.trailing, 4)
                }
            }

            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    let maxSkillPoints = Int(256_000 * skill.timeMultiplier)
                    let currentPoints = skill.currentSkillPoints ?? 0
                    let pointsText = String(
                        format: NSLocalizedString("Main_Skills_Points_Progress", comment: ""),
                        FormatUtil.formatInteger(currentPoints),
                        FormatUtil.formatInteger(maxSkillPoints)
                    )

                    Text(pointsText)
                        .font(.system(.caption, design: .monospaced))

                    if let rate = skill.trainingRate {
                        Text("(\(FormatUtil.formatInteger(rate))/h)")
                            .font(.system(.caption, design: .monospaced))
                    }
                    Spacer()

                    // 添加下一级训练时间显示
                    if let currentLevel = skill.currentLevel,
                       currentLevel >= -1 && currentLevel < 5, // 只有当前等级在-1 ~ 4之间时才显示
                       let rate = skill.trainingRate
                    {
                        let level = currentLevel == -1 ? 0 : currentLevel
                        let nextLevelPoints = Int(
                            Double(SkillTreeManager.levelBasePoints[level])
                                * skill.timeMultiplier
                        )
                        let remainingSP = nextLevelPoints - (skill.currentSkillPoints ?? 0)
                        let trainingTimeHours = Double(remainingSP) / Double(rate)
                        let trainingTime = trainingTimeHours * 3600 // 转换为秒
                        Text(
                            String(
                                format: NSLocalizedString("Main_Skills_Time_Required", comment: ""),
                                FormatUtil.formatCompactDuration(trainingTime, rounding: .ceil)
                            )
                        )
                        .font(.system(.caption, design: .monospaced))
                    }
                }

                // 检查技能状态，在新的一行显示（仅未完成的队列项显示"队列中"）
                let isTraining = viewModel?.isSkillCurrentlyTraining(skill.typeId) ?? false
                let hasActiveQueue = viewModel?.hasActiveQueueItem(skill.typeId) ?? false

                if isTraining {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 8, weight: .semibold))
                                .accessibilityHidden(true)
                            Text(NSLocalizedString("Main_Skills_Training", comment: ""))
                        }
                        .foregroundStyle(.blue)
                        Spacer()
                    }
                } else if showsQueueStatus && hasActiveQueue {
                    HStack {
                        Text(NSLocalizedString("Main_Skills_In_Queue", comment: ""))
                            .foregroundColor(.blue)
                        Spacer()
                    }
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }.contextMenu {
            Button {
                UIPasteboard.general.string = skill.name
            } label: {
                Label(NSLocalizedString("Misc_Copy", comment: ""), systemImage: "doc.on.doc")
            }
        }
    }
}

/// 分类进度始终以整个分类的满级技能点为基准，不随筛选改变。
private struct SkillCategoryRow: View {
    let group: SkillGroup
    let queueCount: Int
    let queueSkillPoints: Int
    let isTraining: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var progress: Double {
        guard group.maxTotalSkillPoints > 0 else { return 0 }
        return min(max(Double(group.learnedTotalSkillPoints) / Double(group.maxTotalSkillPoints), 0), 1)
    }

    private var progressColor: Color {
        progress >= 1
            ? (colorScheme == .dark
                ? Color(red: 1.0, green: 0.84, blue: 0.25)
                : Color(red: 0.95, green: 0.72, blue: 0.08))
            : .green
    }

    private var queuedProgress: Double {
        guard group.maxTotalSkillPoints > 0 else { return 0 }
        return min(max(Double(queueSkillPoints) / Double(group.maxTotalSkillPoints), 0), 1 - progress)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(SkillGroupIconManager.shared.getIconName(for: group.id))
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .modifier(SkillGroupIconModifier(colorScheme: colorScheme))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 6) {
                    Text(group.name)
                        .font(.body.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    if isTraining {
                        Text("Main_Skills_Training")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                            .fixedSize()
                    }
                    if progress >= 1 {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(progressColor)
                    }
                    Spacer(minLength: 4)
                    if group.maxTotalSkillPoints > 0 {
                        Text(verbatim: "\(FormatUtil.format(progress * 100, maxFractionDigits: 1))%")
                            .font(.system(.caption, design: .monospaced).weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(Text("Main_Skills_Category_Progress"))
                            .accessibilityValue(Text(verbatim: "\(FormatUtil.format(progress * 100, maxFractionDigits: 1))%"))
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        skillSummary
                        Spacer(minLength: 0)
                        queueSummary
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        skillSummary
                        queueSummary
                    }
                }

                if group.maxTotalSkillPoints > 0 {
                    if progress >= 1 {
                        completedProgressBar
                    } else {
                        trainingProgressBar
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var completedProgressBar: some View {
        SegmentedProgressBar(segments: [.init(value: 1, color: progressColor)])
            .accessibilityHidden(true)
    }

    private var trainingProgressBar: some View {
        SegmentedProgressBar(segments: [
            .init(value: progress, color: progressColor),
            .init(value: queuedProgress, color: .blue),
            .init(value: max(0, 1 - progress - queuedProgress), color: .secondary.opacity(0.16)),
        ])
        .accessibilityHidden(true)
    }

    private var skillSummary: some View {
        (Text("\(group.skills.count) \(NSLocalizedString("Main_Skills_number", comment: ""))")
            + Text(" · ")
            + Text("\(FormatUtil.formatInteger(group.totalSkillPoints)) SP")
            .font(.system(.caption, design: .monospaced)))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var queueSummary: some View {
        if queueCount > 0 {
            Text(String(format: NSLocalizedString("Main_Skills_Queue_Count", comment: ""), queueCount))
                .font(.caption)
                .foregroundStyle(.blue)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

struct SkillCategoryView: View {
    let characterId: Int
    let databaseManager: DatabaseManager
    @StateObject private var viewModel: SkillCategoryViewModel
    @State private var isFirstAppear = true // 添加一个状态来跟踪是否是首次出现
    init(characterId: Int, databaseManager: DatabaseManager) {
        self.characterId = characterId
        self.databaseManager = databaseManager
        _viewModel = StateObject(
            wrappedValue: SkillCategoryViewModel(
                characterId: characterId,
                databaseManager: databaseManager,
                characterDatabaseManager: CharacterDatabaseManager.shared
            )
        )
    }

    var body: some View {
        List {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                if viewModel.searchText.isEmpty {
                    // 添加筛选器 Picker（始终显示，即使没有技能）
                    Picker("Filter", selection: $viewModel.selectedFilter) {
                        ForEach(SkillFilter.allCases, id: \.self) { filter in
                            Text(filter.localized).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    // .padding(.horizontal)
                    .onChange(of: viewModel.selectedFilter) { _, _ in
                        viewModel.updateFilteredGroups()
                    }

                    // 显示技能组列表或空状态
                    if viewModel.skillGroups.isEmpty {
                        Text(NSLocalizedString("Main_Skills_No_Skills", comment: ""))
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(
                            viewModel.skillGroups.sorted(by: {
                                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                            })
                        ) { group in
                            NavigationLink {
                                SkillGroupDetailView(
                                    group: group, databaseManager: databaseManager,
                                    characterId: characterId
                                )
                            } label: {
                                SkillCategoryRow(
                                    group: group,
                                    queueCount: viewModel.getQueueCount(for: group),
                                    queueSkillPoints: viewModel.getQueueSkillPoints(for: group),
                                    isTraining: viewModel.isGroupCurrentlyTraining(group)
                                )
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 18))
                    }
                } else {
                    // 显示搜索结果
                    if viewModel.filteredSkills.isEmpty {
                        Text(NSLocalizedString("Main_Search_No_Results", comment: ""))
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(viewModel.filteredSkills, id: \.typeId) { skill in
                            NavigationLink {
                                ShowItemInfo(
                                    databaseManager: databaseManager,
                                    itemID: skill.typeId
                                )
                            } label: {
                                SkillCellView(skill: skill, viewModel: viewModel)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Skills_Category", comment: ""))
        .searchable(
            text: $viewModel.searchText,
            // placement: .navigationBarDrawer(displayMode: .always),
            prompt: NSLocalizedString("Main_Search_Placeholder", comment: "")
        )
        .refreshable {
            // 下拉刷新功能
            await viewModel.loadSkills(forceRefresh: true)
        }
        .onAppear {
            if isFirstAppear {
                Task {
                    await viewModel.loadSkills()
                    isFirstAppear = false
                }
            }
        }
    }
}

/// 技能组详情视图
struct SkillGroupDetailView: View {
    let group: SkillGroup
    let databaseManager: DatabaseManager
    let characterId: Int
    @StateObject private var viewModel: SkillCategoryViewModel

    init(group: SkillGroup, databaseManager: DatabaseManager, characterId: Int) {
        self.group = group
        self.databaseManager = databaseManager
        self.characterId = characterId
        _viewModel = StateObject(
            wrappedValue: SkillCategoryViewModel(
                characterId: characterId,
                databaseManager: databaseManager,
                characterDatabaseManager: CharacterDatabaseManager.shared
            )
        )
    }

    var body: some View {
        List {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                // 将技能分为队列中的技能和其他技能
                let sortedSkills = group.skills.sorted { skill1, skill2 in
                    let name1 = viewModel.allSkillsDict[skill1.skill_id]?.names.resolved() ?? ""
                    let name2 = viewModel.allSkillsDict[skill2.skill_id]?.names.resolved() ?? ""
                    return name1.localizedCaseInsensitiveCompare(name2) == .orderedAscending
                }

                // 队列中的技能（仅未完成的：正在训练或等待中，排除已全部完成的）
                let queuedSkills = sortedSkills.filter { skill in
                    viewModel.hasActiveQueueItem(skill.skill_id)
                }

                // 其他技能（不在活跃队列中的）
                let otherSkills = sortedSkills.filter { skill in
                    !viewModel.hasActiveQueueItem(skill.skill_id)
                }

                // 将队列中的技能排序：正在训练的技能排在第一个，其他按名称排序
                let sortedQueuedSkills = queuedSkills.sorted { skill1, skill2 in
                    let isTraining1 = viewModel.isSkillCurrentlyTraining(skill1.skill_id)
                    let isTraining2 = viewModel.isSkillCurrentlyTraining(skill2.skill_id)

                    // 如果一个是正在训练的，另一个不是，正在训练的排在前面
                    if isTraining1 && !isTraining2 {
                        return true
                    }
                    if !isTraining1 && isTraining2 {
                        return false
                    }

                    // 如果都是或都不是正在训练的，按名称排序
                    let name1 = viewModel.allSkillsDict[skill1.skill_id]?.names.resolved() ?? ""
                    let name2 = viewModel.allSkillsDict[skill2.skill_id]?.names.resolved() ?? ""
                    return name1.localizedCaseInsensitiveCompare(name2) == .orderedAscending
                }

                // 如果有队列中的技能，显示"队列中"section
                if !sortedQueuedSkills.isEmpty {
                    Section(header: Text(NSLocalizedString("Main_Skills_In_Queue", comment: ""))) {
                        ForEach(sortedQueuedSkills, id: \.skill_id) { skill in
                            if let skillInfo = viewModel.allSkillsDict[skill.skill_id] {
                                NavigationLink {
                                    ShowItemInfo(
                                        databaseManager: databaseManager,
                                        itemID: skill.skill_id
                                    )
                                } label: {
                                    SkillCellView(
                                        skill: (
                                            typeId: skill.skill_id,
                                            name: skillInfo.names.resolved(),
                                            timeMultiplier: skillInfo.timeMultiplier,
                                            currentSkillPoints: skillInfo.currentSkillPoints,
                                            currentLevel: skillInfo.currentLevel,
                                            trainingRate: skillInfo.trainingRate
                                        ),
                                        viewModel: viewModel,
                                        showsQueueStatus: false
                                    )
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }
                }

                // 显示其他技能
                if !otherSkills.isEmpty {
                    ForEach(otherSkills, id: \.skill_id) { skill in
                        if let skillInfo = viewModel.allSkillsDict[skill.skill_id] {
                            NavigationLink {
                                ShowItemInfo(
                                    databaseManager: databaseManager,
                                    itemID: skill.skill_id
                                )
                            } label: {
                                SkillCellView(
                                    skill: (
                                        typeId: skill.skill_id,
                                        name: skillInfo.names.resolved(),
                                        timeMultiplier: skillInfo.timeMultiplier,
                                        currentSkillPoints: skillInfo.currentSkillPoints,
                                        currentLevel: skillInfo.currentLevel,
                                        trainingRate: skillInfo.trainingRate
                                    ),
                                    viewModel: viewModel
                                )
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }
        }
        .navigationTitle(group.name)
        .refreshable {
            // 下拉刷新功能
            await viewModel.loadSkills(forceRefresh: true)
        }
    }
}

/// 技能组图标修饰符，在浅色模式下反色
struct SkillGroupIconModifier: ViewModifier {
    let colorScheme: ColorScheme

    func body(content: Content) -> some View {
        if colorScheme == .light {
            content.colorInvert()
        } else {
            content
        }
    }
}
