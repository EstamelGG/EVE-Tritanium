import Foundation
import SwiftUI

extension DatabaseManager {
    func getTypeName(for typeID: Int) -> String? {
        ItemInfoMap.typeName(for: typeID)
    }

    /// 获取属性名称
    func getAttributeName(for attributeID: Int) -> String? {
        SDEMemoryStore.dogmaAttribute(for: attributeID)?.displayName
    }

    /// 加载物品的所有属性组
    func loadAttributeGroups(for typeID: Int, modifiedAttributes: [Int: Double]? = nil, baseAttributes: [Int: Double]? = nil)
        -> [AttributeGroup]
    {
        // 1. 首先加载所有属性分类
        let categoryQuery = """
            SELECT attribute_category_id, name, description
            FROM dogmaAttributeCategories
            ORDER BY attribute_category_id
        """

        let categoryResult = executeQuery(categoryQuery)
        var categories: [Int: DogmaAttributeCategory] = [:]

        if case let .success(rows) = categoryResult {
            for row in rows {
                guard let id = row["attribute_category_id"] as? Int,
                      let name = row["name"] as? String,
                      let description = row["description"] as? String
                else {
                    continue
                }
                categories[id] = DogmaAttributeCategory(
                    id: id, name: name, description: description
                )
            }
        }

        // 2. 加载物品的所有属性值（dogmaAttributes 字段从 SDEMemoryStore 内存获取，避免 JOIN）
        let attributeQuery = """
            SELECT attribute_id, value
            FROM typeAttributes
            WHERE type_id = ?
        """

        let attributeResult = executeQuery(attributeQuery, parameters: [typeID])
        var baseValues: [Int: Double] = [:]
        if case let .success(rows) = attributeResult {
            for row in rows {
                if let id = row["attribute_id"] as? Int, let value = row["value"] as? Double {
                    baseValues[id] = value
                }
            }
        }
        // Include attributes introduced by the simulation, and use its actual starting values.
        baseValues.merge(baseAttributes ?? [:]) { _, simulationBase in simulationBase }
        let attributeIDs = Set(baseValues.keys).union(modifiedAttributes?.keys.map { $0 } ?? [])
        var attributesByCategory: [Int: [DogmaAttribute]] = [:]
        for attributeID in attributeIDs {
            guard let attr = SDEMemoryStore.dogmaAttribute(for: attributeID) else { continue }
            let categoryID = attr.categoryID.flatMap { categories[$0] == nil ? nil : $0 } ?? 0
            let attribute = DogmaAttribute(
                id: attributeID,
                categoryID: categoryID,
                name: attr.name,
                displayName: attr.displayName,
                iconID: attr.iconID,
                iconFileName: attr.iconFilename.isEmpty ? IconManager.defaultIcon : attr.iconFilename,
                value: baseValues[attributeID] ?? 0,
                unitID: attr.unitID,
                highIsGood: attr.highIsGood,
                modifiedValue: modifiedAttributes?[attributeID]
            )
            if attribute.shouldDisplay {
                attributesByCategory[categoryID, default: []].append(attribute)
            }
        }

        // 3. 组合成最终的属性组列表
        var resultGroups: [AttributeGroup] = []

        // 先添加所有有分类的属性组
        for (categoryId, category) in categories.sorted(by: { $0.key < $1.key }) where categoryId != 0 {
            if let attributes = attributesByCategory[categoryId], !attributes.isEmpty {
                resultGroups.append(AttributeGroup(
                    id: categoryId,
                    name: category.name,
                    attributes: attributes.sorted { $0.id < $1.id } // 按 attribute_id 排序
                ))
            }
        }

        // 4. 添加 categoryID 为 0 的属性到"其他"分类
        if let uncategorizedAttributes = attributesByCategory[0], !uncategorizedAttributes.isEmpty {
            resultGroups.append(AttributeGroup(
                id: 0, // 使用 0 作为特殊标识，表示"其他"分类
                name: NSLocalizedString("Main_Other", comment: ""),
                attributes: uncategorizedAttributes.sorted { $0.id < $1.id }
            ))
        }

        return resultGroups
    }

