import Foundation

/// 属性显示规则配置
enum AttributeDisplayConfig {
    /// 转换结果类型
    enum TransformResult {
        case number(Double, String?) // 数值和可选单位
        case text(String) // 纯文本
        case resistance([Double]) // 抗性显示（EM, Thermal, Kinetic, Explosive）
    }

    /// 特殊值映射类型
    private enum SpecialValueType {
        case boolean
        case size
        case gender

        private static let sizeLabels = [1: "Small", 2: "Medium", 3: "Large", 4: "X-large"]
        private static let genderLabels = [1: "Male", 2: "Unisex", 3: "Female"]

        func transform(_ value: Double) -> String {
            switch self {
            case .boolean:
                return value == 1 ? "True" : "False"
            case .size:
                return Self.sizeLabels[Int(value)] ?? NSLocalizedString("Unknown", comment: "")
            case .gender:
                return Self.genderLabels[Int(value)] ?? NSLocalizedString("Unknown", comment: "")
            }
        }
    }

    /// 特殊值映射配置
    private static let specialValueMappings: [Int: SpecialValueType] = {
        var map = Dictionary(uniqueKeysWithValues: [128, 1031, 1547].map { ($0, SpecialValueType.size) })
        map[1773] = .gender
        for id in [
            786, 854, 861, 1014, 1074, 1158, 1167, 1245, 1252,
            1785, 1798, 1806, 1854, 1890, 1916, 1920, 1927, 1945,
            1958, 1970, 2343, 2354, 2395, 2453, 2454, 2791, 2826,
            2827, 3117, 3123, 5206, 5425, 5426, 5561, 5700,
        ] {
            map[id] = .boolean
        }
        return map
    }()

    /// 抗性属性组定义
    struct ResistanceGroup {
        let groupID: Int
        let emIDs: [Int]
        let thermalIDs: [Int]
        let kineticIDs: [Int]
        let explosiveIDs: [Int]

        var allIDs: [Int] {
            emIDs + thermalIDs + kineticIDs + explosiveIDs
        }
    }

    /// 定义抗性属性组
    private static let resistanceGroups: [ResistanceGroup] = [
        ResistanceGroup( // 护盾抗性
            groupID: 2,
            emIDs: [271, 1423, 2118],
            thermalIDs: [274, 1425, 2119],
            kineticIDs: [273, 1424, 2120],
            explosiveIDs: [272, 1422, 2121]
        ),
        ResistanceGroup( // 装甲抗性
            groupID: 3,
            emIDs: [267, 1418],
            thermalIDs: [270, 1419],
            kineticIDs: [269, 1420],
            explosiveIDs: [268, 1421]
        ),
        ResistanceGroup( // 结构抗性
            groupID: 4,
            emIDs: [113, 974, 1426],
            thermalIDs: [110, 977, 1429],
            kineticIDs: [109, 976, 1428],
            explosiveIDs: [111, 975, 1427]
        ),
    ]

    private static let resistanceAttributeIDs: Set<Int> = Set(
        resistanceGroups.flatMap(\.allIDs)
    )

    /// 运算符类型
    enum Operation: String {
        case add = "+"
        case subtract = "-"
        case multiply = "*"
        case divide = "/"

        func calculate(_ a: Double, _ b: Double) -> Double {
            switch self {
            case .add: return a + b
            case .subtract: return a - b
            case .multiply: return a * b
            case .divide: return b == 0 ? 0 : a / b
            }
        }
    }

    /// 属性值计算配置
    struct AttributeCalculation {
        let sourceAttribute1: Int
        let sourceAttribute2: Int
        let operation: Operation
    }

    private static let defaultGroupOrder: [Int: Int] = [:]
    private static let defaultHiddenGroups: Set<Int> = [9, 52]
    private static let defaultHiddenAttributes: Set<Int> = [
        3, 15, 600, 715, 716, 1137, 1336, 1547,
    ]
    private static let defaultAttributeOrder: [Int: [Int: Int]] = [:]

    /// 属性单位
    private static var attributeUnits: [Int: String] = [:]

    /// 属性组内属性的自定义排序配置
    private static var customAttributeOrder: [Int: [Int: Int]]?

    private static var activeAttributeOrder: [Int: [Int: Int]] {
        customAttributeOrder ?? defaultAttributeOrder
    }

    /// 属性值计算规则
    private static var attributeCalculations: [Int: AttributeCalculation] = [
        1281: AttributeCalculation(
            sourceAttribute1: 1281, sourceAttribute2: 600, operation: .multiply
        ),
    ]

    /// 基于 Attribute_id 的值转换规则
    private static let valueTransformRules: [Int: (Double) -> Double] = [:]

    /// 基于 unitID 的值转换规则，参考 https://sde.hoboleaks.space/tq/dogmaunits.json
    private static let unitTransformRules: [Int: (Double) -> Double] = [
        108: { (1 - $0) * 100 },
        111: { (1 - $0) * 100 },
        127: { $0 * 100 },
    ]

    /// 基于 unitID 的值格式化规则，参考 https://sde.hoboleaks.space/tq/dogmaunits.json
    private static let unitFormatRules: [Int: (Double, String?) -> String] = [
        109: { value, _ in
            let diff = value - 1
            return diff > 0
                ? "+\(FormatUtil.format(diff * 100))%" : "\(FormatUtil.format(diff * 100))%"
        },
        3: { value, _ in FormatUtil.formatTimeWithPrecision(value) },
        101: { value, _ in FormatUtil.formatTimeWithMillisecondPrecision(value) },
    ]

