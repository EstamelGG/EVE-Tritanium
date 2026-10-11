import SwiftUI

private let attributeRowInsets = EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)

/// 图标 + 标题 + 右侧数值的通用属性行
private struct AttributeMetricRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack {
            Image(icon)
                .resizable()
                .frame(width: 32, height: 32)
            Text(title)
                .font(.body)
            Spacer()
            Text(value)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Resistance Bar

/// 抗性条显示组件
struct ResistanceBarView: View {
    let resistances: [Double]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(DamageTypePalette.resistanceIcons.indices, id: \.self) { index in
                ResistanceColumn(
                    iconName: DamageTypePalette.resistanceIcons[index],
                    color: DamageTypePalette.colors[index],
                    value: resistances[index]
                )
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ResistanceColumn: View {
    let iconName: String
    let color: Color
    let value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 2) {
                Image(iconName)
                    .resizable()
                    .frame(width: 20, height: 20)
                Text("\(Self.roundedPercentage(value))%")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(height: 24)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(color.opacity(0.8))
                        .overlay(Color.black.opacity(0.5))
                        .frame(width: geometry.size.width)
                    Rectangle()
                        .fill(color)
                        .saturation(1.2)
                        .brightness(0.1)
                        .frame(width: geometry.size.width * CGFloat(value) / 100)
                }
            }
            .frame(height: 16)
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .frame(maxWidth: .infinity)
    }

    private static func roundedPercentage(_ value: Double) -> String {
        String(format: "%.2f", value)
            .replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
    }
}

// MARK: - Attribute Item

/// 单个属性的显示组件
struct AttributeItemView: View {
    private enum UnitID {
        static let group = 115
        static let type = 116
        static let attribute = 119
    }

    let attribute: DogmaAttribute
    let allAttributes: [Int: Double]
    @ObservedObject var databaseManager: DatabaseManager

    private var isNavigable: Bool {
        attribute.unitID == UnitID.group || attribute.unitID == UnitID.type
    }

    private var resolvedID: Int? {
        allAttributes[attribute.id].map { Int($0) }
    }

    private var displayName: String {
        guard let id = resolvedID else { return "" }
        let unknown = NSLocalizedString("Main_Database_Unknown", comment: "未知")
        switch attribute.unitID {
        case UnitID.group:
            return databaseManager.getGroupName(for: id) ?? unknown
        case UnitID.type:
            return databaseManager.getTypeName(for: id) ?? unknown
        case UnitID.attribute:
            return databaseManager.getAttributeName(for: id) ?? unknown
        default:
            return ""
        }
    }

    private var formattedValue: String {
        formatTransformedValue(using: allAttributes) ?? ""
    }

    private var formattedModifiedValue: String? {
        guard let modifiedValue = attribute.modifiedValue else { return nil }
        var attrs = allAttributes
        attrs[attribute.id] = modifiedValue
        return formatTransformedValue(using: attrs)
    }

    private var isModifiedValueBetter: Bool? {
        guard let modifiedValue = attribute.modifiedValue,
              modifiedValue != attribute.value
        else { return nil }
        return attribute.highIsGood
            ? modifiedValue > attribute.value
            : modifiedValue < attribute.value
    }

    private var modifiedValueColor: Color {
        switch isModifiedValueBetter {
        case true: .green
        case false: .red
        case nil: .secondary
        }
    }

    var body: some View {
        if AttributeDisplayConfig.shouldShowAttribute(attribute.id, attribute: attribute) {
            if isNavigable, let id = resolvedID {
                NavigationLink {
                    navigableDestination(id: id)
                } label: {
                    defaultAttributeView
                        .foregroundStyle(.primary)
                }
            } else {
                defaultAttributeView
                    .attributeInfluences([attribute.id])
            }
        }
    }

    private var defaultAttributeView: some View {
        HStack {
            if attribute.iconID != 0 {
                IconManager.shared.loadImage(for: attribute.iconFileName)
                    .resizable()
                    .frame(width: 32, height: 32)
            }

            Text(attribute.displayTitle)
                .font(.body)

            Spacer()

            trailingValueView
        }
    }

