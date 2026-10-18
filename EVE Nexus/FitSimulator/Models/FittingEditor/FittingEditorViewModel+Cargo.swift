import Foundation
import SwiftUI

extension FittingEditorViewModel {
    // MARK: - 货舱相关方法

    /// 添加物品到货舱
    func addCargoItem(typeId: Int, name: String, iconFileName: String?, quantity: Int) {
        // 获取物品体积
        let volume = getItemVolume(typeId: typeId)

        // 检查是否已存在相同类型的物品
        if let index = simulationInput.cargo.items.firstIndex(where: { $0.typeId == typeId }) {
            // 更新现有物品数量
            let existingItem = simulationInput.cargo.items[index]
            let newQuantity = existingItem.quantity + quantity

            // 创建更新后的物品对象
            let updatedItem = SimCargoItem(
                typeId: existingItem.typeId,
                quantity: newQuantity,
                volume: existingItem.volume,
                name: existingItem.name,
                iconFileName: existingItem.iconFileName
            )

            // 更新物品列表
            var updatedItems = simulationInput.cargo.items
            updatedItems[index] = updatedItem

            // 直接更新货舱，不调用updateCargo来避免重新计算属性
            simulationInput.cargo = SimCargo(items: updatedItems)
        } else {
            // 添加新的物品
            let newItem = SimCargoItem(
                typeId: typeId,
                quantity: quantity,
                volume: volume,
                name: name,
                iconFileName: iconFileName
            )

            // 添加到物品列表
            var updatedItems = simulationInput.cargo.items
            updatedItems.append(newItem)

            // 直接更新货舱，不调用updateCargo来避免重新计算属性
            simulationInput.cargo = SimCargo(items: updatedItems)
        }

        Logger.info("添加货舱物品成功: \(name), 数量: \(quantity)")
    }

    /// 移除指定类型的货舱物品
    func removeCargoItem(typeId: Int) {
        // 检查是否存在该类型的物品
        let initialCount = simulationInput.cargo.items.count

        // 移除指定类型的物品
        var updatedItems = simulationInput.cargo.items
        updatedItems.removeAll(where: { $0.typeId == typeId })

        // 如果数量没变，说明没有移除任何物品
        if updatedItems.count == initialCount {
            return
        }

        // 直接更新货舱，不调用updateCargo来避免重新计算属性
        simulationInput.cargo = SimCargo(items: updatedItems)

        Logger.info("移除货舱物品成功，类型ID: \(typeId)")
    }

    /// 移除指定索引的货舱物品
    func removeCargoItem(at index: Int) {
        // 检查索引是否有效
        guard index >= 0, index < simulationInput.cargo.items.count else {
            return
        }

        // 移除指定索引的物品
        var updatedItems = simulationInput.cargo.items
        updatedItems.remove(at: index)

        // 直接更新货舱，不调用updateCargo来避免重新计算属性
        simulationInput.cargo = SimCargo(items: updatedItems)

        Logger.info("移除索引为\(index)的货舱物品成功")
    }

    /// 更新货舱物品数量
    func updateCargoItemQuantity(typeId: Int, quantity: Int) {
        // 检查是否存在该类型的物品
        guard let index = simulationInput.cargo.items.firstIndex(where: { $0.typeId == typeId })
        else {
            return
        }

        // 获取当前物品
        let item = simulationInput.cargo.items[index]

        // 如果数量为0或负数，移除物品
        if quantity <= 0 {
            removeCargoItem(typeId: typeId)
            return
        }

        // 创建更新后的物品对象
        let updatedItem = SimCargoItem(
            typeId: item.typeId,
            quantity: quantity,
            volume: item.volume,
            name: item.name,
            iconFileName: item.iconFileName
        )

        // 更新物品列表
        var updatedItems = simulationInput.cargo.items
        updatedItems[index] = updatedItem

        // 直接更新货舱，不调用updateCargo来避免重新计算属性
        simulationInput.cargo = SimCargo(items: updatedItems)

        Logger.info("更新货舱物品成功: \(item.name), 数量: \(quantity)")
    }

    /// 获取物品体积
    func getItemVolume(typeId: Int) -> Double {
        if let volume = ItemInfoMap.typeInfo(for: typeId)?.volume, volume > 0 {
            return volume
        }

        // 如果查询失败或体积为0，返回默认值
        return 1.0
    }
}
