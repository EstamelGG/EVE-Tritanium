import Foundation
import SQLite3

/// universe / regions / solarsystems / constellations / factions / divisions 加载与查询
extension SDEMemoryStore {
    static func loadRegions(_ db: DatabaseManager) {
        loadLocalizedTable(db, table: "regions", idColumn: "regionID", into: &regionNames)
    }

    static func loadSolarSystems(_ db: DatabaseManager) {
        loadLocalizedTable(db, table: "solarsystems", idColumn: "solarSystemID", estimatedCount: 16384, into: &solarSystemNames)

        // 加载星系 → 星域映射（用于市场地点类型判断）
        var mapping: [Int: Int] = [:]
        mapping.reserveCapacity(16384)
        db.executeQueryMapped(
            "SELECT solarsystem_id, region_id FROM universe",
            context: "universe(星系映射)"
        ) { resolve in
            let (iSystem, iRegion) = (resolve.index("solarsystem_id"), resolve.index("region_id"))
            return { stmt in
                guard let systemID = directIntOrNil(stmt, iSystem),
                      let regionID = directIntOrNil(stmt, iRegion)
                else { return }
                mapping[systemID] = regionID
            }
        }
        systemRegionIDs = mapping
    }

    /// universe 星系摘要：安等 + 8 类行星计数（8490 行，约 1MB）
    static let planetCountColumns = [
        "temperate", "barren", "oceanic", "ice", "gas", "lava", "storm", "plasma",
    ]

    static func loadUniverseSystems(_ db: DatabaseManager) {
        let columns = ([
            "solarsystem_id", "region_id", "constellation_id", "system_security", "system_type",
            "x", "y", "z", "hasStation", "hasJumpGate", "isJSpace",
        ] + planetCountColumns)
            .joined(separator: ", ")
        var cache: [Int: UniverseSystemInfo] = [:]
        cache.reserveCapacity(16384)
        db.executeQueryMapped(
            "SELECT \(columns) FROM universe",
            context: "universe"
        ) { resolve in
            // 全部按名解析，8 个同型行星计数列由此杜绝索引错位
            let iSystem = resolve.index("solarsystem_id")
            let iRegion = resolve.index("region_id")
            let iConstellation = resolve.index("constellation_id")
            let iSecurity = resolve.index("system_security")
            let iSystemType = resolve.index("system_type")
            let (iX, iY, iZ) = (resolve.index("x"), resolve.index("y"), resolve.index("z"))
            let (iHasStation, iHasGate, iIsJSpace) = (
                resolve.index("hasStation"), resolve.index("hasJumpGate"), resolve.index("isJSpace")
            )
            let planetIndexes = planetCountColumns.map { resolve.index($0) }
            return { stmt in
                func intOr(_ index: Int32) -> Int? {
                    directIntOrNil(stmt, index)
                }
                func doubleOr(_ index: Int32) -> Double {
                    sqlite3_column_type(stmt, index) == SQLITE_NULL
                        ? 0 : sqlite3_column_double(stmt, index)
                }
                guard let systemID = intOr(iSystem), let regionID = intOr(iRegion) else { return }

                var counts: [String: Int] = [:]
                for (n, column) in planetCountColumns.enumerated() {
                    counts[column] = intOr(planetIndexes[n]) ?? 0
                }

                cache[systemID] = UniverseSystemInfo(
                    regionID: regionID,
                    constellationID: intOr(iConstellation) ?? 0,
                    security: doubleOr(iSecurity),
                    planetCounts: counts,
                    systemType: intOr(iSystemType),
                    x: doubleOr(iX),
                    y: doubleOr(iY),
                    z: doubleOr(iZ),
                    hasStation: (intOr(iHasStation) ?? 0) != 0,
                    hasJumpGate: (intOr(iHasGate) ?? 0) != 0,
                    isJSpace: (intOr(iIsJSpace) ?? 0) != 0
                )
            }
        }
        universeSystems = cache
    }

    static func loadConstellations(_ db: DatabaseManager) {
        loadLocalizedTable(db, table: "constellations", idColumn: "constellationID", into: &constellationNames)
    }

    static func loadFactions(_ db: DatabaseManager) {
        var cache: [Int: FactionInfo] = [:]
        if case let .success(rows) = db.executeQuery(
            "SELECT id, iconName, \(nameColumns) FROM factions", useCache: false
        ) {
            for row in rows {
                guard let id = row["id"] as? Int else { continue }
                cache[id] = FactionInfo(
                    id: id,
                    names: LocalizedText.from(row: row),
                    iconName: (row["iconName"] as? String) ?? ""
                )
            }
        }
        factions = cache
    }

    static func loadDivisions(_ db: DatabaseManager) {
        loadLocalizedTable(db, table: "divisions", idColumn: "division_id", into: &divisionNames)
    }

    // MARK: - Lookups

    static func regionName(for id: Int) -> String? {
        regionNames[id]?.resolvedNonEmpty()
    }

    static func solarSystemName(for id: Int) -> String? {
        solarSystemNames[id]?.resolvedNonEmpty()
    }

    static func solarSystemEnglishName(for id: Int) -> String? {
        let en = solarSystemNames[id]?.en ?? ""
        return en.isEmpty ? nil : en
    }

    static func constellationName(for id: Int) -> String? {
        constellationNames[id]?.resolvedNonEmpty()
    }

    static func faction(for id: Int) -> FactionInfo? {
        factions[id]
    }
}