    @ViewBuilder
    private var trailingValueView: some View {
        if attribute.unitID == UnitID.attribute {
            Text(displayName)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        } else if isNavigable {
            Text(displayName)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        } else if let modified = formattedModifiedValue {
            Text(modified)
                .font(.body)
                .foregroundColor(modifiedValueColor)
                .multilineTextAlignment(.trailing)
        } else {
            Text(formattedValue)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    private func navigableDestination(id: Int) -> some View {
        if attribute.unitID == UnitID.group {
            DatabaseBrowserView(
                databaseManager: databaseManager,
                level: .items(
                    groupID: id,
                    groupName: databaseManager.getGroupName(for: id)
                        ?? NSLocalizedString("Main_Database_Unknown", comment: "未知")
                )
            )
        } else {
            ShowItemInfo(databaseManager: databaseManager, itemID: id)
        }
    }

    private func formatTransformedValue(using attrs: [Int: Double]) -> String? {
        let result = AttributeDisplayConfig.transformValue(
            attribute.id, allAttributes: attrs, unitID: attribute.unitID, applyCalculations: false
        )
        switch result {
        case let .number(value, unit):
            if attribute.unitID == UnitID.group || attribute.unitID == UnitID.type {
                return ""
            }
            return unit.map { "\(FormatUtil.format(value))\($0)" } ?? FormatUtil.format(value)
        case let .text(str):
            return str
        case .resistance:
            return nil
        }
    }
}

// MARK: - Attribute Group

/// 属性组的显示组件
struct AttributeGroupView: View {
    static let damageAttributeIDs: Set<Int> = [114, 118, 117, 116]
    private static let missileAttributeID = 507
    private static let missileRateOfFireID = 506
    private static let weaponRateOfFireID = 51
    private static let flightTimeID = 281
    private static let flightSpeedID = 37
    private static let speedMultiplierID = 645
    private static let timeMultiplierID = 646

    let group: AttributeGroup
    let allAttributes: [Int: Double]
    let typeID: Int
    @ObservedObject var databaseManager: DatabaseManager

    private var filteredAttributes: [DogmaAttribute] {
        group.attributes
            .filter { AttributeDisplayConfig.shouldShowAttribute($0.id, attribute: $0) }
            .sorted { lhs, rhs in
                let order1 = AttributeDisplayConfig.getAttributeOrder(attributeID: lhs.id, in: group.id)
                let order2 = AttributeDisplayConfig.getAttributeOrder(attributeID: rhs.id, in: group.id)
                return order1 == order2 ? lhs.id < rhs.id : order1 < order2
            }
    }

    private var hasMissileAttribute: Bool {
        group.attributes.contains { $0.id == Self.missileAttributeID }
    }

    var hasWeaponDamageAttributes: Bool {
        group.attributes.contains { Self.damageAttributeIDs.contains($0.id) }
    }

    private var resistances: [Double]? {
        AttributeDisplayConfig.getResistanceValues(groupID: group.id, from: allAttributes)
    }

    private var shouldShow: Bool {
        AttributeDisplayConfig.shouldShowGroup(group.id)
            && (!filteredAttributes.isEmpty
                || resistances != nil
                || (hasMissileAttribute && getMissileInfo() != nil)
                || (hasWeaponDamageAttributes && getWeaponInfo() != nil))
    }

    var body: some View {
        if shouldShow {
            Section {
                if let resistances {
                    ResistanceBarView(resistances: resistances)
                }

                ForEach(filteredAttributes) { attribute in
                    AttributeItemView(
                        attribute: attribute,
                        allAttributes: allAttributes,
                        databaseManager: databaseManager
                    )
                    .listRowInsets(attributeRowInsets)
                }

                // Keep the combined warp-speed presentation alongside its individual inputs.
                if group.attributes.contains(where: { $0.id == 1281 }),
                   let baseWarpSpeed = allAttributes[1281], let multiplier = allAttributes[600]
                {
                    AttributeMetricRow(icon: "warp_speed",
                                       title: NSLocalizedString("Fitting_warp_speed", comment: "跃迁速度"),
                                       value: "\(FormatUtil.format(baseWarpSpeed * multiplier)) AU/s")
                        .listRowInsets(attributeRowInsets)
                }

                if hasMissileAttribute {
                    missileInfoView()
                        .listRowInsets(attributeRowInsets)

                    if let dph = getMissileDPH() {
                        AttributeMetricRow(icon: "dps", title: "DPH", value: "\(FormatUtil.format(dph)) HP")
                            .listRowInsets(attributeRowInsets)
                    }
                    if let dps = getMissileDPS() {
                        AttributeMetricRow(icon: "dps", title: "DPS", value: "\(FormatUtil.format(dps)) HP/s")
                            .listRowInsets(attributeRowInsets)
                    }
                    if let range = getMissileRange() {
                        AttributeMetricRow(
                            icon: "target_range",
                            title: NSLocalizedString("Fitting_range", comment: "射程"),
                            value: Self.formatDistance(range)
                        )
                        .listRowInsets(attributeRowInsets)
                    }
                }

                if hasWeaponDamageAttributes {
                    weaponDamageView()
                        .listRowInsets(attributeRowInsets)

                    if let dph = getWeaponDPH() {
                        AttributeMetricRow(icon: "dps", title: "DPH", value: "\(FormatUtil.format(dph)) HP")
                            .listRowInsets(attributeRowInsets)
                    }
                    if let dps = getWeaponDPS() {
                        AttributeMetricRow(icon: "dps", title: "DPS", value: "\(FormatUtil.format(dps)) HP/s")
                            .listRowInsets(attributeRowInsets)
                    }
                    if !hasMissileAttribute, let range = getMissileRange() {
                        AttributeMetricRow(
                            icon: "target_range",
                            title: NSLocalizedString("Fitting_range", comment: "射程"),
                            value: Self.formatDistance(range)
                        )
                        .listRowInsets(attributeRowInsets)
                    }
                }
            } header: {
                Text(group.name)
                    .font(.headline)
            }
        }
    }

    // MARK: Calculations

    private func getMissileDPH() -> Double? {
        guard let damages = getMissileInfo()?.actualDamages else { return nil }
        let total = Self.sumDamage(damages)
        return total > 0 ? total : nil
    }

    private func getWeaponDPH() -> Double? {
        guard let damages = getWeaponInfo()?.actualDamages else { return nil }
        let total = Self.sumDamage(damages)
        return total > 0 ? total : nil
    }

    private func getMissileDPS() -> Double? {
        guard let rateOfFire = allAttributes[Self.missileRateOfFireID],
              let damages = getMissileInfo()?.actualDamages
        else { return nil }
        return Self.dps(totalDamage: Self.sumDamage(damages), rateOfFireMs: rateOfFire)
    }

    private func getWeaponDPS() -> Double? {
        guard let rateOfFire = allAttributes[Self.weaponRateOfFireID],
              let damages = getWeaponInfo()?.actualDamages
        else { return nil }
        return Self.dps(totalDamage: Self.sumDamage(damages), rateOfFireMs: rateOfFire)
    }

    /// 导弹/投射物射程。飞行时间或速度缺失时返回 nil。
    private func getMissileRange() -> Double? {
        if let missileInfo = getMissileInfo(),
           let baseFlightTime = missileInfo.flightTime,
           let baseFlightSpeed = missileInfo.flightSpeed,
           let range = Self.flightRange(
               baseTimeMs: baseFlightTime,
               baseSpeed: baseFlightSpeed,
               speedMultiplier: allAttributes[Self.speedMultiplierID] ?? 1.0,
               timeMultiplier: allAttributes[Self.timeMultiplierID] ?? 1.0
           )
        {
            return range
        }

        guard let baseFlightTime = allAttributes[Self.flightTimeID],
              let baseFlightSpeed = allAttributes[Self.flightSpeedID]
        else { return nil }

        return Self.flightRange(
            baseTimeMs: baseFlightTime,
            baseSpeed: baseFlightSpeed,
            speedMultiplier: allAttributes[Self.speedMultiplierID] ?? 1.0,
            timeMultiplier: allAttributes[Self.timeMultiplierID] ?? 1.0
        )
    }

    private static func sumDamage(_ d: (em: Double, therm: Double, kin: Double, exp: Double)) -> Double {
        d.em + d.therm + d.kin + d.exp
    }

    private static func dps(totalDamage: Double, rateOfFireMs: Double) -> Double? {
        guard rateOfFireMs > 0 else { return nil }
        return totalDamage / (rateOfFireMs / 1000.0)
    }

    private static func flightRange(
        baseTimeMs: Double,
        baseSpeed: Double,
        speedMultiplier: Double,
        timeMultiplier: Double
    ) -> Double? {
        guard baseTimeMs > 0, baseSpeed > 0 else { return nil }
        let range = (baseSpeed * speedMultiplier) * (baseTimeMs * timeMultiplier / 1000.0)
        return range > 0 ? range : nil
    }

    /// ≥1km 用 km（最多 2 位小数），否则用 m
    private static func formatDistance(_ distance: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0

        if distance >= 1000 {
            formatter.maximumFractionDigits = 2
            let formatted = formatter.string(from: NSNumber(value: distance / 1000.0)) ?? "0"
            return "\(formatted) km"
        }
        formatter.maximumFractionDigits = 0
        let formatted = formatter.string(from: NSNumber(value: distance)) ?? "0"
        return "\(formatted) m"
    }
}

// MARK: - Attributes View

/// 所有属性组的显示组件
struct AttributesView: View {
    private static let derivativeOreAttributeID = 2711
    private static let skillRequirementsGroupID = 8
    /// 舰载机能力属性分组 id（dogmaAttributeCategories.attribute_category_id=34）
    private static let fighterAbilitiesGroupID = 34

    let attributeGroups: [AttributeGroup]
    let typeID: Int
    @ObservedObject var databaseManager: DatabaseManager

    private var allAttributes: [Int: Double] {
        var dict: [Int: Double] = [:]
        for group in attributeGroups {
            for attribute in group.attributes {
                dict[attribute.id] = attribute.modifiedValue ?? attribute.value
            }
        }
        return dict
    }

    private var sortedGroups: [AttributeGroup] {
        attributeGroups.sorted {
            AttributeDisplayConfig.getGroupOrder($0.id) < AttributeDisplayConfig.getGroupOrder($1.id)
        }
    }

    private var derivativeOreValue: Double? {
        attributeGroups
            .lazy
            .flatMap(\.attributes)
            .first { $0.id == Self.derivativeOreAttributeID }?
            .value
    }

    private var fighterAbilities: [SDEMemoryStore.FighterAbilityInfo] {
        SDEMemoryStore.fighterAbilities(for: typeID)
    }

    /// 是否已存在 id==34 的属性分组（决定 fighter abilities section 的插入位置）
    private var hasFighterAbilitiesGroup: Bool {
        sortedGroups.contains { $0.id == Self.fighterAbilitiesGroupID }
    }

    // MARK: - 指挥脉冲波 / 作战链 buff

    @State private var warfareBuffPairs: [(Int, Double)] = []

    var body: some View {
        Group {
            ForEach(sortedGroups) { group in
                if group.id == Self.skillRequirementsGroupID {
                    SkillRequirementsView(
                        typeID: typeID, groupName: group.name, databaseManager: databaseManager
                    )
                }
                AttributeGroupView(
                    group: group,
                    allAttributes: allAttributes,
                    typeID: typeID,
                    databaseManager: databaseManager
                )
                // 紧跟在 id==34 的属性分组之后展示舰载机能力概览
                if group.id == Self.fighterAbilitiesGroupID && !fighterAbilities.isEmpty {
                    FighterAbilitiesSection(abilities: fighterAbilities)
                }
            }

            // 无 id==34 分组但有数据时，放到所有属性分组之后
            if !fighterAbilities.isEmpty && !hasFighterAbilitiesGroup {
                FighterAbilitiesSection(abilities: fighterAbilities)
            }

            // 指挥脉冲波 / 作战链加成
            if !warfareBuffPairs.isEmpty {
                WarfareBuffSection(typeID: typeID, buffs: warfareBuffPairs)
            }

            if let value = derivativeOreValue {
                let items = databaseManager.getItemsByAttributeValue(
                    attributeID: Self.derivativeOreAttributeID, value: value
                )
                if !items.isEmpty {
                    Section(
                        header: Text(NSLocalizedString("Main_Ore_Variations", comment: "")).font(.headline)
                    ) {
                        ForEach(items, id: \.typeID) { item in
                            NavigationLink {
                                ShowItemInfo(databaseManager: databaseManager, itemID: item.typeID)
                            } label: {
                                HStack {
                                    IconManager.shared.loadImage(for: item.iconFileName)
                                        .resizable()
                                        .frame(width: 32, height: 32)
                                    Text(item.name)
                                        .foregroundColor(.primary)
                                }
                            }
                            .listRowInsets(attributeRowInsets)
                        }
                    }
                }
            }
        }
        .task {
            loadWarfareBuffs()
        }
    }

    /// 按 attribute_key 模式查询 warfareBuff* 属性并解析配对（覆盖弹药、泰坦现象发生器等一切 dbuff 物品）
    private func loadWarfareBuffs() {
        let query = """
            SELECT da.attribute_key, ta.value
            FROM typeAttributes ta
            JOIN dogmaAttributes da ON ta.attribute_id = da.attribute_id
            WHERE ta.type_id = ? AND da.attribute_key LIKE 'warfareBuff%'
        """
        var keyValues: [String: Double] = [:]
        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [typeID]) {
            for row in rows {
                if let key = row["attribute_key"] as? String,
                   let value = row["value"] as? Double
                {
                    keyValues[key] = value
                }
            }
        }
        warfareBuffPairs = SDEMemoryStore.parseWarfareBuffPairs(keyValues)
            .map { ($0.buffID, $0.value) }
    }
}

// MARK: - Warfare Buff Section

/// 指挥脉冲波 / 作战链加成展示：物品自身图标 + 本地化 buff 名称 + 百分比
private struct WarfareBuffSection: View {
    let typeID: Int
    let buffs: [(Int, Double)]

