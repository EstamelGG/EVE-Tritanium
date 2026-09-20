import SwiftUI

/// 通用实体搜索视图（统一处理军团与联盟搜索）
/// 替换原 CorporationSearchView 与 AllianceSearchView 中重复的搜索逻辑
@MainActor
struct EntitySearchView {
    let characterId: Int
    let searchText: String
    let entityType: SearcherView.SearchType
    @Binding var searchResults: [SearcherView.SearchResult]
    @Binding var filteredResults: [SearcherView.SearchResult]
    @Binding var searchingStatus: String
    @Binding var error: Error?
    var strictMatch: Bool = false

    func search() async {
        do {
            searchingStatus = NSLocalizedString(statusKey, comment: "")
            let data = try await CharacterSearchAPI.shared.search(
                characterId: characterId,
                categories: [apiCategory],
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

            if let ids = responseIds(from: searchResponse) {
                // 获取实体名称
                searchingStatus = NSLocalizedString("Main_Search_Status_Loading_Names", comment: "")
                let namesWithCategories = try await UniverseAPI.shared.getNamesWithFallback(
                    ids: ids
                )

                // 创建搜索结果并按前缀优先排序
                let results = ids.compactMap { entityId -> SearcherView.SearchResult? in
                    guard let info = namesWithCategories[entityId] else { return nil }
                    return SearcherView.SearchResult(
                        id: entityId,
                        name: info.name,
                        type: entityType
                    )
                }.sortedBySearchPrefix(searchText)

                searchResults = results
                filteredResults = searchResults // 军团/联盟搜索不进行二次过滤
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

    /// 根据实体类型返回对应的搜索状态文案 Key
    private var statusKey: String {
        switch entityType {
        case .corporation:
            return "Main_Search_Status_Finding_Corporations"
        case .alliance:
            return "Main_Search_Status_Finding_Alliances"
        default:
            return "Main_Search_Status_Searching"
        }
    }

    /// 根据实体类型返回对应的 SearchCategory
    private var apiCategory: SearchCategory {
        switch entityType {
        case .corporation:
            return .corporation
        case .alliance:
            return .alliance
        default:
            return .corporation
        }
    }

    /// 从搜索响应中按实体类型取出 ID 列表
    private func responseIds(from response: SearcherView.SearchResponse) -> [Int]? {
        switch entityType {
        case .corporation:
            return response.corporation
        case .alliance:
            return response.alliance
        default:
            return nil
        }
    }
}

// MARK: - 搜索结果排序扩展

extension Array where Element == SearcherView.SearchResult {
    /// 按"前缀优先 + 字母顺序"排序
    /// - 以搜索文本开头的结果排在前面，其次按字母顺序排序
    /// - Parameter searchText: 搜索关键词
    /// - Returns: 排序后的结果数组
    func sortedBySearchPrefix(_ searchText: String) -> [SearcherView.SearchResult] {
        let searchTextLower = searchText.lowercased()
        return sorted { result1, result2 in
            let starts1 = result1.name.lowercased().hasPrefix(searchTextLower)
            let starts2 = result2.name.lowercased().hasPrefix(searchTextLower)

            if starts1 != starts2 {
                return starts1 // 以搜索文本开头的排在前面
            }
            return result1.name < result2.name // 其次按字母顺序排序
        }
    }
}