    /// 加载属性单位信息
    func loadAttributeUnits() -> [Int: String] {
        var units: [Int: String] = [:]
        for (id, attr) in SDEMemoryStore.dogmaAttributes {
            if let unitName = attr.unitNames.resolvedNonEmpty() {
                units[id] = unitName
            }
        }
        return units
    }

    /// 获取组名称（从 groups 表获取，用于其他场景）
    func getGroupName(for groupID: Int) -> String? {
        SDEMemoryStore.group(for: groupID)?.name
    }

    /// 获取属性完整信息
    func getAttributeInfo(for attributeID: Int) -> (categoryID: Int, name: String, displayName: String?, iconID: Int, iconFileName: String, unitID: Int?, highIsGood: Bool)? {
        guard let attr = SDEMemoryStore.dogmaAttribute(for: attributeID),
              let categoryID = attr.categoryID
        else { return nil }
        return (
            categoryID,
            attr.name,
            attr.displayName,
            attr.iconID,
            attr.iconFilename.isEmpty ? IconManager.defaultIcon : attr.iconFilename,
            attr.unitID,
            attr.highIsGood
        )
    }

    /// 获取属性分类名称
    func getAttributeCategoryName(for categoryID: Int) -> String? {
        let query = "SELECT name FROM dogmaAttributeCategories WHERE attribute_category_id = ?"

        if case let .success(rows) = executeQuery(query, parameters: [categoryID]),
           let row = rows.first,
           let name = row["name"] as? String
        {
            return name
        }
        return nil
    }

    /// 重新加工材料数据结构
    struct TypeMaterial {
        let process_size: Int
        let outputMaterial: Int
        let outputQuantity: Int
        let outputMaterialName: String
        let outputMaterialIcon: String
    }

    func getMissileAttributes(for itemID: Int) -> (damages: (em: Double, therm: Double, kin: Double, exp: Double), flightTime: Double?, flightSpeed: Double?)? {
        var damages: (em: Double, therm: Double, kin: Double, exp: Double) = (0, 0, 0, 0)
        var flightTime: Double?
        var flightSpeed: Double?
        var hasData = false

        // 一次性查询所有需要的属性：伤害(114,116,117,118)、飞行时间(281)、飞行速度(37)
        let query = """
            SELECT attribute_id, value 
            FROM typeAttributes 
            WHERE type_id = ? AND attribute_id IN (114, 116, 117, 118, 281, 37)
        """

        let result = executeQuery(query, parameters: [itemID])

        switch result {
        case let .success(rows):
            for row in rows {
                if let attributeID = row["attribute_id"] as? Int,
                   let value = row["value"] as? Double
                {
                    switch attributeID {
                    case 114: damages.em = value
                    case 118: damages.therm = value
                    case 117: damages.kin = value
                    case 116: damages.exp = value
                    case 281: flightTime = value
                    case 37: flightSpeed = value
                    default: break
                    }
                    hasData = true
                }
            }
        case let .error(error):
            Logger.error("Error fetching missile attributes for item \(itemID): \(error)")
            return nil
        }

        // 至少需要有伤害数据才返回
        guard hasData, damages.em + damages.therm + damages.kin + damages.exp > 0 else {
            return nil
        }

        return (damages: damages, flightTime: flightTime, flightSpeed: flightSpeed)
    }

    /// 获取具有特定属性值的物品
    func getItemsByAttributeValue(attributeID: Int, value: Double) -> [(
        typeID: Int, name: String, iconFileName: String
    )] {
        let query = """
            SELECT t.type_id, t.name, t.icon_filename
            FROM typeAttributes ta
            JOIN types t ON ta.type_id = t.type_id
            WHERE ta.attribute_id = ? AND ta.value = ?
            ORDER BY t.type_id
        """

        var items: [(typeID: Int, name: String, iconFileName: String)] = []

        if case let .success(rows) = executeQuery(query, parameters: [attributeID, value]) {
            for row in rows {
                if let typeID = row["type_id"] as? Int,
                   let name = row["name"] as? String,
                   let iconFileName = row["icon_filename"] as? String
                {
                    items.append(
                        (
                            typeID: typeID,
                            name: name,
                            iconFileName: iconFileName.isEmpty
                                ? IconManager.defaultItemIcon : iconFileName
                        )
                    )
                }
            }
        }

        return items
    }

    // 获取物品可以突变的结果
    // - Parameter typeID: 物品ID
}
