import Foundation
import SwiftUI

struct CorpStarbaseView: View {
    let characterId: Int
    @StateObject private var viewModel: CorpStarbaseViewModel
    @State private var showFilterSheet = false

    init(characterId: Int) {
        self.characterId = characterId
        _viewModel = StateObject(wrappedValue: CorpStarbaseViewModel(characterId: characterId))
    }

    var body: some View {
        List {
            // 加载进度部分（参考 CharacterAssetsViewMain.swift 的设计）
            if viewModel.isLoading || viewModel.loadingDetailProgress != nil {
                Section {
                    HStack {
                        Spacer()
                        if viewModel.isLoading && viewModel.loadingDetailProgress == nil {
                            ProgressView()
                                .progressViewStyle(.circular)
                        } else if let progress = viewModel.loadingDetailProgress {
                            Text(progress)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color(.secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }

            if let error = viewModel.error,
               !viewModel.isLoading && viewModel.starbases.isEmpty
            {
                // 显示错误信息
                ErrorStateSection(message: error.localizedDescription) {
                    Task {
                        do {
                            try await viewModel.loadStarbases(forceRefresh: true)
                        } catch {
                            Logger.error("重试加载星堡信息失败: \(error)")
                        }
                    }
                }
            } else if viewModel.starbases.isEmpty {
                emptyView
            } else if viewModel.filteredStarbases.isEmpty {
                ContentUnavailableView {
                    Label(
                        NSLocalizedString("Misc_No_Data", comment: "无数据"),
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                } description: {
                    Text(NSLocalizedString("Corp_Starbase_No_Filtered_Data", comment: "筛选条件下暂无数据"))
                }
            } else {
                // 所有星堡列表
                starbaseListView
            }
        }
        .refreshable {
            do {
                try await viewModel.loadStarbases(forceRefresh: true)
            } catch {
                if !(error is CancellationError) {
                    Logger.error("刷新星堡信息失败: \(error)")
                }
            }
        }
        .navigationTitle(NSLocalizedString("Corp_Starbase_Title", comment: "军团星堡"))
        .toolbar {
            // 只有当获取到数据时才显示筛选按钮
            if !viewModel.starbases.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showFilterSheet = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                            if viewModel.hasActiveFilters {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            FilterSheetView(viewModel: viewModel)
        }
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label(
                NSLocalizedString("Corp_Starbase_No_Data", comment: "暂无星堡数据"),
                systemImage: "exclamationmark.triangle"
            )
        }
    }

    private var starbaseListView: some View {
        Group {
            // 需要关注的POS section（置顶）
            if !viewModel.attentionStarbases.isEmpty {
                Section(
                    header: Text(NSLocalizedString("Corp_Starbase_Attention_Header", comment: "需要关注"))
                        .fontWeight(.semibold)
                        .font(.system(size: 18))
                        .foregroundColor(.red)
                        .textCase(nil)
                ) {
                    ForEach(0 ..< viewModel.attentionStarbases.count, id: \.self) { index in
                        let starbase = viewModel.attentionStarbases[index]
                        if let typeId = starbase["type_id"] as? Int {
                            StarbaseCell(
                                starbase: starbase,
                                iconName: viewModel.getIconName(typeId: typeId),
                                displayName: viewModel.getDisplayName(for: starbase, in: viewModel.attentionStarbases),
                                detailInfo: viewModel.getStarbaseDetail(starbaseId: starbase["starbase_id"] as? Int),
                                fuelItemNames: viewModel.fuelItemNames,
                                fuelItemIcons: viewModel.fuelItemIcons,
                                fuelThreshold: viewModel.getFuelThreshold(typeId: typeId),
                                hasLowFuel: viewModel.hasLowFuel(starbaseId: starbase["starbase_id"] as? Int ?? 0),
                                viewModel: viewModel
                            )
                        }
                    }
                }
            }

            // 其他POS按位置分组
            ForEach(viewModel.filteredLocationKeys, id: \.self) { location in
                if let starbases = viewModel.filteredGroupedStarbases[location] {
                    Section(
                        header: {
                            if let systemId = starbases.first?["system_id"] as? Int,
                               let securityLevel = viewModel.regionSecs[systemId]
                            {
                                Text(formatSystemSecurity(securityLevel))
                                    .foregroundColor(getSecurityColor(securityLevel)) + Text(" ")
                                    + Text(location)
                            } else {
                                Text(location)
                            }
                        }()
                    ) {
                        ForEach(0 ..< starbases.count, id: \.self) { index in
                            let starbase = starbases[index]
                            if let typeId = starbase["type_id"] as? Int {
                                StarbaseCell(
                                    starbase: starbase,
                                    iconName: viewModel.getIconName(typeId: typeId),
                                    displayName: viewModel.getDisplayName(for: starbase, in: starbases),
                                    detailInfo: viewModel.getStarbaseDetail(starbaseId: starbase["starbase_id"] as? Int),
                                    fuelItemNames: viewModel.fuelItemNames,
                                    fuelItemIcons: viewModel.fuelItemIcons,
                                    fuelThreshold: viewModel.getFuelThreshold(typeId: typeId),
                                    hasLowFuel: viewModel.hasLowFuel(starbaseId: starbase["starbase_id"] as? Int ?? 0),
                                    viewModel: viewModel
                                )
                                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                            }
                        }
                    }
                }
            }
        }
    }
}

struct StarbaseCell: View {
    let starbase: [String: Any]
    let iconName: String?
    let displayName: String
    let detailInfo: StarbaseDetailInfo?
    let fuelItemNames: [Int: String]
    let fuelItemIcons: [Int: String]
    let fuelThreshold: Int // 燃料阈值
    let hasLowFuel: Bool // 燃料不足标记
    @ObservedObject var viewModel: CorpStarbaseViewModel
    @State private var icon: Image?

    var body: some View {
        HStack(spacing: 12) {
            // 左侧图标
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.3))
                    .frame(width: 44, height: 44)

                Circle()
                    .stroke(
                        viewModel.getStateColor(starbase["state"] as? String ?? ""),
                        lineWidth: 2
                    )
                    .frame(width: 44, height: 44)

                if let icon = icon {
                    icon
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                } else {
                    Image("default_char")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                }
            }
            .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)

            // 右侧信息
            VStack(alignment: .leading, spacing: 4) {
                // 显示名称（moon_id，如果同一moon下有多个则拼接starbase_id）
                Text(displayName)
                    .font(.headline)
                    .lineLimit(1)

                // 状态
                HStack {
                    Text(NSLocalizedString("Corp_Starbase_Status", comment: "状态"))
                    Text(viewModel.getStateDisplayName(starbase["state"] as? String ?? "") + (hasLowFuel ? " " + NSLocalizedString("Corp_Starbase_Low_Fuel_Indicator", comment: "[燃料不足]") : ""))
                        .foregroundColor(hasLowFuel ? .red : viewModel.getStateColor(starbase["state"] as? String ?? ""))
                }
                .font(.subheadline)

                // 解除锚定时间
                if let unanchorAt = starbase["unanchor_at"] as? String {
                    HStack {
                        Text(NSLocalizedString("Corp_Starbase_Unanchor_At", comment: "解锚开始于："))
                        Text(formatDateTime(unanchorAt))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .font(.subheadline)
                }

                // 增强结束时间
                if let reinforcedUntil = starbase["reinforced_until"] as? String {
                    HStack {
                        Text(NSLocalizedString("Corp_Starbase_Reinforced_Until", comment: "增强结束于："))
                        Text(formatDateTime(reinforcedUntil))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .font(.subheadline)
                }

                // 访问权限标签
                if let detail = detailInfo {
                    HStack(spacing: 6) {
                        Text(NSLocalizedString("Corp_Starbase_Access_Prefix", comment: "可访问"))
                            .font(.caption)
                            .foregroundColor(.secondary)

                        // 联盟访问权限
                        HStack(spacing: 4) {
                            Text(NSLocalizedString("Corp_Starbase_Access_Alliance", comment: "联盟"))
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(detail.allow_alliance_members ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                                .foregroundColor(detail.allow_alliance_members ? .green : .red)
                                .cornerRadius(4)
                        }

                        // 军团访问权限
                        HStack(spacing: 4) {
                            Text(NSLocalizedString("Corp_Starbase_Access_Corporation", comment: "军团"))
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(detail.allow_corporation_members ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                                .foregroundColor(detail.allow_corporation_members ? .green : .red)
                                .cornerRadius(4)
                        }
                    }
                }

                // 燃料信息
                if let detail = detailInfo, !detail.fuels.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(detail.fuels.filter { $0.type_id > 0 && $0.quantity > 0 }, id: \.type_id) { fuel in
                            HStack(spacing: 4) {
                                // 燃料图标
                                if let iconName = fuelItemIcons[fuel.type_id] {
                                    IconManager.shared.loadImage(for: iconName)
                                        .resizable()
                                        .frame(width: 16, height: 16)
                                }

                                // 燃料名称和数量
                                let fuelName = fuelItemNames[fuel.type_id] ?? "Unknown (\(fuel.type_id))"
                                // 只对特定燃料类型检查阈值
                                let quantityColor: Color = {
                                    if CorpStarbaseViewModel.monitoredFuelTypeIds.contains(fuel.type_id) {
                                        return fuel.quantity <= fuelThreshold ? .red : .primary
                                    } else {
                                        return .primary
                                    }
                                }()
                                HStack(spacing: 0) {
                                    Text("\(fuelName) x ")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(fuel.quantity)")
                                        .font(.caption)
                                        .foregroundColor(quantityColor)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .task {
            if let iconName = iconName {
                icon = IconManager.shared.loadImage(for: iconName)
            }
        }
    }

    private func formatDateTime(_ dateString: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: dateString) else {
            return NSLocalizedString("Corp_Starbase_Invalid_Time", comment: "时间格式错误")
        }
        return FormatUtil.formatDateToLocalTime(date)
    }
}

/// 过滤Sheet视图
struct FilterSheetView: View {
    @ObservedObject var viewModel: CorpStarbaseViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                // 星域筛选
                if !viewModel.availableRegions.isEmpty {
                    Section {
                        ForEach(viewModel.availableRegions, id: \.self) { region in
                            Button(action: {
                                if viewModel.selectedRegion == region {
                                    viewModel.selectedRegion = nil
                                } else {
                                    viewModel.selectedRegion = region
                                }
                            }) {
                                HStack {
                                    Text(region)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if viewModel.selectedRegion == region {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    } header: {
                        HStack {
                            Text(NSLocalizedString("Corp_Starbase_Filter_Region", comment: "星域"))
                            Spacer()
                            if viewModel.selectedRegion != nil {
                                Button(action: {
                                    viewModel.selectedRegion = nil
                                }) {
                                    Text(NSLocalizedString("Corp_Starbase_Filter_Clear", comment: "清除筛选"))
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                }

                // 状态筛选
                if !viewModel.availableStates.isEmpty {
                    Section {
                        ForEach(viewModel.availableStates, id: \.self) { state in
                            Button(action: {
                                if viewModel.selectedState == state {
                                    viewModel.selectedState = nil
                                } else {
                                    viewModel.selectedState = state
                                }
                            }) {
                                HStack {
                                    // 添加彩色圆点
                                    Circle()
                                        .fill(viewModel.getStateColor(state))
                                        .frame(width: 8, height: 8)

                                    Text(viewModel.getStateDisplayName(state))
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if viewModel.selectedState == state {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    } header: {
                        HStack {
                            Text(NSLocalizedString("Corp_Starbase_Filter_State", comment: "状态"))
                            Spacer()
                            if viewModel.selectedState != nil {
                                Button(action: {
                                    viewModel.selectedState = nil
                                }) {
                                    Text(NSLocalizedString("Corp_Starbase_Filter_Clear", comment: "清除筛选"))
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                }

                // 清除所有筛选
                if viewModel.hasActiveFilters {
                    Section {
                        Button(action: {
                            viewModel.selectedRegion = nil
                            viewModel.selectedState = nil
                        }) {
                            Text(NSLocalizedString("Corp_Starbase_Filter_Clear_All", comment: "清除所有筛选"))
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Corp_Starbase_Filter", comment: "筛选"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Common_Done", comment: "完成")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

@MainActor
class CorpStarbaseViewModel: ObservableObject {
    @Published var starbases: [[String: Any]] = []
    @Published private(set) var isLoading = false
    @Published var error: Error?
    @Published var selectedRegion: String? = nil
    @Published var selectedState: String? = nil
    @Published var starbaseDetails: [Int: StarbaseDetailInfo] = [:] // 星堡详细信息，key为starbase_id
    @Published var fuelItemNames: [Int: String] = [:] // 燃料物品名称，key为type_id
    @Published var fuelItemIcons: [Int: String] = [:] // 燃料物品图标，key为type_id
    @Published var loadingDetailProgress: String? = nil // 加载详细信息进度
    private var hasLowFuelCache: [Int: Bool] = [:] // 燃料不足标记缓存，key为starbase_id
    private var typeIcons: [Int: String] = [:]
    private var typeEnNames: [Int: String] = [:] // type_id对应的en_name，用于判断POS类型
    private var systemNames: [Int: String] = [:]
    private var regionNames: [Int: String] = [:]
    private var moonNames: [Int: String] = [:]
    var regionSecs: [Int: Double] = [:] // 星系安全等级
    private let characterId: Int

    /// POS燃料阈值常量
    private enum FuelThreshold {
        static let small: Int = 1800 // 小型
        static let medium: Int = 3600 // 中型
        static let standard: Int = 7200 // 标准
    }

    /// 需要检查阈值的燃料类型ID
    static let monitoredFuelTypeIds = [4051, 4247, 4246, 4312]

    /// 根据type_id获取燃料阈值
    func getFuelThreshold(typeId: Int) -> Int {
        guard let enName = typeEnNames[typeId] else {
            return FuelThreshold.standard
        }

        if enName.hasSuffix("Small") {
            return FuelThreshold.small
        } else if enName.hasSuffix("Medium") {
            return FuelThreshold.medium
        } else {
            return FuelThreshold.standard
        }
    }

    /// 是否有活动的筛选条件
    var hasActiveFilters: Bool {
        return selectedRegion != nil || selectedState != nil
    }

    /// 获取可用的星域列表
    var availableRegions: [String] {
        var regions = Set<String>()
        for starbase in starbases {
            if let systemId = starbase["system_id"] as? Int,
               let regionName = regionNames[systemId]
            {
                regions.insert(regionName)
            }
        }
        return Array(regions).sorted()
    }

    /// 获取可用的状态列表
    var availableStates: [String] {
        var states = Set<String>()
        for starbase in starbases {
            if let state = starbase["state"] as? String {
                states.insert(state)
            }
        }
        // 按固定顺序返回
        let orderedStates = ["online", "offline", "onlining", "reinforced", "unanchoring"]
        return orderedStates.filter { states.contains($0) } + states.subtracting(Set(orderedStates)).sorted()
    }

    /// 获取状态的显示名称
    func getStateDisplayName(_ state: String) -> String {
        switch state {
        case "offline":
            return NSLocalizedString("Corp_Starbase_State_Offline", comment: "离线")
        case "online":
            return NSLocalizedString("Corp_Starbase_State_Online", comment: "在线")
        case "onlining":
            return NSLocalizedString("Corp_Starbase_State_Onlining", comment: "上线中")
        case "reinforced":
            return NSLocalizedString("Corp_Starbase_State_Reinforced", comment: "增强中")
        case "unanchoring":
            return NSLocalizedString("Corp_Starbase_State_Unanchoring", comment: "解锚中")
        default:
            return NSLocalizedString("Corp_Starbase_State_Unknown", comment: "未知")
        }
    }

    /// 获取状态对应的颜色
    func getStateColor(_ state: String) -> Color {
        switch state {
        case "offline":
            return .red
        case "online", "onlining":
            return .green
        case "reinforced":
            return .yellow
        case "unanchoring":
            return .blue
        default:
            return .secondary
        }
    }

    /// 根据筛选条件过滤后的星堡列表
    var filteredStarbases: [[String: Any]] {
        var filtered = starbases

        // 按星域筛选
        if let selectedRegion = selectedRegion {
            filtered = filtered.filter { starbase in
                if let systemId = starbase["system_id"] as? Int,
                   let regionName = regionNames[systemId]
                {
                    return regionName == selectedRegion
                }
                return false
            }
        }

        // 按状态筛选
        if let selectedState = selectedState {
            filtered = filtered.filter { starbase in
                if let state = starbase["state"] as? String {
                    return state == selectedState
                }
                return false
            }
        }

        return filtered
    }

    /// 筛选后的位置键
    var filteredLocationKeys: [String] {
        Array(filteredGroupedStarbases.keys).sorted()
    }

    /// 判断POS是否需要关注
    func needsAttention(_ starbase: [String: Any]) -> Bool {
        // 检查状态：offline、reinforced、unanchoring 需要关注
        if let state = starbase["state"] as? String {
            if state == "offline" || state == "reinforced" || state == "unanchoring" {
                return true
            }
        }

        // 检查燃料：使用缓存的标记
        if let starbaseId = starbase["starbase_id"] as? Int,
           let hasLowFuel = hasLowFuelCache[starbaseId],
           hasLowFuel
        {
            return true
        }

        return false
    }

    /// 获取燃料不足标记（使用缓存）
    func hasLowFuel(starbaseId: Int) -> Bool {
        return hasLowFuelCache[starbaseId] ?? false
    }

    /// 星堡排序函数（按moon_id和starbase_id排序）
    private func sortStarbases(_ starbases: [[String: Any]]) -> [[String: Any]] {
        return starbases.sorted { starbase1, starbase2 in
            let moonId1 = starbase1["moon_id"] as? Int
            let moonId2 = starbase2["moon_id"] as? Int

            // 如果其中一个没有moon_id，将其排在后面
            if moonId1 == nil, moonId2 != nil {
                return false
            }
            if moonId1 != nil, moonId2 == nil {
                return true
            }
            if moonId1 == nil, moonId2 == nil {
                // 两个都没有moon_id，按starbase_id排序
                let starbaseId1 = starbase1["starbase_id"] as? Int ?? 0
                let starbaseId2 = starbase2["starbase_id"] as? Int ?? 0
                return starbaseId1 < starbaseId2
            }

            // 两个都有moon_id，先按moon_id排序
            if moonId1! != moonId2! {
                return moonId1! < moonId2!
            }
            // 如果moon_id相同，按starbase_id排序
            let starbaseId1 = starbase1["starbase_id"] as? Int ?? 0
            let starbaseId2 = starbase2["starbase_id"] as? Int ?? 0
            return starbaseId1 < starbaseId2
        }
    }

    /// 需要关注的POS列表
    var attentionStarbases: [[String: Any]] {
        sortStarbases(filteredStarbases.filter { needsAttention($0) })
    }

    /// 筛选后的分组星堡（排除需要关注的，因为它们在单独的section中）
    var filteredGroupedStarbases: [String: [[String: Any]]] {
        // 先过滤掉需要关注的POS
        let nonAttentionStarbases = filteredStarbases.filter { !needsAttention($0) }

        var groups: [String: [[String: Any]]] = [:]
        for starbase in nonAttentionStarbases {
            if let systemId = starbase["system_id"] as? Int {
                let systemName = systemNames[systemId] ?? NSLocalizedString("Unknown", comment: "")
                let regionName = regionNames[systemId] ?? NSLocalizedString("Unknown", comment: "")
                let locationKey = "\(regionName) - \(systemName)"

                if groups[locationKey] == nil {
                    groups[locationKey] = []
                }
                groups[locationKey]?.append(starbase)
            }
        }

        // 对每个区域内的星堡排序
        for (key, value) in groups {
            groups[key] = sortStarbases(value)
        }

        return groups
    }

    init(characterId: Int) {
        self.characterId = characterId
        // 在初始化时立即开始加载数据
        Task {
            do {
                try await loadStarbases()
            } catch {
                // 记录错误，由视图展示错误页（带重试）
                Logger.error("初始化加载星堡信息失败: \(error)")
                self.error = error
            }
        }
    }

    /// 获取显示名称（月球名称，如果同一moon下有多个则拼接starbase_id）
    func getDisplayName(for starbase: [String: Any], in allStarbases: [[String: Any]]) -> String {
        guard let moonId = starbase["moon_id"] as? Int else {
            return NSLocalizedString("Corp_Starbase_Unknown", comment: "未知")
        }

        // 获取月球名称，如果没有则使用moon_id
        let moonName = starbase["moon_name"] as? String ?? "\(moonId)"

        // 统计同一moon_id下的星堡数量
        let sameMoonCount = allStarbases.filter { $0["moon_id"] as? Int == moonId }.count

        if sameMoonCount > 1 {
            // 如果同一moon下有多个，拼接starbase_id
            if let starbaseId = starbase["starbase_id"] as? Int {
                return "\(moonName) (\(starbaseId))"
            } else {
                return moonName
            }
        } else {
            // 只有一个，只显示月球名称
            return moonName
        }
    }

    func loadStarbases(forceRefresh: Bool = false) async throws {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            // 从API获取数据
            let starbases = try await CorpStarbaseAPI.shared.fetchStarbases(
                characterId: characterId,
                forceRefresh: forceRefresh
            )

            // 将 StarbaseInfo 转换为字典
            let starbaseDicts: [[String: Any]] = starbases.map { starbase in
                var dict: [String: Any] = [
                    "starbase_id": starbase.starbase_id,
                    "type_id": starbase.type_id,
                    "system_id": starbase.system_id,
                    "state": starbase.state,
                ]

                if let moonId = starbase.moon_id {
                    dict["moon_id"] = moonId
                }

                if let onlinedSince = starbase.onlined_since {
                    dict["onlined_since"] = onlinedSince
                }

                if let reinforcedUntil = starbase.reinforced_until {
                    dict["reinforced_until"] = reinforcedUntil
                }

                if let unanchorAt = starbase.unanchor_at {
                    dict["unanchor_at"] = unanchorAt
                }

                return dict
            }

            // 收集所有需要查询的ID
            let typeIds = Set(starbaseDicts.compactMap { $0["type_id"] as? Int })
            let systemIds = Set(starbaseDicts.compactMap { $0["system_id"] as? Int })
            let moonIds = Set(starbaseDicts.compactMap { $0["moon_id"] as? Int })

            // 查询类型图标
            await loadTypeIcons(typeIds: Array(typeIds))

            // 查询星系和星域信息
            await loadLocationInfo(systemIds: Array(systemIds))

            // 查询月球名称
            await loadMoonNames(moonIds: Array(moonIds))

            // 更新星堡数据，添加月球名称
            self.starbases = starbaseDicts.map { dict in
                var updatedDict = dict
                if let moonId = dict["moon_id"] as? Int,
                   let moonName = moonNames[moonId]
                {
                    updatedDict["moon_name"] = moonName
                }
                return updatedDict
            }
        } catch {
            Logger.error("加载星堡信息失败: \(error)")
            self.error = error
            throw error
        }

        // 在 defer 之前加载星堡详细信息，这样 isLoading 还是 true
        // 但即使 isLoading 变成 false，loadingDetailProgress 也会显示进度
        await loadStarbaseDetails(forceRefresh: forceRefresh)
    }

    /// 加载所有星堡的详细信息
    func loadStarbaseDetails(forceRefresh: Bool = false) async {
        // 获取军团ID
        guard let corporationId = try? await CharacterDatabaseManager.shared.getCharacterCorporationId(
            characterId: characterId
        ) else {
            Logger.error("无法获取军团ID，跳过加载星堡详细信息")
            return
        }

        // 构建查询参数数组
        var queries: [StarbaseQueryParams] = []
        for starbase in starbases {
            if let starbaseId = starbase["starbase_id"] as? Int,
               let systemId = starbase["system_id"] as? Int
            {
                queries.append(StarbaseQueryParams(
                    starbaseId: starbaseId,
                    corporationId: corporationId,
                    systemId: systemId
                ))
            }
        }

        guard !queries.isEmpty else {
            Logger.info("没有需要查询的星堡详细信息")
            return
        }

        Logger.info("开始批量加载星堡详细信息 - 总数: \(queries.count)")

        // 初始化进度（立即显示）
        loadingDetailProgress = String(
            format: NSLocalizedString(
                "Corp_Starbase_Loading_Detail_Progress",
                comment: "正在加载星堡详细信息 %d/%d"
            ),
            0, queries.count
        )

        // 批量查询详细信息
        let results = await CorpStarbaseDetailAPI.shared.fetchStarbaseDetailsBatch(
            queries: queries,
            characterId: characterId,
            forceRefresh: forceRefresh,
            progressCallback: { current, total in
                Task { @MainActor [weak self] in
                    self?.loadingDetailProgress = String(
                        format: NSLocalizedString(
                            "Corp_Starbase_Loading_Detail_Progress",
                            comment: "正在加载星堡详细信息 %d/%d"
                        ),
                        current, total
                    )
                    Logger.debug("更新加载进度: \(current)/\(total)")
                }
            }
        )

        // 存储详细信息并计算燃料不足标记
        hasLowFuelCache.removeAll()
        for (query, detail) in results {
            if let detail = detail {
                starbaseDetails[query.starbaseId] = detail

                // 计算并缓存燃料不足标记
                if let starbase = starbases.first(where: { ($0["starbase_id"] as? Int) == query.starbaseId }),
                   let typeId = starbase["type_id"] as? Int
                {
                    let threshold = getFuelThreshold(typeId: typeId)
                    var hasLowFuel = false
                    for fuel in detail.fuels {
                        if Self.monitoredFuelTypeIds.contains(fuel.type_id), fuel.quantity > 0, fuel.quantity <= threshold {
                            hasLowFuel = true
                            break
                        }
                    }
                    hasLowFuelCache[query.starbaseId] = hasLowFuel
                }

                // 收集燃料物品ID
                let fuelTypeIds = detail.fuels.map { $0.type_id }.filter { $0 > 0 }
                if !fuelTypeIds.isEmpty {
                    await loadFuelItemInfo(typeIds: fuelTypeIds)
                }
            }
        }

        Logger.success("完成加载星堡详细信息 - 成功: \(results.values.compactMap { $0 }.count), 失败: \(results.values.filter { $0 == nil }.count)")

        // 清除进度信息
        loadingDetailProgress = nil
    }

    /// 加载燃料物品信息（名称和图标）
    private func loadFuelItemInfo(typeIds: [Int]) async {
        guard !typeIds.isEmpty else { return }

        for typeId in Set(typeIds) {
            guard let info = ItemInfoMap.typeInfo(for: typeId), !info.name.isEmpty else { continue }
            fuelItemNames[typeId] = info.name
            fuelItemIcons[typeId] = info.iconFilename
        }
    }

    private func loadTypeIcons(typeIds: [Int]) async {
        for typeId in typeIds {
            guard let info = ItemInfoMap.typeInfo(for: typeId) else { continue }
            typeIcons[typeId] = info.iconFilename
            if !info.enName.isEmpty {
                typeEnNames[typeId] = info.enName
            }
        }
    }

    private func loadLocationInfo(systemIds: [Int]) async {
        // 内存索引获取星系位置信息
        for systemId in Set(systemIds) {
            guard let info = SDEMemoryStore.universeSystems[systemId] else { continue }
            if let systemName = SDEMemoryStore.solarSystemName(for: systemId) {
                systemNames[systemId] = systemName
            }
            if let regionName = SDEMemoryStore.regionName(for: info.regionID) {
                regionNames[systemId] = regionName
            }
            regionSecs[systemId] = info.security
        }
    }

    private func loadMoonNames(moonIds: [Int]) async {
        guard !moonIds.isEmpty else { return }
        moonNames = DatabaseManager.shared.getCelestialNames(itemIDs: moonIds)
    }

    func getIconName(typeId: Int) -> String? {
        return typeIcons[typeId]
    }

    /// 获取星堡详细信息
    func getStarbaseDetail(starbaseId: Int?) -> StarbaseDetailInfo? {
        guard let starbaseId = starbaseId else { return nil }
        return starbaseDetails[starbaseId]
    }
}
