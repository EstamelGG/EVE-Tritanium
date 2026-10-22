
//  MiningVolumeCharts.swift
//  EVE Nexus

//  Created on 2025/01/XX.
//  挖矿体积图表视图组件，用于显示按星系、人物、矿石类型分组的挖矿体积数据

import Charts
import SwiftUI

// MARK: - 图表配置常量

/// 图表最大显示数据点数量（避免纹理创建失败）
let MAX_CHART_DATA_POINTS = 50

// MARK: - 颜色工具

/// 加深颜色
func darkenColor(_ color: Color, factor: CGFloat) -> Color {
    // 将 SwiftUI Color 转换为 UIColor 以提取 RGB 值
    let uiColor = UIColor(color)
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0

    uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

    // 应用暗化因子
    return Color(red: red * factor, green: green * factor, blue: blue * factor, opacity: alpha)
}

// MARK: - 各星系挖矿量图表（横向柱状图）

struct MiningSystemVolumeChartView: View {
    let entries: [MiningLedgerEntryWithOwner]
    let itemVolumes: [Int: Double]
    let solarSystemNames: [Int: String]
    let solarSystemSecurities: [Int: Double]
    let dataCount: Int // 数据点数量，用于计算固定高度
    let sortType: MiningChartSortType
    let marketPrices: [Int: MarketPriceData]

    /// 计算各星系的数据（体积/数量/估价）
    private var systemData: [(systemId: Int, systemName: String, security: Double?, value: Double)] {
        var dataBySystem: [Int: (volume: Double, quantity: Int64, price: Double)] = [:]

        for entryWithOwner in entries {
            let entry = entryWithOwner.entry
            let volume = itemVolumes[entry.type_id] ?? 0.0
            let totalVolume = Double(entry.quantity) * volume
            let totalQuantity = entry.quantity
            let priceData = marketPrices[entry.type_id]
            let totalPrice = (priceData?.averagePrice ?? 0.0) * Double(entry.quantity)

            let existing = dataBySystem[entry.solar_system_id] ?? (0.0, Int64(0), 0.0)
            dataBySystem[entry.solar_system_id] = (
                volume: existing.volume + totalVolume,
                quantity: existing.quantity + Int64(totalQuantity),
                price: existing.price + totalPrice
            )
        }

        return dataBySystem.map { systemId, data in
            let systemName = solarSystemNames[systemId] ?? "System \(systemId)"
            let security = solarSystemSecurities[systemId]
            let value: Double
            switch sortType {
            case .volume:
                value = data.volume
            case .quantity:
                value = Double(data.quantity)
            case .price:
                value = data.price
            }
            return (systemId: systemId, systemName: systemName, security: security, value: value)
        }
        .sorted { $0.value > $1.value } // 按值降序排序
        .prefix(MAX_CHART_DATA_POINTS) // 只显示前N个
        .map { $0 } // 转换为数组
    }

