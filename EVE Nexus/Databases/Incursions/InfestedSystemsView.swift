import SwiftUI

/// 受入侵影响星系的行模型
struct InfestedSystemRow: Identifiable {
    let systemId: Int
    let systemName: String
    let security: Double
    let sovereignty: SovereigntyInfo?

    var id: Int {
        systemId
    }
}

@MainActor
final class InfestedSystemsViewModel: ObservableObject {
    @Published var systems: [InfestedSystemRow] = []
    @Published var isLoading = false
    /// 主权数据仍在加载（名称走网络）：列表已可见，主权列显示占位而非「无主权」
    @Published var isLoadingSovereignty = false

    private let databaseManager: DatabaseManager
    private let systemIds: [Int]

    init(databaseManager: DatabaseManager, systemIds: [Int]) {
        self.databaseManager = databaseManager
        self.systemIds = systemIds
    }

    func loadData(forceRefresh: Bool = false) async {
        isLoading = true
        isLoadingSovereignty = true

        // 主权数据（网络）与星系位置（本地库）并行：不等主权，先把星系列表显示出来
        async let engineTask = SovereigntySearchEngine.shared.loadAll(forceRefresh: forceRefresh)
        let infoMap = await getBatchSolarSystemInfo(
            solarSystemIds: systemIds,
            databaseManager: databaseManager
        )

        // 第一阶段：仅星系名 + 安等
        systems = systemIds.compactMap { systemId in
            guard let info = infoMap[systemId] else { return nil }
            return InfestedSystemRow(
                systemId: systemId,
                systemName: info.systemName,
                security: info.security,
                sovereignty: nil
            )
        }
        .sorted { $0.systemName < $1.systemName }
        isLoading = false

        // 第二阶段：主权数据到位后回填（名称与派系图标已随 loadAll 解析完毕）
        do {
            _ = try await engineTask
        } catch {
            Logger.error("获取主权数据失败: \(error)")
        }

        let engine = SovereigntySearchEngine.shared
        systems = systems.map { row in
            InfestedSystemRow(
                systemId: row.systemId,
                systemName: row.systemName,
                security: row.security,
                sovereignty: engine.sovereigntyInfo(forSystemId: row.systemId)
            )
        }
        isLoadingSovereignty = false
    }
}

struct InfestedSystemsView: View {
    @StateObject private var viewModel: InfestedSystemsViewModel
    @StateObject private var iconLoader = AllianceIconLoader()

    /// 入侵集结星系（行右侧以 station 图标标记）
    private let stagingSystemId: Int

    init(databaseManager: DatabaseManager, systemIds: [Int], stagingSystemId: Int) {
        _viewModel = StateObject(
            wrappedValue: InfestedSystemsViewModel(
                databaseManager: databaseManager, systemIds: systemIds
            )
        )
        self.stagingSystemId = stagingSystemId
    }

    var body: some View {
        List {
            if viewModel.isLoading {
                ForEach(0 ..< 8, id: \.self) { _ in
                    ListSkeletonRow(iconSize: 36, lineWidths: [160, 110])
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            } else {
                ForEach(viewModel.systems) { row in
                    systemRow(row)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Main_Infested_Systems", comment: ""))
        .task {
            await viewModel.loadData()
            loadIconsForCurrentSystems()
        }
        .refreshable {
            iconLoader.cancelAllTasks()
            await viewModel.loadData(forceRefresh: true)
            loadIconsForCurrentSystems()
        }
    }

    /// 行视图：复用全局星系行组件（与主权搜索结果页同款），长按复制星系名
    private func systemRow(_ row: InfestedSystemRow) -> some View {
        let sovereignty = row.sovereignty
        let allianceId = sovereignty?.isAlliance == true ? sovereignty?.id : nil
        let icon = allianceId.flatMap { iconLoader.icons[$0] } ?? sovereignty?.icon
        // 主权数据未到位时同样视为加载中，避免把「尚未加载」误显示为「无主权」
        let isIconLoading =
            viewModel.isLoadingSovereignty
                || (allianceId.map { iconLoader.loadingIconIds.contains($0) } ?? false)

        return SystemRowView(
            name: row.systemName,
            security: row.security,
            showsSovereignty: true,
            sovereigntyIcon: icon,
            sovereigntyName: sovereignty?.name,
            isSovereigntyLoading: isIconLoading
        )
        .overlay(alignment: .trailing) {
            if row.systemId == stagingSystemId {
                Image("station")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
            }
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = row.systemName
            } label: {
                Label(
                    NSLocalizedString("Misc_Copy_Location", comment: ""),
                    systemImage: "doc.on.doc"
                )
            }

            // 显示名与英文名不同时，追加复制英文名
            if let enName = SDEMemoryStore.solarSystemEnglishName(
                for: row.systemId
            ), enName != row.systemName {
                Button {
                    UIPasteboard.general.string = enName
                } label: {
                    Label(
                        NSLocalizedString("Misc_Copy_Trans", comment: ""),
                        systemImage: "translate"
                    )
                }
            }
        }
    }

    /// 为当前列表中的主权联盟加载图标（派系图标本地已内嵌于 SovereigntyInfo）
    private func loadIconsForCurrentSystems() {
        let ids = Set(
            viewModel.systems.compactMap { row -> Int? in
                guard row.sovereignty?.isAlliance == true else { return nil }
                return row.sovereignty?.id
            }
        )
        guard !ids.isEmpty else { return }
        iconLoader.loadIcons(for: Array(ids))
    }
}
