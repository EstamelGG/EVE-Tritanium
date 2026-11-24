import SwiftUI

/// 共用的图标尺寸常量（模块内共享）
enum CharacterAssetsIconSize {
    static let standard: CGFloat = 32
    static let location: CGFloat = 36
    static let pathSegment: CGFloat = 20
}

/// 共用的图标视图（模块内共享，供主列表与 LocationAssetsView 使用）
struct AssetIconView: View {
    @Environment(\.timeZone) private var displayTimeZone
    private let iconName: String?
    private let uiImage: UIImage?
    let size: CGFloat

    init(iconName: String, size: CGFloat = CharacterAssetsIconSize.standard) {
        self.iconName = iconName
        uiImage = nil
        self.size = size
    }

    init(uiImage: UIImage, size: CGFloat = CharacterAssetsIconSize.standard) {
        iconName = nil
        self.uiImage = uiImage
        self.size = size
    }

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage).resizable()
            } else if let iconName {
                IconManager.shared.loadImage(for: iconName).resizable()
            }
        }
        .frame(width: size, height: size)
        .cornerRadius(max(size / 6, 2))
    }
}

/// 人物归属行：头像 + 名称（与搜索存放位置行一致）
struct AssetOwnerRowLabel: View {
    @Environment(\.timeZone) private var displayTimeZone
    let ownerId: Int
    let ownerName: String?
    let ownerPortrait: UIImage?
    var iconSize: CGFloat = CharacterAssetsIconSize.pathSegment

