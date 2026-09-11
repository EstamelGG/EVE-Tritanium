import Foundation
import SQLite3

/// dogmaAttributes / typeAttributes / typeEffects / dogmaEffects 加载与查询
extension SDEMemoryStore {
    static func loadDogmaAttributes(_ db: DatabaseManager) {
        let query = """
            SELECT attribute_id, categoryID, attribute_key, iconID, icon_filename,
                   unitID, highIsGood, stackable, defaultValue,
                   \(nameColumns),
                   unit_de_name, unit_en_name, unit_es_name, unit_fr_name,
                   unit_ja_name, unit_ko_name, unit_ru_name, unit_zh_name
            FROM dogmaAttributes
        """
        var cache: [Int: DogmaAttributeInfo] = [:]
        cache.reserveCapacity(4096)
        if case let .success(rows) = db.executeQuery(query, useCache: false) {
            for row in rows {
                guard let id = row["attribute_id"] as? Int else { continue }
                let rawIcon = (row["icon_filename"] as? String) ?? ""
                cache[id] = DogmaAttributeInfo(
                    id: id,
                    categoryID: row["categoryID"] as? Int,
                    name: (row["attribute_key"] as? String) ?? (row["name"] as? String) ?? "",
                    displayNames: LocalizedText.from(row: row),
                    iconID: (row["iconID"] as? Int) ?? 0,
                    iconFilename: rawIcon,
                    unitID: row["unitID"] as? Int,
                    unitNames: LocalizedText.units(from: row),
                    highIsGood: (row["highIsGood"] as? Int) == 1,
                    stackable: (row["stackable"] as? Int) == 1,
                    defaultValue: (row["defaultValue"] as? Double) ?? 0.0
                )
            }
        }
        dogmaAttributes = cache
        dogmaAttributeIDsByName = Dictionary(
            cache.map { ($0.value.name, $0.key) }, uniquingKeysWith: { first, _ in first }
        )
    }

    /// typeAttributes 扁平预加载（64.6 万行 → 平行数组 + 区间索引，约 11MB）。
    /// 直读接口绕过行字典与 Any 装箱，Swift 侧开销趋近于零。
    static func loadTypeAttributes(_ db: DatabaseManager) {
        let query = """
            SELECT type_id, attribute_id, value
            FROM typeAttributes
            ORDER BY type_id, attribute_id
        """
        var ids: [Int32] = []
        var values: [Double] = []
        var ranges: [Int: Range<Int>] = [:]
        ids.reserveCapacity(655_360)
        values.reserveCapacity(655_360)
        ranges.reserveCapacity(52864)

        var currentTypeID = Int64.min
        var rangeStart = 0

        db.executeQueryMapped(query, context: "typeAttributes") { resolve in
            let (iType, iAttr, iValue) = (
                resolve.index("type_id"), resolve.index("attribute_id"), resolve.index("value")
            )
            return { stmt in
                // value 为 NULL 时跳过整行（与旧字典版行为一致；实测该表无 NULL 行）
                guard sqlite3_column_type(stmt, iValue) != SQLITE_NULL else { return }
                let typeID = sqlite3_column_int64(stmt, iType)
                let attrID = sqlite3_column_int64(stmt, iAttr)
                let value = sqlite3_column_double(stmt, iValue)

                if typeID != currentTypeID {
                    if currentTypeID != Int64.min {
                        ranges[Int(currentTypeID)] = rangeStart ..< ids.count
                    }
                    currentTypeID = typeID
                    rangeStart = ids.count
                }
                ids.append(Int32(attrID))
                values.append(value)
            }
        }
        if currentTypeID != Int64.min {
            ranges[Int(currentTypeID)] = rangeStart ..< ids.count
        }
        typeAttrIDs = ids
        typeAttrValues = values
        typeAttrRanges = ranges
    }

    static func loadTypeEffects(_ db: DatabaseManager) {
        var cache: [Int: [Int]] = [:]
        var entries: [Int: [(effectID: Int, isDefault: Bool)]] = [:]
        cache.reserveCapacity(32768)
        if case let .success(rows) = db.executeQuery(
            "SELECT type_id, effect_id, is_default FROM typeEffects", useCache: false
        ) {
            for row in rows {
                guard let typeID = row["type_id"] as? Int,
                      let effectID = row["effect_id"] as? Int
                else { continue }
                cache[typeID, default: []].append(effectID)
                entries[typeID, default: []].append(
                    (effectID: effectID, isDefault: (row["is_default"] as? Int ?? 0) == 1)
                )
            }
        }
        typeEffectIDs = cache
        typeEffectEntries = entries
    }

    /// dogmaEffects 全量预加载（3417 行，约 2MB：modifier_info + 八语 name/description）
    static func loadDogmaEffects(_ db: DatabaseManager) {
        let query = """
            SELECT effect_id, effect_category, effect_name, is_offensive, is_assistance,
                   resistance_attribute_id, modifier_info,
                   de_name, en_name, es_name, fr_name, ja_name, ko_name, ru_name, zh_name,
                   de_description, en_description, es_description, fr_description,
                   ja_description, ko_description, ru_description, zh_description
            FROM dogmaEffects
        """
        var cache: [Int: DogmaEffectInfo] = [:]
        cache.reserveCapacity(4096)
        db.executeQueryMapped(query, context: "dogmaEffects") { resolve in
            let (iID, iCategory, iName, iMod) = (
                resolve.index("effect_id"), resolve.index("effect_category"),
                resolve.index("effect_name"), resolve.index("modifier_info")
            )
            let (iOffensive, iAssist, iResist) = (
                resolve.index("is_offensive"), resolve.index("is_assistance"),
                resolve.index("resistance_attribute_id")
            )
            let (iNames, iDescriptions) = (
                localizedIndexes(resolve),
                localizedIndexes(resolve, suffix: "description")
            )
            return { stmt in
                guard let id = directIntOrNil(stmt, iID) else { return }
                cache[id] = DogmaEffectInfo(
                    effectID: id,
                    effectName: directText(stmt, iName),
                    effectCategory: directIntOrNil(stmt, iCategory),
                    isOffensive: (directIntOrNil(stmt, iOffensive) ?? 0) == 1,
                    isAssistance: (directIntOrNil(stmt, iAssist) ?? 0) == 1,
                    resistanceAttributeID: directIntOrNil(stmt, iResist),
                    modifierInfo: sqlite3_column_type(stmt, iMod) == SQLITE_NULL
                        ? nil : directText(stmt, iMod),
                    displayNames: localizedText(stmt, iNames),
                    descriptions: localizedText(stmt, iDescriptions)
                )
            }
        }
        dogmaEffects = cache
    }

