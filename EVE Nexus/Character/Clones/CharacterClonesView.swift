import SwiftUI

/// 合并的克隆体信息
private struct MergedCloneLocation: Identifiable {
    let id: Int
    let locationType: String
    let locationId: Int
    let clones: [JumpClone]

    var cloneCount: Int {
        clones.count
    }

    /// 计算该位置所有克隆体的植入体总数
    var totalImplantsCount: Int {
        clones.reduce(0) { $0 + $1.implants.count }
    }
}

/// 植入体信息结构
private struct ImplantInfo {
    let typeId: Int
    let name: String
    let icon: String
    let attributeValue: Double

    static func loadImplantInfo(typeIds: [Int], databaseManager _: DatabaseManager) async
        -> [ImplantInfo]
    {
        var implantInfos: [ImplantInfo] = []

        // 获取基本信息（内存索引；attribute 331 = 植入体槽位）
        for typeId in typeIds.sorted() {
            guard let info = SDEMemoryStore.type(for: typeId) else { continue }
            let attributeValue = SDEMemoryStore.typeAttributeValue(
                for: typeId, attributeID: 331
            ) ?? 0.0
            implantInfos.append(
                ImplantInfo(
                    typeId: typeId,
                    name: info.name,
                    icon: info.iconFilename.isEmpty
                        ? IconManager.defaultItemIcon : info.iconFilename,
                    attributeValue: attributeValue
                )
            )
        }

        // 按属性值和ID排序
        return implantInfos.sorted { first, second in
            if first.attributeValue == second.attributeValue {
                return first.typeId < second.typeId
            }
            return first.attributeValue < second.attributeValue
        }
    }
}

struct CharacterClonesView: View {
    @Environment(\.locale) private var displayLocale
    @Environment(\.timeZone) private var displayTimeZone
    let character: EVECharacterInfo
    @ObservedObject var databaseManager: DatabaseManager
    @State private var cloneInfo: CharacterCloneInfo?
    @State private var implants: [Int]?
    @State private var isLoading = true
    @State private var homeLocationDetail: LocationInfoDetail?
    @State private var locationLoader: LocationInfoLoader?
    @State private var locationTypeId: Int?
    @State private var implantDetails: [ImplantInfo] = [] // 修改类型
    @State private var mergedCloneLocations: [MergedCloneLocation] = []
    @State private var hasInitialized = false // 追踪是否已执行初始化

    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    init(character: EVECharacterInfo, databaseManager: DatabaseManager = DatabaseManager()) {
        self.character = character
        self.databaseManager = databaseManager
        _locationLoader = State(
            initialValue: LocationInfoLoader(
                databaseManager: databaseManager, characterId: Int64(character.CharacterID)
            )
        )
    }

    /// 加载克隆体数据，但只在首次调用时执行
    private func loadCloneDataIfNeeded() {
        guard !hasInitialized else { return }

        hasInitialized = true

        Task {
            await loadCloneData()
        }
    }

