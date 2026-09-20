import SwiftUI

struct ESIStatusView: View {
    // MARK: - 属性

    @State private var esiStatus: [ESIStatus] = []
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var lastRefreshTime: Date? = nil
    @State private var selectedFilter: String? = nil // nil表示不过滤

    // MARK: - 计算属性

    private var redCount: Int {
        esiStatus.filter { $0.isRed }.count
    }

    private var yellowCount: Int {
        esiStatus.filter { $0.isYellow }.count
    }

    private var greenCount: Int {
        esiStatus.filter { $0.isGreen }.count
    }

    private var orangeCount: Int {
        esiStatus.filter { $0.isOrange }.count
    }

    private var filteredStatus: [ESIStatus] {
        if selectedFilter == nil {
            return esiStatus
        } else if selectedFilter == "red" {
            return esiStatus.filter { $0.isRed }
        } else if selectedFilter == "yellow" {
            return esiStatus.filter { $0.isYellow }
        } else if selectedFilter == "green" {
            return esiStatus.filter { $0.isGreen }
        } else if selectedFilter == "orange" {
            return esiStatus.filter { $0.isOrange }
        }
        return esiStatus
    }

    private var statusByTag: [String: [ESIStatus]] {
        Dictionary(grouping: filteredStatus) { $0.tags.first ?? "其他" }
    }

    // MARK: - 视图主体

