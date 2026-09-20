import Foundation

/// 代理人全表内存索引：一次 SQL 加载后，筛选 / 下拉 / Cell 均走内存字典。
@MainActor
final class AgentDataStore {
    static let shared = AgentDataStore()

    private(set) var agents: [AgentItem] = []
    private(set) var factions: [(Int, String, String)] = []
    private(set) var divisions: [(Int, String, String)] = []
    private(set) var agentTypes: [(Int, String)] = []
    private(set) var corporationToFaction: [Int: Int] = [:]
    private(set) var corporationsByFaction: [Int: [(Int, String, String)]] = [:]

    private var systemRegion: [Int: Int] = [:]
    private var stationSystem: [Int: Int] = [:]
    private var validSystems: Set<Int> = []
    private var loadedForUpdateFlag: Bool?
    private var isLoading = false

    private init() {}

    func ensureLoaded(databaseManager: DatabaseManager) {
        if isLoaded(for: databaseManager) || isLoading {
            return
        }
        isLoading = true
        defer { isLoading = false }
        load(databaseManager: databaseManager)
        loadedForUpdateFlag = databaseManager.databaseUpdated
    }

    private func isLoaded(for databaseManager: DatabaseManager) -> Bool {
        !agents.isEmpty && loadedForUpdateFlag == databaseManager.databaseUpdated
    }

    private func load(databaseManager: DatabaseManager) {
        loadGeography(databaseManager: databaseManager)
        loadAgents(databaseManager: databaseManager)
        rebuildIndexes()
        Logger.info("AgentDataStore 已加载 \(agents.count) 个代理人")
    }

    private func loadGeography(databaseManager: DatabaseManager) {
        systemRegion = [:]
        stationSystem = [:]
        validSystems = []

        let universeQuery = """
            SELECT solarsystem_id, region_id
            FROM universe
            WHERE region_id < 11000000
        """
        if case let .success(rows) = databaseManager.executeQuery(universeQuery) {
            for row in rows {
                guard let systemID = row["solarsystem_id"] as? Int,
                      let regionID = row["region_id"] as? Int
                else { continue }
                systemRegion[systemID] = regionID
                validSystems.insert(systemID)
            }
        }

        // 站点→星系映射来自 SDEMemoryStore 内存缓存
        for (_, info) in SDEMemoryStore.stations {
            if let systemID = info.solarSystemID {
                stationSystem[info.id] = systemID
            }
        }
    }

