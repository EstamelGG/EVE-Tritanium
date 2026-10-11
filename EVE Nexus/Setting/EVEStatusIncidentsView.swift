import SwiftUI

// MARK: - EVE状态事件列表视图

struct EVEStatusIncidentsView: View {
    @StateObject private var rssManager = EVEStatusRSSManager.shared

    var body: some View {
        NavigationStack {
            if rssManager.isLoading {
                LoadingStateView()
            } else if rssManager.incidents.isEmpty {
                EmptyStateView()
            } else {
                IncidentsListView(incidents: rssManager.incidents)
            }
        }
        .navigationTitle(NSLocalizedString("EVE_Status_Incidents_Title", comment: "EVE Online 故障通知"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    Task {
                        await rssManager.refreshIncidents()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(rssManager.isLoading)
            }
        }
        .refreshable {
            await rssManager.refreshIncidents()
        }
        .onAppear {
            if rssManager.incidents.isEmpty {
                Task {
                    await rssManager.fetchIncidents()
                }
            }
        }
    }
}

// MARK: - 加载状态视图

struct LoadingStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)

            Text(NSLocalizedString("EVE_Status_Loading", comment: "正在加载状态信息..."))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 空状态视图

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)

            VStack(spacing: 8) {
                Text(NSLocalizedString("EVE_Status_All_Good", comment: "一切正常"))
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(NSLocalizedString("EVE_Status_No_Issues", comment: "当前没有EVE Online服务问题"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - 事件列表视图

struct IncidentsListView: View {
    let incidents: [RSSItem]

    var body: some View {
        List {
            ForEach(incidents) { incident in
                NavigationLink(destination: IncidentDetailView(incident: incident)) {
                    IncidentRowView(incident: incident)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
        }
    }
}

// MARK: - 事件行视图（第一层）

struct IncidentRowView: View {
    @Environment(\.locale) private var displayLocale
    @Environment(\.timeZone) private var displayTimeZone
    let incident: RSSItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 第一行：标题
            Text(incident.title)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            // 第二行：左侧时间，右侧状态标签
            HStack {
                // 左侧：状态标签
                StatusBadgeView(incident: incident)
                Spacer()
                // 右侧：时间
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(incident.formattedDate)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }
}

// MARK: - 事件详情视图（第二层）

struct IncidentDetailView: View {
    @Environment(\.locale) private var displayLocale
    @Environment(\.timeZone) private var displayTimeZone
    let incident: RSSItem

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    // 第一行：标题、状态标签、时间
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            StatusBadgeView(incident: incident)
                            Spacer()
                        }

                        Text(incident.title)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack {
                            Image(systemName: "clock")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Text(incident.formattedDate)
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Spacer()
                        }
                    }
                    Divider()
                    // 第二行：正文描述
                    Text(incident.cleanDescription)
                        .font(.body)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    Divider()
                    // 第三行：外部链接
                    if let url = URL(string: incident.link) {
                        HStack {
                            Image(systemName: "safari")
                                .font(.title3)
                                .foregroundColor(.blue)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("EVE_Status_View_Details", comment: "在浏览器中查看详情"))
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)

                                Text("status.eveonline.com")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .cornerRadius(10)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("EVE_Status_Incident_Detail", comment: "事件详情"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 状态徽章视图

struct StatusBadgeView: View {
    let incident: RSSItem

    private var statusInfo: (color: Color, icon: String, text: String) {
        let description = incident.description.lowercased()

        // 首先检查描述中是否包含解决状态
        if description.contains("<strong>resolved</strong>") || description.contains("<strong>completed</strong>") {
            return (.green, "checkmark.circle.fill", NSLocalizedString("EVE_Status_Resolved", comment: "已解决"))
        } else {
            return (.red, "exclamationmark.circle.fill", NSLocalizedString("EVE_Status_Issue", comment: "问题"))
        }
    }

    var body: some View {
        let info = statusInfo

        HStack(spacing: 4) {
            Image(systemName: info.icon)
                .font(.caption)
                .foregroundColor(info.color)

            Text(info.text)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(info.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(info.color.opacity(0.1))
        .cornerRadius(6)
    }
}

// MARK: - 预览

#Preview {
    EVEStatusIncidentsView()
}