    var body: some View {
        List {
            // 状态摘要部分
            Section {
                HStack(spacing: 20) {
                    StatusCountView(
                        count: redCount,
                        color: .red,
                        label: NSLocalizedString("ESI_Status_Down", comment: ""),
                        isSelected: selectedFilter == "red",
                        action: {
                            selectedFilter = selectedFilter == "red" ? nil : "red"
                        }
                    )
                    StatusCountView(
                        count: yellowCount,
                        color: .yellow,
                        label: NSLocalizedString("ESI_Status_Degraded", comment: ""),
                        isSelected: selectedFilter == "yellow",
                        action: {
                            selectedFilter = selectedFilter == "yellow" ? nil : "yellow"
                        }
                    )
                    StatusCountView(
                        count: orangeCount,
                        color: .orange,
                        label: NSLocalizedString("ESI_Status_Recovering", comment: ""),
                        isSelected: selectedFilter == "orange",
                        action: {
                            selectedFilter = selectedFilter == "orange" ? nil : "orange"
                        }
                    )
                    StatusCountView(
                        count: greenCount,
                        color: .green,
                        label: NSLocalizedString("ESI_Status_OK", comment: ""),
                        isSelected: selectedFilter == "green",
                        action: {
                            selectedFilter = selectedFilter == "green" ? nil : "green"
                        }
                    )
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } header: {
                HStack {
                    Text(NSLocalizedString("ESI_Status_Overview", comment: ""))
                    Spacer()
                    if let lastRefresh = lastRefreshTime {
                        Text(
                            String(
                                format: NSLocalizedString("ESI_Status_Last_Refresh", comment: ""),
                                timeAgoString(from: lastRefresh)
                            )
                        )
                        .font(.caption)
                        .foregroundColor(.gray)
                    }
                }
            }

            // 详细端点状态部分
            ForEach(statusByTag.keys.sorted(), id: \.self) { tag in
                Section {
                    ForEach(statusByTag[tag] ?? [], id: \.uniqueID) { status in
                        EndpointStatusRow(status: status)
                    }
                } header: {
                    Text(localizedTagName(tag))
                }
            }
        }
        .navigationTitle(NSLocalizedString("ESI_Status_Title", comment: ""))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { refreshStatus(forceRefresh: true) }) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .overlay {
            if isLoading {
                ProgressView(NSLocalizedString("ESI_Status_Loading", comment: ""))
                    .frame(width: 120, height: 120)
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(10)
                    .shadow(radius: 5)
            }
        }
        .alert(
            NSLocalizedString("ESI_Status_Load_Failed", comment: ""),
            isPresented: .init(get: { errorMessage != nil }, set: {
                if !$0 {
                    errorMessage = nil
                }
            })
        ) {
            Button(NSLocalizedString("ESI_Status_Button_OK", comment: ""), role: .cancel) {
                errorMessage = nil
            }
            Button(NSLocalizedString("ESI_Status_Retry", comment: "")) { refreshStatus() }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
        .onAppear {
            refreshStatus()
        }
    }

    // MARK: - 方法

    private func refreshStatus(forceRefresh: Bool = false) {
        isLoading = true
        errorMessage = nil

        // 不再清空当前数据，保持原有内容直到新数据加载完成

        Task {
            do {
                // 获取数据
                let status = try await ESIStatusAPI.shared.fetchESIStatus(
                    forceRefresh: forceRefresh
                )

                // 获取缓存时间戳
                // 无论是否强制刷新，都使用缓存创建的时间
                let cacheTime = await ESIStatusAPI.shared.getLastCacheTimestamp() ?? Date()

                // 确保在主线程更新UI
                await MainActor.run {
                    // 更新UI数据
                    withAnimation {
                        self.esiStatus = status
                        self.lastRefreshTime = cacheTime
                    }
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    private func localizedTagName(_ tag: String) -> String {
        switch tag {
        case "Alliances": return NSLocalizedString("ESI_Tag_Alliance", comment: "")
        case "Assets": return NSLocalizedString("ESI_Tag_Assets", comment: "")
        case "Bookmarks": return NSLocalizedString("ESI_Tag_Bookmarks", comment: "")
        case "Calendar": return NSLocalizedString("ESI_Tag_Calendar", comment: "")
        case "Characters": return NSLocalizedString("ESI_Tag_Character", comment: "")
        case "Clones": return NSLocalizedString("ESI_Tag_Clones", comment: "")
        case "Contacts": return NSLocalizedString("ESI_Tag_Contacts", comment: "")
        case "Contracts": return NSLocalizedString("ESI_Tag_Contracts", comment: "")
        case "Corporations": return NSLocalizedString("ESI_Tag_Corporation", comment: "")
        case "Dogma": return NSLocalizedString("ESI_Tag_Dogma", comment: "")
        case "Fw": return NSLocalizedString("ESI_Tag_FactionWarfare", comment: "")
        case "Fittings": return NSLocalizedString("ESI_Tag_Fittings", comment: "")
        case "Fleets": return NSLocalizedString("ESI_Tag_Fleets", comment: "")
        case "Incursions": return NSLocalizedString("ESI_Tag_Incursions", comment: "")
        case "Industry": return NSLocalizedString("ESI_Tag_Industry", comment: "")
        case "Insurance": return NSLocalizedString("ESI_Tag_Insurance", comment: "")
        case "Killmails": return NSLocalizedString("ESI_Tag_Killmails", comment: "")
        case "Location": return NSLocalizedString("ESI_Tag_Location", comment: "")
        case "Loyalty": return NSLocalizedString("ESI_Tag_Loyalty", comment: "")
        case "Mail": return NSLocalizedString("ESI_Tag_Mail", comment: "")
        case "Markets": return NSLocalizedString("ESI_Tag_Market", comment: "")
        case "Opportunities": return NSLocalizedString("ESI_Tag_Opportunities", comment: "")
        case "PlanetaryInteraction":
            return NSLocalizedString("ESI_Tag_PlanetaryInteraction", comment: "")
        case "Route": return NSLocalizedString("ESI_Tag_Routes", comment: "")
        case "Search": return NSLocalizedString("ESI_Tag_Search", comment: "")
        case "Skills": return NSLocalizedString("ESI_Tag_Skills", comment: "")
        case "Sovereignty": return NSLocalizedString("ESI_Tag_Sovereignty", comment: "")
        case "Status": return NSLocalizedString("ESI_Tag_Status", comment: "")
        case "Universe": return NSLocalizedString("ESI_Tag_Universe", comment: "")
        case "Ui": return NSLocalizedString("ESI_Tag_UserInterface", comment: "")
        case "Wallet": return NSLocalizedString("ESI_Tag_Wallet", comment: "")
        case "Wars": return NSLocalizedString("ESI_Tag_Wars", comment: "")
        default: return NSLocalizedString("ESI_Tag_Other", comment: "")
        }
    }

    private func timeAgoString(from date: Date) -> String {
        return FormatUtil.formatRelativeAgoShort(since: date)
    }
}

// MARK: - 辅助视图

struct StatusCountView: View {
    let count: Int
    let color: Color
    let label: String
    let isSelected: Bool
    let action: () -> Void

    init(
        count: Int, color: Color, label: String, isSelected: Bool = false,
        action: @escaping () -> Void = {}
    ) {
        self.count = count
        self.color = color
        self.label = label
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack {
                Text("\(count)")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(color)
                Text(label)
                    .font(.caption)
                    .foregroundColor(color)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(color.opacity(isSelected ? 0.3 : 0.1))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? color : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct EndpointStatusRow: View {
    let status: ESIStatus

    var body: some View {
        HStack {
            // 状态指示圆点
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 4) {
                // 端点名称
                Text(endpointDisplayName)
                    .font(.system(size: 16))

                // 路由路径
                HStack(spacing: 4) {
                    Text(status.route)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
            }

            Spacer()

            // HTTP方法标签
            Text(status.method.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .foregroundColor(.white)
                .background(Color.gray.opacity(0.7))
                .cornerRadius(4)
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        return status.statusColor
    }

    private var endpointDisplayName: String {
        // 从路由中提取更友好的名称
        let components = status.route.split(separator: "/")
        if components.count > 1 {
            let lastComponent = components.last!
            if lastComponent.contains("{") {
                // 如果最后一个组件是参数，使用前一个组件
                return String(components[components.count - 2])
            } else {
                return String(lastComponent)
            }
        } else if !components.isEmpty {
            return String(components[0])
        } else {
            return status.endpoint
        }
    }
}
