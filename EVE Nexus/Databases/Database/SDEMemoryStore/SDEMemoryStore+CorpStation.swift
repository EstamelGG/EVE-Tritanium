import Foundation
import SQLite3

/// npcCorporations / stations 加载与查询
extension SDEMemoryStore {
    static func loadNPCCorporations(_ db: DatabaseManager) {
        var cache: [Int: NPCCorporationInfo] = [:]
        if case let .success(rows) = db.executeQuery(
            """
            SELECT corporation_id, icon_filename, faction_id, militia_faction, \(nameColumns)
            FROM npcCorporations
            """,
            useCache: false
        ) {
            for row in rows {
                guard let id = row["corporation_id"] as? Int else { continue }
                let rawIcon = (row["icon_filename"] as? String) ?? ""
                cache[id] = NPCCorporationInfo(
                    id: id,
                    names: LocalizedText.from(row: row),
                    iconFilename: rawIcon.isEmpty ? IconManager.defaultIcon : rawIcon,
                    factionID: row["faction_id"] as? Int,
                    militiaFaction: row["militia_faction"] as? Int
                )
            }
        }
        npcCorporations = cache
    }

    static func loadStations(_ db: DatabaseManager) {
        let query = """
            SELECT stationID, stationTypeID, regionID, solarSystemID, security, LPStore, \(nameColumns)
            FROM stations
        """
        var cache: [Int: StationInfo] = [:]
        cache.reserveCapacity(8192)
        db.executeQueryMapped(query, context: "stations") { resolve in
            let (iID, iType, iRegion) = (
                resolve.index("stationID"), resolve.index("stationTypeID"), resolve.index("regionID")
            )
            let (iSystem, iSecurity, iLP) = (
                resolve.index("solarSystemID"), resolve.index("security"), resolve.index("LPStore")
            )
            let iNames = localizedIndexes(resolve)
            return { stmt in
                guard let id = directIntOrNil(stmt, iID) else { return }
                cache[id] = StationInfo(
                    id: id,
                    stationTypeID: directIntOrNil(stmt, iType),
                    regionID: directIntOrNil(stmt, iRegion),
                    solarSystemID: directIntOrNil(stmt, iSystem),
                    names: localizedText(stmt, iNames),
                    security: directDoubleOrNil(stmt, iSecurity),
                    lpStore: directIntOrNil(stmt, iLP)
                )
            }
        }
        stations = cache
    }

    // MARK: - Lookups

    static func npcCorporation(for id: Int) -> NPCCorporationInfo? {
        npcCorporations[id]
    }

    static func station(for id: Int) -> StationInfo? {
        stations[id]
    }

    static func stationEnglishName(for id: Int) -> String? {
        let en = stations[id]?.names.en ?? ""
        return en.isEmpty ? nil : en
    }

    /// LP 商店属于指定军团的空间站，按 stationID 升序
    static func stationsWithLPStore(corporationId: Int) -> [StationInfo] {
        stations.values
            .filter { $0.lpStore == corporationId }
            .sorted { $0.id < $1.id }
    }
}
