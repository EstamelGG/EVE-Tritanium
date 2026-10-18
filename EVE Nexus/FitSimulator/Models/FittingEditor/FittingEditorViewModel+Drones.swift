import Foundation
import SwiftUI

extension FittingEditorViewModel {
    // MARK: - 无人机相关属性

    /// 无人机属性计算结果
    var droneAttributes:
        (
            bandwidth: (current: Double, total: Double), capacity: (current: Double, total: Double),
            dronesCount: Int, activeDronesCount: Int
        )
    {
        // 计算无人机带宽
        let totalBandwidth: Double
        if let simulationOutput = simulationOutput {
            totalBandwidth = simulationOutput.ship.attributesByName["droneBandwidth"] ?? 0
        } else {
            totalBandwidth = simulationInput.ship.baseAttributesByName["droneBandwidth"] ?? 0
        }

        // 计算当前使用的带宽
        var currentBandwidth = 0.0
        for drone in simulationInput.drones {
            if drone.activeCount > 0 {
                // 尝试从计算后的属性中获取带宽需求
                let droneBandwidthNeed: Double
                if let simulationOutput = simulationOutput,
                   let droneIndex = simulationOutput.drones.firstIndex(where: {
                       $0.typeId == drone.typeId
                   }),
                   let bandwidth = simulationOutput.drones[droneIndex].attributesByName[
                       "droneBandwidthUsed"
                   ]
                {
                    droneBandwidthNeed = bandwidth
                } else {
                    droneBandwidthNeed = drone.attributesByName["droneBandwidthUsed"] ?? 0
                }
                currentBandwidth += droneBandwidthNeed * Double(drone.activeCount)
            }
        }

        // 计算无人机舱容量
        let totalCapacity: Double
        if let simulationOutput = simulationOutput {
            totalCapacity = simulationOutput.ship.attributesByName["droneCapacity"] ?? 0
        } else {
            totalCapacity = simulationInput.ship.baseAttributesByName["droneCapacity"] ?? 0
        }

        // 计算当前使用的容量
        var currentCapacity = 0.0
        for drone in simulationInput.drones {
            // 尝试从计算后的属性中获取无人机体积
            let droneVolume: Double
            if let simulationOutput = simulationOutput,
               let droneIndex = simulationOutput.drones.firstIndex(where: {
                   $0.typeId == drone.typeId
               }),
               let volume = simulationOutput.drones[droneIndex].attributesByName["volume"]
            {
                droneVolume = volume
            } else {
                droneVolume = drone.attributesByName["volume"] ?? 0.0
            }
            currentCapacity += droneVolume * Double(drone.quantity)
        }

        // 计算无人机数量
        let dronesCount = simulationInput.drones.reduce(0) { $0 + $1.quantity }

        // 计算激活的无人机数量
        let activeDronesCount = simulationInput.drones.reduce(0) { $0 + $1.activeCount }

        return (
            bandwidth: (current: currentBandwidth, total: totalBandwidth),
            capacity: (current: currentCapacity, total: totalCapacity),
            dronesCount: dronesCount,
            activeDronesCount: activeDronesCount
        )
    }

    /// 最大可激活无人机数量
    var maxActiveDrones: Int {
        // 从角色属性中获取maxActiveDrones值（属性ID 352）
        if let simulationOutput = simulationOutput,
           let maxDrones = simulationOutput.ship.characterAttributes[352]
        {
            return Int(maxDrones)
        }
        // 如果无法获取计算后的值，从模拟输入中获取基础值
        return Int(simulationInput.character.baseAttributes[352] ?? 5)
    }

    // MARK: - 无人机相关方法