    private func loadAgents(databaseManager: DatabaseManager) {
        let query = """
            SELECT
                a.agent_id,
                a.agent_type,
                COALESCE(a.agent_name, 'Unknown') as name,
                a.level,
                a.corporationID,
                a.divisionID,
                a.isLocator,
                a.locationID,
                COALESCE(st.stationName, 'Unknown') as locationName,
                a.solarSystemID,
                st.security as station_security,
                st.solarSystemID as station_system_id,
                u.system_security,
                c.name as corporationName,
                c.icon_filename as corporationIcon,
                f.id as factionID,
                f.name as factionName,
                f.iconName as factionIcon,
                d.name as divisionName
            FROM agents a
            LEFT JOIN stations st ON a.locationID = st.stationID
            LEFT JOIN universe u ON u.solarsystem_id = COALESCE(a.solarSystemID, st.solarSystemID)
            JOIN npcCorporations c ON a.corporationID = c.corporation_id
            JOIN factions f ON c.faction_id = f.id
            LEFT JOIN divisions d ON a.divisionID = d.division_id
        """

        guard case let .success(rows) = databaseManager.executeQuery(query) else {
            agents = []
            return
        }

        agents = rows.compactMap { row in
            guard let agentID = row["agent_id"] as? Int,
                  let name = row["name"] as? String,
                  let level = row["level"] as? Int,
                  let corporationID = row["corporationID"] as? Int,
                  let divisionID = row["divisionID"] as? Int,
                  let isLocator = row["isLocator"] as? Int,
                  let locationID = row["locationID"] as? Int,
                  let corporationName = row["corporationName"] as? String,
                  let factionID = row["factionID"] as? Int,
                  let factionName = row["factionName"] as? String
            else { return nil }

            let solarSystemID = row["solarSystemID"] as? Int
            let stationSystemID = row["station_system_id"] as? Int
            let effectiveSystemID = solarSystemID ?? stationSystemID ?? stationSystem[locationID]
            let regionID = effectiveSystemID.flatMap { systemRegion[$0] }
            let solarSystemName = effectiveSystemID.flatMap { SDEMemoryStore.solarSystemName(for: $0) }

            let systemSecurity = row["system_security"] as? Double
            let stationSecurity = row["station_security"] as? Double
            let security = solarSystemID != nil ? systemSecurity : (stationSecurity ?? systemSecurity)

            return AgentItem(
                agentID: agentID,
                agentType: row["agent_type"] as? Int ?? 0,
                name: name,
                level: level,
                corporationID: corporationID,
                divisionID: divisionID,
                isLocator: isLocator == 1,
                locationID: locationID,
                locationName: row["locationName"] as? String
                    ?? NSLocalizedString("Unknown_Location", comment: "未知位置"),
                solarSystemID: solarSystemID,
                solarSystemName: solarSystemName,
                security: security,
                corporationName: corporationName,
                corporationIcon: row["corporationIcon"] as? String ?? "corporation_default",
                factionID: factionID,
                factionName: factionName,
                factionIcon: row["factionIcon"] as? String ?? "faction_default",
                divisionName: row["divisionName"] as? String
                    ?? NSLocalizedString("Unknown", comment: ""),
                regionID: regionID,
                effectiveSolarSystemID: effectiveSystemID,
                sortLocation: solarSystemName ?? "Unknown"
            )
        }
        .sorted {
            let loc = $0.sortLocation.localizedStandardCompare($1.sortLocation)
            if loc != .orderedSame {
                return loc == .orderedAscending
            }
            let fac = $0.factionName.localizedStandardCompare($1.factionName)
            if fac != .orderedSame {
                return fac == .orderedAscending
            }
            let corp = $0.corporationName.localizedStandardCompare($1.corporationName)
            if corp != .orderedSame {
                return corp == .orderedAscending
            }
            let div = $0.divisionName.localizedStandardCompare($1.divisionName)
            if div != .orderedSame {
                return div == .orderedAscending
            }
            if $0.level != $1.level {
                return $0.level > $1.level
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func rebuildIndexes() {
        var factionMap: [Int: (String, String)] = [:]
        var divisionMap: [Int: String] = [:]
        var typeSet = Set<Int>()
        var corpToFaction: [Int: Int] = [:]
        var corpsByFaction: [Int: [Int: (String, String)]] = [:]

        for agent in agents {
            factionMap[agent.factionID] = (agent.factionName, agent.factionIcon)
            divisionMap[agent.divisionID] = agent.divisionName
            typeSet.insert(agent.agentType)
            corpToFaction[agent.corporationID] = agent.factionID
            corpsByFaction[agent.factionID, default: [:]][agent.corporationID] =
                (agent.corporationName, agent.corporationIcon)
        }

        factions = factionMap
            .map { ($0.key, $0.value.0, $0.value.1) }
            .sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }

        let mainDivisionIDs = [24, 23, 22, 18]
        var mainDivisions: [(Int, String, String)] = []
        var otherDivisions: [(Int, String, String)] = []
        for (id, name) in divisionMap {
            let tuple = (id, name, divisionIcons[id] ?? "agent")
            if mainDivisionIDs.contains(id) {
                mainDivisions.append(tuple)
            } else {
                otherDivisions.append(tuple)
            }
        }
        mainDivisions.sort {
            (mainDivisionIDs.firstIndex(of: $0.0) ?? .max)
                < (mainDivisionIDs.firstIndex(of: $1.0) ?? .max)
        }
        otherDivisions.sort { $0.0 < $1.0 }
        divisions = mainDivisions + otherDivisions

        let mainTypeIDs = [2, 4, 6, 9]
        let secondaryTypeIDs = [5, 10, 12]
        var mainTypes: [(Int, String)] = []
        var secondaryTypes: [(Int, String)] = []
        var otherTypes: [(Int, String)] = []
        for typeID in typeSet {
            let tuple = (typeID, "\(typeID)")
            if mainTypeIDs.contains(typeID) {
                mainTypes.append(tuple)
            } else if secondaryTypeIDs.contains(typeID) {
                secondaryTypes.append(tuple)
            } else {
                otherTypes.append(tuple)
            }
        }
        mainTypes.sort {
            (mainTypeIDs.firstIndex(of: $0.0) ?? .max)
                < (mainTypeIDs.firstIndex(of: $1.0) ?? .max)
        }
        secondaryTypes.sort {
            (secondaryTypeIDs.firstIndex(of: $0.0) ?? .max)
                < (secondaryTypeIDs.firstIndex(of: $1.0) ?? .max)
        }
        otherTypes.sort { $0.0 < $1.0 }
        agentTypes = mainTypes + secondaryTypes + otherTypes

        corporationToFaction = corpToFaction
        corporationsByFaction = corpsByFaction.mapValues { corps in
            corps.map { ($0.key, $0.value.0, $0.value.1) }
                .sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
        }
    }

    func corporations(forFaction factionID: Int) -> [(Int, String, String)] {
        corporationsByFaction[factionID] ?? []
    }

    struct SearchFilter {
        var divisionID: Int?
        var level: Int?
        var securityLevel: String?
        var factionID: Int?
        var corporationID: Int?
        var isLocatorOnly = false
        var isSpaceAgentOnly = false
        var agentType: Int?
        var regionID: Int?
        var solarSystemID: Int?
    }

    func search(_ filter: SearchFilter) -> [AgentItem] {
        agents.filter { agent in
            if let divisionID = filter.divisionID, agent.divisionID != divisionID {
                return false
            }
            if let level = filter.level, agent.level != level {
                return false
            }
            if let factionID = filter.factionID, agent.factionID != factionID {
                return false
            }
            if let corporationID = filter.corporationID, agent.corporationID != corporationID {
                return false
            }
            if filter.isLocatorOnly, !agent.isLocator {
                return false
            }
            if filter.isSpaceAgentOnly, agent.solarSystemID == nil {
                return false
            }
            if let agentType = filter.agentType, agent.agentType != agentType {
                return false
            }

            if let regionID = filter.regionID {
                guard agent.regionID == regionID else { return false }
            } else if let spaceSystem = agent.solarSystemID {
                // 与旧 SQL 一致：无星域时空间代理人限制在 region_id < 11000000；
                // 空间站代理人（solarSystemID == nil）一律放行
                guard validSystems.contains(spaceSystem) else { return false }
            }

            if let solarSystemID = filter.solarSystemID {
                guard agent.effectiveSolarSystemID == solarSystemID else { return false }
            }

            if let securityLevel = filter.securityLevel {
                let display = calculateDisplaySecurity(agent.security ?? 0)
                switch securityLevel {
                case "highsec": if display < 0.5 {
                        return false
                    }
                case "lowsec": if display >= 0.5 || display < 0.0 {
                        return false
                    }
                case "nullsec": if display >= 0.0 {
                        return false
                    }
                default: break
                }
            }
            return true
        }
    }

    /// Hierarchy：按搜索结果中的军团反查势力列表
    func factions(in results: [AgentItem]) -> [(Int, String, String)] {
        var counts: [Int: Int] = [:]
        var info: [Int: (String, String)] = [:]
        for agent in results {
            counts[agent.factionID, default: 0] += 1
            info[agent.factionID] = (agent.factionName, agent.factionIcon)
        }
        return info
            .map { ($0.key, $0.value.0, $0.value.1) }
            .sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
    }

    func factionAgentCounts(in results: [AgentItem]) -> [Int: Int] {
        var counts: [Int: Int] = [:]
        for agent in results {
            counts[agent.factionID, default: 0] += 1
        }
        return counts
    }

    func corporations(in results: [AgentItem], factionID: Int) -> [(Int, String, String)] {
        let ids = Set(results.map(\.corporationID))
        return corporations(forFaction: factionID).filter { ids.contains($0.0) }
    }

    func divisions(in results: [AgentItem], corporationID: Int) -> [(Int, String, String)] {
        var seen = Set<Int>()
        var list: [(Int, String, String)] = []
        for agent in results where agent.corporationID == corporationID {
            guard seen.insert(agent.divisionID).inserted else { continue }
            list.append((
                agent.divisionID,
                agent.divisionName,
                divisionIcons[agent.divisionID] ?? "not_found"
            ))
        }
        return list.sorted { $0.0 > $1.0 }
    }
}
