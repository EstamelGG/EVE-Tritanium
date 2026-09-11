import SwiftUI

/// 用于存储星系信息的结构体
struct FWSystemInfo {
    let id: Int
    let security: Double
    let constellationId: Int
    let regionId: Int

    var name: String {
        SDEMemoryStore.solarSystemName(for: id) ?? "System \(id)"
    }

    var constellationName: String {
        SDEMemoryStore.constellationName(for: constellationId) ?? "Constellation \(constellationId)"
    }

    var regionName: String {
        SDEMemoryStore.regionName(for: regionId) ?? "Region \(regionId)"
    }
}

struct InsurgencySystemCell: View {
    let systemInfo: FWSystemInfo
    let insurgency: Insurgency
    let factionIconMap: [Int: String]

    private var hasEnoughWidth: Bool {
        DeviceUtils.screenWidth >= 428 // 只在屏幕宽度大于等于 428 时显示额外信息
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 第一行：星系信息、腐蚀信息、镇压信息
            HStack(spacing: 12) {
                // 左侧星系信息
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(formatSystemSecurity(systemInfo.security))
                            .foregroundColor(getSecurityColor(systemInfo.security))
                            .font(.system(.subheadline, design: .monospaced))
                        // 添加势力图标，仅在屏幕宽度足够时显示
                        if hasEnoughWidth,
                           let occupierFactionId = insurgency.solarSystem.occupierFactionId,
                           let iconName = factionIconMap[occupierFactionId]
                        {
                            IconManager.shared.loadImage(for: iconName)
                                .resizable()
                                .frame(width: 24, height: 24)
                                .cornerRadius(4)
                        }
                        Text(systemInfo.name)
                            .fontWeight(.semibold)
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.string = systemInfo.name
                                } label: {
                                    Label(
                                        NSLocalizedString("Misc_Copy_Location", comment: ""),
                                        systemImage: "doc.on.doc"
                                    )
                                }

                                // 显示名与英文名不同时，追加复制英文名
                                if let enName = SDEMemoryStore.solarSystemEnglishName(
                                    for: systemInfo.id
                                ), enName != systemInfo.name {
                                    Button {
                                        UIPasteboard.general.string = enName
                                    } label: {
                                        Label(
                                            NSLocalizedString("Misc_Copy_Trans", comment: ""),
                                            systemImage: "translate"
                                        )
                                    }
                                }
                            }
                    }

                    if hasEnoughWidth {
                        Text("\(systemInfo.constellationName) / \(systemInfo.regionName)")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    } else {
                        Text(systemInfo.regionName)
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }

                Spacer()

                // 腐蚀状态
                HStack(spacing: 8) {
                    ZStack {
                        // 进度圆环
                        Circle()
                            .stroke(Color(.gray).opacity(0.2), lineWidth: 2)
                            .frame(width: 32, height: 32)

                        // 进度填充
                        Circle()
                            .trim(from: 0, to: CGFloat(insurgency.corruptionPercentage / 100.0))
                            .stroke(
                                Color(red: 142 / 255, green: 243 / 255, blue: 13 / 255),
                                lineWidth: 2
                            )
                            .frame(width: 32, height: 32)
                            .rotationEffect(.degrees(-90))

                        // 腐蚀图标
                        IconManager.shared.loadImage(
                            for: "corruption_\(insurgency.corruptionState)"
                        )
                        .resizable()
                        .frame(width: 24, height: 24)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(insurgency.corruptionState)/5")
                            .foregroundColor(insurgency.corruptionState == 5 ? .red : .secondary)
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(insurgency.corruptionState == 5 ? .semibold : .regular)
                        Text(formatPercentage(insurgency.corruptionPercentage))
                            .foregroundColor(.secondary)
                            .font(.system(.caption, design: .monospaced))
                    }
                }

                // 镇压状态
                HStack(spacing: 8) {
                    ZStack {
                        // 进度圆环
                        Circle()
                            .stroke(Color(.gray).opacity(0.2), lineWidth: 2)
                            .frame(width: 32, height: 32)

                        // 进度填充
                        Circle()
                            .trim(from: 0, to: CGFloat(insurgency.suppressionPercentage / 100.0))
                            .stroke(Color.blue, lineWidth: 2)
                            .frame(width: 32, height: 32)
                            .rotationEffect(.degrees(-90))

                        // 镇压图标
                        IconManager.shared.loadImage(
                            for: "suppression_\(insurgency.suppressionState)"
                        )
                        .resizable()
                        .frame(width: 24, height: 24)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(insurgency.suppressionState)/5")
                            .foregroundColor(.secondary)
                            .font(.system(.caption, design: .monospaced))
                        Text(formatPercentage(insurgency.suppressionPercentage))
                            .foregroundColor(.secondary)
                            .font(.system(.caption, design: .monospaced))
                    }
                }
            }

            // 第二行：星系类型
            if let state = FWSystemStateManager.shared.getSystemState(for: systemInfo.id) {
                Text(NSLocalizedString("Main_system_fw_status", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    + Text(state.systemType.localizedString)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(state.systemType == .frontline ? .red : .secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct InsurgencyView: View {
    let campaigns: [InsurgencyCampaign]
    let databaseManager: DatabaseManager
    let factionName: String
    @State private var originSystemInfo: [Int: FWSystemInfo] = [:]
    @State private var insurgencySystemInfo: [Int: FWSystemInfo] = [:]
    @State private var sortType: SortType = .corruption
    @State private var searchText = ""
    @State private var isSearchActive = false
    @State private var factionIconMap: [Int: String] = [:]
    @State private var isInfoSheetPresented = false
    @Environment(\.colorScheme) private var colorScheme

    private var hasEnoughWidth: Bool {
        DeviceUtils.screenWidth >= 428 // 只在屏幕宽度大于等于 428 时显示额外信息
    }

    enum SortType {
        case corruption
        case suppression
        case name

        var localizedString: String {
            switch self {
            case .corruption:
                return NSLocalizedString("Main_ByCorruption", comment: "Main_ByCorruption")
            case .suppression:
                return NSLocalizedString("Main_BySuppression", comment: "Main_BySuppression")
            case .name: return NSLocalizedString("Main_ByName", comment: "Main_ByName")
            }
        }

        mutating func next() {
            switch self {
            case .corruption: self = .suppression
            case .suppression: self = .name
            case .name: self = .corruption
            }
        }
    }

    /// 计算腐败进度
    private func calculateCorruptionProgress() -> (current: Int, total: Int) {
        let totalThreshold = campaigns.reduce(0) { $0 + $1.corruptionThresHold }
        let completedCount = campaigns.flatMap { $0.insurgencies }
            .filter { $0.corruptionState == 5 }
            .count
        return (completedCount, totalThreshold)
    }

    /// 计算镇压进度
    private func calculateSuppressionProgress() -> (current: Int, total: Int) {
        let totalThreshold = campaigns.reduce(0) { $0 + $1.suppressionThresHold }
        let completedCount = campaigns.flatMap { $0.insurgencies }
            .filter { $0.suppressionState == 5 }
            .count
        return (completedCount, totalThreshold)
    }

    var filteredInsurgencies: [Insurgency] {
        let allInsurgencies = campaigns.flatMap { $0.insurgencies }

        if searchText.isEmpty {
            switch sortType {
            case .corruption:
                return allInsurgencies.sorted { insurgency1, insurgency2 in
                    if insurgency1.corruptionPercentage != insurgency2.corruptionPercentage {
                        return insurgency1.corruptionPercentage > insurgency2.corruptionPercentage
                    }
                    let name1 = insurgencySystemInfo[insurgency1.solarSystem.id]?.name ?? ""
                    let name2 = insurgencySystemInfo[insurgency2.solarSystem.id]?.name ?? ""
                    return name1.localizedStandardCompare(name2) == .orderedAscending
                }
            case .suppression:
                return allInsurgencies.sorted { insurgency1, insurgency2 in
                    if insurgency1.suppressionPercentage != insurgency2.suppressionPercentage {
                        return insurgency1.suppressionPercentage > insurgency2.suppressionPercentage
                    }
                    let name1 = insurgencySystemInfo[insurgency1.solarSystem.id]?.name ?? ""
                    let name2 = insurgencySystemInfo[insurgency2.solarSystem.id]?.name ?? ""
                    return name1.localizedStandardCompare(name2) == .orderedAscending
                }
            case .name:
                return allInsurgencies.sorted { insurgency1, insurgency2 in
                    let name1 = insurgencySystemInfo[insurgency1.solarSystem.id]?.name ?? ""
                    let name2 = insurgencySystemInfo[insurgency2.solarSystem.id]?.name ?? ""
                    return name1.localizedStandardCompare(name2) == .orderedAscending
                }
            }
        }

        // 在内存中搜索匹配的星系
        let filtered = allInsurgencies.filter { insurgency in
            SDEMemoryStore.solarSystemNames[insurgency.solarSystem.id]?.matchesSearch(searchText)
                == true
        }

        switch sortType {
        case .corruption:
            return filtered.sorted { insurgency1, insurgency2 in
                if insurgency1.corruptionPercentage != insurgency2.corruptionPercentage {
                    return insurgency1.corruptionPercentage > insurgency2.corruptionPercentage
                }
                let name1 = insurgencySystemInfo[insurgency1.solarSystem.id]?.name ?? ""
                let name2 = insurgencySystemInfo[insurgency2.solarSystem.id]?.name ?? ""
                return name1.localizedStandardCompare(name2) == .orderedAscending
            }
        case .suppression:
            return filtered.sorted { insurgency1, insurgency2 in
                if insurgency1.suppressionPercentage != insurgency2.suppressionPercentage {
                    return insurgency1.suppressionPercentage > insurgency2.suppressionPercentage
                }
                let name1 = insurgencySystemInfo[insurgency1.solarSystem.id]?.name ?? ""
                let name2 = insurgencySystemInfo[insurgency2.solarSystem.id]?.name ?? ""
                return name1.localizedStandardCompare(name2) == .orderedAscending
            }
        case .name:
            return filtered.sorted { insurgency1, insurgency2 in
                let name1 = insurgencySystemInfo[insurgency1.solarSystem.id]?.name ?? ""
                let name2 = insurgencySystemInfo[insurgency2.solarSystem.id]?.name ?? ""
                return name1.localizedStandardCompare(name2) == .orderedAscending
            }
        }
    }

    var body: some View {
        List {
            if let firstCampaign = campaigns.first {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        // 第一行：势力图标和星系信息
                        HStack(spacing: 12) {
                            // 左侧海盗图标（走内存缓存）
                            if let iconName = SDEMemoryStore.faction(
                                for: firstCampaign.pirateFactionId
                            )?.iconName {
                                IconManager.shared.loadImage(for: iconName)
                                    .resizable()
                                    .frame(width: 64, height: 64)
                                    .cornerRadius(4)
                            }

                            // 右侧星系信息
                            if let systemInfo = originSystemInfo[firstCampaign.originSolarSystem.id] {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 4) {
                                        Text(formatSystemSecurity(systemInfo.security))
                                            .foregroundColor(getSecurityColor(systemInfo.security))
                                            .font(.system(.subheadline, design: .monospaced))
                                        Text(systemInfo.name)
                                            .fontWeight(.semibold)
                                            .contextMenu {
                                                Button {
                                                    UIPasteboard.general.string = systemInfo.name
                                                } label: {
                                                    Label(
                                                        NSLocalizedString(
                                                            "Misc_Copy_Location", comment: ""
                                                        ),
                                                        systemImage: "doc.on.doc"
                                                    )
                                                }

                                                // 显示名与英文名不同时，追加复制英文名
                                                if let enName = SDEMemoryStore
                                                    .solarSystemEnglishName(for: systemInfo.id),
                                                    enName != systemInfo.name
                                                {
                                                    Button {
                                                        UIPasteboard.general.string = enName
                                                    } label: {
                                                        Label(
                                                            NSLocalizedString(
                                                                "Misc_Copy_Trans", comment: ""
                                                            ),
                                                            systemImage: "translate"
                                                        )
                                                    }
                                                }
                                            }
                                    }

                                    if hasEnoughWidth {
                                        Text(
                                            "\(systemInfo.constellationName) / \(systemInfo.regionName)"
                                        )
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                    } else {
                                        Text(systemInfo.regionName)
                                            .foregroundColor(.secondary)
                                            .font(.caption)
                                    }
                                }
                            }
                        }

                        // 腐蚀进度
                        HStack(spacing: 12) {
                            IconManager.shared.loadImage(for: "corruption")
                                .resizable()
                                .frame(width: 32, height: 32)
                                .cornerRadius(4)
                                .brightness(colorScheme == .dark ? 0.3 : 0)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(NSLocalizedString("Main_Corruption_Progress", comment: ""))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                let corruption = calculateCorruptionProgress()
                                ProgressView(
                                    value: Double(corruption.current),
                                    total: Double(corruption.total)
                                )
                                .tint(Color(red: 142 / 255, green: 243 / 255, blue: 13 / 255))
                                Text("\(corruption.current)/\(corruption.total)")
                                    .foregroundColor(.secondary)
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }

                        // 镇压进度
                        HStack {
                            IconManager.shared.loadImage(for: "suppression")
                                .resizable()
                                .frame(width: 32, height: 32)
                                .cornerRadius(4)
                                .brightness(colorScheme == .dark ? 0.3 : 0)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(NSLocalizedString("Main_Suppression_Progress", comment: ""))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                let suppression = calculateSuppressionProgress()
                                ProgressView(
                                    value: Double(suppression.current),
                                    total: Double(suppression.total)
                                )
                                .tint(.blue)
                                Text("\(suppression.current)/\(suppression.total)")
                                    .foregroundColor(.secondary)
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text(NSLocalizedString("Main_Insurgency_FOB", comment: ""))
                        .font(.headline)
                }

                Section {
                    if filteredInsurgencies.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 30))
                                    .foregroundColor(.gray)
                                Text(NSLocalizedString("Misc_No_Data", comment: ""))
                                    .foregroundColor(.gray)
                            }
                            .padding()
                            Spacer()
                        }
                    } else {
                        ForEach(filteredInsurgencies, id: \.solarSystem.id) { insurgency in
                            if let systemInfo = insurgencySystemInfo[insurgency.solarSystem.id] {
                                InsurgencySystemCell(
                                    systemInfo: systemInfo, insurgency: insurgency,
                                    factionIconMap: factionIconMap
                                )
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(NSLocalizedString("Main_Insurgency_System", comment: ""))
                            .font(.headline)
                        Spacer()
                        Button(action: {
                            sortType.next()
                        }) {
                            HStack(spacing: 4) {
                                Text(sortType.localizedString)
                                    .font(.subheadline)
                                Image(systemName: "arrow.up.arrow.down")
                            }
                            .foregroundColor(.blue)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(factionName)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    isInfoSheetPresented = true
                }) {
                    Image(systemName: "info.circle")
                }
            }
        }
        .sheet(isPresented: $isInfoSheetPresented) {
            NavigationView {
                List {
                    Section {
                        Text(NSLocalizedString("Insurgency_info_text", comment: ""))
                            .padding(.vertical, 8)
                    } header: {
                        Text(NSLocalizedString("Insurgency_info", comment: ""))
                            .font(.headline)
                    }

                    Section {
                        HStack(spacing: 8) {
                            IconManager.shared.loadImage(for: "corruption_1")
                                .resizable()
                                .frame(width: 40, height: 40)
                                .cornerRadius(4)
                            Text(
                                String(
                                    format: NSLocalizedString("Insurgency_info_corr_s1", comment: ""),
                                    FormatUtil.formatSignedPercentFrom100(7.5, fractionDigits: 1)
                                )
                            )
                            .font(.body)
                            Spacer()
                        }
                        HStack(spacing: 8) {
                            IconManager.shared.loadImage(for: "suppression_1")
                                .resizable()
                                .frame(width: 40, height: 40)
                                .cornerRadius(4)
                            Text(
                                String(
                                    format: NSLocalizedString("Insurgency_info_supp_s1", comment: ""),
                                    FormatUtil.formatSignedPercentFrom100(5, fractionDigits: 0)
                                )
                            )
                            .font(.body)
                            Spacer()
                        }
                    } header: {
                        Text(String.localizedStringWithFormat(NSLocalizedString("Insurgency_stage", comment: ""), 1))
                            .font(.headline)
                    }

                    Section {
                        HStack(spacing: 8) {
                            IconManager.shared.loadImage(for: "corruption_2")
                                .resizable()
                                .frame(width: 40, height: 40)
                                .cornerRadius(4)
                            Text(NSLocalizedString("Insurgency_info_corr_s2", comment: ""))
                                .font(.body)
                            Spacer()
                        }
                        HStack(spacing: 8) {
                            IconManager.shared.loadImage(for: "suppression_2")
                                .resizable()
                                .frame(width: 40, height: 40)
                                .cornerRadius(4)
                            Text(
                                String(
                                    format: NSLocalizedString("Insurgency_info_supp_s2", comment: ""),
                                    FormatUtil.formatSignedPercentFrom100(5, fractionDigits: 0)
                                )
                            )
                            .font(.body)
                            Spacer()
                        }
                    } header: {
                        Text(String.localizedStringWithFormat(NSLocalizedString("Insurgency_stage", comment: ""), 2))
                            .font(.headline)
                    }

                    Section {
                        HStack(spacing: 8) {
                            IconManager.shared.loadImage(for: "corruption_3")
                                .resizable()
                                .frame(width: 40, height: 40)
                                .cornerRadius(4)
                            Text(NSLocalizedString("Insurgency_info_corr_s3", comment: ""))
                                .font(.body)
                            Spacer()
                        }
                        HStack(spacing: 8) {
                            IconManager.shared.loadImage(for: "suppression_3")
                                .resizable()
                                .frame(width: 40, height: 40)
                                .cornerRadius(4)
                            Text(
                                String(
                                    format: NSLocalizedString("Insurgency_info_supp_s3", comment: ""),
                                    FormatUtil.formatSignedPercentFrom100(-30, fractionDigits: 0)
                                )
                            )
                            .font(.body)
                            Spacer()
                        }
                    } header: {
                        Text(String.localizedStringWithFormat(NSLocalizedString("Insurgency_stage", comment: ""), 3))
                            .font(.headline)
                    }

                    Section {
                        HStack(spacing: 8) {
                            IconManager.shared.loadImage(for: "corruption_4")
                                .resizable()
                                .frame(width: 40, height: 40)
                                .cornerRadius(4)
                            Text(NSLocalizedString("Insurgency_info_corr_s4", comment: ""))
                                .font(.body)
                            Spacer()
                        }
                        HStack(spacing: 8) {
                            IconManager.shared.loadImage(for: "suppression_4")
                                .resizable()
                                .frame(width: 40, height: 40)
                                .cornerRadius(4)
                            Text(
                                String(
                                    format: NSLocalizedString("Insurgency_info_supp_s4", comment: ""),
                                    FormatUtil.formatSignedPercentFrom100(10, fractionDigits: 0)
                                )
                            )
                            .font(.body)
                            Spacer()
                        }
                    } header: {
                        Text(String.localizedStringWithFormat(NSLocalizedString("Insurgency_stage", comment: ""), 4))
                            .font(.headline)
                    }

                    Section {
                        HStack(spacing: 8) {
                            IconManager.shared.loadImage(for: "corruption_5")
                                .resizable()
                                .frame(width: 40, height: 40)
                                .cornerRadius(4)
                            Text(NSLocalizedString("Insurgency_info_corr_s5", comment: ""))
                                .font(.body)
                            Spacer()
                        }
                        HStack(spacing: 8) {
                            IconManager.shared.loadImage(for: "suppression_5")
                                .resizable()
                                .frame(width: 40, height: 40)
                                .cornerRadius(4)
                            Text(NSLocalizedString("Insurgency_info_supp_s5", comment: ""))
                                .font(.body)
                            Spacer()
                        }
                    } header: {
                        Text(String.localizedStringWithFormat(NSLocalizedString("Insurgency_stage", comment: ""), 5))
                            .font(.headline)
                    }
                }
                .navigationTitle(NSLocalizedString("Insurgency_info", comment: ""))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            isInfoSheetPresented = false
                        } label: {
                            Image(systemName: "xmark")
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
        }
        .searchable(
            text: $searchText,
            isPresented: $isSearchActive,
            // placement: .navigationBarDrawer(displayMode: .always),
            prompt: NSLocalizedString("System_Search_Placeholder", comment: "")
        )
        .task {
            // 获取所有需要查询的星系ID
            let originSystemIds = campaigns.map { $0.originSolarSystem.id }
            let insurgencySystemIds = campaigns.flatMap { $0.insurgencies }.map {
                $0.solarSystem.id
            }

            // 一次性获取所有星系信息
            let originSystemInfoMap = await getBatchSolarSystemInfo(
                solarSystemIds: originSystemIds,
                databaseManager: databaseManager
            )

            let insurgencySystemInfoMap = await getBatchSolarSystemInfo(
                solarSystemIds: insurgencySystemIds,
                databaseManager: databaseManager
            )

            // 获取所有不重复的占领势力ID
            let occupierFactionIds = Set(
                campaigns.flatMap { $0.insurgencies }
                    .compactMap { $0.solarSystem.occupierFactionId }
            )

            // 势力图标走内存缓存
            for factionId in occupierFactionIds {
                if let iconName = SDEMemoryStore.faction(for: factionId)?.iconName {
                    factionIconMap[factionId] = iconName
                }
            }

            // 更新星系信息
            for (id, info) in originSystemInfoMap {
                originSystemInfo[id] = FWSystemInfo(
                    id: id,
                    security: info.security,
                    constellationId: info.constellationId,
                    regionId: info.regionId
                )
            }

            for (id, info) in insurgencySystemInfoMap {
                insurgencySystemInfo[id] = FWSystemInfo(
                    id: id,
                    security: info.security,
                    constellationId: info.constellationId,
                    regionId: info.regionId
                )
            }
        }
    }
}

/// 在 InsurgencyView 结构体外部添加格式化函数
private func formatPercentage(_ value: Double) -> String {
    if value >= 100 {
        return "100 %"
    } else if value >= 10 {
        let formatted = String(format: "%.1f%%", value)
        return formatted.hasSuffix(".0%") ? String(format: "%.1f%%", value) : formatted
    } else if value >= 1 {
        let formatted = String(format: "%.1f%%", value)
        return formatted.hasSuffix(".0%")
            ? String(format: "%.1f %%", value) : String(format: "%.1f %%", value)
    } else {
        return String(format: "%.2f%%", value)
    }
}
