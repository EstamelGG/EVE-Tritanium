import SwiftUI

@MainActor
struct CharacterSearchView {
    let characterId: Int
    let searchText: String
    @Binding var searchResults: [SearcherView.SearchResult]
    @Binding var filteredResults: [SearcherView.SearchResult]
    @Binding var searchingStatus: String
    @Binding var error: Error?

    var corporationFilter: String
    var allianceFilter: String
    var strictMatch: Bool = false

    func search() async {
        do {
            searchingStatus = NSLocalizedString(
                "Main_Search_Status_Finding_Characters", comment: ""
            )
            let data = try await CharacterSearchAPI.shared.search(
                characterId: characterId,
                categories: [.character],
                searchText: searchText,
                strict: strictMatch
            )

            if Task.isCancelled {
                return
            }

            // 解析搜索结果
            let searchResponse = try JSONDecoder().decode(
                SearcherView.SearchResponse.self, from: data
            )

            if let characters = searchResponse.character {
                // 一次性获取所有角色名称
                searchingStatus = NSLocalizedString("Main_Search_Status_Loading_Names", comment: "")
                let namesWithCategories = try await UniverseAPI.shared.getNamesWithFallback(
                    ids: characters
                )
                let names = namesWithCategories.mapValues { $0.name }

                // 创建基本的搜索结果
                let results = characters.compactMap { id -> SearcherView.SearchResult? in
                    guard let name = names[id] else { return nil }
                    return SearcherView.SearchResult(
                        id: id,
                        name: name,
                        type: .character
                    )
                }.sortedBySearchPrefix(searchText)

                if Task.isCancelled {
                    return
                }

                // 更新结果
                searchResults = results

                // 一次性获取所有角色的军团和联盟信息
                searchingStatus = NSLocalizedString(
                    "Main_Search_Status_Loading_Details", comment: ""
                )
                let affiliations = try await CharacterAffiliationAPI.shared
                    .fetchAffiliationsInBatches(characterIds: characters)

                // 收集所有需要查询的军团和联盟ID
                var corpIds = Set<Int>()
                var allianceIds = Set<Int>()

                for affiliation in affiliations {
                    corpIds.insert(affiliation.corporation_id)
                    if let allianceId = affiliation.alliance_id {
                        allianceIds.insert(allianceId)
                    }
                }

                // 获取军团名称
                searchingStatus = NSLocalizedString("Main_Search_Status_Loading_Corps", comment: "")
                let corporationNamesWithCategories = try await UniverseAPI.shared
                    .getNamesWithFallback(ids: Array(corpIds))
                let corporationNames = corporationNamesWithCategories.mapValues { $0.name }

                // 获取联盟名称
                var allianceNames: [Int: String] = [:]
                if !allianceIds.isEmpty {
                    searchingStatus = NSLocalizedString(
                        "Main_Search_Status_Loading_Alliances", comment: ""
                    )
                    let allianceNamesWithCategories = try await UniverseAPI.shared
                        .getNamesWithFallback(ids: Array(allianceIds))
                    allianceNames = allianceNamesWithCategories.mapValues { $0.name }
                }

                // 更新搜索结果的军团和联盟信息
                for affiliation in affiliations {
                    if let index = searchResults.firstIndex(where: {
                        $0.id == affiliation.character_id
                    }) {
                        searchResults[index].corporationId = affiliation.corporation_id
                        searchResults[index].corporationName =
                            corporationNames[affiliation.corporation_id]
                        if let allianceId = affiliation.alliance_id {
                            searchResults[index].allianceId = allianceId
                            searchResults[index].allianceName = allianceNames[allianceId]
                        }
                    }
                }

                // 应用过滤条件
                filterResults()

                Logger.info("搜索完成，找到 \(searchResults.count) 个结果")

            } else {
                searchResults = []
                filteredResults = []
            }

        } catch {
            if error is CancellationError {
                Logger.debug("搜索任务被取消")
                return
            }
            Logger.error("搜索失败: \(error)")
            self.error = error
        }

        searchingStatus = ""
    }

    private func filterResults() {
        let corpFilter = corporationFilter.lowercased()
        let allianceFilter = allianceFilter.lowercased()

        if corpFilter.isEmpty, allianceFilter.isEmpty {
            // 如果没有过滤条件，显示所有结果
            filteredResults = searchResults
        } else {
            // 根据过滤条件筛选结果
            filteredResults = searchResults.filter { result in
                let matchCorp =
                    corpFilter.isEmpty
                        || (result.corporationName?.lowercased().contains(corpFilter) ?? false)
                let matchAlliance =
                    allianceFilter.isEmpty
                        || (result.allianceName?.lowercased().contains(allianceFilter) ?? false)
                return matchCorp && matchAlliance
            }
        }
    }
}