    /// 免疫等特殊布尔文案（与 specialValueMappings 中的 True/False 区分）
    private static let immuneAttributeID = 188

    // 自定义配置 - 不设置则使用默认值
    static var customGroupOrder: [Int: Int]?
    static var customHiddenGroups: Set<Int>?
    static var customHiddenAttributes: Set<Int>?

    /// 只显示重要属性（有 displayName 的属性）
    static var showImportantOnly: Bool {
        get {
            UserDefaults.standard.object(forKey: "ShowImportantOnly") as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "ShowImportantOnly")
        }
    }

    static var activeGroupOrder: [Int: Int] {
        customGroupOrder ?? defaultGroupOrder
    }

    static var activeHiddenGroups: Set<Int> {
        customHiddenGroups ?? defaultHiddenGroups
    }

    static var activeHiddenAttributes: Set<Int> {
        customHiddenAttributes ?? defaultHiddenAttributes
    }

    static func initializeUnits(with units: [Int: String]) {
        attributeUnits = units
    }

    /// 判断属性组是否应该显示
    static func shouldShowGroup(_ groupId: Int) -> Bool {
        // categoryID 为 0 的「其他」分类只在关闭「只展示重要属性」时显示
        if groupId == 0 {
            return !showImportantOnly
        }
        if activeHiddenGroups.contains(groupId) && showImportantOnly {
            return false
        }
        return true
    }

    /// 判断具体属性是否应该显示
    static func shouldShowAttribute(_ attributeID: Int, attribute: DogmaAttribute) -> Bool {
        if resistanceAttributeIDs.contains(attributeID) {
            return false
        }
        if activeHiddenAttributes.contains(attributeID) && showImportantOnly {
            return false
        }
        if showImportantOnly {
            return attribute.localizedDisplayName != nil
        }
        return !attribute.name.isEmpty
    }

    /// 获取属性组的排序权重
    static func getGroupOrder(_ groupId: Int) -> Int {
        groupId == 0 ? 9999 : (activeGroupOrder[groupId] ?? 999)
    }

    /// 计算属性值
    private static func calculateValue(for attributeID: Int, in allAttributes: [Int: Double])
        -> Double
    {
        if let calc = attributeCalculations[attributeID],
           let value1 = allAttributes[calc.sourceAttribute1],
           let value2 = allAttributes[calc.sourceAttribute2]
        {
            return calc.operation.calculate(value1, value2)
        }
        return allAttributes[attributeID] ?? 0
    }

    private static func findResistanceGroup(for groupID: Int) -> ResistanceGroup? {
        resistanceGroups.first { $0.groupID == groupID }
    }

    struct ResistanceHits {
        let emID: Int?
        let thermalID: Int?
        let kineticID: Int?
        let explosiveID: Int?

        var hasAnyResistance: Bool {
            emID != nil || thermalID != nil || kineticID != nil || explosiveID != nil
        }
    }

    private static func findResistanceAttributes(groupID: Int, in allAttributes: [Int: Double])
        -> ResistanceHits?
    {
        guard let group = findResistanceGroup(for: groupID) else { return nil }

        let hits = ResistanceHits(
            emID: group.emIDs.first { allAttributes[$0] != nil },
            thermalID: group.thermalIDs.first { allAttributes[$0] != nil },
            kineticID: group.kineticIDs.first { allAttributes[$0] != nil },
            explosiveID: group.explosiveIDs.first { allAttributes[$0] != nil }
        )
        return hits.hasAnyResistance ? hits : nil
    }

    static func getResistanceValues(groupID: Int, from allAttributes: [Int: Double]) -> [Double]? {
        guard let hits = findResistanceAttributes(groupID: groupID, in: allAttributes) else {
            return nil
        }
        func percent(_ id: Int?) -> Double {
            (1 - (id.flatMap { allAttributes[$0] } ?? 1.0)) * 100
        }
        return [percent(hits.emID), percent(hits.thermalID), percent(hits.kineticID), percent(hits.explosiveID)]
    }

    /// 转换属性值，将数值与单位拼接
    static func transformValue(_ attributeID: Int, allAttributes: [Int: Double], unitID: Int?)
        -> TransformResult
    {
        let value = calculateValue(for: attributeID, in: allAttributes)

        if let specialType = specialValueMappings[attributeID] {
            return .text(specialType.transform(value))
        }

        if attributeID == immuneAttributeID {
            if value == 1 {
                return .text(NSLocalizedString("Main_Database_Item_info_Immune", comment: ""))
            } else {
                return .text(NSLocalizedString("Main_Database_Item_info_NonImmune", comment: ""))
            }
        }

        var transformedValue = value

        if let transformRule = valueTransformRules[attributeID] {
            transformedValue = transformRule(transformedValue)
        }

        if let unitID, let unitTransform = unitTransformRules[unitID] {
            transformedValue = unitTransform(transformedValue)
        }

        if let unitID, let formatRule = unitFormatRules[unitID] {
            return .text(formatRule(transformedValue, attributeUnits[attributeID]))
        }

        if let unit = attributeUnits[attributeID] {
            return .number(transformedValue, unit == "%" ? unit : " " + unit)
        }
        return .number(transformedValue, nil)
    }

    /// 获取属性在组内的排序权重
    static func getAttributeOrder(attributeID: Int, in groupID: Int) -> Int {
        activeAttributeOrder[groupID]?[attributeID] ?? 999
    }
}