    /// 物品自身图标
    private var itemIcon: String? {
        let icon = SDEMemoryStore.types[typeID]?.iconFilename ?? ""
        return icon.isEmpty ? nil : icon
    }

    var body: some View {
        Section(
            header: Text(NSLocalizedString("Misc_Warfare_Buffs", comment: "")).font(.headline)
        ) {
            ForEach(Array(buffs.enumerated()), id: \.offset) { _, pair in
                WarfareBuffRow(
                    name: SDEMemoryStore.warfareBuff(for: pair.0, typeID: typeID)?.displayName ?? "Buff \(pair.0)",
                    iconFileName: itemIcon,
                    multiplier: pair.1
                )
                .listRowInsets(attributeRowInsets)
            }
        }
    }
}

/// 单个 buff 行（物品属性页与装配页模块行共用，样式经参数区分）
/// 属性页用默认样式；装配页传 .caption 字号、20pt 图标并开启 isInline 内嵌样式
struct WarfareBuffRow: View {
    let name: String
    let iconFileName: String?
    let multiplier: Double
    /// 文本字号（属性页 .body / 装配页 .caption）
    var font: Font = .body
    /// 图标边长（属性页 24 / 装配页 20）
    var iconSize: CGFloat = 24
    /// 百分比小数位数（属性页 0 / 装配页 2）
    var fractionDigits: Int = 0
    /// 内嵌样式（装配页）：整体间距 4、图标 1pt 圆角、名称灰色单行追加冒号、数值紧随名称而非右对齐
    var isInline: Bool = false

