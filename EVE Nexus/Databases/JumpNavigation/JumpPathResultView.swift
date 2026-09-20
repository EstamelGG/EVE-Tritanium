import SwiftUI

struct JumpPathResultView: View {
    let pathResult: PathResult
    let allJumpSystems: [JumpSystemData]
    let shipEnName: String
    let jdcLevel: Int
    let startPointId: Int?
    let waypointIds: [Int]
    let avoidSystemIds: [Int]
    let avoidIncursions: Bool

    /// 内部计算的映射，按需使用
    private var systemIdToName: [Int: String] {
        JumpSystemData.getSystemIdToNameMap(from: allJumpSystems)
    }

    private var systemIdToSecurity: [Int: Double] {
        JumpSystemData.getSystemIdToSecurityMap(from: allJumpSystems)
    }

    // 添加入侵星系缓存
    @State private var incursionSystems: Set<Int> = []
    @State private var isLoadingIncursions: Bool = false

    /// 添加一个状态变量存储计算好的URL
    @State private var dotlanUrl: String? = nil

    /// ViewModel 用于处理数据加载和缓存
    @StateObject private var viewModel = JumpResultViewModel()

    var body: some View {
        List {
            // 总距离信息
            Section {
                HStack {
                    Text(NSLocalizedString("Jump_Navigation_Total_Distance", comment: ""))
                        .foregroundColor(.primary)
                    Spacer()
                    Text("\(String(format: "%.2f", pathResult.totalDistance)) ly")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text(NSLocalizedString("Jump_Navigation_Total_Jumps", comment: ""))
                        .foregroundColor(.primary)
                    Spacer()
                    Text("\(pathResult.segments.count)")
                        .foregroundColor(.secondary)
                }

                // 添加DOTLAN URL
                if let url = dotlanUrl {
                    Link(destination: URL(string: url)!) {
                        HStack {
                            Text(NSLocalizedString("Jump_Navigation_DOTLAN_Route", comment: ""))
                                .foregroundColor(.blue)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }

            // 显示每一跳的信息
            ForEach(Array(pathResult.segments.enumerated()), id: \.element.src) { index, segment in
                Section(
                    header: Text(
                        String(
                            format: NSLocalizedString("Jump_Navigation_Jump_Format", comment: ""),
                            index + 1, String(format: "%.2f", segment.range)
                        )
                    )
                ) {
                    // 起点星系
                    SystemJumpRow(
                        systemId: segment.src,
                        systemName: systemIdToName[segment.src] ?? "Unknown System(\(segment.src))",
                        security: systemIdToSecurity[segment.src] ?? 0.0,
                        isSource: true,
                        isIncursionSystem: incursionSystems.contains(segment.src),
                        viewModel: viewModel
                    )

                    // 终点星系
                    SystemJumpRow(
                        systemId: segment.dst,
                        systemName: systemIdToName[segment.dst] ?? "Unknown System(\(segment.dst))",
                        security: systemIdToSecurity[segment.dst] ?? 0.0,
                        isSource: false,
                        isIncursionSystem: incursionSystems.contains(segment.dst),
                        viewModel: viewModel
                    )
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Jump_Navigation_Calculate", comment: ""))
        .onAppear {
            // 收集所有路径中涉及的星系ID
            let systemIds = getAllSystemIds()
            viewModel.loadSovereigntyData(forSystemIds: systemIds)

            // 加载入侵数据
            loadIncursionSystems()

            // 一次性计算DOTLAN URL，避免重复计算
            dotlanUrl = generateDotlanUrl()
        }
    }

    /// 加载入侵星系数据
    private func loadIncursionSystems() {
        if isLoadingIncursions {
            return
        }
        isLoadingIncursions = true

        Task {
            do {
                let incursions = try await IncursionsAPI.shared.fetchIncursions()
                var systems = Set<Int>()

                for incursion in incursions {
                    for systemId in incursion.infestedSolarSystems {
                        systems.insert(systemId)
                    }
                }

                await MainActor.run {
                    self.incursionSystems = systems
                    self.isLoadingIncursions = false
                    Logger.info("加载了 \(systems.count) 个入侵星系")
                }
            } catch {
                Logger.error("加载入侵星系数据失败: \(error.localizedDescription)")
                await MainActor.run {
                    self.isLoadingIncursions = false
                }
            }
        }
    }

    /// 收集所有路径中涉及的星系ID
    private func getAllSystemIds() -> [Int] {
        var systemIds: [Int] = []

        // 添加所有跳跃段的起点和终点
        for segment in pathResult.segments {
            systemIds.append(segment.src)
            systemIds.append(segment.dst)
        }

        // 去重
        return Array(Set(systemIds))
    }

    /// 生成DOTLAN URL
    private func generateDotlanUrl() -> String? {
        // 获取所有路径点的英文名称
        var waypointNames: [String] = []

        // 添加起点
        if let startId = startPointId {
            if let name = SDEMemoryStore.solarSystemNames[startId]?.en, !name.isEmpty {
                let encodedName = name.replacingOccurrences(of: " ", with: "_")
                waypointNames.append(encodedName)
                Logger.info("添加起点到DOTLAN URL: \(encodedName)")
            } else {
                Logger.warning("未找到起点英文名称: \(startId)")
            }
        }

        // 添加用户选择的路径点
        for waypointId in waypointIds {
            if let name = SDEMemoryStore.solarSystemNames[waypointId]?.en, !name.isEmpty {
                let encodedName = name.replacingOccurrences(of: " ", with: "_")
                waypointNames.append(encodedName)
                Logger.info("添加路径点到DOTLAN URL: \(encodedName)")
            } else {
                Logger.warning("未找到路径点英文名称: \(waypointId)")
            }
        }

        // 如果没有路径点，返回nil
        if waypointNames.isEmpty {
            Logger.error("没有可用的星系英文名称，无法生成DOTLAN URL")
            return nil
        }

        // 添加规避星系
        var avoidNames: [String] = []
        for avoidId in avoidSystemIds {
            if let name = SDEMemoryStore.solarSystemNames[avoidId]?.en, !name.isEmpty {
                let encodedName = "-\(name.replacingOccurrences(of: " ", with: "_"))"
                avoidNames.append(encodedName)
                Logger.info("添加规避点到DOTLAN URL: \(encodedName)")
            } else {
                Logger.warning("未找到规避点英文名称: \(avoidId)")
            }
        }

        // 构造URL
        let waypointsString = waypointNames.joined(separator: ":") // 路径点参数
        let avoidString = avoidNames.joined(separator: ":") // 规避星系参数

        // 创建URL
        var dotlanUrl: String
        var base_params = "\(shipEnName),\(jdcLevel)44"
        // 如果有规避入侵设置，添加到URL中
        if avoidIncursions {
            base_params += ",I"
        }
        // 如果有规避星系，添加到URL中
        if !avoidString.isEmpty {
            base_params += ",\(avoidString)"
        }
        // 最终结果
        dotlanUrl = "https://evemaps.dotlan.net/jump/\(base_params)/\(waypointsString)"
        Logger.info("生成DOTLAN URL: \(dotlanUrl)")
        return dotlanUrl
    }
}

/// 管理跳跃结果所需数据的ViewModel
class JumpResultViewModel: ObservableObject {
    @Published var sovereigntyData: [SovereigntyData] = []
    @Published var isLoadingSovereignty: Bool = false

    // 图标和名称缓存
    @Published var allianceIconLoader = AllianceIconLoader()
    @Published var factionIcons: [Int: Image] = [:]
    @Published var allianceNames: [Int: String] = [:]
    @Published var factionNames: [Int: String] = [:]

    /// 跟踪正在加载的星系
    @Published var loadingSystemIcons: Set<Int> = []

    // 主权映射
    private var allianceToSystems: [Int: [Int]] = [:]
    private var factionToSystems: [Int: [Int]] = [:]

    /// 加载任务管理
    private var loadingTasks: [Int: Task<Void, Never>] = [:]

    func loadSovereigntyData(forSystemIds systemIds: [Int]) {
        Task { @MainActor in
            isLoadingSovereignty = true

            do {
                // 获取主权数据
                let data = try await SovereigntyDataAPI.shared.fetchSovereigntyData(
                    forceRefresh: false
                )

                // 确保在主线程更新UI
                sovereigntyData = data

                // 建立主权映射关系
                setupSovereigntyMapping(systemIds: systemIds)

                // 加载图标和名称
                await loadAllIcons()

                isLoadingSovereignty = false
            } catch {
                Logger.error("无法获取主权数据: \(error)")
                isLoadingSovereignty = false
            }
        }
    }

    @MainActor
    func setupSovereigntyMapping(systemIds: [Int]) {
        // 清除现有映射
        allianceToSystems.removeAll()
        factionToSystems.removeAll()

        // 为每个星系ID查找主权信息并建立映射
        for systemId in systemIds {
            if let systemData = sovereigntyData.first(where: { $0.systemId == systemId }) {
                // 标记星系正在加载图标
                loadingSystemIcons.insert(systemId)

                // 建立联盟到星系的映射
                if let allianceId = systemData.allianceId {
                    allianceToSystems[allianceId, default: []].append(systemId)
                }
                // 建立派系到星系的映射
                else if let factionId = systemData.factionId {
                    factionToSystems[factionId, default: []].append(systemId)
                } else {
                    // 如果既没有联盟也没有派系，移除加载状态
                    loadingSystemIcons.remove(systemId)
                }
            }
        }
    }

    func loadAllIcons() async {
        // 加载联盟图标和名称
        let allianceIds = Array(allianceToSystems.keys)

        // 批量加载联盟名称
        if !allianceIds.isEmpty {
            let task = Task {
                do {
                    Logger.debug("开始批量加载联盟名称，数量: \(allianceIds.count)")

                    // 使用 getNamesWithFallback 批量获取联盟名称
                    let namesMap = try await UniverseAPI.shared.getNamesWithFallback(ids: allianceIds)

                    await MainActor.run {
                        // 更新联盟名称缓存
                        for (allianceId, info) in namesMap {
                            allianceNames[allianceId] = info.name
                        }

                        // 更新所有联盟相关星系的加载状态
                        for allianceId in allianceIds {
                            if let systems = allianceToSystems[allianceId] {
                                for systemId in systems {
                                    self.loadingSystemIcons.remove(systemId)
                                }
                            }
                        }

                        Logger.debug("批量加载联盟名称成功，数量: \(namesMap.count)")
                    }
                } catch {
                    Logger.error("批量加载联盟名称失败: \(error)")

                    // 即使失败也要清除加载状态
                    await MainActor.run {
                        for allianceId in allianceIds {
                            if let systems = allianceToSystems[allianceId] {
                                for systemId in systems {
                                    self.loadingSystemIcons.remove(systemId)
                                }
                            }
                        }
                    }
                }
            }
            loadingTasks[-1] = task // 使用-1作为批量加载任务的key
        }

        // 使用 AllianceIconLoader 加载联盟图标
        await MainActor.run {
            allianceIconLoader.loadIcons(for: allianceIds)
        }

        // 加载派系图标和名称
        for (factionId, systems) in factionToSystems {
            let task = Task {
                Logger.debug("开始加载派系图标: \(factionId)，影响 \(systems.count) 个星系")

                guard let faction = SDEMemoryStore.faction(for: factionId) else {
                    Logger.error("派系图标加载失败: \(factionId)")
                    await MainActor.run {
                        for systemId in systems {
                            loadingSystemIcons.remove(systemId)
                        }
                    }
                    return
                }

                let icon = IconManager.shared.loadImage(for: faction.iconName)

                // 保存到缓存 - 确保在主线程更新UI
                await MainActor.run {
                    factionIcons[factionId] = icon
                    factionNames[factionId] = faction.name

                    // 更新所有使用这个派系图标的星系的加载状态
                    for systemId in systems {
                        loadingSystemIcons.remove(systemId)
                    }
                }
                Logger.debug("派系图标和名称加载成功: \(factionId)")
            }
            loadingTasks[factionId] = task
        }

        // 等待所有任务完成
        for task in loadingTasks.values {
            _ = await task.value
        }
    }

    /// 获取星系的主权信息
    func getSovereigntyForSystem(_ systemId: Int) -> SovereigntyData? {
        return sovereigntyData.first(where: { $0.systemId == systemId })
    }

    /// 检查星系是否正在加载图标
    func isLoadingIconForSystem(_ systemId: Int) -> Bool {
        return loadingSystemIcons.contains(systemId)
    }

    /// 获取星系的图标
    func getIconForSystem(_ systemId: Int) -> Image? {
        if let sovereignty = getSovereigntyForSystem(systemId) {
            if let allianceId = sovereignty.allianceId {
                return allianceIconLoader.icons[allianceId]
            } else if let factionId = sovereignty.factionId {
                return factionIcons[factionId]
            }
        }
        return nil
    }

    /// 获取星系的拥有者名称
    func getOwnerNameForSystem(_ systemId: Int) -> String? {
        if let sovereignty = getSovereigntyForSystem(systemId) {
            if let allianceId = sovereignty.allianceId {
                return allianceNames[allianceId]
            } else if let factionId = sovereignty.factionId {
                return factionNames[factionId]
            }
        }
        return nil
    }

    deinit {
        // 取消所有加载任务
        loadingTasks.values.forEach { $0.cancel() }
        allianceIconLoader.cancelAllTasks()
    }
}

/// 自定义星系跳跃行视图组件
struct SystemJumpRow: View {
    let systemId: Int
    let systemName: String
    let security: Double
    let isSource: Bool
    let isIncursionSystem: Bool

    @ObservedObject var viewModel: JumpResultViewModel

    var body: some View {
        HStack(spacing: 12) {
            // 左侧图标 - 只在加载中或有图标时显示
            if viewModel.isLoadingIconForSystem(systemId) {
                ProgressView()
                    .frame(width: 36, height: 36)
            } else if let icon = viewModel.getIconForSystem(systemId) {
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .cornerRadius(6)
            }

            // 右侧文本区域
            VStack(alignment: .leading, spacing: 4) {
                // 第一行：安全等级和星系名称
                HStack(spacing: 8) {
                    Text(formatSystemSecurity(security))
                        .foregroundColor(getSecurityColor(security))
                        .font(.system(.body, design: .monospaced))

                    Text(systemName)
                        .foregroundColor(.primary)
                }

                // 第二行：只在有联盟/派系名称时显示
                if let ownerName = viewModel.getOwnerNameForSystem(systemId) {
                    Text(ownerName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // 如果是入侵星系，显示入侵图标
            if isIncursionSystem {
                Spacer()
                Image("incursions")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .cornerRadius(6)
            }
        }
        .padding(.vertical, 2)
    }
}
