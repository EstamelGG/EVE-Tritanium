import SwiftUI

@MainActor
final class CharacterSheetViewModel: ObservableObject {
    let character: EVECharacterInfo
    let characterPortrait: UIImage?
    let databaseManager: DatabaseManager

    @Published var corporationInfo: CorporationInfo?
    @Published var corporationLogo: UIImage?
    @Published var allianceInfo: AllianceInfo?
    @Published var allianceLogo: UIImage?
    @Published var onlineStatus: CharacterOnlineStatus?
    @Published var isLoadingOnlineStatus = true
    @Published var currentLocation: SolarSystemInfo?
    @Published var locationStatus: CharacterLocation.LocationStatus?
    @Published var locationDetail: LocationInfoDetail?
    @Published var locationTypeId: Int?
    @Published var currentShip: CharacterShipInfo?
    @Published var shipTypeName: String?
    @Published var securityStatus: Double?
    @Published var fatigue: CharacterFatigue?
    @Published var isLoadingFatigue = true
    @Published var birthday: String?
    /// 是否有 NPC 势力（决定是否显示「势力与军衔」入口；详情由子页面懒加载）
    @Published var hasFaction = false

    private let lastShipTypeIdKey: String
    private let lastLocationKey: String

    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private let locationLoader: LocationInfoLoader?

    /// 位置信息缓存结构体
    private struct LocationCache: Codable {
        let solarSystemId: Int
        let stationId: Int?
        let structureId: Int?
        let locationStatus: String
        let typeId: Int?
    }

    init(
        character: EVECharacterInfo,
        characterPortrait: UIImage?,
        databaseManager: DatabaseManager = DatabaseManager()
    ) {
        self.character = character
        self.characterPortrait = characterPortrait
        self.databaseManager = databaseManager
        locationLoader = LocationInfoLoader(
            databaseManager: databaseManager, characterId: Int64(character.CharacterID)
        )
        lastShipTypeIdKey = "LastShipTypeId_\(character.CharacterID)"
        lastLocationKey = "LastLocation_\(character.CharacterID)"

        if let lastShipTypeId = UserDefaults.standard.object(forKey: lastShipTypeIdKey) as? Int,
           let typeName = ItemInfoMap.typeName(for: lastShipTypeId)
        {
            currentShip = CharacterShipInfo(
                ship_item_id: 0, ship_name: "", ship_type_id: lastShipTypeId
            )
            shipTypeName = typeName
        }
    }

    var portraitImage: Image {
        if let portrait = characterPortrait {
            return Image(uiImage: portrait)
        } else {
            return Image("default_char")
        }
    }

    /// 初始化数据加载：本地 -> 缓存 -> 网络并行
    func loadInitialData() {
        loadLocalData()

        Task {
            if let data = UserDefaults.standard.data(forKey: lastLocationKey),
               let locationCache = try? JSONDecoder().decode(LocationCache.self, from: data)
            {
                await loadLocationFromCache(locationCache)
            }

            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.loadOnlineStatus() }
                group.addTask { await self.loadLocationInfo(forceRefresh: true) }
                group.addTask { await self.loadShipInfo() }
                group.addTask { await self.loadFatigueInfo() }
                group.addTask { await self.loadCorporationAndAllianceInfo() }
            }
        }
    }

    /// 下拉刷新：强制重新获取所有网络数据
    func refresh() async {
        Logger.info("开始刷新人物表单的所有数据")

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadOnlineStatus(forceRefresh: true) }
            group.addTask { await self.loadLocationInfo(forceRefresh: true) }
            group.addTask { await self.loadShipInfo() }
            group.addTask { await self.loadFatigueInfo() }
            group.addTask { await self.loadCorporationAndAllianceInfo(forceRefresh: true) }
        }

        Logger.info("所有数据刷新完成")
    }
}

// MARK: - 位置相关

extension CharacterSheetViewModel {
    private func loadLocationFromCache(_ cache: LocationCache) async {
        if let locationId = (cache.structureId.map(Int64.init) ?? cache.stationId.map(Int64.init)),
           let info = await locationLoader?.loadLocationInfo(locationIds: [locationId]).first?.value
        {
            locationDetail = info
            currentLocation = nil
            locationStatus = CharacterLocation.LocationStatus(rawValue: cache.locationStatus)
            locationTypeId = cache.typeId
        } else if let info = await getSolarSystemInfo(
            solarSystemId: cache.solarSystemId, databaseManager: databaseManager
        ) {
            locationDetail = nil
            currentLocation = info
            locationStatus = CharacterLocation.LocationStatus(rawValue: cache.locationStatus)
            locationTypeId = nil
        }
    }

