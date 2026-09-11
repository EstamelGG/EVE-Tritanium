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

    private let databaseManager: DatabaseManager
    private let systemIds: [Int]

    init(databaseManager: DatabaseManager, systemIds: [Int]) {
        self.databaseManager = databaseManager
        self.systemIds = systemIds
    }

    func loadData(forceRefresh: Bool = false) async {
        isLoading = true
        defer { isLoading = false }

        // 星系位置与主权索引并行（主权名称已随引擎 loadAll 解析，无二次加载阶段）
        async let engineTask = SovereigntySearchEngine.shared.loadAll(forceRefresh: forceRefresh)
        let infoMap = await getBatchSolarSystemInfo(
            solarSystemIds: systemIds,
            databaseManager: databaseManager
        )
        _ = try? await engineTask

        let engine = SovereigntySearchEngine.shared
        systems = systemIds.compactMap { systemId in
            guard let info = infoMap[systemId] else { return nil }
            return InfestedSystemRow(
                systemId: systemId,
                systemName: info.systemName,
                security: info.security,
                sovereignty: engine.sovereigntyInfo(forSystemId: systemId)
            )
        }
        .sorted { $0.systemName < $1.systemName }
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
        let isIconLoading = allianceId.map { iconLoader.loadingIconIds.contains($0) } ?? false

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
