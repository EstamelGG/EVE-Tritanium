import SwiftUI

struct CharacterEmploymentHistoryView: View {
    let history: [CharacterEmploymentHistory]
    let corporationNamesCache: [Int: String]
    let character: EVECharacterInfo
    let isLoadingCorpNames: Bool
    /// 雇佣记录本身是否在加载（加载期间显示加载指示器，不显示"无数据"）
    let isLoading: Bool
    @ObservedObject var allianceCache: EmploymentAllianceCache
    let npcCorporationIds: Set<Int>

    var body: some View {
        if isLoading {
            HStack(spacing: 8) {
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
                Text(NSLocalizedString("Misc_Loading", comment: ""))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .transition(.opacity)
        } else if history.isEmpty {
            ContentUnavailableView {
                Label(
                    NSLocalizedString("Misc_No_Data", comment: "无数据"),
                    systemImage: "exclamationmark.triangle"
                )
            }
            .transition(.opacity)
        } else {
            ForEach(Array(history.enumerated()), id: \.element.record_id) { index, record in
                if let startDate = parseDate(record.start_date) {
                    let endDate = index > 0 ? parseDate(history[index - 1].start_date) : nil

                    VStack(spacing: 0) {
                        EmploymentHistoryRowView(
                            recordId: record.record_id,
                            corporationId: record.corporation_id,
                            startDate: startDate,
                            endDate: endDate,
                            corporationNamesCache: corporationNamesCache,
                            character: character,
                            isLoadingCorpNames: isLoadingCorpNames,
                            allianceCache: allianceCache,
                            npcCorporationIds: npcCorporationIds
                        )
                    }
                }
            }
            .transition(.opacity)
        }
    }

    private func parseDate(_ dateString: String) -> Date? {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        return dateFormatter.date(from: dateString)
    }
}

struct EmploymentHistoryRowView: View {
    @Environment(\.locale) private var displayLocale
    @Environment(\.timeZone) private var displayTimeZone
    let recordId: Int
    let corporationId: Int
    let startDate: Date
    let endDate: Date?
    let corporationNamesCache: [Int: String]
    let character: EVECharacterInfo
    let isLoadingCorpNames: Bool
    @ObservedObject var allianceCache: EmploymentAllianceCache
    let npcCorporationIds: Set<Int>

    private var allianceState: EmploymentAllianceCache.RowAllianceState {
        allianceCache.state(recordId: recordId)
    }

    var body: some View {
        HStack(spacing: 6) {
            if let icon = allianceCache.icons[corporationId] {
                Image(uiImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(3)
            } else {
                Image(systemName: "building.2.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
                    .foregroundColor(.secondary.opacity(0.6))
                    .frame(width: 32, height: 32)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(3)
            }

            VStack(alignment: .leading, spacing: 2) {
                if isLoadingCorpNames {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text(NSLocalizedString("Misc_Loading", comment: ""))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    HStack(spacing: 4) {
                        if npcCorporationIds.contains(corporationId) {
                            Text("NPC")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(Color(red: 0.7, green: 0.5, blue: 0.9))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color(red: 0.7, green: 0.5, blue: 0.9).opacity(0.15))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(Color(red: 0.7, green: 0.5, blue: 0.9).opacity(0.3), lineWidth: 0.5)
                                )
                        }

                        Text(corporationNamesCache[corporationId] ?? NSLocalizedString("Unknown", comment: ""))
                            .font(.system(size: 12))
                            .lineLimit(1)
                    }
                }

                // 联盟行：活取协调器三态（loading 骨架 / 失败可重试 / 已解析）
                allianceLine

                HStack(spacing: 4) {
                    Text(FormatUtil.formatHistoryDateRange(start: startDate, end: endDate))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text(FormatUtil.formatHistoryDuration(start: startDate, end: endDate))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.clear)
        .contentShape(Rectangle())
        .contextMenu {
            NavigationLink {
                CorporationDetailView(corporationId: corporationId, character: character)
            } label: {
                Label(
                    NSLocalizedString("View Corporation", comment: ""),
                    systemImage: "info.circle"
                )
            }

            if case let .alliance(allianceId) = allianceState {
                NavigationLink {
                    AllianceDetailView(allianceId: allianceId, character: character)
                } label: {
                    Label(
                        NSLocalizedString("View Alliance", comment: ""),
                        systemImage: "info.circle"
                    )
                }
            }
        }
    }

    /// 联盟行：活取加载器结果（loading 骨架 / 失败可重试 / 已解析）
    @ViewBuilder
    private var allianceLine: some View {
        switch allianceState {
        case .none:
            // 已确认当时无联盟，不显示
            EmptyView()
        case .loading:
            HStack(spacing: 4) {
                EntitySkeletonBar(width: 16, height: 16, cornerRadius: 2)
                EntitySkeletonBar(width: 100, height: 12)
            }
        case .failed:
            Button {
                Task { await allianceCache.retry() }
            } label: {
                Text(NSLocalizedString("Misc_Load_Failed", comment: ""))
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                    .lineLimit(1)
            }
            .buttonStyle(.borderless)
        case let .alliance(allianceId):
            HStack(spacing: 4) {
                if let icon = allianceCache.icons[allianceId] {
                    Image(uiImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                        .cornerRadius(2)
                } else {
                    EntitySkeletonBar(width: 16, height: 16, cornerRadius: 2)
                }

                if let name = allianceCache.allianceNames[allianceId] {
                    Text(name)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    EntitySkeletonBar(width: 110, height: 12)
                }
            }
        }
    }
}