    private func saveLocationToCache(location: CharacterLocation, typeId: Int? = nil) async {
        let cache = LocationCache(
            solarSystemId: location.solar_system_id,
            stationId: location.station_id,
            structureId: location.structure_id,
            locationStatus: location.locationStatus.rawValue,
            typeId: typeId
        )

        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: lastLocationKey)
        }
    }

    private func isSameLocation(location: CharacterLocation, cache: LocationCache) -> Bool {
        location.solar_system_id == cache.solarSystemId
            && location.station_id == cache.stationId
            && location.structure_id == cache.structureId
            && location.locationStatus.rawValue == cache.locationStatus
    }

    private func loadLocationInfo(forceRefresh: Bool = false) async {
        do {
            let location = try await CharacterLocationAPI.shared.fetchCharacterLocation(
                characterId: character.CharacterID, forceRefresh: forceRefresh
            )

            if let data = UserDefaults.standard.data(forKey: lastLocationKey),
               let locationCache = try? JSONDecoder().decode(LocationCache.self, from: data),
               isSameLocation(location: location, cache: locationCache)
            {
                return
            }

            if let structureId = location.structure_id {
                let structureInfo = try? await UniverseStructureAPI.shared.fetchStructureInfo(
                    structureId: Int64(structureId), characterId: character.CharacterID
                )
                if let info = await locationLoader?.loadLocationInfo(locationIds: [Int64(structureId)]).first?.value {
                    locationDetail = info
                    currentLocation = nil
                    locationStatus = location.locationStatus
                    locationTypeId = structureInfo?.type_id
                    await saveLocationToCache(location: location, typeId: structureInfo?.type_id)
                }
            } else if let stationId = location.station_id {
                let typeId = SDEMemoryStore.station(for: Int(stationId))?.stationTypeID
                if let info = await locationLoader?.loadLocationInfo(locationIds: [Int64(stationId)]).first?.value {
                    locationDetail = info
                    currentLocation = nil
                    locationStatus = location.locationStatus
                    locationTypeId = typeId
                    await saveLocationToCache(location: location, typeId: typeId)
                }
            } else {
                if let info = await getSolarSystemInfo(
                    solarSystemId: location.solar_system_id, databaseManager: databaseManager
                ) {
                    locationDetail = nil
                    currentLocation = info
                    locationStatus = location.locationStatus
                    locationTypeId = nil
                    await saveLocationToCache(location: location)
                }
            }

            if let ship = currentShip {
                await saveCharacterState(location: location, ship: ship)
            }
        } catch {
            Logger.error("获取位置信息失败: \(error)")
        }
    }

    private func saveCharacterState(location: CharacterLocation, ship: CharacterShipInfo?) async {
        let query = """
            INSERT OR REPLACE INTO character_current_state (
                character_id, solar_system_id, station_id, structure_id,
                location_status, ship_item_id, ship_type_id, ship_name,
                last_update
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        let parameters: [Any] = [
            Int64(character.CharacterID),
            Int64(location.solar_system_id),
            location.station_id.map { Int64($0) } ?? NSNull(),
            location.structure_id.map { Int64($0) } ?? NSNull(),
            location.locationStatus.rawValue,
            ship.map { Int64($0.ship_item_id) } ?? NSNull(),
            ship.map { Int64($0.ship_type_id) } ?? NSNull(),
            ship?.ship_name ?? NSNull(),
            Int64(Date().timeIntervalSince1970),
        ]

        if case let .error(error) = CharacterDatabaseManager.shared.executeQuery(
            query, parameters: parameters
        ) {
            Logger.error("保存角色状态失败: \(error)")
        }
    }
}

// MARK: - 网络加载

extension CharacterSheetViewModel {
    private func loadOnlineStatus(forceRefresh: Bool = false) async {
        let status = try? await CharacterLocationAPI.shared.fetchCharacterOnlineStatus(
            characterId: character.CharacterID, forceRefresh: forceRefresh
        )
        withAnimation(.easeInOut(duration: 0.3)) {
            onlineStatus = status
            isLoadingOnlineStatus = false
        }
    }

    private func loadShipInfo() async {
        do {
            let shipInfo = try await CharacterLocationAPI.shared.fetchCharacterShip(
                characterId: character.CharacterID
            )
            if let typeName = ItemInfoMap.typeName(for: shipInfo.ship_type_id) {
                currentShip = shipInfo
                shipTypeName = typeName
                UserDefaults.standard.set(shipInfo.ship_type_id, forKey: lastShipTypeIdKey)
            }
        } catch {
            Logger.error("获取飞船信息失败: \(error)")
        }
    }

    private func loadFatigueInfo() async {
        let fatigue = try? await CharacterFatigueAPI.shared.fetchCharacterFatigue(
            characterId: character.CharacterID
        )
        withAnimation(.easeInOut(duration: 0.3)) {
            self.fatigue = fatigue
            isLoadingFatigue = false
        }
    }

    private func loadCorporationAndAllianceInfo(forceRefresh: Bool = false) async {
        if let publicInfo = try? await CharacterAPI.shared.fetchCharacterPublicInfo(
            characterId: character.CharacterID, forceRefresh: forceRefresh
        ) {
            async let corpInfoTask = CorporationAPI.shared.fetchCorporationInfo(
                corporationId: publicInfo.corporation_id
            )
            async let corpLogoTask = CorporationAPI.shared.fetchCorporationLogo(
                corporationId: publicInfo.corporation_id
            )

            if let (info, logo) = try? await (corpInfoTask, corpLogoTask) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    corporationInfo = info
                    corporationLogo = logo
                }
            }

            if let allianceId = publicInfo.alliance_id {
                async let allianceInfoTask = AllianceAPI.shared.fetchAllianceInfo(allianceId: allianceId)
                async let allianceLogoTask = AllianceAPI.shared.fetchAllianceLogo(allianceID: allianceId)

                if let (info, logo) = try? await (allianceInfoTask, allianceLogoTask) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        allianceInfo = info
                        allianceLogo = logo
                    }
                }
            }

            withAnimation(.easeInOut(duration: 0.3)) {
                securityStatus = publicInfo.security_status
            }

            // 势力详情由子页面懒加载，这里只记录是否存在（publicInfo 同一响应，零额外请求）
            hasFaction = publicInfo.faction_id != nil
        }
    }

    private func loadLocalData() {
        let query = "SELECT birthday, security_status FROM character_info WHERE character_id = ?"
        if case let .success(rows) = CharacterDatabaseManager.shared.executeQuery(
            query, parameters: [character.CharacterID]
        ),
            let row = rows.first
        {
            if let birthdayStr = row["birthday"] as? String {
                birthday = birthdayStr
            }
            if let security = row["security_status"] as? Double {
                securityStatus = security
            }
        }
    }
}

// MARK: - 图标辅助

extension CharacterSheetViewModel {
    func getTypeIcon(typeId: Int) -> String? {
        ItemInfoMap.iconFilename(for: typeId)
    }

    func getSystemIcon(solarSystemId: Int) -> String? {
        // 星系类型图标（内存索引：universe.system_type → types.icon_filename）
        guard let systemType = SDEMemoryStore.universeSystems[solarSystemId]?.systemType,
              let iconFileName = SDEMemoryStore.type(for: systemType)?.iconFilename
        else {
            return nil
        }

        return iconFileName.isEmpty ? IconManager.defaultItemIcon : iconFileName
    }

    func getSecurityStatusColor(_ security: Double) -> Color {
        if security <= 0 {
            return .red
        } else if security <= 4 {
            return .green
        } else {
            return .blue
        }
    }

    func formatRemainingTime(_ seconds: TimeInterval) -> String {
        return FormatUtil.formatCompactDuration(seconds, rounding: .ceil)
    }

    func formatDate(_ date: Date) -> String {
        FormatUtil.formatDateToLocalTime(date)
    }

    func formatBirthday(_ date: Date) -> String {
        FormatUtil.formatDateToLocalDate(date)
    }

    func calculateAge(from birthday: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current

        let now = Date()
        let components = calendar.dateComponents([.year, .month, .day], from: birthday, to: now)

        if let years = components.year,
           let months = components.month,
           let days = components.day
        {
            return String(
                format: NSLocalizedString("Character_Age", comment: ""), years, months, days
            )
        }
        return ""
    }
}

// MARK: - 日期格式化器访问

extension CharacterSheetViewModel {
    var isoDateFormatter: ISO8601DateFormatter {
        dateFormatter
    }
}
