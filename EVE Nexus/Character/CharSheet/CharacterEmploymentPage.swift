import SwiftUI

/// 人物表单子页面：雇佣记录（懒加载；军团名/图标/联盟信息由行异步加载）
struct CharacterEmploymentPage: View {
    let character: EVECharacterInfo

    @State private var employmentHistory: [CharacterEmploymentHistory] = []
    @State private var employmentCorporationNames: [Int: String] = [:]
    @State private var isLoading = true
    /// 玩家军团名是否仍在加载（NPC 军团已通过 SDE 同步就绪）
    @State private var isLoadingCorpNames = false
    @State private var npcCorporationIds: Set<Int> = []
    @StateObject private var allianceCache = EmploymentAllianceCache()

    var body: some View {
        List {
            Section {
                CharacterEmploymentHistoryView(
                    history: employmentHistory,
                    corporationNamesCache: employmentCorporationNames,
                    character: character,
                    isLoadingCorpNames: isLoadingCorpNames,
                    isLoading: isLoading,
                    allianceCache: allianceCache,
                    npcCorporationIds: npcCorporationIds
                )
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        }
        .navigationTitle(NSLocalizedString("Employment History", comment: ""))
        .task {
            await load()
        }
        .refreshable {
            await load(forceRefresh: true)
        }
    }

    /// 加载雇佣历史：拿到记录即返回，section 立即显示，军团名/图标/联盟信息由 row 异步加载
    private func load(forceRefresh: Bool = false) async {
        isLoading = true

        let history = try? await CharacterAPI.shared.fetchEmploymentHistory(
            characterId: character.CharacterID, forceRefresh: forceRefresh
        )
        employmentHistory = history ?? []

        // NPC 军团名走 SDE 同步查表（零网络），立即填充
        applyNPCCorporationNames()

        // 数据就绪后以动画方式切换到展示状态（loading -> 列表）
        withAnimation(.easeInOut(duration: 0.3)) {
            isLoading = false
        }

        // 玩家军团名异步加载，不阻塞 section，加载完通过 @State 自动刷新
        isLoadingCorpNames = true
        await loadPlayerCorporationNames()

        // 联盟信息流水线：一次性批量加载（军团史并发 → 名称一次批量 → 图标并发）
        await allianceCache.loadIfNeeded(history: employmentHistory)
    }

    /// 从 SDE 同步填充 NPC 军团名称和 ID 集合
    private func applyNPCCorporationNames() {
        let corporationIds = Set(employmentHistory.map { $0.corporation_id })
        var npcIds = Set<Int>()
        var names = employmentCorporationNames

        for corpId in corporationIds {
            if let npc = SDEMemoryStore.npcCorporation(for: corpId) {
                npcIds.insert(corpId)
                names[corpId] = npc.name
            }
        }

        npcCorporationIds = npcIds
        employmentCorporationNames = names
    }

    /// 异步批量加载玩家军团名称
    private func loadPlayerCorporationNames() async {
        defer { isLoadingCorpNames = false }

        let playerCorps = Set(employmentHistory.map { $0.corporation_id })
            .subtracting(npcCorporationIds)

        guard !playerCorps.isEmpty,
              let namesMap = try? await UniverseAPI.shared.getNamesWithFallback(
                  ids: Array(playerCorps)
              )
        else { return }

        var names = employmentCorporationNames
        for (corpId, info) in namesMap {
            names[corpId] = info.name
        }
        employmentCorporationNames = names
    }
}
