import Foundation

/// 战斗记录数据转换器
/// 以 ESI 为核心，补充名称/星系/价值，输出强类型（无 evetools 格式）
class KillMailDataConverter {
    static let shared = KillMailDataConverter()
    private let databaseManager = DatabaseManager.shared
    private let maxConcurrentRequests = 10

    private init() {}

    /// 获取列表数据（以 ESI 为核心，输出强类型）
    func fetchKillMailListEntities(zkbEntries: [ZKBKillMailEntry]) async throws -> [KillMailListEntity] {
        Logger.debug("开始转换 \(zkbEntries.count) 个 killmail 数据")

        // 步骤 1: 并发获取 ESI 详情（最多10个并发）
        let esiDetails = try await fetchESIDetailsConcurrently(zkbEntries: zkbEntries)
        Logger.debug("成功获取 \(esiDetails.count) 个 ESI 详情")

        // 步骤 2: 解析 ESI 数据，提取关键字段并收集所有需要查询的 ID
        var extractedData: [(killmailId: Int, zkb: ZKBInfo, esi: ESIKillMail)] = []
        var characterIds = Set<Int>()
        var corporationIds = Set<Int>()
        var allianceIds = Set<Int>()
        var shipTypeIds = Set<Int>()
        var solarSystemIds = Set<Int>()

        for zkbEntry in zkbEntries {
            guard let esiDetail = esiDetails[zkbEntry.killmail_id] else {
                Logger.warning("缺少 killmail_id \(zkbEntry.killmail_id) 的 ESI 详情，跳过")
                continue
            }

            extractedData.append((zkbEntry.killmail_id, zkbEntry.zkb, esiDetail))

            // 收集 ID
            if let charId = esiDetail.victim.character_id {
                characterIds.insert(charId)
            }
            corporationIds.insert(esiDetail.victim.corporation_id)
            if let allyId = esiDetail.victim.alliance_id {
                allianceIds.insert(allyId)
            }
            shipTypeIds.insert(esiDetail.victim.ship_type_id)
            solarSystemIds.insert(esiDetail.solar_system_id)
        }

        let allEntityIds = Array(characterIds) + Array(corporationIds) + Array(allianceIds)
        let namesMap = try await UniverseAPI.shared.getNamesWithFallback(ids: allEntityIds)
        var names: [Int: String] = [:]
        for (id, (name, _)) in namesMap {
            names[id] = name
        }

        let systemInfoMap = await getBatchSolarSystemInfo(
            solarSystemIds: Array(solarSystemIds),
            databaseManager: databaseManager
        )

        var result: [KillMailListEntity] = []
        for (killmailId, zkb, esi) in extractedData {
            let timestamp = convertISO8601ToTimestamp(esi.killmail_time) ?? 0
            let system: KillMailSystemSummary? = {
                guard let info = systemInfoMap[esi.solar_system_id] else { return nil }
                return KillMailSystemSummary(
                    systemId: info.systemId,
                    regionId: info.regionId,
                    security: info.security
                )
            }()
            result.append(KillMailListEntity(
                killmailId: killmailId,
                timestamp: timestamp,
                zkb: zkb,
                victim: esi.victim,
                names: names,
                system: system
            ))
        }

        Logger.success("成功转换 \(result.count) 个 killmail 数据")
        return result
    }

    /// 并发获取 ESI 详情（最多10个并发）
    private func fetchESIDetailsConcurrently(
        zkbEntries: [ZKBKillMailEntry]
    ) async throws -> [Int: ESIKillMail] {
        var results: [Int: ESIKillMail] = [:]
        var pendingEntries = zkbEntries

        await withTaskGroup(of: (Int, ESIKillMail?).self) { group in
            // 初始添加并发数量的任务
            for _ in 0 ..< min(maxConcurrentRequests, pendingEntries.count) {
                if pendingEntries.isEmpty {
                    break
                }

                let entry = pendingEntries.removeFirst()
                group.addTask {
                    do {
                        let esiDetail = try await ZKillMailsAPI.shared.fetchESIDetail(
                            killmailId: entry.killmail_id,
                            hash: entry.zkb.hash
                        )
                        return (entry.killmail_id, esiDetail)
                    } catch {
                        Logger.error("获取 ESI 详情失败 - killmail_id: \(entry.killmail_id), error: \(error)")
                        return (entry.killmail_id, nil)
                    }
                }
            }

            // 处理结果并添加新任务
            while let (killmailId, esiDetail) = await group.next() {
                if let detail = esiDetail {
                    results[killmailId] = detail
                }

                // 如果还有待处理的条目，添加新任务
                if !pendingEntries.isEmpty {
                    let entry = pendingEntries.removeFirst()
                    group.addTask {
                        do {
                            let esiDetail = try await ZKillMailsAPI.shared.fetchESIDetail(
                                killmailId: entry.killmail_id,
                                hash: entry.zkb.hash
                            )
                            return (entry.killmail_id, esiDetail)
                        } catch {
                            Logger.error("获取 ESI 详情失败 - killmail_id: \(entry.killmail_id), error: \(error)")
                            return (entry.killmail_id, nil)
                        }
                    }
                }
            }
        }

        return results
    }