    /// 带符号百分比：%+ 自动补正负号，无需手动拼接
    private var bonusText: String {
        String(format: "%+.*f%%", fractionDigits, multiplier)
    }

    var body: some View {
        HStack(spacing: isInline ? 4 : 8) {
            // 上游已保证：iconFileName 非 nil 时必为非空串（空串在来源处已回退为 nil/默认图标）
            if let icon = iconFileName {
                IconManager.shared.loadImage(for: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: isInline ? 1 : 0))
            } else {
                Image(systemName: "bolt.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .foregroundColor(isInline ? .green.opacity(0.7) : .green)
            }

            if isInline {
                HStack(spacing: 0) {
                    Text(name + ": ")
                        .font(font)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Text(bonusText)
                        .font(font)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
            } else {
                Text(name)
                    .font(font)
                    .lineLimit(2)

                Spacer()

                Text(bonusText)
                    .font(font)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Fighter Abilities Section

/// 舰载机能力概览（每个 slot 一行：图标 + 名称 + 描述 + 冷却/装填/重装）
private struct FighterAbilitiesSection: View {
    let abilities: [SDEMemoryStore.FighterAbilityInfo]

    var body: some View {
        Section(
            header: Text(NSLocalizedString("Ability_Overview", comment: "")).font(.headline)
        ) {
            ForEach(abilities, id: \.slot) { ability in
                FighterAbilityRow(ability: ability)
                    .listRowInsets(attributeRowInsets)
            }
        }
    }
}

private struct FighterAbilityRow: View {
    let ability: SDEMemoryStore.FighterAbilityInfo

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            IconManager.shared.loadImage(for: ability.iconFilename)
                .resizable()
                .frame(width: 32, height: 32)
                .cornerRadius(6)
            VStack(alignment: .leading, spacing: 2) {
                Text(ability.name)
                    .font(.body)
                    .foregroundColor(.primary)
                if !ability.description.isEmpty {
                    Text(ability.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let stats = statsLine {
                    Text(stats)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// 冷却/装填/重装 以圆点拼接，仅有值字段参与；全空返回 nil
    private var statsLine: String? {
        var parts: [String] = []
        if let cooldown = ability.cooldownSeconds {
            parts.append("\(NSLocalizedString("Cooldown", comment: "")) \(cooldown)\(NSLocalizedString("Seconds_Suffix", comment: ""))")
        }
        if let charge = ability.chargeCount {
            parts.append("\(NSLocalizedString("Charges", comment: "")) \(charge)\(NSLocalizedString("Count_Suffix", comment: ""))")
        }
        if let rearm = ability.rearmTimeSeconds {
            parts.append("\(NSLocalizedString("Rearm", comment: "")) \(rearm)\(NSLocalizedString("Seconds_Suffix", comment: ""))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