    // MARK: - Lookups

    static func dogmaAttribute(for id: Int) -> DogmaAttributeInfo? {
        dogmaAttributes[id]
    }

    /// 按属性 key 名（如 "fighterTubes"）查 attributeID
    static func attributeID(named name: String) -> Int? {
        dogmaAttributeIDsByName[name]
    }

    static func effectIDs(forType typeID: Int) -> [Int] {
        typeEffectIDs[typeID] ?? []
    }

    /// typeEffects 带默认标志
    static func typeEffects(forType typeID: Int) -> [(effectID: Int, isDefault: Bool)] {
        typeEffectEntries[typeID] ?? []
    }

    /// dogmaEffects 效果定义点查
    static func dogmaEffect(for effectID: Int) -> DogmaEffectInfo? {
        dogmaEffects[effectID]
    }

    /// 单类型属性点查 → [attributeID: value]
    static func typeAttributes(for typeID: Int) -> [Int: Double] {
        guard let range = typeAttrRanges[typeID] else { return [:] }
        var result: [Int: Double] = [:]
        result.reserveCapacity(range.count)
        for i in range {
            result[Int(typeAttrIDs[i])] = typeAttrValues[i]
        }
        return result
    }

    /// 单类型属性（按 ID + 按名称，与旧 SQL `JOIN dogmaAttributes` 行为一致）
    static func typeAttributesFull(for typeID: Int) -> (
        attributes: [Int: Double], attributesByName: [String: Double]
    ) {
        guard let range = typeAttrRanges[typeID] else { return ([:], [:]) }
        var byID: [Int: Double] = [:]
        var byName: [String: Double] = [:]
        byID.reserveCapacity(range.count)
        for i in range {
            let attrID = Int(typeAttrIDs[i])
            let value = typeAttrValues[i]
            byID[attrID] = value
            if let name = dogmaAttributes[attrID]?.name {
                byName[name] = value
            }
        }
        return (byID, byName)
    }

    /// 批量属性查询（替代旧 SQL `WHERE type_id IN (...)` 场景）
    static func typeAttributes(for typeIDs: [Int]) -> [Int: (
        attributes: [Int: Double], attributesByName: [String: Double]
    )] {
        var result: [Int: (attributes: [Int: Double], attributesByName: [String: Double])] = [:]
        for typeID in typeIDs where typeAttrRanges[typeID] != nil {
            result[typeID] = typeAttributesFull(for: typeID)
        }
        return result
    }

    /// 单属性点查（替代旧 SQL `SELECT value FROM typeAttributes WHERE type_id=? AND attribute_id=?`）
    static func typeAttributeValue(for typeID: Int, attributeID: Int) -> Double? {
        guard let range = typeAttrRanges[typeID] else { return nil }
        // 区间内 attribute_id 升序，二分查找
        var low = range.lowerBound
        var high = range.upperBound - 1
        let target = Int32(attributeID)
        while low <= high {
            let mid = (low + high) / 2
            let midID = typeAttrIDs[mid]
            if midID == target { return typeAttrValues[mid] }
            if midID < target { low = mid + 1 } else { high = mid - 1 }
        }
        return nil
    }

    // MARK: - 增效剂副作用

    /// 增效剂「副作用」对应的惩罚属性 ID。
    /// 从 dogmaAttributes 动态推导：attribute_key 以 `booster` 开头且以 `Penalty` 结尾（如 boosterArmorHpPenalty）。
    static let boosterSideEffectPenaltyAttributeIDs: Set<Int> = Set(
        dogmaAttributes.values
            .filter { $0.name.hasPrefix("booster") && $0.name.hasSuffix("Penalty") }
            .map(\.id)
    )

    /// 判断某属性是否为增效剂副作用惩罚属性
    static func isBoosterSideEffectAttribute(_ attributeID: Int) -> Bool {
        boosterSideEffectPenaltyAttributeIDs.contains(attributeID)
    }

    /// 某个增效剂实际存在的副作用列表（按属性 ID 升序）
    static func boosterSideEffects(forType typeID: Int) -> [BoosterSideEffect] {
        boosterSideEffectPenaltyAttributeIDs.compactMap { attributeID in
            guard let value = typeAttributeValue(for: typeID, attributeID: attributeID) else {
                return nil
            }
            let name = dogmaAttribute(for: attributeID)?.displayName ?? "Attribute \(attributeID)"
            return BoosterSideEffect(attributeID: attributeID, name: name, value: value)
        }
        .sorted { $0.attributeID < $1.attributeID }
    }

    /// 单条增效剂副作用
    struct BoosterSideEffect {
        let attributeID: Int
        let name: String
        let value: Double
    }
}
