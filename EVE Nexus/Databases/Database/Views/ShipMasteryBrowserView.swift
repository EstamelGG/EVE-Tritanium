import SwiftUI

/// 专精浏览首页：categoryID=6（飞船）下所有含专精数据的组
/// 行设计简化为：组图标 + 名称 + 组内飞船数
struct ShipMasteryBrowserView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @StateObject private var skillsManager = SharedSkillsManager.shared

    @State private var groups: [(
        id: Int, name: String, iconFileName: String, typeIDs: [Int]
    )] = []
    /// 专精等级筛选：nil = 不过滤，-1 = 不达标（开不了），-2 = 达标（非不达标），0-5 = 专精等级
    @State private var selectedFilter: Int?
    /// 按当前筛选条件的各组命中数缓存（state 底层含 SQL，避免每次渲染全量重算约 3500 艘船）
    @State private var matchedCounts: [Int: Int] = [:]

    /// 重算各组命中数（groups 加载后、筛选或技能数据变化时调用一次）
    private func recomputeMatchedCounts() {
        guard !groups.isEmpty else { return }
        var counts: [Int: Int] = [:]
        for group in groups {
            guard let filter = selectedFilter else {
                counts[group.id] = group.typeIDs.count
                continue
            }
            counts[group.id] = group.typeIDs.filter { typeID in
                MasteryDisplayHelper.matchesFilter(
                    filter,
                    state: MasteryDisplayHelper.state(
                        typeID: typeID,
                        databaseManager: databaseManager,
                        skillsManager: skillsManager
                    )
                )
            }.count
        }
        matchedCounts = counts
    }

    /// 筛选菜单项：Toggle 形式，系统在选中行显示对勾，未选中行保留对勾位，文本自然对齐
    private func filterMenuButton(_ filter: Int?) -> some View {
        Toggle(
            MasteryDisplayHelper.filterTitle(filter),
            isOn: Binding(
                get: { selectedFilter == filter },
                set: { if $0 { selectedFilter = filter } }
            )
        )
    }

    var body: some View {
        List {
            ForEach(groups, id: \.id) { group in
                let matchedCount = matchedCounts[group.id] ?? 0
                if matchedCount > 0 {
                    NavigationLink {
                        ShipMasteryGroupView(
                            groupID: group.id,
                            groupName: group.name,
                            databaseManager: databaseManager,
                            selectedFilter: selectedFilter
                        )
                    } label: {
                        HStack {
                            Image(uiImage: IconManager.shared.loadUIImage(for: group.iconFileName))
                                .resizable()
                                .frame(width: 32, height: 32)
                                .cornerRadius(6)
                            Text(group.name)
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(matchedCount)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Mastery_Detail_Title", comment: "专精"))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    ForEach([nil, -1, -2] as [Int?], id: \.self) { filter in
                        filterMenuButton(filter)
                    }

                    Divider()

                    ForEach([0, 1, 2, 3, 4, 5], id: \.self) { filter in
                        filterMenuButton(filter)
                    }
                } label: {
                    Image(systemName: selectedFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
        .onAppear {
            skillsManager.preloadSkills()
            if groups.isEmpty {
                groups = Self.loadShipGroups()
            }
            recomputeMatchedCounts()
        }
        .onChange(of: selectedFilter) { _, _ in
            recomputeMatchedCounts()
        }
        .onChange(of: skillsManager.characterSkills) { _, _ in
            recomputeMatchedCounts()
        }
        .onChange(of: skillsManager.masteryCertLevels) { _, _ in
            recomputeMatchedCounts()
        }
        .onChange(of: skillsManager.isLoading) { _, _ in
            recomputeMatchedCounts()
        }
    }

    /// 静态计算：有专精数据的飞船按组聚合（全内存，约 3500 次遍历）
    static func loadShipGroups() -> [(
        id: Int, name: String, iconFileName: String, typeIDs: [Int]
    )] {
        var shipsByGroup: [Int: [Int]] = [:]
        for typeID in SDEMemoryStore.shipMasteryCerts.keys {
            guard let typeInfo = SDEMemoryStore.type(for: typeID),
                  let groupID = typeInfo.groupID
            else { continue }
            shipsByGroup[groupID, default: []].append(typeID)
        }

        return SDEMemoryStore.groups(inCategory: 6)
            .filter { $0.published }
            .compactMap { group in
                let typeIDs = shipsByGroup[group.id] ?? []
                guard !typeIDs.isEmpty else { return nil }
                return (
                    id: group.id,
                    name: group.name,
                    iconFileName: group.iconFilename.isEmpty
                        ? IconManager.defaultItemIcon : group.iconFilename,
                    typeIDs: typeIDs
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// 某飞船组下的专精列表
/// 行设计简化为：物品图标 + 名称，右侧显示当前角色已满足的专精等级图标，行带渐变背景
/// 已发布飞船按衍生等级（metaGroup）分区，未发布飞船独立分区（参考数据功能）
struct ShipMasteryGroupView: View {
    let groupID: Int
    let groupName: String
    @ObservedObject var databaseManager: DatabaseManager
    @StateObject private var skillsManager = SharedSkillsManager.shared
    /// 由上级组列表页传入的筛选条件：nil = 不过滤，-1 = 不达标，-2 = 达标，0-5 = 专精等级
    let selectedFilter: Int?
    @Environment(\.colorScheme) private var colorScheme

    struct ShipItem {
        let typeID: Int
        let name: String
        let iconFileName: String
        let metaGroupID: Int
        let published: Bool
    }

    @State private var ships: [ShipItem] = []

    /// 某船是否命中当前筛选（state 为该船的专精显示状态）
    private func matchesFilter(_ filter: Int?, state: MasteryLevelState?) -> Bool {
        guard let filter else { return true }
        return MasteryDisplayHelper.matchesFilter(filter, state: state)
    }

    var body: some View {
        // state 底层含 SQL 查询，单次渲染对每艘船只求值一次，过滤与行展示共用
        let stateMap: [Int: MasteryLevelState] = ships.reduce(into: [:]) { map, ship in
            if let state = MasteryDisplayHelper.state(
                typeID: ship.typeID,
                databaseManager: databaseManager,
                skillsManager: skillsManager
            ) {
                map[ship.typeID] = state
            }
        }
        let published = ships.filter(\.published).filter {
            matchesFilter(selectedFilter, state: stateMap[$0.typeID])
        }
        let unpublished = ships.filter { !$0.published }.filter {
            matchesFilter(selectedFilter, state: stateMap[$0.typeID])
        }

        return List {
            ForEach(SDEMemoryStore.metaGroupSections(published) { $0.metaGroupID }, id: \.id) { group in
                Section(
                    header: Text(group.name)
                ) {
                    ForEach(group.items, id: \.typeID) { ship in
                        shipRow(ship, state: stateMap[ship.typeID])
                    }
                }
            }

            if !unpublished.isEmpty {
                Section(
                    header: Text(NSLocalizedString("Main_Database_unpublished", comment: "未发布"))
                ) {
                    ForEach(unpublished, id: \.typeID) { ship in
                        shipRow(ship, state: stateMap[ship.typeID])
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(groupName)
        .overlay {
            if let filter = selectedFilter, published.isEmpty, unpublished.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text(
                        String.localizedStringWithFormat(
                            NSLocalizedString("Mastery_Filter_Empty", comment: "没有符合筛选的飞船"),
                            MasteryDisplayHelper.filterTitle(filter)
                        )
                    )
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
            }
        }
        .onAppear {
            skillsManager.preloadSkills()
            if ships.isEmpty {
                ships = Self.loadShips(inGroup: groupID)
            }
        }
    }

    private func shipRow(_ ship: ShipItem, state: MasteryLevelState?) -> some View {
        NavigationLink {
            ItemInfoMap.getItemInfoView(
                itemID: ship.typeID,
                databaseManager: databaseManager
            )
        } label: {
            HStack(spacing: 12) {
                Image(uiImage: IconManager.shared.loadUIImage(for: ship.iconFileName))
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
                Text(ship.name)
                Spacer()
                if let state {
                    Image(MasteryDisplayHelper.iconName(for: state))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 42, height: 42)
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        .listRowBackground(rowBackground(for: state))
    }

    /// 行渐变背景：左侧保持默认行底色，右侧渐入专精色
    /// 专精行色较 backdropColor 更亮，浅色用高透明度、深色用低透明度（调色台实测值）
    @ViewBuilder
    private func rowBackground(for state: MasteryLevelState?) -> some View {
        if let state {
            let base = Color(UIColor.secondarySystemGroupedBackground)
            let tintOpacity = colorScheme == .dark ? 0.4 : 0.7
            LinearGradient(
                stops: [
                    .init(color: base, location: 0),
                    .init(color: base, location: 0.55),
                    .init(color: Self.rowTintColor(for: state).opacity(tintOpacity), location: 1.0),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    /// 列表行专精色：locked = 红，0-4 级 = 蓝，5 级 = 金
    private static func rowTintColor(for state: MasteryLevelState) -> Color {
        switch state {
        case .locked:
            return Color(red: 0xB0 / 255.0, green: 0x43 / 255.0, blue: 0x3C / 255.0)
        case let .level(level) where level >= 5:
            return Color(red: 0xB4 / 255.0, green: 0x8F / 255.0, blue: 0x3F / 255.0)
        case .level:
            return Color(red: 0x41 / 255.0, green: 0x63 / 255.0, blue: 0xAC / 255.0)
        }
    }

    /// 静态计算：该组下所有有专精数据的飞船（按名称排序）
    static func loadShips(inGroup groupID: Int) -> [ShipItem] {
        SDEMemoryStore.shipMasteryCerts.keys.compactMap { typeID in
            guard let typeInfo = SDEMemoryStore.type(for: typeID),
                  typeInfo.groupID == groupID
            else { return nil }
            return ShipItem(
                typeID: typeID,
                name: typeInfo.name,
                iconFileName: typeInfo.iconFilename.isEmpty
                    ? IconManager.defaultItemIcon : typeInfo.iconFilename,
                metaGroupID: typeInfo.metaGroupID ?? 0,
                published: typeInfo.published
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