    var body: some View {
        let data = systemData
        if data.isEmpty {
            Text(NSLocalizedString("No_Chart_Data", comment: "无图表数据"))
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            Chart {
                ForEach(Array(data.enumerated()), id: \.element.systemId) { _, item in
                    // 根据安全等级获取颜色并加深
                    let baseColor = item.security.map { getSecurityColor($0) } ?? .blue
                    let barColor = darkenColor(baseColor, factor: 0.7)
                    BarMark(
                        x: .value("Value", item.value),
                        y: .value("System", item.systemName)
                    )
                    .foregroundStyle(barColor.gradient)
                    .annotation(position: .trailing) {
                        Text(formatValue(item.value))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .chartYScale(type: .category)
            .chartXAxis {
                AxisMarks(position: .bottom) { value in
                    if let val = value.as(Double.self) {
                        AxisValueLabel {
                            Text(formatValue(val))
                                .font(.caption2)
                        }
                        AxisGridLine()
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    if let systemName = value.as(String.self) {
                        AxisValueLabel {
                            // 查找对应的安全等级
                            let systemInfo = data.first { $0.systemName == systemName }
                            if let security = systemInfo?.security {
                                HStack(spacing: 4) {
                                    Text(formatSystemSecurity(security))
                                        .foregroundColor(getSecurityColor(security))
                                        .font(.system(.caption2, design: .monospaced))
                                    Text(systemName)
                                        .font(.caption2)
                                        .foregroundColor(.primary)
                                }
                            } else {
                                Text(systemName)
                                    .font(.caption2)
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                }
            }
        }
    }

    /// 格式化显示值
    private func formatValue(_ value: Double) -> String {
        switch sortType {
        case .volume:
            return "\(FormatUtil.format(value)) m³"
        case .quantity:
            return FormatUtil.format(value)
        case .price:
            return FormatUtil.formatISK(value)
        }
    }
}

// MARK: - 各人物挖矿量图表（横向柱状图）

struct MiningCharacterVolumeChartView: View {
    let entries: [MiningLedgerEntryWithOwner]
    let itemVolumes: [Int: Double]
    let dataCount: Int // 数据点数量，用于计算固定高度
    let sortType: MiningChartSortType
    let marketPrices: [Int: MarketPriceData]

    @State private var characterPortraits: [Int: UIImage] = [:] // 角色头像缓存

    /// 获取所有角色信息
    private var allCharacters: [(id: Int, name: String)] {
        CharacterSkillsUtils.getAllCharacters()
    }

    /// 计算各人物的数据（体积/数量/估价）
    private var characterData: [(characterId: Int, characterName: String, value: Double)] {
        var dataByCharacter: [Int: (volume: Double, quantity: Int64, price: Double)] = [:]

        for entryWithOwner in entries {
            let entry = entryWithOwner.entry
            let volume = itemVolumes[entry.type_id] ?? 0.0
            let totalVolume = Double(entry.quantity) * volume
            let totalQuantity = entry.quantity
            let priceData = marketPrices[entry.type_id]
            let totalPrice = (priceData?.averagePrice ?? 0.0) * Double(entry.quantity)

            let existing = dataByCharacter[entryWithOwner.ownerId] ?? (0.0, Int64(0), 0.0)
            dataByCharacter[entryWithOwner.ownerId] = (
                volume: existing.volume + totalVolume,
                quantity: existing.quantity + Int64(totalQuantity),
                price: existing.price + totalPrice
            )
        }

        let characters = allCharacters
        return dataByCharacter.map { characterId, data in
            let characterName = characters.first(where: { $0.id == characterId })?.name ?? "Character \(characterId)"
            let value: Double
            switch sortType {
            case .volume:
                value = data.volume
            case .quantity:
                value = Double(data.quantity)
            case .price:
                value = data.price
            }
            return (characterId: characterId, characterName: characterName, value: value)
        }
        .sorted { $0.value > $1.value } // 按值降序排序
        .prefix(MAX_CHART_DATA_POINTS) // 只显示前N个
        .map { $0 } // 转换为数组
    }

    var body: some View {
        let data = characterData
        Group {
            if data.isEmpty {
                Text(NSLocalizedString("No_Chart_Data", comment: "无图表数据"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Chart {
                    ForEach(Array(data.enumerated()), id: \.element.characterId) { _, item in
                        // 使用浅蓝色并加深
                        let baseColor = Color(red: 115 / 255, green: 203 / 255, blue: 244 / 255) // 浅蓝色
                        let barColor = darkenColor(baseColor, factor: 0.7)
                        BarMark(
                            x: .value("Value", item.value),
                            y: .value("Character", item.characterName)
                        )
                        .foregroundStyle(barColor.gradient)
                        .annotation(position: .trailing) {
                            Text(formatValue(item.value))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .chartYScale(type: .category)
                .chartXAxis {
                    AxisMarks(position: .bottom) { value in
                        if let val = value.as(Double.self) {
                            AxisValueLabel {
                                Text(formatValue(val))
                                    .font(.caption2)
                            }
                            AxisGridLine()
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        if let characterName = value.as(String.self) {
                            AxisValueLabel {
                                // 查找对应的角色ID和头像
                                let characterInfo = data.first { $0.characterName == characterName }
                                if let characterId = characterInfo?.characterId {
                                    HStack(spacing: 4) {
                                        // 显示角色头像
                                        if let portrait = characterPortraits[characterId] {
                                            Image(uiImage: portrait)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 12, height: 12)
                                                .clipShape(Circle())
                                        } else {
                                            Circle()
                                                .fill(Color.gray.opacity(0.2))
                                                .frame(width: 12, height: 12)
                                        }
                                        Text(characterName)
                                            .font(.caption2)
                                            .foregroundColor(.primary)
                                    }
                                } else {
                                    Text(characterName)
                                        .font(.caption2)
                                        .foregroundColor(.primary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .task(id: data.map(\.characterId).sorted()) {
            // 加载所有角色的头像
            let characterIds = Set(data.map { $0.characterId })
            await loadCharacterPortraits(characterIds: Array(characterIds))
        }
    }

    /// 格式化显示值
    private func formatValue(_ value: Double) -> String {
        switch sortType {
        case .volume:
            return "\(FormatUtil.format(value)) m³"
        case .quantity:
            return FormatUtil.format(value)
        case .price:
            return FormatUtil.formatISK(value)
        }
    }

    /// 加载角色头像
    private func loadCharacterPortraits(characterIds: [Int]) async {
        for characterId in characterIds {
            // 在主线程上检查是否已经加载过
            let alreadyLoaded = await MainActor.run {
                characterPortraits[characterId] != nil
            }
            if alreadyLoaded {
                continue
            }

            do {
                let portrait = try await CharacterAPI.shared.fetchCharacterPortrait(
                    characterId: characterId,
                    size: 32,
                    forceRefresh: false
                )
                await MainActor.run {
                    characterPortraits[characterId] = portrait
                }
            } catch {
                // 加载失败时使用默认头像（已在UI中处理）
            }
        }
    }
}

// MARK: - 各矿石类型挖矿量图表（横向柱状图）

struct MiningOreTypeVolumeChartView: View {
    let entries: [MiningItemSummary]
    let itemVolumes: [Int: Double]
    let dataCount: Int // 数据点数量，用于计算固定高度
    let sortType: MiningChartSortType
    let marketPrices: [Int: MarketPriceData]
    let databaseColors: [Int: Color] // 从数据库预加载的矿石颜色

    @State private var itemIcons: [Int: Image] = [:] // 矿石图标缓存
    @State private var itemColors: [Int: Color] = [:] // 矿石颜色缓存（优先使用数据库颜色，否则从图标中心点采样）

    /// 计算各矿石类型的数据（体积/数量/估价）
    private var oreTypeData: [(typeId: Int, name: String, iconFileName: String, value: Double)] {
        entries.map { entry in
            let volume = itemVolumes[entry.id] ?? 0.0
            let totalVolume = Double(entry.totalQuantity) * volume
            let totalQuantity = Double(entry.totalQuantity)
            let priceData = marketPrices[entry.id]
            let totalPrice = (priceData?.averagePrice ?? 0.0) * Double(entry.totalQuantity)

            let value: Double
            switch sortType {
            case .volume:
                value = totalVolume
            case .quantity:
                value = totalQuantity
            case .price:
                value = totalPrice
            }
            return (typeId: entry.id, name: entry.name, iconFileName: entry.iconFileName, value: value)
        }
        .sorted { $0.value > $1.value } // 按值降序排序
        .prefix(MAX_CHART_DATA_POINTS) // 只显示前N个
        .map { $0 } // 转换为数组
    }

    var body: some View {
        let data = oreTypeData
        Group {
            if data.isEmpty {
                Text(NSLocalizedString("No_Chart_Data", comment: "无图表数据"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Chart {
                    ForEach(Array(data.enumerated()), id: \.element.typeId) { _, item in
                        // 从图标提取主题色，如果没有则使用默认绿色，并加深
                        let baseColor = itemColors[item.typeId] ?? .green
                        let barColor = darkenColor(baseColor, factor: 0.7)
                        BarMark(
                            x: .value("Value", item.value),
                            y: .value("Ore", item.name)
                        )
                        .foregroundStyle(barColor.gradient)
                        .annotation(position: .trailing) {
                            Text(formatValue(item.value))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .chartYScale(type: .category)
                .chartXAxis {
                    AxisMarks(position: .bottom) { value in
                        if let val = value.as(Double.self) {
                            AxisValueLabel {
                                Text(formatValue(val))
                                    .font(.caption2)
                            }
                            AxisGridLine()
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        if let oreName = value.as(String.self) {
                            AxisValueLabel {
                                // 查找对应的矿石ID和图标
                                let oreInfo = data.first { $0.name == oreName }
                                if let typeId = oreInfo?.typeId {
                                    HStack(spacing: 4) {
                                        // 显示矿石图标
                                        if let icon = itemIcons[typeId] {
                                            icon
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .frame(width: 16, height: 16)
                                        } else {
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(Color.gray.opacity(0.2))
                                                .frame(width: 16, height: 16)
                                        }
                                        Text(oreName)
                                            .font(.caption2)
                                            .foregroundColor(.primary)
                                    }
                                } else {
                                    Text(oreName)
                                        .font(.caption2)
                                        .foregroundColor(.primary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .task {
            // 加载所有矿石的图标并提取主题色
            // 此时 databaseColors 已经加载完成（因为视图只在颜色加载完成后才显示）
            for entry in entries {
                if itemIcons[entry.id] == nil {
                    let icon = IconManager.shared.loadImage(for: entry.iconFileName)
                    itemIcons[entry.id] = icon
                }

                // 优先使用数据库中的颜色，如果没有则从图标提取主题色
                if let dbColor = databaseColors[entry.id] {
                    Logger.debug("使用数据库颜色: typeId=\(entry.id)")
                    await MainActor.run {
                        itemColors[entry.id] = dbColor
                    }
                } else {
                    // 从图标提取主题色作为兜底
                    Logger.debug("数据库中没有找到颜色，将从图标提取: typeId=\(entry.id)")
                    Logger.info("从图标提取主题色: \(entry.iconFileName)")
                    let uiImage = IconManager.shared.loadUIImage(for: entry.iconFileName)
                    if let themeColor = uiImage.computeThemeColor() {
                        await MainActor.run {
                            itemColors[entry.id] = themeColor.primaryColor
                        }
                    } else {
                        // 如果提取失败，使用默认颜色
                        await MainActor.run {
                            itemColors[entry.id] = .green
                        }
                    }
                }
            }
        }
    }

    /// 格式化显示值
    private func formatValue(_ value: Double) -> String {
        switch sortType {
        case .volume:
            return "\(FormatUtil.format(value)) m³"
        case .quantity:
            return FormatUtil.format(value)
        case .price:
            return FormatUtil.formatISK(value)
        }
    }
}