    /// 添加无人机到配置中
    func addDrone(
        typeId: Int, name: String, iconFileName: String?, quantity: Int, activeCount: Int = 0
    ) {
        // 获取无人机信息
        let droneInfo = getDroneInfo(typeId: typeId)

        // 如果无法获取无人机信息，直接返回
        guard let droneInfo = droneInfo else {
            Logger.error("无法获取无人机信息: \(typeId)")
            return
        }

        // 检查是否已存在相同类型的无人机
        if let index = simulationInput.drones.firstIndex(where: { $0.typeId == typeId }) {
            // 更新现有无人机数量
            let existingDrone = simulationInput.drones[index]
            let newQuantity = existingDrone.quantity + quantity
            let newActiveCount = existingDrone.activeCount + activeCount

            // 创建更新后的无人机对象（保留突变数据）
            var updatedDrone = SimDrone(
                typeId: existingDrone.typeId,
                attributes: existingDrone.attributes,
                attributesByName: existingDrone.attributesByName,
                effects: existingDrone.effects,
                quantity: newQuantity,
                activeCount: newActiveCount,
                groupID: existingDrone.groupID,
                requiredSkills: existingDrone.requiredSkills,
                name: existingDrone.name,
                iconFileName: existingDrone.iconFileName
            )
            // 保留突变数据（包括显示信息）
            updatedDrone.selectedMutaplasmidID = existingDrone.selectedMutaplasmidID
            updatedDrone.mutatedAttributes = existingDrone.mutatedAttributes
            updatedDrone.mutatedTypeId = existingDrone.mutatedTypeId
            updatedDrone.mutatedName = existingDrone.mutatedName
            updatedDrone.mutatedIconFileName = existingDrone.mutatedIconFileName

            // 更新无人机列表
            simulationInput.drones[index] = updatedDrone
        } else {
            // 添加新的无人机
            let newDrone = SimDrone(
                typeId: typeId,
                attributes: droneInfo.attributes,
                attributesByName: droneInfo.attributesByName,
                effects: droneInfo.effects,
                quantity: quantity,
                activeCount: activeCount,
                groupID: droneInfo.groupID,
                requiredSkills: FitConvert.extractRequiredSkills(attributes: droneInfo.attributes),
                name: name,
                iconFileName: iconFileName
            )

            // 添加到无人机列表
            simulationInput.drones.append(newDrone)
        }

        // 重新计算属性
        Logger.info("添加无人机，重新计算属性")
        calculateAttributes()

        Logger.info("添加无人机成功: \(name), 数量: \(quantity), 激活数量: \(activeCount)")
    }

    /// 移除指定类型的无人机
    func removeDrone(typeId: Int) {
        // 检查是否存在该类型的无人机
        let initialCount = simulationInput.drones.count

        // 移除指定类型的无人机
        simulationInput.drones.removeAll(where: { $0.typeId == typeId })

        // 如果数量没变，说明没有移除任何无人机
        if simulationInput.drones.count == initialCount {
            return
        }

        // 重新计算属性
        Logger.info("移除无人机，重新计算属性")
        calculateAttributes()

        Logger.info("移除无人机成功，类型ID: \(typeId)")
    }

    /// 移除指定索引的无人机
    func removeDrone(at index: Int) {
        // 检查索引是否有效
        guard index >= 0, index < simulationInput.drones.count else {
            return
        }

        // 移除指定索引的无人机
        simulationInput.drones.remove(at: index)

        // 重新计算属性
        Logger.info("移除无人机，重新计算属性")
        calculateAttributes()

        Logger.info("移除索引为\(index)的无人机成功")
    }