    var body: some View {
        HStack(spacing: 4) {
            if let ownerPortrait {
                AssetIconView(uiImage: ownerPortrait, size: iconSize)
            } else {
                AssetIconView(iconName: IconManager.defaultItemIcon, size: iconSize)
            }
            Text(ownerName ?? String(ownerId))
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}

/// 位置行内容（主列表与位置详情页共用）
struct AssetLocationRowContent: View {
    @Environment(\.timeZone) private var displayTimeZone
    let location: AssetTreeNode
    let stationNameCache: [Int64: String]?
    let solarSystemNameCache: [Int: String]?
    var showItemCount: Bool = true
    /// 递归物品种类数（去重），由调用方按过滤器预计算
    var typeCount: Int?
    var nameFont: Font = .body
    var showOwner: Bool = false
    var ownerId: Int?
    var ownerName: String?
    var ownerPortrait: UIImage?

    var body: some View {
        HStack {
            if location.type_id > 0 {
                AssetIconView(
                    iconName: location.resolvedIconName(itemInfo: nil),
                    size: CharacterAssetsIconSize.location
                )
            } else if location.name == nil {
                Image("not_found")
                    .resizable()
                    .frame(width: CharacterAssetsIconSize.location, height: CharacterAssetsIconSize.location)
                    .cornerRadius(6)
            }

            VStack(alignment: .leading, spacing: 4) {
                LocationInfoView(
                    stationName: location.getLocationName(stationNameCache: stationNameCache),
                    solarSystemName: solarSystemName(),
                    security: location.security_status,
                    locationId: location.location_id,
                    font: nameFont,
                    textColor: .primary,
                    inSpaceNote: location.location_type == "solar_system"
                        ? NSLocalizedString("Character_in_space", comment: "") : nil
                )

                if showOwner, let ownerId {
                    AssetOwnerRowLabel(
                        ownerId: ownerId,
                        ownerName: ownerName,
                        ownerPortrait: ownerPortrait
                    )
                }

                if showItemCount, let typeCount {
                    Text(
                        String(
                            format: NSLocalizedString(
                                "Assets_Item_Summary_Format", comment: ""
                            ),
                            typeCount
                        )
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
        }
    }

    private func solarSystemName() -> String? {
        guard let systemId = location.system_id else { return nil }
        return solarSystemNameCache?[systemId]
    }
}

/// 位置行视图
private struct LocationRowView: View {
    @Environment(\.timeZone) private var displayTimeZone
    let entry: AssetLocationWithOwner
    @EnvironmentObject private var viewModel: CharacterAssetsViewModel

    var body: some View {
        AssetLocationRowContent(
            location: entry.location,
            stationNameCache: viewModel.stationNameCache,
            solarSystemNameCache: viewModel.solarSystemNameCache,
            typeCount: viewModel.typeFilterContext.matchingTypeCount(in: entry.location),
            showOwner: viewModel.multiCharacterMode,
            ownerId: entry.ownerId,
            ownerName: viewModel.ownerName(for: entry.ownerId),
            ownerPortrait: viewModel.ownerPortrait(for: entry.ownerId)
        )
    }
}

/// 合并模式下的位置行视图（横向铺开多个人物头像）
private struct MergedLocationRowView: View {
    @Environment(\.timeZone) private var displayTimeZone
    let merged: MergedAssetLocation
    @EnvironmentObject private var viewModel: CharacterAssetsViewModel

    var body: some View {
        HStack {
            if merged.representativeLocation.type_id > 0 {
                AssetIconView(
                    iconName: merged.representativeLocation.resolvedIconName(
                        itemInfo: viewModel.itemInfoCache[merged.representativeLocation.type_id]
                    ),
                    size: CharacterAssetsIconSize.location
                )
            } else if merged.representativeLocation.name == nil {
                Image("not_found")
                    .resizable()
                    .frame(width: CharacterAssetsIconSize.location, height: CharacterAssetsIconSize.location)
                    .cornerRadius(6)
            }

            VStack(alignment: .leading, spacing: 4) {
                LocationInfoView(
                    stationName: merged.representativeLocation.getLocationName(
                        stationNameCache: viewModel.stationNameCache
                    ),
                    solarSystemName: solarSystemName(),
                    security: merged.representativeLocation.security_status,
                    locationId: merged.representativeLocation.location_id,
                    font: .body,
                    textColor: .primary,
                    inSpaceNote: merged.representativeLocation.location_type == "solar_system"
                        ? NSLocalizedString("Character_in_space", comment: "") : nil
                )

                // 横向铺开人物头像
                HStack(spacing: 4) {
                    ForEach(merged.ownerIds, id: \.self) { ownerId in
                        if let portrait = viewModel.ownerPortrait(for: ownerId) {
                            AssetIconView(uiImage: portrait, size: CharacterAssetsIconSize.pathSegment)
                        } else {
                            AssetIconView(
                                iconName: IconManager.defaultItemIcon,
                                size: CharacterAssetsIconSize.pathSegment
                            )
                        }
                    }
                }

                Text(
                    String(
                        format: NSLocalizedString("Assets_Item_Summary_Format", comment: ""),
                        merged.totalTypeCount
                    )
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
    }

    private func solarSystemName() -> String? {
        guard let systemId = merged.representativeLocation.system_id else { return nil }
        return viewModel.solarSystemNameCache[systemId]
    }
}

private struct AssetRegionRow: View {
    let group: AssetRegionGroup
    let viewModel: CharacterAssetsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text(group.region.name)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                if let regionId = group.region.id,
                   let distribution = viewModel.regionSecurityDistributions[regionId]
                {
                    SecurityDistributionBar(stat: distribution)
                }
            }

            ViewThatFits(in: .horizontal) {
                portraits.fixedSize(horizontal: true, vertical: false)
                ScrollView(.horizontal) { portraits }
                    .scrollIndicators(.hidden)
            }

            Text(
                String.localizedStringWithFormat(
                    NSLocalizedString("Assets_Filter_Active_Item_Count_Format", comment: ""),
                    group.itemCount
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var portraits: some View {
        HStack(spacing: 4) {
            ForEach(group.ownerIds, id: \.self) { ownerId in
                Group {
                    if let portrait = viewModel.ownerPortrait(for: ownerId) {
                        AssetIconView(uiImage: portrait, size: CharacterAssetsIconSize.pathSegment)
                    } else {
                        AssetIconView(
                            iconName: IconManager.defaultItemIcon,
                            size: CharacterAssetsIconSize.pathSegment
                        )
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(viewModel.ownerName(for: ownerId) ?? String(ownerId))
            }
        }
    }
}

/// 加载进度文案（与 AssetLoadingProgress 对应）
private func localizedProgressText(_ progress: AssetLoadingProgress) -> String {
    switch progress {
    case let .loading(page):
        return String(format: NSLocalizedString("Assets_Loading_Fetching", comment: ""), page)
    case .buildingTree:
        return NSLocalizedString("Assets_Loading_Building_Tree", comment: "")
    case .processingLocations:
        return NSLocalizedString("Assets_Loading_Processing_Locations", comment: "")
    case let .fetchingStructureInfo(current, total):
        return String(
            format: NSLocalizedString("Assets_Loading_Fetching_Location_Info", comment: ""),
            current, total
        )
    case .preparingContainers:
        return NSLocalizedString("Assets_Loading_Preparing_Containers", comment: "")
    case let .loadingNames(current, total):
        return String(
            format: NSLocalizedString("Assets_Loading_Names", comment: ""), current, total
        )
    case .savingCache:
        return NSLocalizedString("Assets_Loading_Saving", comment: "")
    case .completed:
        return NSLocalizedString("Assets_Loading_Complete", comment: "")
    }
}

/// 数据加载时间视图
private struct DataLoadTimeView: View {
    @Environment(\.timeZone) private var displayTimeZone
    let loadTime: Date

    var body: some View {
        Text(FormatUtil.formatLoadTimestamp(loadTime))
            .font(.caption2)
            .foregroundColor(.secondary)
    }
}

struct CharacterAssetsView: View {
    @Environment(\.timeZone) private var displayTimeZone
    @StateObject private var viewModel: CharacterAssetsViewModel
    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var isSearching = false
    @State private var showSettingsSheet = false
    @State private var showFilterSheet = false
    @AppStorage("enableLogging") private var enableLogging: Bool = false

    init(characterId: Int) {
        // 构造表达式内联在 autoclosure 中，避免父视图每次重渲染都新建 ViewModel；
        // 数据加载已在 ViewModel init 中启动
        _viewModel = StateObject(wrappedValue: CharacterAssetsViewModel(characterId: characterId))
    }

    var body: some View {
        List {
            statusSection
            searchEmptySection
            errorSection
            searchResultsSection
            assetListSections
            dataLoadTimeSection
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .searchable(
            text: $searchText,
            // placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(NSLocalizedString("Main_Database_Search", comment: ""))
        )
        .onChange(of: searchText) { _, newValue in
            searchTask?.cancel()
            searchTask = Task {
                if !newValue.isEmpty {
                    isSearching = true
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                await viewModel.searchAssets(query: newValue)
                isSearching = false
            }
        }
        .onChange(of: viewModel.filters) { _, _ in refreshSearchIfNeeded() }
        .refreshable {
            Task {
                await viewModel.loadAssets(forceRefresh: true)
            }
        }
        .navigationTitle(
            searchText.isEmpty
                ? NSLocalizedString("Main_Assets", comment: "")
                : NSLocalizedString("Main_Search_Results", comment: "")
        )
        .navigationDestination(for: AssetRegion.self) { region in
            List {
                AssetLocationRows(viewModel: viewModel, region: region)
            }
            .listStyle(.insetGrouped)
            .navigationTitle(region.name)
        }
        .toolbar {
            if #available(iOS 26.0, *) {
                // iOS 26：搜索框与过滤按钮共处底部同一 Liquid Glass 行（搜索框左、过滤右）
                DefaultToolbarItem(kind: .search, placement: .bottomBar)
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    filterButton
                }
            } else {
                ToolbarItem(placement: .navigationBarTrailing) {
                    filterButton
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showSettingsSheet = true
                } label: {
                    Image(systemName: "gear")
                }
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            AssetsFilterSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showSettingsSheet) {
            AssetsSettingsSheet(viewModel: viewModel)
        }
    }

    /// 过滤按钮（iOS 26 位于底部搜索栏右侧，旧系统位于右上角）
    private var filterButton: some View {
        Button {
            showFilterSheet = true
        } label: {
            Image(
                systemName: viewModel.filters.isActive
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
        }
        .accessibilityLabel(NSLocalizedString("Assets_Filter_Title", comment: ""))
    }

    // MARK: - List Sections（按显示顺序）

    private func refreshSearchIfNeeded() {
        guard !searchText.isEmpty else { return }
        Task { await viewModel.searchAssets(query: searchText) }
    }

    @ViewBuilder
    private var statusSection: some View {
        let showLoading = viewModel.isLoading
            || viewModel.loadingProgress != nil
            || viewModel.characterLoadingProgress != nil
        let filterLabels = [
            viewModel.activeSystemFilterLabel,
            viewModel.activeTypeFilterLabel,
            viewModel.activeFilterItemCountLabel,
        ].compactMap { $0 }

        if showLoading || !filterLabels.isEmpty {
            Section {
                VStack(spacing: 4) {
                    if showLoading {
                        if viewModel.isLoading, viewModel.characterLoadingProgress == nil,
                           viewModel.loadingProgress == nil
                        {
                            ProgressView()
                        }
                        if let progress = viewModel.characterLoadingProgress, progress.total > 1 {
                            ProgressView()
                            Text(
                                String.localizedStringWithFormat(
                                    NSLocalizedString("Industry_Loading_Progress", comment: ""),
                                    progress.current, progress.total
                                )
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        if let progress = viewModel.loadingProgress {
                            Text(localizedProgressText(progress))
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    ForEach(filterLabels, id: \.self) { filterLabel in
                        Text(filterLabel)
                            .font(.caption)
                            .foregroundColor(.orange)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowSeparator(.hidden)
            }
        }
    }

    @ViewBuilder
    private var searchEmptySection: some View {
        if !searchText.isEmpty, !isSearching, viewModel.searchItemGroups.isEmpty, !viewModel.isLoading {
            Section { NoDataSection() }
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let error = viewModel.error,
           !viewModel.isLoading,
           viewModel.assetLocations.isEmpty
        {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)
                        Text(NSLocalizedString("Assets_Loading_Error", comment: ""))
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text(error.localizedDescription)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button {
                            Task { await viewModel.loadAssets(forceRefresh: true) }
                        } label: {
                            Text(NSLocalizedString("ESI_Status_Retry", comment: ""))
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .padding(.top, 8)
                    }
                    .padding()
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private var searchResultsSection: some View {
        if !searchText.isEmpty {
            AssetSearchResultsList(
                groups: viewModel.searchItemGroups,
                isSearching: isSearching,
                context: AssetSearchNavigationContext(
                    itemInfoCache: viewModel.itemInfoCache,
                    stationNameCache: viewModel.stationNameCache,
                    solarSystemNameCache: viewModel.solarSystemNameCache,
                    dynamicResultingTypeIds: viewModel.dynamicResultingTypeIds,
                    databaseManager: DatabaseManager(),
                    multiCharacterMode: viewModel.multiCharacterMode,
                    ownerName: viewModel.ownerName(for:),
                    ownerPortrait: viewModel.ownerPortrait(for:),
                    typeFilterContext: viewModel.typeFilterContext
                )
            )
        }
    }

    @ViewBuilder
    private var assetListSections: some View {
        if searchText.isEmpty, !viewModel.isLoading, !viewModel.assetLocations.isEmpty {
            AssetLocationRows(viewModel: viewModel)
            if viewModel.filters.isActive, viewModel.activeFilterItemCount == 0 {
                NoDataSection()
            }
            if viewModel.groupByRegion {
                if !viewModel.unpinnedLocationsByRegion.isEmpty {
                    Section {
                        ForEach(viewModel.unpinnedLocationsByRegion) { group in
                            NavigationLink(value: group.region) {
                                AssetRegionRow(group: group, viewModel: viewModel)
                            }
                        }
                    }
                }
            } else {
                ForEach(viewModel.unpinnedLocationsByRegion) { group in
                    Section(header: Text(group.region.name)) {
                        AssetLocationRows(viewModel: viewModel, region: group.region)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var dataLoadTimeSection: some View {
        if searchText.isEmpty, enableLogging, let loadTime = viewModel.dataLoadTime, !viewModel.isLoading {
            Section {
                HStack {
                    Spacer()
                    DataLoadTimeView(loadTime: loadTime)
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
            }
        }
    }
}

private struct AssetLocationRows: View {
    @ObservedObject var viewModel: CharacterAssetsViewModel
    var region: AssetRegion? = nil

    var body: some View {
        if let region {
            if let group = viewModel.unpinnedLocationsByRegion.first(where: { $0.id == region.id }) {
                if viewModel.mergesAssetLocations {
                    ForEach(viewModel.mergedLocations(in: group)) { merged in
                        mergedLocationRowLink(merged: merged, role: nil)
                    }
                } else {
                    ForEach(group.locations) { entry in
                        locationRowLink(entry: entry, pinLabel: "Assets_Pin", pinIcon: "pin", role: nil)
                    }
                }
            } else {
                NoDataSection()
            }
        } else if viewModel.mergesAssetLocations {
            mergedPinnedLocationsSection
        } else {
            pinnedLocationsSection
        }
    }

    @ViewBuilder
    private var pinnedLocationsSection: some View {
        let locations = viewModel.pinnedLocations
        if !locations.isEmpty {
            Section(
                header: HStack {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.system(size: 16))
                    Text(NSLocalizedString("Assets_Pinned_Locations", comment: ""))
                }
            ) {
                ForEach(locations) { entry in
                    locationRowLink(
                        entry: entry,
                        pinLabel: "Assets_Unpin",
                        pinIcon: "pin.slash",
                        role: .destructive
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var mergedPinnedLocationsSection: some View {
        let locations = viewModel.mergedPinnedLocations
        if !locations.isEmpty {
            Section(
                header: HStack {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.system(size: 16))
                    Text(NSLocalizedString("Assets_Pinned_Locations", comment: ""))
                }
            ) {
                ForEach(locations) { merged in
                    mergedLocationRowLink(merged: merged, role: .destructive)
                }
            }
        }
    }

    // MARK: - 导航与行构建

    private func locationDestination(_ entry: AssetLocationWithOwner) -> LocationAssetsView {
        LocationAssetsView(
            location: entry.location,
            preloadedItemInfo: viewModel.itemInfoCache,
            stationNameCache: viewModel.stationNameCache,
            solarSystemNameCache: viewModel.solarSystemNameCache,
            dynamicResultingTypeIds: viewModel.dynamicResultingTypeIds,
            showOwner: viewModel.multiCharacterMode,
            ownerId: entry.ownerId,
            ownerName: viewModel.ownerName(for: entry.ownerId),
            ownerPortrait: viewModel.ownerPortrait(for: entry.ownerId),
            typeFilterContext: viewModel.typeFilterContext
        )
    }

    private func mergedLocationDestination(
        _ merged: MergedAssetLocation
    ) -> MergedLocationAssetsView {
        MergedLocationAssetsView(
            merged: merged,
            itemInfoCache: viewModel.itemInfoCache,
            stationNameCache: viewModel.stationNameCache,
            solarSystemNameCache: viewModel.solarSystemNameCache,
            dynamicResultingTypeIds: viewModel.dynamicResultingTypeIds,
            ownerName: viewModel.ownerName(for:),
            ownerPortrait: viewModel.ownerPortrait(for:),
            typeFilterContext: viewModel.typeFilterContext
        )
    }

    @ViewBuilder
    private func mergedLocationRowLink(
        merged: MergedAssetLocation, role: ButtonRole?
    ) -> some View {
        // 旁路：地点只有1个人物时直接跳转到该人物的仓库页，跳过人物列表
        let link = NavigationLink {
            if merged.entries.count == 1, let entry = merged.entries.first {
                locationDestination(entry)
            } else {
                mergedLocationDestination(merged)
            }
        } label: {
            MergedLocationRowView(merged: merged)
                .environmentObject(viewModel)
        }
        if role == .destructive {
            link
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        // 取消置顶该地点所有人物（不受过滤器影响）
                        for entry in viewModel.entriesForLocation(merged.locationId) {
                            if viewModel.isLocationPinned(entry) {
                                viewModel.togglePinLocation(entry)
                            }
                        }
                    } label: {
                        Label(
                            NSLocalizedString("Assets_Unpin", comment: ""),
                            systemImage: "pin.slash"
                        )
                    }
                    .tint(.red)
                }
        } else {
            link
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        // 置顶该地点所有人物（不受过滤器影响）
                        for entry in viewModel.entriesForLocation(merged.locationId) {
                            if !viewModel.isLocationPinned(entry) {
                                viewModel.togglePinLocation(entry)
                            }
                        }
                    } label: {
                        Label(
                            NSLocalizedString("Assets_Pin", comment: ""),
                            systemImage: "pin"
                        )
                    }
                    .tint(.blue)
                }
        }
    }

    private func locationRowLink(
        entry: AssetLocationWithOwner,
        pinLabel: String,
        pinIcon: String,
        role: ButtonRole?
    ) -> some View {
        let link = NavigationLink(destination: locationDestination(entry)) {
            LocationRowView(entry: entry)
                .environmentObject(viewModel)
        }
        return Group {
            if role == .destructive {
                link
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            viewModel.togglePinLocation(entry)
                        } label: {
                            Label(NSLocalizedString(pinLabel, comment: ""), systemImage: pinIcon)
                        }
                        .tint(.red)
                    }
            } else {
                link
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            viewModel.togglePinLocation(entry)
                        } label: {
                            Label(NSLocalizedString(pinLabel, comment: ""), systemImage: pinIcon)
                        }
                        .tint(.blue)
                    }
            }
        }
    }
}

// MARK: - 设置

struct AssetsSettingsSheet: View {
    @Environment(\.timeZone) private var displayTimeZone
    @ObservedObject var viewModel: CharacterAssetsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $viewModel.groupByRegion) {
                        VStack(alignment: .leading) {
                            Text(NSLocalizedString("Assets_Group_By_Region", comment: ""))
                            Text(NSLocalizedString("Assets_Group_By_Region_Description", comment: ""))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Toggle(isOn: $viewModel.multiCharacterMode) {
                        VStack(alignment: .leading) {
                            Text(NSLocalizedString("Settings_Multi_Character", comment: ""))
                            Text(NSLocalizedString("Settings_Multi_Character_Description", comment: ""))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if viewModel.multiCharacterMode {
                        Toggle(isOn: $viewModel.mergeLocations) {
                            VStack(alignment: .leading) {
                                Text(NSLocalizedString("Settings_Merge_Locations", comment: ""))
                                Text(NSLocalizedString("Settings_Merge_Locations_Description", comment: ""))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                if viewModel.multiCharacterMode {
                    MultiCharacterSelectionSection(
                        availableCharacters: viewModel.availableCharacters,
                        selectedCharacterIds: $viewModel.selectedCharacterIds
                    )
                }
            }
            .navigationTitle(NSLocalizedString("Assets_Settings_Title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Common_Done", comment: "")) { dismiss() }
                }
            }
        }
    }
}