    var body: some View {
        List {
            if isLoading {
                Section(NSLocalizedString("Character_Home_Station", comment: "")) {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else {
                // 基地空间站信息
                Section(NSLocalizedString("Character_Home_Station", comment: "")) {
                    if let cloneInfo = cloneInfo {
                        // 基地位置信息
                        if let locationDetail = homeLocationDetail {
                            HStack {
                                if let typeId = locationTypeId,
                                   let iconFileName = getStationIcon(
                                       typeId: typeId, databaseManager: databaseManager
                                   )
                                {
                                    IconManager.shared.loadImage(for: iconFileName)
                                        .resizable()
                                        .frame(width: 36, height: 36)
                                        .cornerRadius(6)
                                } else {
                                    Image("not_found")
                                        .resizable()
                                        .frame(width: 36, height: 36)
                                        .cornerRadius(6)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(NSLocalizedString("Character_Home_Location", comment: ""))
                                    LocationInfoView(
                                        stationName: locationDetail.stationName,
                                        solarSystemName: locationDetail.solarSystemName,
                                        security: locationDetail.security,
                                        font: .caption,
                                        textColor: .secondary
                                    )
                                }
                            }
                        }

                        // 最后跳跃时间
                        if let lastJumpDate = cloneInfo.last_clone_jump_date,
                           let date = dateFormatter.date(from: lastJumpDate)
                        {
                            HStack {
                                Image("jumpclones")
                                    .resizable()
                                    .frame(width: 36, height: 36)
                                    .cornerRadius(6)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(
                                        NSLocalizedString("Character_Last_Clone_Jump", comment: "")
                                    )
                                    Text(formatDate(date))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        // 最后空间站变更时间
                        HStack {
                            Image("station")
                                .resizable()
                                .frame(width: 36, height: 36)
                                .cornerRadius(6)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(
                                    NSLocalizedString("Character_Last_Station_Change", comment: "")
                                )
                                if let lastStationDate = cloneInfo.last_station_change_date,
                                   let date = dateFormatter.date(from: lastStationDate)
                                {
                                    Text(formatDate(date))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text(NSLocalizedString("Character_Never", comment: ""))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

                // 当前植入体信息
                Section(NSLocalizedString("Character_Current_Implants", comment: "")) {
                    if !implantDetails.isEmpty {
                        ForEach(implantDetails, id: \.typeId) { implant in
                            NavigationLink {
                                ShowItemInfo(
                                    databaseManager: databaseManager,
                                    itemID: implant.typeId
                                )
                            } label: {
                                HStack(alignment: .center, spacing: 8) {
                                    IconManager.shared.loadImage(for: implant.icon)
                                        .resizable()
                                        .frame(width: 36, height: 36)
                                        .cornerRadius(6)

                                    Text(implant.name)
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true) // 添加这行以确保正确换行
                                    Spacer()
                                }
                            }
                        }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    } else {
                        Text(NSLocalizedString("Character_No_Implants", comment: ""))
                            .foregroundColor(.secondary)
                    }
                }

                // 克隆体列表
                if cloneInfo != nil, !mergedCloneLocations.isEmpty {
                    Section(NSLocalizedString("Character_Jump_Clones", comment: "")) {
                        ForEach(mergedCloneLocations) { location in
                            NavigationLink {
                                CloneLocationDetailView(
                                    clones: location.clones,
                                    databaseManager: databaseManager
                                )
                            } label: {
                                CloneLocationRow(
                                    locationId: location.locationId,
                                    locationType: location.locationType,
                                    databaseManager: databaseManager,
                                    locationLoader: locationLoader,
                                    characterId: character.CharacterID,
                                    cloneCount: location.cloneCount,
                                    totalImplantsCount: location.totalImplantsCount
                                )
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Jump_Clones", comment: ""))
        .onAppear {
            loadCloneDataIfNeeded()
        }
        .refreshable {
            await loadCloneData(forceRefresh: true)
        }
    }

    private func loadCloneData(forceRefresh: Bool = false) async {
        isLoading = true
        defer { isLoading = false }

        do {
            // 获取克隆体信息
            let cloneInfo = try await CharacterClonesAPI.shared.fetchCharacterClones(
                characterId: character.CharacterID,
                forceRefresh: forceRefresh
            )

            // 合并相同位置的克隆体
            let groupedClones = Dictionary(grouping: cloneInfo.jump_clones) { clone in
                "\(clone.location_type)_\(clone.location_id)"
            }

            let mergedLocations = groupedClones.map { _, clones in
                let firstClone = clones[0]
                return MergedCloneLocation(
                    id: firstClone.location_id,
                    locationType: firstClone.location_type,
                    locationId: firstClone.location_id,
                    clones: clones
                )
            }.sorted { $0.locationId < $1.locationId }

            // 获取植入体信息
            let implants = try await CharacterImplantsAPI.shared.fetchCharacterImplants(
                characterId: character.CharacterID,
                forceRefresh: forceRefresh
            )

            // 获取基地位置详细信息
            let homeLocationId = Int64(cloneInfo.home_location.location_id)
            if let info = await locationLoader?.loadLocationInfo(locationIds: Set([homeLocationId]))
                .first?.value
            {
                // 获取位置类型ID
                if cloneInfo.home_location.location_type == "structure" {
                    let structureInfo = try? await UniverseStructureAPI.shared.fetchStructureInfo(
                        structureId: homeLocationId,
                        characterId: character.CharacterID
                    )
                    await MainActor.run {
                        self.locationTypeId = structureInfo?.type_id
                    }
                } else if cloneInfo.home_location.location_type == "station" {
                    if let typeId = SDEMemoryStore.station(for: Int(homeLocationId))?.stationTypeID {
                        await MainActor.run {
                            self.locationTypeId = typeId
                        }
                    }
                }

                await MainActor.run {
                    self.homeLocationDetail = info
                }
            }

            // 获取植入体详细信息
            var implantDetails: [ImplantInfo] = []
            if !implants.isEmpty {
                implantDetails = await ImplantInfo.loadImplantInfo(
                    typeIds: implants,
                    databaseManager: databaseManager
                )
            }

            // 更新UI
            await MainActor.run {
                self.cloneInfo = cloneInfo
                self.implants = implants
                self.implantDetails = implantDetails
                self.mergedCloneLocations = mergedLocations
            }

        } catch {
            Logger.error("加载克隆体数据失败: \(error)")
        }
    }

    private func formatDate(_ date: Date) -> String {
        return FormatUtil.formatDate(date, dateStyle: .medium, timeStyle: .medium)
    }

    private func getStationIcon(typeId: Int, databaseManager _: DatabaseManager) -> String? {
        ItemInfoMap.iconFilename(for: typeId)
    }
}

/// 克隆体位置行视图
struct CloneLocationRow: View {
    @Environment(\.locale) private var displayLocale
    @Environment(\.timeZone) private var displayTimeZone
    let locationId: Int
    let locationType: String
    let databaseManager: DatabaseManager
    let locationLoader: LocationInfoLoader?
    let characterId: Int
    let cloneCount: Int
    let totalImplantsCount: Int
    @State private var locationDetail: LocationInfoDetail?
    @State private var locationTypeId: Int?

    init(
        locationId: Int, locationType: String, databaseManager: DatabaseManager,
        locationLoader: LocationInfoLoader?, characterId: Int, cloneCount: Int = 1,
        totalImplantsCount: Int = 0
    ) {
        self.locationId = locationId
        self.locationType = locationType
        self.databaseManager = databaseManager
        self.locationLoader = locationLoader
        self.characterId = characterId
        self.cloneCount = cloneCount
        self.totalImplantsCount = totalImplantsCount
    }

    var body: some View {
        HStack {
            if let locationDetail = locationDetail {
                if let typeId = locationTypeId,
                   let iconFileName = getStationIcon(
                       typeId: typeId, databaseManager: databaseManager
                   )
                {
                    IconManager.shared.loadImage(for: iconFileName)
                        .resizable()
                        .frame(width: 36, height: 36)
                        .cornerRadius(6)
                } else {
                    Image("not_found")
                        .resizable()
                        .frame(width: 36, height: 36)
                        .cornerRadius(6)
                }

                VStack(alignment: .leading, spacing: 2) {
                    LocationInfoView(
                        stationName: locationDetail.stationName,
                        solarSystemName: locationDetail.solarSystemName,
                        security: locationDetail.security,
                        font: .body,
                        textColor: .primary
                    )

                    Text(
                        String(
                            format: NSLocalizedString(
                                "Character_Clone_And_Implants_Count", comment: ""
                            ),
                            cloneCount,
                            totalImplantsCount
                        )
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            } else {
                ProgressView()
            }
        }
        .task {
            await loadLocationInfo()
        }
    }

    private func loadLocationInfo() async {
        let locationIdInt64 = Int64(locationId)
        if let info = await locationLoader?.loadLocationInfo(locationIds: Set([locationIdInt64]))
            .first?.value
        {
            // 获取位置类型ID
            if locationType == "structure" {
                let structureInfo = try? await UniverseStructureAPI.shared.fetchStructureInfo(
                    structureId: locationIdInt64,
                    characterId: characterId
                )
                await MainActor.run {
                    self.locationTypeId = structureInfo?.type_id
                }
            } else if locationType == "station" {
                if let typeId = SDEMemoryStore.station(for: locationId)?.stationTypeID {
                    await MainActor.run {
                        self.locationTypeId = typeId
                    }
                }
            }

            await MainActor.run {
                self.locationDetail = info
            }
        }
    }

    private func getStationIcon(typeId: Int, databaseManager _: DatabaseManager) -> String? {
        ItemInfoMap.iconFilename(for: typeId)
    }
}

/// 克隆体位置详情视图
struct CloneLocationDetailView: View {
    @Environment(\.locale) private var displayLocale
    @Environment(\.timeZone) private var displayTimeZone
    let clones: [JumpClone]
    let databaseManager: DatabaseManager
    @State private var implantDetailsMap: [Int: [ImplantInfo]] = [:] // 修改类型

    var body: some View {
        List {
            ForEach(clones, id: \.jump_clone_id) { clone in
                Section {
                    if let name = clone.name {
                        HStack {
                            Image(systemName: "tag")
                                .foregroundColor(.secondary)
                            Text(name)
                                .font(.headline)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                        }
                        .listRowBackground(Color.clear)
                        .padding(.vertical, 4)
                    }

                    if let implants = implantDetailsMap[clone.jump_clone_id], !implants.isEmpty {
                        ForEach(implants, id: \.typeId) { implant in
                            NavigationLink {
                                ShowItemInfo(
                                    databaseManager: databaseManager,
                                    itemID: implant.typeId
                                )
                            } label: {
                                HStack(alignment: .center, spacing: 8) {
                                    IconManager.shared.loadImage(for: implant.icon)
                                        .resizable()
                                        .frame(width: 36, height: 36)
                                        .cornerRadius(6)

                                    Text(implant.name)
                                        .font(.body)
                                        .lineLimit(2)
                                        .lineSpacing(1)

                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    } else {
                        Text(NSLocalizedString("Character_No_Implants", comment: ""))
                            .foregroundColor(.secondary)
                    }
                } header: {
                    if let name = clone.name {
                        Text(name)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    } else {
                        Text(
                            String(
                                format: NSLocalizedString("Character_Clone_ID", comment: ""),
                                clone.jump_clone_id
                            )
                        )
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        }
        .navigationTitle(NSLocalizedString("Character_Clone_Details", comment: ""))
        .task {
            await loadAllImplantDetails()
        }
    }

    private func loadAllImplantDetails() async {
        for clone in clones {
            if !clone.implants.isEmpty {
                let implantDetails = await ImplantInfo.loadImplantInfo(
                    typeIds: clone.implants,
                    databaseManager: databaseManager
                )
                await MainActor.run {
                    self.implantDetailsMap[clone.jump_clone_id] = implantDetails
                }
            }
        }
    }
}
