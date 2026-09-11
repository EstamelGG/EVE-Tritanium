import Foundation

/// 修改位置信息模型（名称从 SDEMemoryStore 动态解析以跟随语言切换）
public struct LocationInfoDetail {
    public let systemId: Int
    public let security: Double
    private let stationId: Int?
    private let structureName: String? // 建筑物名来自 ESI，非本地化

    public var solarSystemName: String {
        SDEMemoryStore.solarSystemName(for: systemId) ?? "System \(systemId)"
    }

    public var stationName: String {
        if let stationId, let name = SDEMemoryStore.station(for: stationId)?.name {
            return name
        }
        return structureName ?? ""
    }

    /// 星系英文名（无翻译时为 nil）
    public var solarSystemEnglishName: String? {
        SDEMemoryStore.solarSystemEnglishName(for: systemId)
    }

    /// 空间站英文名（NPC 站有 SDE 译名；玩家建筑来自 ESI 无翻译，返回 nil）
    public var stationEnglishName: String? {
        guard let stationId else { return nil }
        return SDEMemoryStore.stationEnglishName(for: stationId)
    }

    public init(systemId: Int, security: Double, stationId: Int? = nil, structureName: String? = nil) {
        self.systemId = systemId
        self.security = security
        self.stationId = stationId
        self.structureName = structureName
    }
}

class LocationInfoLoader {
    private let databaseManager: DatabaseManager
    private let characterId: Int64

    init(databaseManager: DatabaseManager, characterId: Int64) {
        self.databaseManager = databaseManager
        self.characterId = characterId
    }

    /// 批量加载位置信息
    /// - Parameter locationIds: 位置ID数组
    /// - Returns: 位置信息字典 [位置ID: 位置信息]
    func loadLocationInfo(locationIds: Set<Int64>) async -> [Int64: LocationInfoDetail] {
        var locationInfoCache: [Int64: LocationInfoDetail] = [:]

        let validIds = locationIds.filter { $0 > 0 }

        if validIds.isEmpty {
            Logger.debug("没有有效的位置ID需要加载")
            return locationInfoCache
        }

        Logger.debug("开始加载位置信息 - 有效位置IDs: \(validIds)")

        let groupedIds = Dictionary(grouping: validIds) { LocationType.from(id: $0) }
        Logger.debug("位置ID分组结果: \(groupedIds.mapValues(\.count))")

        // 1. 处理星系
        if let solarSystemIds = groupedIds[.solarSystem] {
            Logger.debug("加载星系信息 - 数量: \(solarSystemIds.count), IDs: \(solarSystemIds)")
            let securityById = loadUniverseSecurity(systemIds: solarSystemIds.map { Int($0) })
            for systemId64 in solarSystemIds {
                let systemId = Int(systemId64)
                guard let security = securityById[systemId] else { continue }
                locationInfoCache[systemId64] = LocationInfoDetail(
                    systemId: systemId,
                    security: security
                )
            }
        }

        // 2. 处理空间站（名称/系统 ID 走内存）
        if let stationIds = groupedIds[.station] {
            Logger.debug("加载空间站信息 - 数量: \(stationIds.count), IDs: \(stationIds)")
            var missingSecuritySystemIds = Set<Int>()
            var pending: [(stationId64: Int64, stationId: Int, systemId: Int)] = []

            for stationId64 in stationIds {
                let stationId = Int(stationId64)
                guard let station = SDEMemoryStore.station(for: stationId),
                      let systemId = station.solarSystemID
                else { continue }

                if station.security != nil {
                    locationInfoCache[stationId64] = LocationInfoDetail(
                        systemId: systemId,
                        security: station.security!,
                        stationId: stationId
                    )
                } else {
                    pending.append((stationId64, stationId, systemId))
                    missingSecuritySystemIds.insert(systemId)
                }
            }

            if !pending.isEmpty {
                let securityById = loadUniverseSecurity(systemIds: Array(missingSecuritySystemIds))
                for item in pending {
                    guard let security = securityById[item.systemId] else { continue }
                    locationInfoCache[item.stationId64] = LocationInfoDetail(
                        systemId: item.systemId,
                        security: security,
                        stationId: item.stationId
                    )
                }
            }
        }

        // 3. 处理建筑物
        if let structureIds = groupedIds[.structure] {
            Logger.debug("加载建筑物信息 - 数量: \(structureIds.count), IDs: \(structureIds)")

            for structureId in structureIds {
                do {
                    let structureInfo = try await UniverseStructureAPI.shared.fetchStructureInfo(
                        structureId: structureId,
                        characterId: Int(characterId)
                    )

                    let systemId = structureInfo.solar_system_id
                    let security = loadUniverseSecurity(systemIds: [systemId])[systemId] ?? 0

                    locationInfoCache[structureId] = LocationInfoDetail(
                        systemId: systemId,
                        security: security,
                        structureName: structureInfo.name
                    )
                } catch let error as NetworkError {
                    if case let .httpError(statusCode, _) = error, statusCode == 403 {
                        locationInfoCache[structureId] = LocationInfoDetail(
                            systemId: 0,
                            security: 0.0,
                            structureName: NSLocalizedString("Structure_No_Access", comment: "")
                        )
                    } else {
                        Logger.error("加载建筑物信息失败 - ID: \(structureId), 错误: \(error)")
                    }
                } catch {
                    Logger.error("加载建筑物信息失败 - ID: \(structureId), 错误: \(error)")
                }
            }
        }

        let loadedIds = Set(locationInfoCache.keys)
        let unloadedIds = validIds.subtracting(loadedIds)
        if !unloadedIds.isEmpty {
            Logger.error("以下位置ID未能加载信息: \(unloadedIds)")
        }

        return locationInfoCache
    }

    private func loadUniverseSecurity(systemIds: [Int]) -> [Int: Double] {
        var result: [Int: Double] = [:]
        for id in systemIds {
            if let info = SDEMemoryStore.universeSystems[id] {
                result[id] = info.security
            }
        }
        return result
    }
}
