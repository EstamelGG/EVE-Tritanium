import SwiftUI

private struct KMVictimShipSheetItem: Identifiable {
    let typeId: Int
    var id: Int {
        typeId
    }
}

private struct KMFittingSheetItem: Identifiable {
    let id = UUID()
    let fitting: LocalFitting
}

struct BRKillMailDetailView: View {
    let listEntity: KillMailListEntity
    let character: EVECharacterInfo?
    @ObservedObject private var killMailFavorites = KillMailFavoritesStore.shared
    @State private var victimCharacterIcon: UIImage?
    @State private var victimCorporationIcon: UIImage?
    @State private var victimAllianceIcon: UIImage?
    @State private var shipIcon: UIImage?
    @State private var detailData: KillMailDetailData?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var destroyedValue: Double = 0
    @State private var droppedValue: Double = 0
    @State private var totalValue: Double = 0
    @State private var fittedValue: Double = 0
    @State private var itemInfoCache: [Int: (iconFileName: String, bpcIconFileName: String, categoryID: Int)] =
        [:]
    @State private var solarSystemInfo: SolarSystemInfo?
    @State private var zkbInfoFromAPI: ZKBInfo? // 存储从 API 获取的 zkb 信息
    /// 详情列表中各 type 的单价（EIV average）；未写入前 `ItemRow` 显示加载指示器
    @State private var kmMarketUnitPriceByType: [Int: Double] = [:]
    // 每次开始加载详情时递增，用于丢弃上一轮未完成的价格写入
    @State private var kmMarketPriceSession: Int = 0
    @State private var showZkbLinkCopiedAlert = false
    @State private var victimShipDetailSheetItem: KMVictimShipSheetItem?
    @State private var fittingToShow: KMFittingSheetItem?

    /// 监听屏幕方向变化
    @State private var orientation = UIDevice.current.orientation

    /// 布局状态标识符（用于判断是否需要重新渲染视图）
    @State private var layoutMode: LayoutMode = DeviceUtils.currentLayoutMode

    /// 判断是否应该使用紧凑布局（横屏或iPad）
    private var shouldUseCompactLayout: Bool {
        DeviceUtils.shouldUseCompactLayout
    }

    /// 导航辅助方法
    @ViewBuilder
    private func navigationDestination(for id: Int, type: String) -> some View {
        if let character = character {
            switch type {
            case "character":
                CharacterDetailView(characterId: id, character: character)
            case "corporation":
                CorporationDetailView(corporationId: id, character: character)
            case "alliance":
                AllianceDetailView(allianceId: id, character: character)
            default:
                EmptyView()
            }
        }
    }

