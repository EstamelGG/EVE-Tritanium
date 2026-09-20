import Foundation
import SwiftUI

extension DatabaseManager {
    /// 获取指定物品可突变产物的列表
    /// - Parameter typeID: 原始物品 typeID（applicable_type）
    /// - Returns: 去重后的产物列表，按名称排序
    func getMutationResults(for typeID: Int) -> [(typeID: Int, name: String, iconFileName: String)] {
        let mappings = SDEMemoryStore.dynamicMappings(applicableTo: typeID)
        var seen = Set<Int>()
        var results: [(typeID: Int, name: String, iconFileName: String)] = []
        for mapping in mappings {
            let resultingType = mapping.resultingType
            if seen.contains(resultingType) {
                continue
            }
            seen.insert(resultingType)
            guard let info = SDEMemoryStore.type(for: resultingType) else { continue }
            results.append(
                (
                    typeID: resultingType,
                    name: info.name,
                    iconFileName: info.iconFilename.isEmpty
                        ? IconManager.defaultItemIcon : info.iconFilename
                )
            )
        }
        results.sort { $0.name < $1.name }
        return results
    }

    /// 获取用于突变该物品的突变体列表
    /// - Parameter typeID: 原始物品 typeID（applicable_type）
    /// - Returns: 去重后的突变体列表，按 typeID 排序
    func getRequiredMutaplasmids(for typeID: Int) -> [(
        typeID: Int, name: String, iconFileName: String
    )] {
        let mappings = SDEMemoryStore.dynamicMappings(applicableTo: typeID)
        var seen = Set<Int>()
        var results: [(typeID: Int, name: String, iconFileName: String)] = []
        for mapping in mappings {
            let mutaplasmidID = mapping.typeID
            if seen.contains(mutaplasmidID) {
                continue
            }
            seen.insert(mutaplasmidID)
            guard let info = SDEMemoryStore.type(for: mutaplasmidID) else { continue }
            results.append(
                (
                    typeID: mutaplasmidID,
                    name: info.name,
                    iconFileName: info.iconFilename.isEmpty
                        ? IconManager.defaultItemIcon : info.iconFilename
                )
            )
        }
        results.sort { $0.typeID < $1.typeID }
        return results
    }

    /// 根据原始装备typeID和突变质体ID获取突变后的typeID
    /// - Parameters:
    ///   - applicableTypeID: 原始装备的typeID
    ///   - mutaplasmidID: 突变质体的typeID
    /// - Returns: 突变后的typeID，如果不存在则返回nil
    func getMutatedTypeID(applicableTypeID: Int, mutaplasmidID: Int) -> Int? {
        SDEMemoryStore.dynamicResultingType(
            applicableType: applicableTypeID, typeID: mutaplasmidID
        )
    }

    /// 获取突变来源信息
    func getMutationSource(for itemID: Int) -> (
        sourceItems: [(typeID: Int, name: String, iconFileName: String)],
        mutaplasmids: [(typeID: Int, name: String, iconFileName: String)]
    ) {
        let mappings = SDEMemoryStore.dynamicMappings(resultingIn: itemID)
        var sourceItems: [(typeID: Int, name: String, iconFileName: String)] = []
        var mutaplasmids: [(typeID: Int, name: String, iconFileName: String)] = []
        var seenSourceItems = Set<Int>()
        var seenMutaplasmids = Set<Int>()

        for mapping in mappings {
            if !seenSourceItems.contains(mapping.applicableType),
               let info = SDEMemoryStore.type(for: mapping.applicableType)
            {
                sourceItems.append(
                    (
                        typeID: mapping.applicableType,
                        name: info.name,
                        iconFileName: info.iconFilename.isEmpty
                            ? IconManager.defaultItemIcon : info.iconFilename
                    )
                )
                seenSourceItems.insert(mapping.applicableType)
            }

            if !seenMutaplasmids.contains(mapping.typeID),
               let info = SDEMemoryStore.type(for: mapping.typeID)
            {
                mutaplasmids.append(
                    (
                        typeID: mapping.typeID,
                        name: info.name,
                        iconFileName: info.iconFilename.isEmpty
                            ? IconManager.defaultItemIcon : info.iconFilename
                    )
                )
                seenMutaplasmids.insert(mapping.typeID)
            }
        }

        return (sourceItems: sourceItems, mutaplasmids: mutaplasmids)
    }
}
