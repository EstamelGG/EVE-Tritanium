import SwiftUI

/// 星域数据模型
struct Region: Identifiable {
    let id: Int

    var name: String {
        SDEMemoryStore.regionName(for: id) ?? "Region \(id)"
    }
}

/// 常用地点：支持星域、星系、建筑三种类型
struct PinnedLocation: Identifiable {
    enum Kind {
        case region(Int)
        case system(Int, Int) // systemID, regionID
        case structure(Int64)
    }

    let kind: Kind

    var id: String {
        switch kind {
        case let .region(id): return "region_\(id)"
        case let .system(id, _): return "system_\(id)"
        case let .structure(id): return "structure_\(id)"
        }
    }

    /// 持久化字符串
    var persistedString: String {
        switch kind {
        case let .region(id): return "region_id:\(id)"
        case let .system(id, _): return "system_id:\(id)"
        case let .structure(id): return "structure_id:\(id)"
        }
    }

    /// 选中时使用的 locationID（星域ID / 星系ID / 建筑虚拟ID）
    /// 类型由 MarketLocationType.from(id:) 在运行时判断
    var locationID: Int {
        switch kind {
        case let .region(id): return id
        case let .system(id, _): return id
        case let .structure(id): return MarketLocation.structure(id).virtualRegionID
        }
    }

    /// 显示名称
    var displayName: String {
        switch kind {
        case let .region(id): return SDEMemoryStore.regionName(for: id) ?? "Region \(id)"
        case let .system(id, _): return SDEMemoryStore.solarSystemName(for: id) ?? "System \(id)"
        case let .structure(id):
            return MarketStructureManager.shared.structures
                .first { $0.structureId == Int(id) }?.structureName ?? "Structure"
        }
    }

    /// 副标题
    var subtitle: String? {
        switch kind {
        case .region: return nil
        case let .system(_, regionID):
            return SDEMemoryStore.regionName(for: regionID)
        case let .structure(id):
            if let s = MarketStructureManager.shared.structures
                .first(where: { $0.structureId == Int(id) })
            {
                return "\(formatSystemSecurity(s.security)) \(s.systemName)"
            }
            return nil
        }
    }

    /// 是否为建筑
    var isStructure: Bool {
        if case .structure = kind {
            return true
        }
        return false
    }

    /// 建筑图标文件名
    var iconFileName: String? {
        if case let .structure(id) = kind {
            return MarketStructureManager.shared.structures
                .first { $0.structureId == Int(id) }?.iconFileName
        }
        return nil
    }
}