    var body: some View {
        List {
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if let detail = detailData {
                if shouldUseCompactLayout {
                    compactLayout(detail: detail)
                        .contextMenu {
                            if let charId = detail.esi.victim.character_id {
                                NavigationLink {
                                    navigationDestination(for: charId, type: "character")
                                } label: {
                                    Label(NSLocalizedString("View Character", comment: ""), systemImage: "info.circle")
                                }
                            }
                            if detail.esi.victim.corporation_id > 0 {
                                NavigationLink {
                                    navigationDestination(for: detail.esi.victim.corporation_id, type: "corporation")
                                } label: {
                                    Label(NSLocalizedString("View Corporation", comment: ""), systemImage: "info.circle")
                                }
                            }
                            if let allyId = detail.esi.victim.alliance_id, allyId > 0 {
                                NavigationLink {
                                    navigationDestination(for: allyId, type: "alliance")
                                } label: {
                                    Label(NSLocalizedString("View Alliance", comment: ""), systemImage: "info.circle")
                                }
                            }
                            Divider()
                            let systemName = solarSystemInfo?.systemName ?? detail.system?.systemName ?? ""
                            if !systemName.isEmpty {
                                Button {
                                    UIPasteboard.general.string = systemName
                                } label: {
                                    Label(NSLocalizedString("Misc_Copy_Location", comment: ""), systemImage: "location")
                                }
                            }
                        }
                } else {
                    // 默认竖屏布局
                    defaultLayout(detail: detail)
                }

                // 装配信息部分保持不变
                fittingInfoSections(detail: detail)
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    killMailFavorites.toggle(
                        killmailId: listEntity.killmailId,
                        hash: listEntity.zkb.hash,
                        value: listEntity.zkb.totalValue,
                        droppedValue: listEntity.zkb.droppedValue,
                        destroyedValue: listEntity.zkb.destroyedValue
                    )
                } label: {
                    Image(
                        systemName: killMailFavorites.isFavorite(killmailId: listEntity.killmailId)
                            ? "star.fill" : "star"
                    )
                    .foregroundColor(.yellow)
                }
                .accessibilityLabel(
                    killMailFavorites.isFavorite(killmailId: listEntity.killmailId)
                        ? NSLocalizedString("KillMail_Favorites_Remove_A11y", comment: "")
                        : NSLocalizedString("KillMail_Favorites_Add_A11y", comment: "")
                )
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        UIPasteboard.general.string = zkillboardKillPageURLString(
                            killId: listEntity.killmailId
                        )
                        showZkbLinkCopiedAlert = true
                    } label: {
                        Label(
                            NSLocalizedString("KillMail_ZKB_Copy_Link", comment: ""),
                            systemImage: "doc.on.doc"
                        )
                    }

                    Button {
                        if let detail = detailData,
                           let fitting = detail.toLocalFitting()
                        {
                            fittingToShow = KMFittingSheetItem(fitting: fitting)
                        }
                    } label: {
                        Label(
                            NSLocalizedString("KillMail_Simulate_Fitting", comment: ""),
                            systemImage: "wrench.and.screwdriver"
                        )
                    }
                    .disabled(detailData == nil)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(
                    NSLocalizedString("KillMail_ZKB_Copy_Link_A11y", comment: "")
                )
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    openZKillboard(killId: listEntity.killmailId)
                } label: {
                    Image(systemName: "safari")
                    Text("zKB")
                }
            }
        }
        .alert(
            NSLocalizedString("Misc_Copied", comment: ""),
            isPresented: $showZkbLinkCopiedAlert
        ) {
            Button(NSLocalizedString("Common_OK", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("KillMail_ZKB_Link_Copy_Alert_Message", comment: ""))
        }
        .sheet(item: $victimShipDetailSheetItem) { item in
            NavigationStack {
                ItemInfoMap.getItemInfoView(
                    itemID: item.typeId,
                    databaseManager: DatabaseManager.shared
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(NSLocalizedString("Common_OK", comment: "")) {
                            victimShipDetailSheetItem = nil
                        }
                    }
                }
            }
        }
        .sheet(item: $fittingToShow) { item in
            NavigationStack {
                ShipFittingView(
                    temporaryFitting: item.fitting,
                    databaseManager: DatabaseManager.shared
                )
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(NSLocalizedString("Misc_back", comment: "")) {
                            fittingToShow = nil
                        }
                    }
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .refreshable {
            await loadBRKillMailDetail()
        }
        .task {
            if detailData == nil {
                await loadBRKillMailDetail()
            }
        }
        .onAppear {
            setupOrientationNotification()
        }
        .onDisappear {
            removeOrientationNotification()
        }
        .id(layoutMode)
    }

    // MARK: - 布局视图函数

    /// 紧凑布局（横屏或iPad）
    @ViewBuilder
    private func compactLayout(detail: KillMailDetailData) -> some View {
        // 第一行：左侧装配视图 + 右侧基本信息
        Section {
            GeometryReader { geometry in
                let availableWidth = geometry.size.width
                let fittingWidth = availableWidth * 0.5

                HStack(alignment: .top, spacing: 16) {
                    BRKillMailFittingView(detailData: detail)
                        .frame(width: fittingWidth, height: fittingWidth)
                        .cornerRadius(8)

                    VStack(spacing: 0) {
                        basicInfoList(detailData: detail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .aspectRatio(2, contentMode: .fit) // 2:1的比例
            .padding(.vertical, 8)
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        }

        // 第二行：伤害和价值信息列表
        Section {
            KmValueList()
        }
    }

    @ViewBuilder
    private func defaultLayout(detail: KillMailDetailData) -> some View {
        GeometryReader { geometry in
            BRKillMailFittingView(detailData: detail)
                .frame(width: geometry.size.width, height: geometry.size.width)
                .cornerRadius(8)
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(.vertical, 8)
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

        victimInfoSection(detailData: detail)
        basicInfoRows(detailData: detail)
    }

    private func basicInfoList(detailData: KillMailDetailData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            victimInfoCompact(detailData: detailData)
            Divider()
            shipInfoRow(shipId: detailData.esi.victim.ship_type_id)
            Divider()
            if let sys = detailData.system {
                systemInfoRowCompact(systemName: sys.systemName, regionName: sys.regionName, security: sys.security)
            }
            Divider()
            if let time = detailData.timestamp {
                localTimeRow(time: time)
                Divider()
            }
            DamageRow(dmg: detailData.esi.victim.damage_taken)
            Divider()
            if totalValue >= 0 {
                TotalRow(total: totalValue)
                Divider()
            }
            NavigationLink {
                KillMailAttackersView(detailData: detailData, character: character)
            } label: {
                HStack {
                    Text(NSLocalizedString("Main_KM_Attackers", comment: ""))
                    Spacer()
                    Text("\(detailData.attackers.count)")
                        .foregroundColor(.secondary)
                }
            }
            Divider()
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func victimInfoCompact(detailData: KillMailDetailData) -> some View {
        let v = detailData.esi.victim
        HStack(spacing: 12) {
            if let characterIcon = victimCharacterIcon {
                Image(uiImage: characterIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image("default_char")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            VStack(spacing: 2) {
                if let corpIcon = victimCorporationIcon {
                    Image(uiImage: corpIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                if let allyId = v.alliance_id, allyId > 0, let allyIcon = victimAllianceIcon {
                    Image(uiImage: allyIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                if let charId = v.character_id {
                    Text(detailData.characterName(for: charId))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                Text(detailData.corporationName(for: v.corporation_id))
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let allyId = v.alliance_id, allyId > 0 {
                    Text(detailData.allianceName(for: allyId))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .contextMenu {
                if let charId = v.character_id {
                    NavigationLink {
                        navigationDestination(for: charId, type: "character")
                    } label: {
                        Label(NSLocalizedString("View Character", comment: ""), systemImage: "info.circle")
                    }
                }
                if v.corporation_id > 0 {
                    NavigationLink {
                        navigationDestination(for: v.corporation_id, type: "corporation")
                    } label: {
                        Label(NSLocalizedString("View Corporation", comment: ""), systemImage: "info.circle")
                    }
                }
                if let allyId = v.alliance_id, allyId > 0 {
                    NavigationLink {
                        navigationDestination(for: allyId, type: "alliance")
                    } label: {
                        Label(NSLocalizedString("View Alliance", comment: ""), systemImage: "info.circle")
                    }
                }
            }

            Spacer()
        }
    }

    /// 舰船信息行
    private func shipInfoRow(shipId: Int) -> some View {
        HStack(spacing: 8) {
            Text(NSLocalizedString("Main_KM_Ship", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)

            HStack(spacing: 8) {
                if let shipIcon = shipIcon {
                    Image(uiImage: shipIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                VStack(alignment: .leading, spacing: 1) {
                    let shipInfo = getShipName(shipId)
                    Text(shipInfo.name)
                        .font(.caption)
                    Text(shipInfo.groupName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 4)
            victimShipDetailInlineButton(shipTypeId: shipId)
        }
    }

    private func victimShipDetailInlineButton(shipTypeId: Int) -> some View {
        Button {
            victimShipDetailSheetItem = KMVictimShipSheetItem(typeId: shipTypeId)
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 18))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text(NSLocalizedString("View Ship", comment: "")))
    }

    private func systemInfoRowCompact(systemName: String, regionName: String, security: Double) -> some View {
        HStack(spacing: 8) {
            Text(NSLocalizedString("Main_KM_System", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(formatSecurityStatus(security))
                        .font(.caption2)
                        .fontDesign(.monospaced)
                        .foregroundColor(getSecurityColor(security))
                    Text(solarSystemInfo?.systemName ?? systemName)
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                Text(solarSystemInfo?.regionName ?? regionName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    /// 本地时间行
    private func localTimeRow(time: Int) -> some View {
        HStack(spacing: 8) {
            Text(NSLocalizedString("Main_KM_Local_Time", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(formatLocalTime(time))
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    /// 伤害量行
    private func DamageRow(dmg: Int) -> some View {
        HStack(spacing: 8) {
            Text(NSLocalizedString("Main_KM_Damage", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(FormatUtil.formatInteger(dmg))
                .font(.caption)
                .fontDesign(.monospaced)
                .fontWeight(.semibold)
            Spacer()
        }
    }

    /// 总价值行
    private func TotalRow(total: Double) -> some View {
        HStack(spacing: 8) {
            Text(NSLocalizedString("Main_KM_Total", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(FormatUtil.formatISK(total))
                .font(.caption)
                .fontDesign(.monospaced)
                .fontWeight(.semibold)
            Spacer()
        }
    }

    /// 伤害和价值信息列表
    @ViewBuilder
    private func KmValueList() -> some View {
        // 摧毁价值
        HStack {
            Text(NSLocalizedString("Main_KM_Destroyed_Value", comment: ""))
                .font(.subheadline)
            Spacer()
            Text(FormatUtil.formatISK(destroyedValue))
                .font(.subheadline)
                .fontDesign(.monospaced)
                .foregroundColor(.red)
        }

        // 掉落价值
        HStack {
            Text(NSLocalizedString("Main_KM_Dropped_Value", comment: ""))
                .font(.subheadline)
            Spacer()
            Text(FormatUtil.formatISK(droppedValue))
                .font(.subheadline)
                .fontDesign(.monospaced)
                .foregroundColor(.green)
        }

        // 总价值
        HStack {
            Text(NSLocalizedString("Main_KM_Total", comment: ""))
                .font(.subheadline)
                .fontWeight(.semibold)
            Spacer()
            Text(FormatUtil.formatISK(totalValue))
                .font(.subheadline)
                .fontDesign(.monospaced)
                .fontWeight(.semibold)
        }
    }

    @ViewBuilder
    private func victimInfoSection(detailData: KillMailDetailData) -> some View {
        let v = detailData.esi.victim
        HStack(spacing: 12) {
            if let characterIcon = victimCharacterIcon {
                Image(uiImage: characterIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 66, height: 66)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image("default_char")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 66, height: 66)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(spacing: 2) {
                if let corpIcon = victimCorporationIcon {
                    Image(uiImage: corpIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                if let allyId = v.alliance_id, allyId > 0, let allyIcon = victimAllianceIcon {
                    Image(uiImage: allyIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                if let charId = v.character_id {
                    Text(detailData.characterName(for: charId))
                        .font(.headline)
                }
                Text(detailData.corporationName(for: v.corporation_id))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                if let allyId = v.alliance_id, allyId > 0 {
                    Text(detailData.allianceName(for: allyId))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .contextMenu {
                if let charId = v.character_id {
                    NavigationLink {
                        navigationDestination(for: charId, type: "character")
                    } label: {
                        Label(NSLocalizedString("View Character", comment: ""), systemImage: "info.circle")
                    }
                }
                if v.corporation_id > 0 {
                    NavigationLink {
                        navigationDestination(for: v.corporation_id, type: "corporation")
                    } label: {
                        Label(NSLocalizedString("View Corporation", comment: ""), systemImage: "info.circle")
                    }
                }
                if let allyId = v.alliance_id, allyId > 0 {
                    NavigationLink {
                        navigationDestination(for: allyId, type: "alliance")
                    } label: {
                        Label(NSLocalizedString("View Alliance", comment: ""), systemImage: "info.circle")
                    }
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
    }

    @ViewBuilder
    private func basicInfoRows(detailData: KillMailDetailData) -> some View {
        let shipId = detailData.esi.victim.ship_type_id
        HStack {
            Text(NSLocalizedString("Main_KM_Ship", comment: ""))
                .frame(width: 110, alignment: .leading)
            HStack {
                if let shipIcon = shipIcon {
                    Image(uiImage: shipIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                VStack(alignment: .leading) {
                    let shipInfo = getShipName(shipId)
                    Text(shipInfo.name)
                    Text(shipInfo.groupName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 8)
            victimShipDetailInlineButton(shipTypeId: shipId)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

        if let sys = detailData.system {
            HStack {
                Text(NSLocalizedString("Main_KM_System", comment: ""))
                    .frame(width: 110, alignment: .leading)
                    .frame(maxHeight: .infinity, alignment: .center)
                VStack(alignment: .leading) {
                    HStack {
                        Text(formatSecurityStatus(sys.security))
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(getSecurityColor(sys.security))
                        Text(solarSystemInfo?.systemName ?? sys.systemName)
                            .fontWeight(.semibold)
                    }
                    Text(solarSystemInfo?.regionName ?? sys.regionName)
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .contextMenu {
                let systemName = solarSystemInfo?.systemName ?? sys.systemName
                if !systemName.isEmpty {
                    Button {
                        UIPasteboard.general.string = systemName
                    } label: {
                        Label(
                            NSLocalizedString("Misc_Copy_Location", comment: ""),
                            systemImage: "location"
                        )
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        }

        // Local Time
        HStack {
            Text(NSLocalizedString("Main_KM_Local_Time", comment: ""))
                .frame(width: 110, alignment: .leading)
            if let time = detailData.timestamp {
                Text(formatLocalTime(time))
                    .foregroundColor(.secondary)
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

        // Damage
        HStack {
            Text(NSLocalizedString("Main_KM_Damage", comment: ""))
                .frame(width: 110, alignment: .leading)
            Text(FormatUtil.formatInteger(detailData.esi.victim.damage_taken))
                .foregroundColor(.secondary)
                .font(.system(.body, design: .monospaced))
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

        // Destroyed
        HStack {
            Text(NSLocalizedString("Main_KM_Destroyed_Value", comment: ""))
                .frame(width: 110, alignment: .leading)
            Text(FormatUtil.formatISK(destroyedValue))
                .foregroundColor(.red)
                .font(.system(.body, design: .monospaced))
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

        // Dropped
        HStack {
            Text(NSLocalizedString("Main_KM_Dropped_Value", comment: ""))
                .frame(width: 110, alignment: .leading)
            Text(FormatUtil.formatISK(droppedValue))
                .foregroundColor(.green)
                .font(.system(.body, design: .monospaced))
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

        // Total
        HStack {
            Text(NSLocalizedString("Main_KM_Total", comment: ""))
                .frame(width: 110, alignment: .leading)
            Text(FormatUtil.formatISK(totalValue))
                .font(.system(.body, design: .monospaced))
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

        // 参与者（attackers）
        NavigationLink {
            KillMailAttackersView(detailData: detailData, character: character)
        } label: {
            HStack {
                Text(NSLocalizedString("Main_KM_Attackers", comment: ""))
                    .frame(width: 110, alignment: .leading)
                Spacer()
                Text("\(detailData.attackers.count)")
                    .foregroundColor(.secondary)
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
    }

    private func itemDepth(_ item: [Int]) -> Int {
        item.count > 5 ? item[5] : 0
    }

    private func killMailLegacyItemRows(_ items: [[Int]]) -> some View {
        ForEach(items, id: \.self) { item in
            let typeId = item[1]
            let depth = itemDepth(item)
            let singleton = item.count > 4 ? item[4] : 0
            let flag = item[0]
            let chargeTypeId = item.count > 6 ? item[6] : 0
            let chargeQuantity = item.count > 7 ? item[7] : 0
            if item[2] > 0 {
                ItemRow(
                    typeId: typeId, quantity: item[2], isDropped: true,
                    itemInfoCache: itemInfoCache,
                    resolvedUnitPrice: kmMarketUnitPriceByType[typeId],
                    depth: depth,
                    singleton: singleton,
                    flag: flag,
                    chargeTypeId: chargeTypeId,
                    chargeQuantity: chargeQuantity
                )
            }
            if item[3] > 0 {
                ItemRow(
                    typeId: typeId, quantity: item[3], isDropped: false,
                    itemInfoCache: itemInfoCache,
                    resolvedUnitPrice: kmMarketUnitPriceByType[typeId],
                    depth: depth,
                    singleton: singleton,
                    flag: flag,
                    chargeTypeId: chargeTypeId,
                    chargeQuantity: chargeQuantity
                )
            }
        }
    }

    private func killMailDisplayItemRows(_ rows: [KillMailDisplayRow]) -> some View {
        ForEach(rows) { row in
            if row.quantityDropped > 0 {
                ItemRow(
                    typeId: row.typeId, quantity: row.quantityDropped, isDropped: true,
                    itemInfoCache: itemInfoCache,
                    resolvedUnitPrice: kmMarketUnitPriceByType[row.typeId],
                    depth: row.depth,
                    singleton: row.singleton,
                    flag: row.flag
                )
            }
            if row.quantityDestroyed > 0 {
                ItemRow(
                    typeId: row.typeId, quantity: row.quantityDestroyed, isDropped: false,
                    itemInfoCache: itemInfoCache,
                    resolvedUnitPrice: kmMarketUnitPriceByType[row.typeId],
                    depth: row.depth,
                    singleton: row.singleton,
                    flag: row.flag
                )
            }
        }
    }

    @ViewBuilder
    private func fittingInfoSections(detail: KillMailDetailData) -> some View {
        let items = detail.convertedItemsForFitting
        if !items.isEmpty {
            shipFittingSlotSections(items: items)
            nonFittingNestedItemSections(detail: detail)
        }
    }

    @ViewBuilder
    private func shipFittingSlotSections(items: [[Int]]) -> some View {
        let rowInsets = EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)
        let implantItems = KillMailItemTreeBuilder.sortFittingSiblingRows(
            items.filter { $0[0] == 89 && $0.count >= 4 },
            itemInfoCache: itemInfoCache
        )
        if !implantItems.isEmpty {
            Section(header: kmSectionHeader(NSLocalizedString("Main_KM_Implants", comment: ""))) {
                killMailLegacyItemRows(implantItems)
            }
            .listRowInsets(rowInsets)
        }

        fittingSlotSection(
            title: NSLocalizedString("Main_KM_High_Slots", comment: ""),
            slotItems: KillMailItemTreeBuilder.sortFittingSiblingRows(
                items.filter { (27 ... 34).contains($0[0]) && $0.count >= 4 },
                itemInfoCache: itemInfoCache
            ),
            rowInsets: rowInsets
        )
        fittingSlotSection(
            title: NSLocalizedString("Main_KM_Medium_Slots", comment: ""),
            slotItems: KillMailItemTreeBuilder.sortFittingSiblingRows(
                items.filter { (19 ... 26).contains($0[0]) && $0.count >= 4 },
                itemInfoCache: itemInfoCache
            ),
            rowInsets: rowInsets
        )
        fittingSlotSection(
            title: NSLocalizedString("Main_KM_Low_Slots", comment: ""),
            slotItems: KillMailItemTreeBuilder.sortFittingSiblingRows(
                items.filter { (11 ... 18).contains($0[0]) && $0.count >= 4 },
                itemInfoCache: itemInfoCache
            ),
            rowInsets: rowInsets
        )
        fittingSlotSection(
            title: NSLocalizedString("Main_KM_Rig_Slots", comment: ""),
            slotItems: items.filter { (92 ... 94).contains($0[0]) && $0.count >= 4 }.sorted { $0[0] < $1[0] },
            rowInsets: rowInsets
        )
        fittingSlotSection(
            title: NSLocalizedString("Main_KM_Subsystem_Slots", comment: ""),
            slotItems: items.filter { (125 ... 128).contains($0[0]) && $0.count >= 4 }.sorted { $0[0] < $1[0] },
            rowInsets: rowInsets
        )
        fittingSlotSection(
            title: NSLocalizedString("Main_KM_Fighter_Tubes", comment: ""),
            slotItems: items.filter { (159 ... 163).contains($0[0]) && $0.count >= 4 }.sorted { $0[0] < $1[0] },
            rowInsets: rowInsets
        )
    }

    @ViewBuilder
    private func fittingSlotSection(
        title: String,
        slotItems: [[Int]],
        rowInsets: EdgeInsets
    ) -> some View {
        if !slotItems.isEmpty {
            Section(header: kmSectionHeader(title)) {
                killMailLegacyItemRows(slotItems)
            }
            .listRowInsets(rowInsets)
        }
    }

    private func kmSectionHeader(_ title: String) -> some View {
        Text(title)
    }

    @ViewBuilder
    private func nonFittingNestedItemSections(detail: KillMailDetailData) -> some View {
        let victimRoots = detail.esi.victim.items ?? []
        let nonFittingFlags = Set(
            victimRoots.map(\.flag).filter { !isShipFittingFlag($0) }
        ).sorted()

        ForEach(nonFittingFlags, id: \.self) { flag in
            nonFittingFlagSection(detail: detail, flag: flag)
        }
    }

    private func isShipFittingFlag(_ flag: Int) -> Bool {
        (11 ... 18).contains(flag)
            || (19 ... 26).contains(flag)
            || (27 ... 34).contains(flag)
            || (92 ... 94).contains(flag)
            || (125 ... 128).contains(flag)
            || (159 ... 163).contains(flag)
            || flag == 89
    }

    @ViewBuilder
    private func nonFittingFlagSection(detail: KillMailDetailData, flag: Int) -> some View {
        let displayRows = detail.displayRows(
            forFlag: flag,
            unitPriceByType: kmMarketUnitPriceByType
        )
        if !displayRows.isEmpty {
            Section(header: kmSectionHeader(getFlagName(flag))) {
                killMailDisplayItemRows(displayRows)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        }
    }

    // MARK: - 方向变化通知处理

    /// 设置方向变化通知
    private func setupOrientationNotification() {
        NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            self.orientation = UIDevice.current.orientation

            // 只有当布局模式真正发生变化时才更新layoutMode
            let newLayoutMode = DeviceUtils.currentLayoutMode
            if DeviceUtils.shouldUpdateLayout(from: self.layoutMode, to: newLayoutMode) {
                Logger.debug("布局模式变化: \(self.layoutMode.rawValue) -> \(newLayoutMode.rawValue)")
                self.layoutMode = newLayoutMode
            }
        }
    }

    /// 移除方向变化通知
    private func removeOrientationNotification() {
        NotificationCenter.default.removeObserver(
            self,
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }

    // MARK: - 原有的辅助函数

    @MainActor
    private func loadBRKillMailDetail() async {
        isLoading = true
        kmMarketPriceSession += 1
        let priceSession = kmMarketPriceSession
        kmMarketUnitPriceByType = [:]
        defer { isLoading = false }

        do {
            let killId = listEntity.killmailId
            let hash = listEntity.zkb.hash
            Logger.debug("开始加载战报ID \(killId) 的详细信息")

            let detail = try await KillMailDataConverter.shared.fetchKillMailDetail(
                killmailId: killId,
                hash: hash,
                zkb: listEntity.zkb
            )

            if let zkb = detail.zkb { zkbInfoFromAPI = zkb }

            loadAllItemInfo(from: detail)
            await loadIcons(from: detail)

            solarSystemInfo = await getSolarSystemInfo(
                solarSystemId: detail.esi.solar_system_id,
                databaseManager: DatabaseManager.shared
            )

            let zkb = zkbInfoFromAPI ?? listEntity.zkb
            fittedValue = zkb.fittedValueValue
            droppedValue = zkb.droppedValueValue
            destroyedValue = zkb.destroyedValueValue
            totalValue = zkb.totalValueValue
            detailData = detail

            if killMailFavorites.isFavorite(killmailId: killId) {
                KillMailFavoritesStore.shared.updateStoredZkbFieldsIfMissing(
                    killmailId: killId,
                    totalValue: zkb.totalValue,
                    droppedValue: zkb.droppedValue,
                    destroyedValue: zkb.destroyedValue
                )
            }

            let priceTypeIds = collectKillMailPriceTypeIds(detail)
            Task {
                await applyKillMailMarketPrices(typeIds: priceTypeIds, session: priceSession)
            }
        } catch {
            Logger.error("加载战斗日志详情失败: \(error)")
            errorMessage = "加载失败: \(error.localizedDescription)"
        }
    }

    private func collectKillMailPriceTypeIds(_ detail: KillMailDetailData) -> [Int] {
        var typeIds = Set<Int>()
        typeIds.insert(detail.esi.victim.ship_type_id)
        for typeId in KillMailDetailData.allVictimItemTypeIds(from: detail.esi.victim.items) {
            typeIds.insert(typeId)
        }
        return Array(typeIds)
    }

    /// EIV 全表一次拉取后批量写入状态，避免按 type 逐条更新触发多次重排/重绘。
    /// 展示前 `kmMarketUnitPriceByType` 为空，排序等价于单价 0；写入后货舱区仅再排序一次。
    private func applyKillMailMarketPrices(typeIds: [Int], session: Int) async {
        guard !typeIds.isEmpty else { return }
        let marketPrices = await MarketPriceUtil.getMarketPrices(typeIds: typeIds)
        var unitByType: [Int: Double] = [:]
        unitByType.reserveCapacity(typeIds.count)
        for typeId in typeIds {
            unitByType[typeId] = marketPrices[typeId]?.averagePrice ?? 0
        }
        Logger.debug("战报详情: 市场价格批量获取完成，一次性写入 \(unitByType.count)/\(typeIds.count) 条")
        await MainActor.run {
            guard session == kmMarketPriceSession else { return }
            kmMarketUnitPriceByType = unitByType
        }
    }

    @MainActor
    private func loadIcons(from detail: KillMailDetailData) async {
        if let charId = detail.esi.victim.character_id {
            do {
                victimCharacterIcon = try await CharacterAPI.shared.fetchCharacterPortrait(
                    characterId: charId,
                    size: 128
                )
            } catch {
                Logger.error("加载角色头像失败: \(error)")
            }
        }

        let corpId = detail.esi.victim.corporation_id
        do {
            victimCorporationIcon = try await CorporationAPI.shared.fetchCorporationLogo(
                corporationId: corpId,
                size: 64
            )
        } catch {
            Logger.error("加载军团图标失败: \(error)")
        }

        if let allyId = detail.esi.victim.alliance_id, allyId > 0 {
            do {
                victimAllianceIcon = try await AllianceAPI.shared.fetchAllianceLogo(
                    allianceID: allyId,
                    size: 64
                )
            } catch {
                Logger.error("加载联盟图标失败: \(error)")
            }
        }

        let shipId = detail.esi.victim.ship_type_id
        Task {
            do {
                let image = try await ItemRenderAPI.shared.fetchItemRender(
                    typeId: shipId, size: 64
                )
                await MainActor.run {
                    shipIcon = image
                }
            } catch {
                Logger.error("击毁详情: 加载舰船图标失败 - \(error)")
            }
        }
    }

    private func getShipName(_ shipId: Int) -> (name: String, groupName: String) {
        guard let type = ItemInfoMap.typeInfo(for: shipId), !type.name.isEmpty else {
            return ("Unknown Ship", "Unknown Group")
        }
        let groupName: String
        if let groupID = type.groupID,
           let group = SDEMemoryStore.group(for: groupID),
           !group.name.isEmpty
        {
            groupName = group.name
        } else {
            groupName = "Unknown Group"
        }
        return (type.name, groupName)
    }

    private func formatSecurityStatus(_ value: Double) -> String {
        return String(format: "%.1f", value)
    }

    private func formatLocalTime(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    private func zkillboardKillPageURLString(killId: Int) -> String {
        "https://zkillboard.com/kill/\(killId)/"
    }

    private func openZKillboard(killId: Int) {
        if let url = URL(string: zkillboardKillPageURLString(killId: killId)) {
            UIApplication.shared.open(url)
        }
    }

    private func getFlagName(_ flag: Int) -> String {
        return FlagMapping.getFlagName(for: flag)
    }

    private func loadAllItemInfo(from detail: KillMailDetailData) {
        var typeIds = Set<Int>()
        typeIds.insert(detail.esi.victim.ship_type_id)
        for typeId in KillMailDetailData.allVictimItemTypeIds(from: detail.esi.victim.items) {
            typeIds.insert(typeId)
        }

        for typeId in typeIds {
            guard let info = SDEMemoryStore.type(for: typeId) else { continue }
            itemInfoCache[typeId] = (
                info.iconFilename,
                info.bpcIconFilename ?? "",
                info.categoryID
            )
        }
    }
}

struct ItemRow: View {
    let typeId: Int
    let quantity: Int
    let isDropped: Bool // 是否为掉落物品
    let itemInfoCache: [Int: (iconFileName: String, bpcIconFileName: String, categoryID: Int)]
    /// 已解析的单价；`nil` 表示价格仍在加载，显示占位指示器
    let resolvedUnitPrice: Double?
    /// 嵌套深度（0=顶层，>0 为容器内容物，用于左侧缩进）
    var depth: Int = 0
    /// ESI singleton 字段（0=BPO/可堆叠，非0=BPC/单件）
    var singleton: Int = 0
    /// 物品所在舱位 flag（5=船舱/Cargo）
    var flag: Int = 0
    /// 装配槽位装备行附带的弹药 type_id（0 表示无弹药）
    var chargeTypeId: Int = 0
    /// 装配槽位装备行附带的弹药数量（dropped+destroyed 合并）
    var chargeQuantity: Int = 0

    private var nestedIndent: CGFloat {
        CGFloat(depth) * 16
    }

    /// 判断是否为蓝图复制品（BPC）：位于船舱 + 蓝图类别 + singleton 非 0
    private var isBPC: Bool {
        flag == 5 && itemInfoCache[typeId]?.categoryID == 9 && singleton != 0
    }

    /// BPC 单价统一为 0.01 ISK
    private var effectiveUnitPrice: Double? {
        if isBPC { return 0.01 }
        return resolvedUnitPrice
    }

    /// 当前应显示的图标文件名（BPC 使用 bpc_icon_filename，无则回退到普通图标）
    private var iconFileName: String {
        guard let info = itemInfoCache[typeId] else { return "" }
        if isBPC && !info.bpcIconFileName.isEmpty {
            return info.bpcIconFileName
        }
        return info.iconFileName
    }

    /// 是否附带弹药
    private var hasCharge: Bool {
        chargeTypeId > 0
    }

    /// 弹药图标文件名
    private var chargeIconFileName: String {
        itemInfoCache[chargeTypeId]?.iconFileName ?? ""
    }

    var body: some View {
        if itemInfoCache[typeId] != nil {
            NavigationLink(destination: {
                ItemInfoMap.getItemInfoView(
                    itemID: typeId,
                    databaseManager: DatabaseManager.shared
                )
            }) {
                HStack(spacing: 8) {
                    if nestedIndent > 0 {
                        Color.clear.frame(width: nestedIndent, height: 1)
                    }
                    Image(uiImage: IconManager.shared.loadUIImage(for: iconFileName))
                        .resizable()
                        .frame(width: 32, height: 32)
                        .cornerRadius(6)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(SDEMemoryStore.type(for: typeId)?.name ?? "Type \(typeId)")
                        if hasCharge {
                            chargeLine
                        }
                        priceCaptionLine
                    }

                    Spacer()
                    if quantity > 1 {
                        Text("×\(quantity)")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            .listRowBackground(
                isDropped ? Color.green.opacity(0.2) : nil
            )
        } else {
            HStack(spacing: 8) {
                if nestedIndent > 0 {
                    Color.clear.frame(width: nestedIndent, height: 1)
                }
                Image("not_found")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        String(
                            format: NSLocalizedString("KillMail_Unknown_Item", comment: ""), typeId
                        )
                    )
                    priceCaptionLine
                }
                Spacer()
                if quantity > 1 {
                    Text("×\(quantity)")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }

    /// 弹药行：图标 + 名称 + 数量（与装配模拟的弹药行设计一致）
    private var chargeLine: some View {
        HStack(spacing: 4) {
            Image(uiImage: IconManager.shared.loadUIImage(for: chargeIconFileName))
                .resizable()
                .frame(width: 20, height: 20)
                .cornerRadius(2)
            Text(SDEMemoryStore.type(for: chargeTypeId)?.name ?? "Type \(chargeTypeId)")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            if chargeQuantity > 1 {
                Text("×\(chargeQuantity)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var priceCaptionLine: some View {
        if let unit = effectiveUnitPrice {
            Text(FormatUtil.formatISK(unit * Double(quantity)))
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.85)
                .frame(height: 14)
        }
    }
}

// MARK: - 仅 kill ID 时的加载器（用于 killreport 链接等场景）

struct KillMailDetailLoaderView: View {
    let killmailId: Int
    let character: EVECharacterInfo?
    @State private var listEntity: KillMailListEntity?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let entity = listEntity {
                BRKillMailDetailView(listEntity: entity, character: character)
            } else if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .task {
            await loadEntity()
        }
    }

    private func loadEntity() async {
        do {
            let zkbEntry = try await zKbToolAPI.shared.fetchZKBKillMailByID(killmailId: killmailId)
            let detail = try await KillMailDataConverter.shared.fetchKillMailDetail(
                killmailId: killmailId,
                hash: zkbEntry.zkb.hash,
                zkb: zkbEntry.zkb
            )
            let timestamp = detail.timestamp ?? 0
            let entity = KillMailListEntity(
                killmailId: killmailId,
                timestamp: timestamp,
                zkb: zkbEntry.zkb,
                victim: detail.esi.victim,
                names: detail.names,
                system: detail.system
            )
            await MainActor.run {
                listEntity = entity
            }
        } catch {
            Logger.error("加载战斗日志失败 - killmail_id: \(killmailId), error: \(error)")
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - 参与者（attackers）页面

/// 用于 ForEach 的稳定 id，避免搜索过滤时视图复用导致头像/图标错位
private struct AttackerRowItem: Identifiable {
    let attacker: ESIAttacker
    let id: String // section 前缀 + 原始索引，确保跨 section 唯一
    init(attacker: ESIAttacker, stableId: Int, section: String) {
        self.attacker = attacker
        id = "\(section)_\(stableId)"
    }
}

struct KillMailAttackersView: View {
    let detailData: KillMailDetailData
    let character: EVECharacterInfo?
    @State private var searchText = ""
    /// 参与者页按需加载的实体名称（与 `detailData.names` 合并后展示；受害者名称以详情中为准）
    @State private var supplementalAttackerNames: [Int: String] = [:]
    /// 名称批量解析中（未解析名称显示骨架占位而非 ID 兜底文案）
    @State private var isLoadingNames = true

    /// 搜索关键词（至少2字符才生效）
    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearchActive: Bool {
        searchQuery.count >= 2
    }

    /// 详情中已解析名称 + 参与者页补充名称（同 id 以详情为准）
    private var mergedEntityNames: [Int: String] {
        supplementalAttackerNames.merging(detailData.names) { _, fromDetail in fromDetail }
    }

    /// 参与者是否匹配搜索（人物名、军团名、联盟名）
    private func attackerMatchesSearch(_ atk: ESIAttacker) -> Bool {
        guard isSearchActive else { return true }
        let q = searchQuery.lowercased()
        let m = mergedEntityNames
        let charName = atk.character_id.map { m[$0] ?? "Character \($0)" } ?? ""
        let corpName = atk.corporation_id.map { m[$0] ?? "Corporation \($0)" } ?? ""
        let allyName = (atk.alliance_id ?? 0) > 0 ? (m[atk.alliance_id!] ?? "Alliance \(atk.alliance_id!)") : ""
        return charName.localizedCaseInsensitiveContains(q)
            || corpName.localizedCaseInsensitiveContains(q)
            || allyName.localizedCaseInsensitiveContains(q)
    }

    /// 最后一击：final_blow == true
    private var finalBlowAttackers: [ESIAttacker] {
        detailData.attackers.filter { $0.final_blow }
    }

    /// 最多伤害：damage_done 最高者，同值按 character_id 排序
    private var mostDamageAttackers: [ESIAttacker] {
        let attackers = detailData.attackers
        guard let maxDmg = attackers.map(\.damage_done).max(), maxDmg > 0 else { return [] }
        return attackers
            .filter { $0.damage_done == maxDmg }
            .sorted { sortKey($0) < sortKey($1) }
    }

    /// 我的击杀：当前登录角色参与的参与者
    private var myAttackers: [ESIAttacker] {
        guard let myCharId = character?.CharacterID else { return [] }
        return detailData.attackers
            .filter { $0.character_id == myCharId }
            .sorted { a, b in
                if a.damage_done != b.damage_done { return a.damage_done > b.damage_done }
                return sortKey(a) < sortKey(b)
            }
    }

    /// 所有人：按 damage_done 降序，次按 character_id
    private var allAttackers: [ESIAttacker] {
        detailData.attackers.sorted { a, b in
            if a.damage_done != b.damage_done { return a.damage_done > b.damage_done }
            return sortKey(a) < sortKey(b)
        }
    }

    /// 应用搜索过滤后的列表
    private var filteredMyAttackers: [ESIAttacker] {
        myAttackers.filter(attackerMatchesSearch)
    }

    private var filteredFinalBlowAttackers: [ESIAttacker] {
        finalBlowAttackers.filter(attackerMatchesSearch)
    }

    private var filteredMostDamageAttackers: [ESIAttacker] {
        mostDamageAttackers.filter(attackerMatchesSearch)
    }

    private var filteredAllAttackers: [ESIAttacker] {
        allAttackers.filter(attackerMatchesSearch)
    }

    private var totalDamageDone: Int {
        detailData.attackers.reduce(0) { $0 + $1.damage_done }
    }

    private func sortKey(_ a: ESIAttacker) -> Int {
        a.character_id ?? a.corporation_id ?? a.alliance_id ?? 0
    }

    /// 获取 attacker 在原始列表中的索引，作为 ForEach 的稳定 id，避免过滤时视图复用导致头像错位
    private func attackerStableId(_ atk: ESIAttacker) -> Int {
        detailData.attackers.firstIndex { a in
            a.character_id == atk.character_id
                && a.corporation_id == atk.corporation_id
                && a.alliance_id == atk.alliance_id
                && a.ship_type_id == atk.ship_type_id
                && a.weapon_type_id == atk.weapon_type_id
                && a.damage_done == atk.damage_done
                && a.final_blow == atk.final_blow
        } ?? -1
    }

    var body: some View {
        let total = totalDamageDone
        let nameMap = mergedEntityNames
        List {
            if !filteredMyAttackers.isEmpty {
                Section(NSLocalizedString("Main_KM_Attackers_My_Kills", comment: "")) {
                    ForEach(filteredMyAttackers.map { AttackerRowItem(attacker: $0, stableId: attackerStableId($0), section: "my") }) { item in
                        AttackerRowView(
                            attacker: item.attacker, entityNameMap: nameMap,
                            totalDamageDone: total, character: character,
                            isNamesLoading: isLoadingNames
                        )
                    }
                }
            }
            if !filteredFinalBlowAttackers.isEmpty {
                Section(NSLocalizedString("Main_KM_Attackers_Final_Blow", comment: "")) {
                    ForEach(filteredFinalBlowAttackers.map { AttackerRowItem(attacker: $0, stableId: attackerStableId($0), section: "final") }) { item in
                        AttackerRowView(
                            attacker: item.attacker, entityNameMap: nameMap,
                            totalDamageDone: total, character: character,
                            isNamesLoading: isLoadingNames
                        )
                    }
                }
            }
            if !filteredMostDamageAttackers.isEmpty {
                Section(NSLocalizedString("Main_KM_Attackers_Most_Damage", comment: "")) {
                    ForEach(filteredMostDamageAttackers.map { AttackerRowItem(attacker: $0, stableId: attackerStableId($0), section: "damage") }) { item in
                        AttackerRowView(
                            attacker: item.attacker, entityNameMap: nameMap,
                            totalDamageDone: total, character: character,
                            isNamesLoading: isLoadingNames
                        )
                    }
                }
            }
            Section(String(format: NSLocalizedString("Main_KM_Attackers_All_With_Count", comment: ""), filteredAllAttackers.count)) {
                if filteredAllAttackers.isEmpty && isSearchActive {
                    Text(NSLocalizedString("Main_Search_No_Results", comment: ""))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    ForEach(filteredAllAttackers.map { AttackerRowItem(attacker: $0, stableId: attackerStableId($0), section: "all") }) { item in
                        AttackerRowView(
                            attacker: item.attacker, entityNameMap: nameMap,
                            totalDamageDone: total, character: character,
                            isNamesLoading: isLoadingNames
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: NSLocalizedString("Main_KM_Attackers_Search_Placeholder", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("")
        .task {
            await loadAttackerEntityNamesIfNeeded()
        }
    }

    /// 仅查询参与者相关且详情中尚未有的实体名称（触发 `universe_names` 等）
    private func loadAttackerEntityNamesIfNeeded() async {
        defer { isLoadingNames = false }

        var ids = Set<Int>()
        for atk in detailData.attackers {
            if let c = atk.character_id { ids.insert(c) }
            if let c = atk.corporation_id { ids.insert(c) }
            if let a = atk.alliance_id, a > 0 { ids.insert(a) }
        }
        let missing = ids.filter { detailData.names[$0] == nil }
        guard !missing.isEmpty else { return }
        do {
            let fetched = try await UniverseAPI.shared.getNamesWithFallback(ids: Array(missing))
            await MainActor.run {
                var merged = supplementalAttackerNames
                for (id, pair) in fetched {
                    merged[id] = pair.name
                }
                supplementalAttackerNames = merged
            }
        } catch {
            Logger.error("战报参与者: 批量解析名称失败 - \(error)")
        }
    }
}

// MARK: - 参与者行视图

private struct AttackerRowView: View {
    let attacker: ESIAttacker
    // 角色/军团/联盟 id → 名称（含详情预取 + 参与者页补充）
    let entityNameMap: [Int: String]
    let totalDamageDone: Int
    let character: EVECharacterInfo?
    /// 名称批量解析中：未解析名称显示骨架占位，完成后才落 ID 兜底文案
    var isNamesLoading: Bool = false
    @State private var characterPortrait: UIImage?
    @State private var resolvedShipName: String? // 未知参与者时，从数据库查询 ship_type_id 的 name

    private var damagePercentage: String {
        guard totalDamageDone > 0 else { return "0%" }
        let pct = Double(attacker.damage_done) / Double(totalDamageDone) * 100
        return String(format: "%.1f%%", pct)
    }

    private func formatDamage(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    /// 是否为“未知”参与者（无 character/alliance/corporation 信息）
    private var isUnknownParticipant: Bool {
        attacker.character_id == nil
            && (attacker.alliance_id == nil || attacker.alliance_id == 0)
            && attacker.corporation_id == nil
    }

    private var displayName: String {
        if let id = attacker.character_id { return entityNameMap[id] ?? "Character \(id)" }
        if let id = attacker.alliance_id, id > 0 { return entityNameMap[id] ?? "Alliance \(id)" }
        if let id = attacker.corporation_id { return entityNameMap[id] ?? "Corporation \(id)" }
        return NSLocalizedString("Unknown", comment: "")
    }

    /// 最终显示名称：未知参与者时优先显示 ship_type_id 的 name
    private var displayNameText: String {
        if isUnknownParticipant, let name = resolvedShipName, !name.isEmpty {
            return name
        }
        return displayName
    }

    private var corporationName: String {
        guard let id = attacker.corporation_id else { return "-" }
        return entityNameMap[id] ?? "Corporation \(id)"
    }

    private var allianceName: String {
        guard let id = attacker.alliance_id, id > 0 else { return "-" }
        return entityNameMap[id] ?? "Alliance \(id)"
    }

    /// 名称三态：已解析 → 文本；解析中 → 骨架；完成仍缺失 → ID 兜底
    private var isPrimaryNamePending: Bool {
        let id = attacker.character_id
            ?? (attacker.alliance_id ?? 0 > 0 ? attacker.alliance_id : nil)
            ?? attacker.corporation_id
        guard let id else { return false }
        return entityNameMap[id] == nil && isNamesLoading
    }

    private var isCorpNamePending: Bool {
        guard let id = attacker.corporation_id else { return false }
        return entityNameMap[id] == nil && isNamesLoading
    }

    private var isAllianceNamePending: Bool {
        guard let id = attacker.alliance_id, id > 0 else { return false }
        return entityNameMap[id] == nil && isNamesLoading
    }

    /// 上方图标：优先 ship_type_id，缺失时用 weapon_type_id 替代
    private var shipIconName: String {
        let typeId = attacker.ship_type_id ?? attacker.weapon_type_id
        guard let id = typeId else { return "not_found" }
        return DatabaseManager.shared.getItemIconFileName(for: id) ?? "not_found"
    }

    /// 下方图标：优先 weapon_type_id，缺失时用 ship_type_id 替代
    private var weaponIconName: String {
        let typeId = attacker.weapon_type_id ?? attacker.ship_type_id
        guard let id = typeId else { return "not_found" }
        return DatabaseManager.shared.getItemIconFileName(for: id) ?? "not_found"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            // 左侧头像 64x64
            (characterPortrait.map { Image(uiImage: $0) } ?? Image("default_char"))
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            // 头像右侧：上下两个 32x32 图标
            VStack(spacing: 2) {
                Image(uiImage: IconManager.shared.loadUIImage(for: shipIconName))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Image(uiImage: IconManager.shared.loadUIImage(for: weaponIconName))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            // 中间三行文字
            VStack(alignment: .leading, spacing: 4) {
                if isPrimaryNamePending {
                    EntitySkeletonBar(width: 110, height: 16)
                } else {
                    Text(displayNameText)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                if isCorpNamePending {
                    EntitySkeletonBar(width: 140, height: 12)
                } else {
                    Text(corporationName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if isAllianceNamePending {
                    EntitySkeletonBar(width: 130, height: 12)
                } else {
                    Text(allianceName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 右侧：damage_done 及占比
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatDamage(attacker.damage_done))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .font(.system(.body, design: .monospaced))
                Text(damagePercentage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        .contextMenu {
            if let charId = attacker.character_id, character != nil {
                NavigationLink {
                    CharacterDetailView(characterId: charId, character: character!)
                } label: {
                    Label(NSLocalizedString("View Character", comment: ""), systemImage: "info.circle")
                }
            }
            if let corpId = attacker.corporation_id, character != nil {
                NavigationLink {
                    CorporationDetailView(corporationId: corpId, character: character!)
                } label: {
                    Label(NSLocalizedString("View Corporation", comment: ""), systemImage: "info.circle")
                }
            }
            if let allyId = attacker.alliance_id, allyId > 0, character != nil {
                NavigationLink {
                    AllianceDetailView(allianceId: allyId, character: character!)
                } label: {
                    Label(NSLocalizedString("View Alliance", comment: ""), systemImage: "info.circle")
                }
            }
            if let shipTypeId = attacker.ship_type_id ?? attacker.weapon_type_id {
                NavigationLink {
                    ItemInfoMap.getItemInfoView(itemID: shipTypeId, databaseManager: DatabaseManager.shared)
                } label: {
                    Label(NSLocalizedString("View Ship", comment: ""), systemImage: "info.circle")
                }
            }
        }
        .task {
            if let charId = attacker.character_id {
                do {
                    let img = try await CharacterAPI.shared.fetchCharacterPortrait(characterId: charId, size: 128)
                    await MainActor.run { characterPortrait = img }
                } catch {
                    Logger.error("加载参与者头像失败 - character_id: \(charId), error: \(error)")
                }
            }
        }
        .task(id: "\(attacker.ship_type_id ?? 0)_\(attacker.weapon_type_id ?? 0)") {
            guard isUnknownParticipant else { return }
            guard let typeId = attacker.ship_type_id ?? attacker.weapon_type_id else { return }
            let name = Self.queryTypeName(typeId: typeId)
            await MainActor.run { resolvedShipName = name }
        }
    }

    /// 从内存索引查询 type_id 对应的 name
    private static func queryTypeName(typeId: Int) -> String? {
        ItemInfoMap.typeName(for: typeId)
    }
}