    /// 获取无人机信息
    func getDroneInfo(typeId: Int) -> (
        attributes: [Int: Double], attributesByName: [String: Double], effects: [Int],
        volume: Double, bandwidth: Double, groupID: Int
    )? {
        var attributes: [Int: Double] = [:]
        var attributesByName: [String: Double] = [:]
        var effects: [Int] = []
        var volume: Double = 0
        var bandwidth: Double = 0
        let groupID = getDroneGroupID(typeId: typeId)

        // 查询无人机属性（内存索引）
        (attributes, attributesByName) = SDEMemoryStore.typeAttributesFull(for: typeId)

        // 如果是带宽属性，记录下来
        if let value = attributesByName["droneBandwidthUsed"] {
            bandwidth = value
        }

        // 查询无人机效果
        effects = SDEMemoryStore.effectIDs(forType: typeId)

        // 查询无人机体积
        if let info = ItemInfoMap.typeInfo(for: typeId), info.volume > 0 {
            volume = info.volume

            // 将volume添加到属性字典中
            attributes[161] = volume
            attributesByName["volume"] = volume
        }

        return (
            attributes: attributes, attributesByName: attributesByName, effects: effects,
            volume: volume, bandwidth: bandwidth, groupID: groupID
        )
    }

    /// 更新无人机数量和激活数量
    func updateDroneQuantity(typeId: Int, quantity: Int, activeCount: Int) {
        // 检查是否存在该类型的无人机
        guard let index = simulationInput.drones.firstIndex(where: { $0.typeId == typeId }) else {
            return
        }

        // 获取当前无人机
        let drone = simulationInput.drones[index]

        // 创建更新后的无人机对象（保留突变数据）
        var updatedDrone = SimDrone(
            typeId: drone.typeId,
            attributes: drone.attributes,
            attributesByName: drone.attributesByName,
            effects: drone.effects,
            quantity: quantity,
            activeCount: activeCount,
            groupID: drone.groupID,
            requiredSkills: drone.requiredSkills,
            name: drone.name,
            iconFileName: drone.iconFileName
        )
        // 保留突变数据（包括显示信息）
        updatedDrone.selectedMutaplasmidID = drone.selectedMutaplasmidID
        updatedDrone.mutatedAttributes = drone.mutatedAttributes
        updatedDrone.mutatedTypeId = drone.mutatedTypeId
        updatedDrone.mutatedName = drone.mutatedName
        updatedDrone.mutatedIconFileName = drone.mutatedIconFileName

        // 更新无人机列表
        simulationInput.drones[index] = updatedDrone

        // 移除重新计算属性的调用，只更新无人机相关的UI
        // calculateAttributes()

        Logger.info("更新无人机成功: \(drone.name), 数量: \(quantity), 激活数量: \(activeCount)")
    }

    /// 更新无人机的突变数据
    func updateDroneMutation(typeId: Int, mutaplasmidID: Int?, mutatedAttributes: [Int: Double]) {
        guard let index = simulationInput.drones.firstIndex(where: { $0.typeId == typeId }) else {
            Logger.warning("更新无人机突变数据失败: 未找到无人机 typeId \(typeId)")
            return
        }

        let currentDrone = simulationInput.drones[index]

        // 查询突变后的typeID、名称和图标
        var mutatedTypeId: Int? = nil
        var mutatedName: String? = nil
        var mutatedIconFileName: String? = nil

        if let mutaplasmidID = mutaplasmidID {
            if let resultingTypeId = databaseManager.getMutatedTypeID(
                applicableTypeID: currentDrone.typeId,
                mutaplasmidID: mutaplasmidID
            ) {
                mutatedTypeId = resultingTypeId

                // 查询突变后的名称和图标
                if let info = ItemInfoMap.typeInfo(for: resultingTypeId) {
                    mutatedName = info.name
                    mutatedIconFileName = info.iconFilename
                }
            }
        }

        var updatedDrone = currentDrone
        updatedDrone.selectedMutaplasmidID = mutaplasmidID
        updatedDrone.mutatedAttributes = mutatedAttributes
        updatedDrone.mutatedTypeId = mutatedTypeId
        updatedDrone.mutatedName = mutatedName
        updatedDrone.mutatedIconFileName = mutatedIconFileName

        simulationInput.drones[index] = updatedDrone

        // 重新计算属性（突变会影响属性值）
        Logger.info("更新无人机突变数据，重新计算属性")
        calculateAttributes()

        Logger.info("更新无人机突变数据成功: \(currentDrone.name), 突变质体ID: \(mutaplasmidID?.description ?? "nil"), 突变属性数量: \(mutatedAttributes.count)")
    }

