import SwiftUI

@MainActor
final class EmploymentAllianceCache: ObservableObject {
    /// record_id → 当时联盟ID（nil 表示当时无联盟）
    @Published private(set) var recordAlliance: [Int: Int?] = [:]
    @Published private(set) var allianceNames: [Int: String] = [:]
    /// 军团/联盟共用图标表
    @Published private(set) var icons: [Int: UIImage] = [:]
    @Published private(set) var failedRecordIds: Set<Int> = []

    private var isLoaded = false
    private var lastHistory: [CharacterEmploymentHistory] = []

    enum RowAllianceState {
        case loading
        case failed
        case none
        case alliance(Int)
    }

    func state(recordId: Int) -> RowAllianceState {
        if let allianceId = recordAlliance[recordId] {
            return allianceId.map { .alliance($0) } ?? .none
        }
        if failedRecordIds.contains(recordId) {
            return .failed
        }
        return .loading
    }

    func loadIfNeeded(history: [CharacterEmploymentHistory], force: Bool = false) async {
        guard force || !isLoaded else { return }
        isLoaded = true
        lastHistory = history

        let records = Self.records(from: history)
        guard !records.isEmpty else { return }

        let uniqueCorpIds = Array(Set(records.map(\.corporationId)))

        async let corpIconsTask: Void = fetchCorpIcons(uniqueCorpIds)

        var resolved: [Int: Int?] = [:]
        var failed: Set<Int> = []
        await withTaskGroup(of: (Int, [CorporationAllianceHistory]?).self) { group in
            for corpId in uniqueCorpIds {
                group.addTask {
                    (
                        corpId,
                        try? await CorporationAPI.shared.fetchAllianceHistory(corporationId: corpId)
                    )
                }
            }
            for await (corpId, history) in group {
                let corpRecords = records.filter { $0.corporationId == corpId }
                guard let history else {
                    failed.formUnion(corpRecords.map(\.recordId))
                    failedRecordIds = failed
                    continue
                }
                for record in corpRecords {
                    resolved[record.recordId] = Self.findAlliance(
                        at: record.endDate ?? Date(), in: history
                    )
                }
                recordAlliance = resolved
            }
        }
        recordAlliance = resolved
        failedRecordIds = failed
        if !failed.isEmpty {
            // 有失败则允许下次进入/重试时重跑
            isLoaded = false
        }

        let allianceIds = Array(Set(resolved.values.compactMap { $0 }))
        guard !allianceIds.isEmpty else {
            await corpIconsTask
            return
        }

        async let namesTask: Void = fetchAllianceNames(allianceIds)
        async let allianceIconsTask: Void = fetchAllianceIcons(allianceIds)
        await namesTask
        await allianceIconsTask
        await corpIconsTask
    }

    private func fetchCorpIcons(_ corpIds: [Int]) async {
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for corpId in corpIds where icons[corpId] == nil {
                group.addTask {
                    (
                        corpId,
                        try? await CorporationAPI.shared.fetchCorporationLogo(corporationId: corpId)
                    )
                }
            }
            for await (corpId, image) in group {
                if let image {
                    icons[corpId] = image
                }
            }
        }
    }

    /// 名称保持整批：逐行请求会触发 ESI 限速；不可解析的以 "Alliance {id}" 兜底
    private func fetchAllianceNames(_ allianceIds: [Int]) async {
        guard let namesMap = try? await UniverseAPI.shared.getNamesWithFallback(ids: allianceIds)
        else { return }

        var names = allianceNames
        for id in allianceIds {
            names[id] = namesMap[id]?.name ?? "Alliance \(id)"
        }
        allianceNames = names
    }

    private func fetchAllianceIcons(_ allianceIds: [Int]) async {
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for allianceId in allianceIds where icons[allianceId] == nil {
                group.addTask {
                    (
                        allianceId,
                        try? await AllianceAPI.shared.fetchAllianceLogo(allianceID: allianceId)
                    )
                }
            }
            for await (allianceId, image) in group {
                if let image {
                    icons[allianceId] = image
                }
            }
        }
    }

    /// 失败行点击触发，重跑上次的历史
    func retry() async {
        failedRecordIds.removeAll()
        await loadIfNeeded(history: lastHistory, force: true)
    }

    /// 结束时间 = 更新一条记录的开始时间（与行视图一致）
    static func records(from history: [CharacterEmploymentHistory]) -> [(
        recordId: Int, corporationId: Int, endDate: Date?
    )] {
        history.enumerated().compactMap { index, record in
            guard parseDate(record.start_date) != nil else { return nil }
            let endDate = index > 0 ? parseDate(history[index - 1].start_date) : nil
            return (recordId: record.record_id, corporationId: record.corporation_id, endDate: endDate)
        }
    }

    /// 联盟史记录按开始时间倒序，取第一条不晚于 date 的联盟
    private static func findAlliance(at date: Date, in history: [CorporationAllianceHistory]) -> Int? {
        for record in history {
            guard let recordDate = parseDate(record.start_date) else { continue }
            if recordDate <= date {
                return record.alliance_id
            }
        }
        return nil
    }

    static func parseDate(_ dateString: String) -> Date? {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        return dateFormatter.date(from: dateString)
    }
}
