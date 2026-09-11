import SwiftUI

struct CorpStructureView: View {
    let characterId: Int
    @StateObject private var viewModel: CorpStructureViewModel
    @State private var showSettings = false
    @AppStorage("structureFuelMonitorDays") private var fuelMonitorDays: Int = 7 {
        didSet {
            viewModel.updateLowFuelStructures(within: fuelMonitorDays)
        }
    }

    @State private var tempDays: String = ""
    @State private var isRefreshing = false

    init(characterId: Int) {
        self.characterId = characterId
        _viewModel = StateObject(wrappedValue: CorpStructureViewModel(characterId: characterId))
        _tempDays = State(initialValue: "7")
    }

    var body: some View {
        List {
            if viewModel.isLoading {
                loadingView
            } else if let error = viewModel.error,
                      !viewModel.isLoading && viewModel.structures.isEmpty
            {
                // 显示错误信息
                ErrorStateSection(message: error.localizedDescription) {
                    Task {
                        do {
                            try await viewModel.loadStructures(forceRefresh: true)
                        } catch {
                            Logger.error("重试加载建筑信息失败: \(error)")
                        }
                    }
                }
            } else if viewModel.structures.isEmpty {
                emptyView
            } else {
                // 即将耗尽燃料的建筑
                if !viewModel.lowFuelStructuresCache.isEmpty {
                    Section(
                        header: Text(
                            String(
                                format: NSLocalizedString("Corp_Structure_Low_Fuel", comment: ""),
                                fuelMonitorDays
                            )
                        )
                        .foregroundColor(.red)
                        .fontWeight(.semibold)
                        .font(.system(size: 18))
                        .textCase(nil)
                    ) {
                        ForEach(viewModel.lowFuelStructuresCache.indices, id: \.self) { index in
                            let structure = viewModel.lowFuelStructuresCache[index]
                            if let typeId = structure["type_id"] as? Int {
                                StructureCell(
                                    structure: structure,
                                    iconName: viewModel.getIconName(typeId: typeId), isLowFuel: true
                                )
                            }
                        }
                    }
                }

                // 所有建筑列表
                structureListView
            }
        }
        .refreshable {
            do {
                try await viewModel.loadStructures(forceRefresh: true)
            } catch {
                if !(error is CancellationError) {
                    Logger.error("刷新建筑信息失败: \(error)")
                }
            }
        }
        .navigationTitle(NSLocalizedString("Corp_Structure_Title", comment: ""))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    Button(action: {
                        refreshData()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                            .animation(
                                isRefreshing
                                    ? .linear(duration: 1).repeatForever(autoreverses: false)
                                    : .default, value: isRefreshing
                            )
                    }
                    .disabled(isRefreshing)

                    Button(action: {
                        tempDays = String(fuelMonitorDays)
                        showSettings = true
                    }) {
                        Image(systemName: "gear")
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationView {
                Form {
                    Section {
                        NavigationLink {
                            List {
                                ForEach(
                                    [
                                        (
                                            name: NSLocalizedString(
                                                "Corp_Structure_Monitor_1Week", comment: ""
                                            ),
                                            days: 7
                                        ),
                                        (
                                            name: NSLocalizedString(
                                                "Corp_Structure_Monitor_2Weeks", comment: ""
                                            ),
                                            days: 14
                                        ),
                                        (
                                            name: NSLocalizedString(
                                                "Corp_Structure_Monitor_3Weeks", comment: ""
                                            ),
                                            days: 21
                                        ),
                                        (
                                            name: NSLocalizedString(
                                                "Corp_Structure_Monitor_1Month", comment: ""
                                            ),
                                            days: 30
                                        ),
                                        (
                                            name: NSLocalizedString(
                                                "Corp_Structure_Monitor_2Months", comment: ""
                                            ),
                                            days: 60
                                        ),
                                    ], id: \.days
                                ) { option in
                                    HStack {
                                        Text(option.name)
                                        Spacer()
                                        if fuelMonitorDays == option.days {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.accentColor)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        fuelMonitorDays = option.days
                                        showSettings = false
                                    }
                                }
                            }
                            .navigationTitle(
                                NSLocalizedString("Corp_Structure_Monitor_Time", comment: "")
                            )
                            .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            HStack {
                                Text(NSLocalizedString("Corp_Structure_Monitor_Time", comment: ""))
                                Spacer()
                                Text(
                                    String(
                                        format: NSLocalizedString(
                                            "Corp_Structure_Days", comment: ""
                                        ), fuelMonitorDays
                                    )
                                )
                                .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .navigationTitle(NSLocalizedString("Corp_Structure_Settings", comment: ""))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(NSLocalizedString("Corp_Structure_Done", comment: "")) {
                            showSettings = false
                        }
                    }
                }
            }
        }
    }

    private func refreshData() {
        isRefreshing = true

        Task {
            do {
                try await viewModel.loadStructures(forceRefresh: true)
            } catch {
                if !(error is CancellationError) {
                    Logger.error("刷新建筑信息失败: \(error)")
                }
            }

            isRefreshing = false
        }
    }

    private var loadingView: some View {
        HStack {
            Spacer()
            ProgressView()
                .progressViewStyle(.circular)
            Spacer()
        }
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label(
                NSLocalizedString("Corp_Structure_No_Data", comment: ""),
                systemImage: "building.2"
            )
        }
    }

    private var structureListView: some View {
        ForEach(viewModel.locationKeys, id: \.self) { location in
            if let structures = viewModel.groupedStructures[location] {
                Section(
                    header: {
                        if let systemId = structures.first?["system_id"] as? Int,
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
                    ForEach(structures.indices, id: \.self) { index in
                        let structure = structures[index]
                        if let typeId = structure["type_id"] as? Int {
                            StructureCell(
                                structure: structure,
                                iconName: viewModel.getIconName(typeId: typeId)
                            )
                            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                        }
                    }
                }
            }
        }
    }
}

struct StructureCell: View {
    let structure: [String: Any]
    let iconName: String?
    let isLowFuel: Bool
    @State private var icon: Image?

    init(structure: [String: Any], iconName: String?, isLowFuel: Bool = false) {
        self.structure = structure
        self.iconName = iconName
        self.isLowFuel = isLowFuel
    }

    var body: some View {
        HStack(spacing: 12) {
            // 左侧图标
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.3))
                    .frame(width: 44, height: 44)

                Circle()
                    .stroke(
                        isLowFuel
                            ? .red : getStateColor(state: structure["state"] as? String ?? ""),
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
                Text(
                    structure["name"] as? String
                        ?? NSLocalizedString("Corp_Structure_Unknown", comment: "")
                )
                .font(.headline)
                .lineLimit(1)

                if let fuelExpires = structure["fuel_expires"] as? String {
                    HStack {
                        Text(NSLocalizedString("Corp_Structure_Fuel_Expires", comment: ""))
                        Text(formatDateTime(fuelExpires).localTime)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .font(.subheadline)

                    HStack {
                        Text(NSLocalizedString("Corp_Structure_Time_Remaining", comment: ""))
                        Text(formatDateTime(fuelExpires).remainingTime)
                            .foregroundColor(isLowFuel ? .red : .secondary)
                    }
                    .font(.subheadline)
                }

                HStack {
                    Text(NSLocalizedString("Corp_Structure_Status", comment: ""))
                    Text(getStateText(state: structure["state"] as? String ?? ""))
                        .foregroundColor(getStateColor(state: structure["state"] as? String ?? ""))
                }
                .font(.subheadline)

                if let services = structure["services"] as? [[String: String]] {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("Corp_Structure_Services", comment: ""))
                            .font(.subheadline)
                        ForEach(services, id: \.["name"]) { service in
                            if let name = service["name"], let state = service["state"] {
                                Text(name)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        state == "online"
                                            ? Color.green.opacity(0.2) : Color.red.opacity(0.2)
                                    )
                                    .cornerRadius(4)
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

    private func formatDateTime(_ dateString: String) -> (localTime: String, remainingTime: String) {
        guard let date = ISO8601DateFormatter().date(from: dateString) else {
            return ("error time format", "error time format")
        }

        let localTime = FormatUtil.formatDateToLocalTime(date)

        let remainingTime = date.timeIntervalSince(Date())
        let days = Int(remainingTime / (24 * 3600))
        let hours = Int((remainingTime.truncatingRemainder(dividingBy: 24 * 3600)) / 3600)
        let minutes = Int((remainingTime.truncatingRemainder(dividingBy: 3600)) / 60)

        let remainingTimeString: String
        if days > 0 {
            if hours > 0 {
                remainingTimeString = String(
                    format: NSLocalizedString("Corp_Structure_Time_Format_Days_Hours", comment: ""),
                    days, hours
                )
            } else {
                remainingTimeString = String(
                    format: NSLocalizedString("Corp_Structure_Time_Format_Days", comment: ""), days
                )
            }
        } else if hours > 0 {
            remainingTimeString = String(
                format: NSLocalizedString("Corp_Structure_Time_Format_Hours", comment: ""), hours
            )
        } else {
            remainingTimeString = String(
                format: NSLocalizedString("Corp_Structure_Time_Format_Minutes", comment: ""),
                minutes
            )
        }

        return (localTime, remainingTimeString)
    }

    private func getStateColor(state: String) -> Color {
        switch state {
        case "shield_reinforce":
            return .blue.opacity(0.7) // 淡蓝色
        case "armor_reinforce":
            return .orange
        case "hull_reinforce":
            return .red
        default:
            return .green
        }
    }

    private func getStateText(state: String) -> String {
        switch state {
        case "shield_vulnerable":
            return NSLocalizedString("Corp_Structure_State_Shield_Vulnerable", comment: "")
        case "armor_vulnerable":
            return NSLocalizedString("Corp_Structure_State_Armor_Vulnerable", comment: "")
        case "armor_reinforce":
            return NSLocalizedString("Corp_Structure_State_Armor_Reinforce", comment: "")
        case "hull_vulnerable":
            return NSLocalizedString("Corp_Structure_State_Hull_Vulnerable", comment: "")
        case "hull_reinforce":
            return NSLocalizedString("Corp_Structure_State_Hull_Reinforce", comment: "")
        case "online_deprecated":
            return NSLocalizedString("Corp_Structure_State_Online_Deprecated", comment: "")
        case "anchor_vulnerable":
            return NSLocalizedString("Corp_Structure_State_Anchor_Vulnerable", comment: "")
        case "anchoring":
            return NSLocalizedString("Corp_Structure_State_Anchoring", comment: "")
        case "deploy_vulnerable":
            return NSLocalizedString("Corp_Structure_State_Deploy_Vulnerable", comment: "")
        case "fitting_invulnerable":
            return NSLocalizedString("Corp_Structure_State_Fitting_Invulnerable", comment: "")
        case "unanchored":
            return NSLocalizedString("Corp_Structure_State_Unanchored", comment: "")
        default:
            return NSLocalizedString("Corp_Structure_State_Unknown", comment: "")
        }
    }
}

@MainActor
class CorpStructureViewModel: ObservableObject {
    @Published var structures: [[String: Any]] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lowFuelStructuresCache: [[String: Any]] = []
    @Published var error: Error?
    private var typeIcons: [Int: String] = [:]
    private var systemNames: [Int: String] = [:]
    private var regionNames: [Int: String] = [:]
    var regionSecs: [Int: Double] = [:]
    private let characterId: Int
    private var currentMonitorDays: Int

    init(characterId: Int) {
        self.characterId = characterId
        // 从 UserDefaults 获取保存的监控时间
        currentMonitorDays = UserDefaults.standard.integer(forKey: "structureFuelMonitorDays")
        if currentMonitorDays == 0 {
            currentMonitorDays = 7
        }

        // 在初始化时立即开始加载数据
        Task {
            do {
                try await loadStructures()
            } catch {
                // 记录错误，由视图展示错误页（带重试）
                Logger.error("初始化加载建筑信息失败: \(error)")
                self.error = error
            }
        }
    }

    /// 获取燃料不足的建筑，按照燃料耗尽时间升序排序
    func updateLowFuelStructures(within days: Int = 7) {
        let monitorDays = days <= 0 ? 7 : days
        currentMonitorDays = monitorDays

        lowFuelStructuresCache = structures.filter { structure in
            guard let fuelExpires = structure["fuel_expires"] as? String,
                  let expirationDate = ISO8601DateFormatter().date(from: fuelExpires)
            else {
                return false
            }

            let timeInterval = expirationDate.timeIntervalSince(Date())
            return timeInterval > 0 && timeInterval <= Double(monitorDays) * 24 * 3600
        }.sorted { structure1, structure2 in
            guard let fuelExpires1 = structure1["fuel_expires"] as? String,
                  let fuelExpires2 = structure2["fuel_expires"] as? String,
                  let date1 = ISO8601DateFormatter().date(from: fuelExpires1),
                  let date2 = ISO8601DateFormatter().date(from: fuelExpires2)
            else {
                return false
            }
            return date1 < date2
        }
    }

    var locationKeys: [String] {
        Array(groupedStructures.keys).sorted()
    }

    var groupedStructures: [String: [[String: Any]]] {
        var groups: [String: [[String: Any]]] = [:]
        for structure in structures {
            if let systemId = structure["system_id"] as? Int {
                let systemName = systemNames[systemId] ?? NSLocalizedString("Unknown", comment: "")
                let regionName = regionNames[systemId] ?? NSLocalizedString("Unknown", comment: "")
                let locationKey = "\(regionName) - \(systemName)"

                if groups[locationKey] == nil {
                    groups[locationKey] = []
                }
                groups[locationKey]?.append(structure)
            }
        }

        // 对每个区域内的建筑按名称排序
        for (key, value) in groups {
            groups[key] = value.sorted { structure1, structure2 in
                let name1 = structure1["name"] as? String ?? ""
                let name2 = structure2["name"] as? String ?? ""
                return name1 < name2
            }
        }

        return groups
    }

    func loadStructures(forceRefresh: Bool = false) async throws {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            // 从API获取数据
            let structures = try await CorpStructureAPI.shared.fetchStructures(
                characterId: characterId,
                forceRefresh: forceRefresh
            )

            // 将 StructureInfo 转换为字典
            let structureDicts: [[String: Any]] = structures.map { structure in
                var dict: [String: Any] = [
                    "structure_id": structure.structure_id,
                    "type_id": structure.type_id,
                    "system_id": structure.system_id,
                    "state": structure.state,
                    "name": structure.name ?? NSLocalizedString("Unknown", comment: ""),
                ]

                if let fuelExpires = structure.fuel_expires {
                    dict["fuel_expires"] = fuelExpires
                }

                if let services = structure.services {
                    dict["services"] = services.map { ["name": $0.name, "state": $0.state] }
                }

                return dict
            }

            // 收集所有需要查询的ID
            let typeIds = Set(structureDicts.compactMap { $0["type_id"] as? Int })
            let systemIds = Set(structureDicts.compactMap { $0["system_id"] as? Int })

            // 查询类型图标
            await loadTypeIcons(typeIds: Array(typeIds))

            // 查询星系和星域信息
            await loadLocationInfo(systemIds: Array(systemIds))

            // 更新结构数据
            self.structures = structureDicts
            // 更新低燃料缓存，使用当前的监控天数
            updateLowFuelStructures(within: currentMonitorDays)
        } catch {
            Logger.error("加载建筑信息失败: \(error)")
            self.error = error
            throw error
        }
    }

    private func loadTypeIcons(typeIds: [Int]) async {
        for typeId in typeIds {
            typeIcons[typeId] = ItemInfoMap.iconFilename(for: typeId)
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

    func getIconName(typeId: Int) -> String? {
        return typeIcons[typeId]
    }
}