    /// 替换无人机（保持数量和激活数量）
    func replaceDrone(oldTypeId: Int, newTypeId: Int) {
        // 检查是否存在旧无人机
        guard let index = simulationInput.drones.firstIndex(where: { $0.typeId == oldTypeId })
        else {
            return
        }

        // 获取旧无人机信息
        let oldDrone = simulationInput.drones[index]
        let oldQuantity = oldDrone.quantity
        let oldActiveCount = oldDrone.activeCount

        // 如果新旧ID相同，无需替换
        if oldTypeId == newTypeId {
            return
        }

        // 检查新类型无人机是否已存在
        if let existingIndex = simulationInput.drones.firstIndex(where: { $0.typeId == newTypeId }) {
            // 已存在新类型无人机，将旧的数量合并到新的上
            let existingDrone = simulationInput.drones[existingIndex]
            let newQuantity = existingDrone.quantity + oldQuantity
            let newActiveCount = existingDrone.activeCount + oldActiveCount

            // 创建更新后的无人机对象（保留突变数据）
            var updatedDrone = SimDrone(
                typeId: existingDrone.typeId,
                attributes: existingDrone.attributes,
                attributesByName: existingDrone.attributesByName,
                effects: existingDrone.effects,
                quantity: newQuantity,
                activeCount: newActiveCount,
                groupID: existingDrone.groupID,
                requiredSkills: existingDrone.requiredSkills,
                name: existingDrone.name,
                iconFileName: existingDrone.iconFileName
            )
            // 保留突变数据（包括显示信息）
            updatedDrone.selectedMutaplasmidID = existingDrone.selectedMutaplasmidID
            updatedDrone.mutatedAttributes = existingDrone.mutatedAttributes
            updatedDrone.mutatedTypeId = existingDrone.mutatedTypeId
            updatedDrone.mutatedName = existingDrone.mutatedName
            updatedDrone.mutatedIconFileName = existingDrone.mutatedIconFileName

            // 更新已存在的无人机
            simulationInput.drones[existingIndex] = updatedDrone

            // 移除旧无人机
            simulationInput.drones.remove(at: index)
        } else {
            // 获取新无人机信息
            guard let newDroneInfo = getDroneInfo(typeId: newTypeId) else {
                Logger.error("无法获取新无人机信息: \(newTypeId)")
                return
            }

            // 查询新无人机的名称和图标
            var newName = "无人机"
            var newIconFileName: String? = nil

            if let info = ItemInfoMap.typeInfo(for: newTypeId) {
                newName = info.name
                newIconFileName = info.iconFilename
            }

            // 创建新无人机（无人机更换后清除突变信息）
            var newDrone = SimDrone(
                typeId: newTypeId,
                attributes: newDroneInfo.attributes,
                attributesByName: newDroneInfo.attributesByName,
                effects: newDroneInfo.effects,
                quantity: oldQuantity,
                activeCount: oldActiveCount,
                groupID: newDroneInfo.groupID,
                requiredSkills: FitConvert.extractRequiredSkills(
                    attributes: newDroneInfo.attributes
                ),
                name: newName,
                iconFileName: newIconFileName
            )
            // 清除突变信息
            newDrone.selectedMutaplasmidID = nil
            newDrone.mutatedAttributes = [:]

            // 替换无人机
            simulationInput.drones[index] = newDrone
        }

        // 重新计算属性
        Logger.info("替换无人机，重新计算属性")
        calculateAttributes()

        Logger.info("替换无人机成功: 从ID \(oldTypeId) 到 ID \(newTypeId)")
    }

    func getDroneGroupID(typeId: Int) -> Int {
        ItemInfoMap.typeInfo(for: typeId)?.groupID ?? 0
    }
}