    /// 将 ISO 8601 字符串转换为 Unix 时间戳
    private func convertISO8601ToTimestamp(_ iso8601String: String) -> Int? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = isoFormatter.date(from: iso8601String) {
            return Int(date.timeIntervalSince1970)
        }

        // 尝试不带毫秒的格式
        let isoFormatter2 = ISO8601DateFormatter()
        isoFormatter2.formatOptions = [.withInternetDateTime]

        if let date = isoFormatter2.date(from: iso8601String) {
            return Int(date.timeIntervalSince1970)
        }

        Logger.error("无法解析时间字符串: \(iso8601String)")
        return nil
    }

    /// 获取单个 killmail 的完整详情（以 ESI 为核心，输出强类型）
    /// - Parameter zkb: 若从列表进入可传入，用于价值展示；否则详情页需单独请求 zkillboard
    func fetchKillMailDetail(killmailId: Int, hash: String, zkb: ZKBInfo? = nil) async throws -> KillMailDetailData {
        Logger.debug("开始获取 killmail 详情 - killmail_id: \(killmailId)")

        // 从 ESI 获取详情
        let esiDetail = try await ZKillMailsAPI.shared.fetchESIDetail(killmailId: killmailId, hash: hash)

        // 收集所有需要查询的 ID
        var characterIds = Set<Int>()
        var corporationIds = Set<Int>()
        var allianceIds = Set<Int>()
        var shipTypeIds = Set<Int>()
        var solarSystemIds = Set<Int>()

        // 受害者信息
        if let charId = esiDetail.victim.character_id {
            characterIds.insert(charId)
        }
        corporationIds.insert(esiDetail.victim.corporation_id)
        if let allyId = esiDetail.victim.alliance_id {
            allianceIds.insert(allyId)
        }
        shipTypeIds.insert(esiDetail.victim.ship_type_id)
        solarSystemIds.insert(esiDetail.solar_system_id)

        // 物品信息（含嵌套容器内容）
        for typeId in KillMailDetailData.allVictimItemTypeIds(from: esiDetail.victim.items) {
            shipTypeIds.insert(typeId)
        }

        // 参与者名称不在此预取，避免打开详情即查库；进入参与者页时再批量解析（见 KillMailAttackersView）

        Logger.debug("收集到 - 角色: \(characterIds.count), 军团: \(corporationIds.count), 联盟: \(allianceIds.count), 物品: \(shipTypeIds.count), 星系: \(solarSystemIds.count)")

        // 批量获取名称
        let allEntityIds = Array(characterIds) + Array(corporationIds) + Array(allianceIds)
        let namesMap = try await UniverseAPI.shared.getNamesWithFallback(ids: allEntityIds)

        let systemInfoMap = await getBatchSolarSystemInfo(
            solarSystemIds: Array(solarSystemIds),
            databaseManager: databaseManager
        )

        var names: [Int: String] = [:]
        for (id, (name, _)) in namesMap {
            names[id] = name
        }

        let system: KillMailSystemSummary? = {
            guard let info = systemInfoMap[esiDetail.solar_system_id] else { return nil }
            return KillMailSystemSummary(
                systemId: info.systemId,
                regionId: info.regionId,
                security: info.security
            )
        }()

        Logger.success("成功获取 killmail 详情 - killmail_id: \(killmailId)")
        return KillMailDetailData(
            killmailId: killmailId,
            esi: esiDetail,
            zkb: zkb,
            names: names,
            system: system
        )
    }
}