/// 星域选择器视图
struct MarketRegionPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedLocation: Int
    @Binding var saveSelection: Bool
    let databaseManager: DatabaseManager

    @State private var isEditMode = false
    @State private var allRegions: [Region] = []
    @State private var pinnedLocations: [PinnedLocation] = []
    @State private var searchText = ""
    @State private var isSearchActive = false
    @State private var sectionedRegions: [String: [Region]] = [:]
    @State private var sectionTitles: [String] = []
    @State private var commonSystems: [CommonSystem] = []
    @StateObject private var structureManager = MarketStructureManager.shared

    /// 统一行间距
    private let rowInsets = EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)

    /// 5 大贸易星系 ID（按固定顺序，显示名称由 SDEMemoryStore 提供）
    static let majorSystemIDs: [Int] = [
        30_000_142, // Jita
        30_002_187, // Amarr
        30_002_510, // Rens
        30_002_053, // Hek
        30_100_000, // Zarzakh
    ]

    /// 5 大星系的星系 ID（实例访问，等同于 Self.majorSystemIDs）
    private var commonSystemIDs: [Int] {
        Self.majorSystemIDs
    }

    /// 常见星系数据模型
    struct CommonSystem: Identifiable {
        let id: String
        let regionID: Int?

        var systemName: String? {
            guard let systemId = Int(id) else { return nil }
            return SDEMemoryStore.solarSystemName(for: systemId)
        }
    }

    /// 已置顶的星域 ID 集合（用于从「所有星域」中过滤）
    private var pinnedRegionIDSet: Set<Int> {
        Set(pinnedLocations.compactMap { loc in
            if case let .region(id) = loc.kind {
                return id
            }
            return nil
        })
    }

    private var unpinnedRegions: [Region] {
        allRegions.filter { region in
            !pinnedRegionIDSet.contains(region.id)
        }
    }

    /// 加载星域数据
    private func loadRegions() {
        allRegions = SDEMemoryStore.regionNames.compactMap { id, text in
            guard id < 11_000_000 else { return nil }
            let name = text.resolved()
            guard !name.isEmpty else { return nil }
            return Region(id: id)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        // 加载常见星系数据（需要 regionID 映射）
        loadCommonSystems()

        // 从 UserDefaults 加载置顶的地点
        loadPinnedLocations()

        // 更新分组数据
        updateSections()
    }

    /// 加载常见星系数据（内存索引）
    private func loadCommonSystems() {
        guard !commonSystemIDs.isEmpty else {
            commonSystems = []
            return
        }

        commonSystems = commonSystemIDs.map { id in
            CommonSystem(id: "\(id)", regionID: SDEMemoryStore.universeSystems[id]?.regionID)
        }
    }

    /// 加载置顶地点
    private func loadPinnedLocations() {
        let persisted = UserDefaultsManager.shared.pinnedLocationIDs
        pinnedLocations = persisted.compactMap { parsePinnedLocation($0) }
    }

    /// 解析持久化字符串为 PinnedLocation
    private func parsePinnedLocation(_ str: String) -> PinnedLocation? {
        let parts = str.split(separator: ":")
        guard parts.count == 2 else { return nil }
        let type = String(parts[0])
        let idStr = String(parts[1])

        if type == "region_id", let id = Int(idStr) {
            return PinnedLocation(kind: .region(id))
        } else if type == "system_id", let id = Int(idStr) {
            // 查找星系对应的星域 ID
            if let regionID = commonSystems.first(where: { Int($0.id) == id })?.regionID {
                return PinnedLocation(kind: .system(id, regionID))
            }
            return nil
        } else if type == "structure_id", let id = Int64(idStr) {
            return PinnedLocation(kind: .structure(id))
        }
        return nil
    }

    /// 保存置顶地点
    private func savePinnedLocations() {
        let persisted = pinnedLocations.map { $0.persistedString }
        UserDefaultsManager.shared.pinnedLocationIDs = persisted
    }

    /// 更新分组数据
    private func updateSections() {
        var filteredData = unpinnedRegions

        if !searchText.isEmpty {
            filteredData = unpinnedRegions.filter { region in
                if SDEMemoryStore.regionNames[region.id]?.matchesSearch(searchText) == true {
                    return true
                }
                return commonSystems.contains { system in
                    system.regionID == region.id
                        && Int(system.id).map {
                            SDEMemoryStore.solarSystemNames[$0]?.matchesSearch(searchText) == true
                        } == true
                }
            }
        }

        let grouped = Dictionary(grouping: filteredData) { region -> String in
            region.name.first.map { getFirstLetter(of: String($0)) } ?? "#"
        }

        // 分组内排序
        sectionedRegions = grouped.mapValues { regions in
            regions.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        sectionTitles = grouped.keys.sorted()
    }

    /// 获取字符的首字母（包括中文拼音）
    private func getFirstLetter(of char: String) -> String {
        let uppercaseChar = char.uppercased()

        if uppercaseChar >= "A", uppercaseChar <= "Z" {
            return uppercaseChar
        }

        let pinyin = NSMutableString(string: char) as CFMutableString
        CFStringTransform(pinyin, nil, kCFStringTransformToLatin, false)
        CFStringTransform(pinyin, nil, kCFStringTransformStripDiacritics, false)

        if let firstPinyinChar = String(pinyin as String).first {
            let letter = String(firstPinyinChar).uppercased()
            if letter >= "A", letter <= "Z" {
                return letter
            }
        }

        return "#"
    }

    /// 检查星系是否已置顶
    private func isSystemPinned(_ systemID: Int) -> Bool {
        pinnedLocations.contains { $0.id == "system_\(systemID)" }
    }

    /// 检查建筑是否已置顶
    private func isStructurePinned(_ structureID: Int) -> Bool {
        pinnedLocations.contains { $0.id == "structure_\(Int64(structureID))" }
    }

    /// 检查星域是否已置顶
    private func isRegionPinned(_ regionID: Int) -> Bool {
        pinnedLocations.contains { $0.id == "region_\(regionID)" }
    }

    /// 选中地点
    /// - Parameter id: 选中的地点 ID（星域 ID / 星系 ID / 建筑虚拟 ID）
    /// 类型由 MarketLocationType.from(id:) 在运行时判断
    private func selectLocation(id: Int) {
        if saveSelection {
            UserDefaultsManager.shared.selectedLocation = id
        }
        selectedLocation = id
        if !isEditMode {
            dismiss()
        }
    }

    // MARK: - 行视图

    /// 置顶地点行
    private func pinnedLocationRow(_ loc: PinnedLocation) -> some View {
        PinnedLocationRow(
            location: loc,
            isSelected: selectedLocation == loc.locationID,
            isEditMode: isEditMode,
            onSelect: {
                selectLocation(id: loc.locationID)
            },
            onUnpin: {
                withAnimation {
                    pinnedLocations.removeAll { $0.id == loc.id }
                    savePinnedLocations()
                    updateSections()
                }
            }
        )
    }

    /// 建筑市场行
    private func marketStructureRow(_ structure: MarketStructure) -> some View {
        let virtualID = MarketLocation.structure(Int64(structure.structureId)).virtualRegionID
        let pinned = isStructurePinned(structure.structureId)
        return MarketStructureRow(
            structure: structure,
            isSelected: selectedLocation == virtualID,
            isEditMode: isEditMode,
            isPinned: pinned,
            onSelect: {
                selectLocation(id: virtualID)
            },
            onPin: isEditMode && !pinned
                ? {
                    withAnimation {
                        pinnedLocations.append(
                            PinnedLocation(kind: .structure(Int64(structure.structureId)))
                        )
                        savePinnedLocations()
                    }
                } : nil,
            onUnpin: isEditMode && pinned
                ? {
                    withAnimation {
                        pinnedLocations.removeAll {
                            $0.id == "structure_\(Int64(structure.structureId))"
                        }
                        savePinnedLocations()
                    }
                } : nil
        )
    }

    /// 5 大星系行
    @ViewBuilder
    private func majorSystemRow(_ system: CommonSystem) -> some View {
        if let systemID = Int(system.id), let regionID = system.regionID,
           let name = system.systemName
        {
            let pinned = isSystemPinned(systemID)
            MajorSystemRow(
                systemName: name,
                regionName: SDEMemoryStore.regionName(for: regionID) ?? "",
                isSelected: selectedLocation == systemID,
                isEditMode: isEditMode,
                isPinned: pinned,
                onSelect: {
                    selectLocation(id: systemID)
                },
                onPin: isEditMode && !pinned
                    ? {
                        withAnimation {
                            pinnedLocations.append(
                                PinnedLocation(kind: .system(systemID, regionID))
                            )
                            savePinnedLocations()
                        }
                    } : nil,
                onUnpin: isEditMode && pinned
                    ? {
                        withAnimation {
                            pinnedLocations.removeAll { $0.id == "system_\(systemID)" }
                            savePinnedLocations()
                        }
                    } : nil
            )
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // Section 1: 常用地点
                Section(header: Text(NSLocalizedString("Main_Market_Pinned_Locations", comment: ""))) {
                    if !pinnedLocations.isEmpty {
                        ForEach(pinnedLocations) { loc in
                            pinnedLocationRow(loc)
                                .listRowInsets(rowInsets)
                        }
                        .onMove { from, to in
                            pinnedLocations.move(fromOffsets: from, toOffset: to)
                            savePinnedLocations()
                        }
                    }

                    if !isEditMode {
                        Button(action: {
                            withAnimation {
                                isEditMode = true
                            }
                        }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.blue)
                                Text(NSLocalizedString("Main_Market_Add_Location", comment: ""))
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }

                // Section 2: 建筑市场（编辑模式时隐藏，因为建筑行已有 pin 按钮）
                if !isEditMode {
                    Section(
                        header: Text(
                            NSLocalizedString("Main_Setting_Market_Structure_Select", comment: "")
                        )
                    ) {
                        if !structureManager.structures.isEmpty {
                            ForEach(structureManager.structures) { structure in
                                marketStructureRow(structure)
                                    .listRowInsets(rowInsets)
                            }
                        } else {
                            NavigationLink(destination: MarketStructureSettingsView()) {
                                HStack {
                                    Image(systemName: "gear")
                                        .foregroundColor(.blue)
                                        .font(.title2)

                                    Text(
                                        NSLocalizedString(
                                            "Main_Market_Setup_Structure", comment: "设置建筑市场"
                                        )
                                    )
                                    .foregroundColor(.primary)

                                    Spacer()
                                }
                            }
                        }
                    }
                }

                // Section 3: 5大星系
                Section(header: Text(NSLocalizedString("Main_Market_Major_Systems", comment: ""))) {
                    ForEach(commonSystems) { system in
                        majorSystemRow(system)
                            .listRowInsets(rowInsets)
                    }
                }

                // Section 4: 所有星域（按本地化首字母分组）
                ForEach(sectionTitles, id: \.self) { sectionTitle in
                    if let regionsInSection = sectionedRegions[sectionTitle],
                       !regionsInSection.isEmpty
                    {
                        Section(header: Text(sectionTitle)) {
                            ForEach(regionsInSection) { region in
                                RegionRow(
                                    region: region,
                                    isSelected: selectedLocation == region.id,
                                    isEditMode: isEditMode,
                                    onSelect: {
                                        selectLocation(id: region.id)
                                    },
                                    onPin: isEditMode && !isRegionPinned(region.id)
                                        ? {
                                            withAnimation {
                                                pinnedLocations.append(
                                                    PinnedLocation(kind: .region(region.id))
                                                )
                                                savePinnedLocations()
                                                updateSections()
                                            }
                                        } : nil,
                                    onUnpin: nil
                                )
                                .listRowInsets(rowInsets)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(
                text: $searchText,
                isPresented: $isSearchActive,
                prompt: NSLocalizedString("Region_Search_Placeholder", comment: "搜索星域...")
            )
            .onChange(of: searchText) { _, _ in
                updateSections()
            }
            .onChange(of: isSearchActive) { _, _ in
                updateSections()
            }
            .navigationTitle(NSLocalizedString("Main_Market_Select_Region", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isEditMode {
                        Button(NSLocalizedString("Main_Market_Done", comment: "")) {
                            withAnimation {
                                isEditMode = false
                            }
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(isEditMode ? .active : .inactive))
        }
        .onAppear {
            loadRegions()
            structureManager.loadStructures()
        }
    }
}

// MARK: - 行视图

/// 置顶地点行
struct PinnedLocationRow: View {
    let location: PinnedLocation
    let isSelected: Bool
    let isEditMode: Bool
    let onSelect: () -> Void
    let onUnpin: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // 建筑图标（仅建筑显示图标）
            if location.isStructure, let iconFileName = location.iconFileName {
                IconManager.shared.loadImage(for: iconFileName)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
            }

            // 名称与副标题
            VStack(alignment: .leading, spacing: 2) {
                Text(location.displayName)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                if let subtitle = location.subtitle {
                    Text(subtitle)
                        .foregroundColor(.secondary)
                        .font(.caption)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isEditMode {
                Button(role: .destructive, action: onUnpin) {
                    Image(systemName: "minus.circle.fill")
                }
                .buttonStyle(.borderless)
            } else if isSelected {
                Image(systemName: "checkmark")
                    .foregroundColor(.accentColor)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditMode {
                onSelect()
            }
        }
    }
}

/// 建筑市场行（支持 pin/unpin）
struct MarketStructureRow: View {
    let structure: MarketStructure
    let isSelected: Bool
    let isEditMode: Bool
    let isPinned: Bool
    let onSelect: () -> Void
    var onPin: (() -> Void)?
    var onUnpin: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            IconManager.shared.loadImage(for: structure.iconFileName)
                .resizable()
                .frame(width: 32, height: 32)
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 2) {
                Text(structure.structureName)
                    .font(.body)
                    .foregroundColor(isSelected ? .accentColor : .primary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(formatSystemSecurity(structure.security))
                        .foregroundColor(getSecurityColor(structure.security))
                        .font(.caption)

                    Text(structure.systemName)
                        .foregroundColor(.secondary)
                        .font(.caption)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isEditMode {
                if isPinned, let onUnpin {
                    Button(role: .destructive, action: onUnpin) {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                } else if !isPinned, let onPin {
                    Button(action: onPin) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.borderless)
                }
            } else if isSelected {
                Image(systemName: "checkmark")
                    .foregroundColor(.accentColor)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditMode {
                onSelect()
            }
        }
    }
}

/// 5大星系行
struct MajorSystemRow: View {
    let systemName: String
    let regionName: String
    let isSelected: Bool
    let isEditMode: Bool
    let isPinned: Bool
    let onSelect: () -> Void
    var onPin: (() -> Void)?
    var onUnpin: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(systemName)
                    .foregroundColor(isSelected ? .accentColor : .primary)
                Text(regionName)
                    .foregroundColor(.secondary)
                    .font(.caption)
            }

            Spacer()

            if isEditMode {
                if isPinned, let onUnpin {
                    Button(role: .destructive, action: onUnpin) {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                } else if !isPinned, let onPin {
                    Button(action: onPin) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.borderless)
                }
            } else if isSelected {
                Image(systemName: "checkmark")
                    .foregroundColor(.accentColor)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditMode {
                onSelect()
            }
        }
    }
}

/// 星域行视图
struct RegionRow: View {
    let region: Region
    let isSelected: Bool
    let isEditMode: Bool
    let onSelect: () -> Void
    var onPin: (() -> Void)?
    var onUnpin: (() -> Void)?

    var body: some View {
        HStack {
            Text(region.name)
                .foregroundColor(isSelected ? .accentColor : .primary)

            Spacer()

            if isEditMode {
                if onUnpin != nil {
                    Button(role: .destructive, action: { onUnpin?() }) {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                } else if onPin != nil {
                    Button(action: { onPin?() }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.borderless)
                }
            } else if isSelected {
                Image(systemName: "checkmark")
                    .foregroundColor(.accentColor)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditMode {
                onSelect()
            }
        }
    }
}
