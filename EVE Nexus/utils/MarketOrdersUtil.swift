import Foundation

// 订单类型（买单/卖单）
// // 用于区分市场订单的类型：
// - buy: 买单（玩家挂出的收购订单，价格从高到低排序取最高价）
// - sell: 卖单（玩家挂出的出售订单，价格从低到高排序取最低价）
// // 使用示例：
// ```swift
// // 获取Jita卖价（玩家想卖出时能立即成交的价格）
// let sellPrice = MarketOrdersUtil.calculatePrice(
//     from: orders,
//     orderType: .sell,
//     systemId: 30_000_142
// ).price
// // // 获取Jita买价（玩家想买入时能立即成交的价格）
// let buyPrice = MarketOrdersUtil.calculatePrice(
//     from: orders,
//     orderType: .buy,
//     systemId: 30_000_142
// ).price
// ```
enum OrderType {
    case buy // 买单（收购订单，从高到低排序）
    case sell // 卖单（出售订单，从低到高排序）
}

/// 市场订单工具类 - 提供批量加载市场订单的通用方法
/// // 主要功能：
/// 1. 批量加载星域或建筑的市场订单（自动识别）
/// 2. 支持并发加载（最多10个并发）
/// 3. 支持渐进式UI更新（通过itemCallback）
/// 4. 提供灵活的价格计算方法
/// // 使用场景：
/// - 市场关注列表：批量显示多个物品的价格
/// - 蓝图计算器：计算材料成本
/// - 矿石精炼器：计算产出价值
/// - 合同估价：评估合同价值
enum MarketOrdersUtil {
    // MARK: - 批量加载订单（原始数据）

    // 批量加载市场订单（自动判断星域/建筑）- 推荐使用此方法
    //     // 使用场景：
    // - 需要获取多个物品的市场订单数据
    // - 需要自动适配星域和建筑市场
    // - 需要渐进式显示加载进度
    //     // 示例：
    // ```swift
    // let orders = await MarketOrdersUtil.loadOrders(
    //     typeIds: [34, 35, 36],           // 矿物ID
    //     regionID: 10_000_002,             // Jita星域
    //     itemCallback: { typeId, orders in  // 每完成一个物品就更新UI
    //         Task { @MainActor in
    //             marketOrders[typeId] = orders
    //         }
    //     }
    // )
    // ```
    //     // - Parameters:
    //   - typeIds: 物品ID数组
    //   - regionID: 星域ID（正数，如10000002）或建筑ID（负数，通过StructureMarketManager生成）
    //   - forceRefresh: 是否强制刷新缓存，默认false（使用3小时缓存）
    //   - progressCallback: 进度回调（仅建筑市场有效），用于显示"第X页/共Y页"
    //   - itemCallback: 物品订单完成回调，每完成一个物品的订单加载就调用一次，支持渐进式UI更新
    // - Returns: [物品ID: 订单数组]，失败的物品不会包含在结果中
    static func loadOrders(
        typeIds: [Int],
        regionID: Int,
        forceRefresh: Bool = false,
        progressCallback: ((StructureOrdersProgress) -> Void)? = nil,
        itemCallback: ((Int, [MarketOrder]) -> Void)? = nil
    ) async -> [Int: [MarketOrder]] {
        guard !typeIds.isEmpty else { return [:] }

        // 判断是建筑还是星域
        if StructureMarketManager.isStructureId(regionID) {
            return await loadStructureOrders(
                typeIds: typeIds,
                regionID: regionID,
                forceRefresh: forceRefresh,
                progressCallback: progressCallback,
                itemCallback: itemCallback
            )
        } else {
            return await loadRegionOrders(
                typeIds: typeIds,
                regionID: regionID,
                forceRefresh: forceRefresh,
                itemCallback: itemCallback
            )
        }
    }

    // MARK: - 星域市场订单加载

    // 加载星域市场订单（并发）- 仅需星域订单时使用
    //     // 使用场景：
    // - 已确定是星域市场（非建筑）
    // - 需要从特定星域获取订单数据
    //     // 示例：
    // ```swift
    // // 获取Jita星域的矿物价格
    // let orders = await MarketOrdersUtil.loadRegionOrders(
    //     typeIds: [34, 35, 36],
    //     regionID: 10_000_002,  // The Forge (Jita)
    //     itemCallback: { typeId, orders in
    //         // 实时更新UI
    //     }
    // )
    // ```
    //     // 注意：大多数情况下应使用 loadOrders()，它会自动判断星域/建筑
    //     // - Parameters:
    //   - typeIds: 物品ID数组
    //   - regionID: 星域ID（必须是正数，如10000002表示The Forge）
    //   - forceRefresh: 是否强制刷新
    //   - itemCallback: 可选的回调函数，每完成一个物品的订单加载就会被调用（支持渐进式UI更新）
    // - Returns: [物品ID: 订单数组]
    static func loadRegionOrders(
        typeIds: [Int],
        regionID: Int,
        forceRefresh: Bool = false,
        itemCallback: ((Int, [MarketOrder]) -> Void)? = nil
    ) async -> [Int: [MarketOrder]] {
        guard !typeIds.isEmpty else { return [:] }

        let concurrency = max(1, min(10, typeIds.count))
        Logger.info(" 开始加载星域订单，星域ID: \(regionID)，物品数量: \(typeIds.count)，并发数: \(concurrency)")

        let startTime = Date()
        var result: [Int: [MarketOrder]] = [:]

        await withTaskGroup(of: (Int, [MarketOrder])?.self) { group in
            var pendingTypeIds = typeIds

            // 初始添加并发数量的任务
            for _ in 0 ..< concurrency {
                if !pendingTypeIds.isEmpty {
                    let typeId = pendingTypeIds.removeFirst()
                    group.addTask {
                        do {
                            let orders = try await MarketOrdersAPI.shared.fetchMarketOrders(
                                typeID: typeId,
                                regionID: regionID,
                                forceRefresh: forceRefresh
                            )
                            return (typeId, orders)
                        } catch {
                            Logger.error("加载星域订单失败 (物品ID: \(typeId)): \(error)")
                            return nil
                        }
                    }
                }
            }

            // 处理结果并添加新任务
            while let taskResult = await group.next() {
                if let (typeId, orders) = taskResult {
                    result[typeId] = orders
                    // 立即回调，支持渐进式UI更新
                    itemCallback?(typeId, orders)
                }

                // 如果还有待处理的物品，添加新任务
                if !pendingTypeIds.isEmpty {
                    let typeId = pendingTypeIds.removeFirst()
                    group.addTask {
                        do {
                            let orders = try await MarketOrdersAPI.shared.fetchMarketOrders(
                                typeID: typeId,
                                regionID: regionID,
                                forceRefresh: forceRefresh
                            )
                            return (typeId, orders)
                        } catch {
                            Logger.error("加载星域订单失败 (物品ID: \(typeId)): \(error)")
                            return nil
                        }
                    }
                }
            }
        }

        let duration = Date().timeIntervalSince(startTime)
        Logger.info(" 完成星域订单加载，成功获取 \(result.count)/\(typeIds.count) 个物品的订单数据，耗时: \(String(format: "%.2f", duration))秒")
        return result
    }

    // MARK: - 建筑市场订单加载

    // 加载建筑市场订单（批量）- 仅需建筑订单时使用
    //     // 使用场景：
    // - 已确定是玩家建筑市场
    // - 需要从特定建筑获取订单数据（如空间站、堡垒）
    //     // 示例：
    // ```swift
    // // 获取玩家建筑的订单
    // let structureRegionID = -1234567890  // 通过StructureMarketManager生成的负数ID
    // let orders = await MarketOrdersUtil.loadStructureOrders(
    //     typeIds: [34, 35, 36],
    //     regionID: structureRegionID,
    //     progressCallback: { progress in
    //         // 显示加载进度 (第1页/共3页)
    //     }
    // )
    // ```
    //     // 注意：
    // - 建筑订单需要授权角色访问
    // - 批量加载完成后会逐个触发itemCallback
    // - 大多数情况下应使用 loadOrders()，它会自动判断星域/建筑
    //     // - Parameters:
    //   - typeIds: 物品ID数组
    //   - regionID: 建筑ID（负数，通过StructureMarketManager.getVirtualRegionId()生成）
    //   - forceRefresh: 是否强制刷新
    //   - progressCallback: 进度回调，显示加载进度（当前页/总页数）
    //   - itemCallback: 物品订单完成回调（批量API会在全部完成后逐个回调）
    // - Returns: [物品ID: 订单数组]
    static func loadStructureOrders(
        typeIds: [Int],
        regionID: Int,
        forceRefresh: Bool = false,
        progressCallback: ((StructureOrdersProgress) -> Void)? = nil,
        itemCallback: ((Int, [MarketOrder]) -> Void)? = nil
    ) async -> [Int: [MarketOrder]] {
        guard !typeIds.isEmpty else { return [:] }

        guard let structureId = StructureMarketManager.getStructureId(from: regionID) else {
            Logger.error("无效的建筑ID: \(regionID)")
            return [:]
        }

        guard let structure = MarketStructureManager.shared.structures.first(where: { $0.structureId == Int(structureId) }) else {
            Logger.error("未找到建筑信息: \(structureId)")
            return [:]
        }

        Logger.info(" 开始加载建筑订单，建筑: \(structure.structureName)，物品数量: \(typeIds.count)")

        do {
            let batchOrders = try await StructureMarketManager.shared.getBatchItemOrdersInStructure(
                structureId: structureId,
                characterId: structure.characterId,
                typeIds: typeIds,
                forceRefresh: forceRefresh,
                progressCallback: progressCallback
            )

            Logger.info(" 完成建筑订单加载，成功获取 \(batchOrders.count)/\(typeIds.count) 个物品的订单数据")

            // 逐个回调，支持渐进式UI更新
            if let callback = itemCallback {
                for (typeId, orders) in batchOrders {
                    callback(typeId, orders)
                }
            }

            return batchOrders
        } catch {
            Logger.error("批量加载建筑订单失败: \(error)")
            return [:]
        }
    }

    // MARK: - 价格计算辅助方法

    // 从订单计算价格（通用方法）- 灵活的价格计算核心方法
    //     // 使用场景：
    // - 计算特定订单类型的价格（买单或卖单）
    // - 需要考虑订单数量和库存情况
    // - 需要过滤特定星系的订单（如只要Jita本地订单）
    //     // 示例：
    // ```swift
    // // 场景1: 获取Jita最低卖价（不考虑数量）
    // let sellPrice = MarketOrdersUtil.calculatePrice(
    //     from: orders,
    //     orderType: .sell,
    //     quantity: nil,
    //     systemId: 30_000_142  // Jita星系
    // ).price
    //     // // 场景2: 计算购买1000个矿物的总成本（考虑订单数量）
    // let result = MarketOrdersUtil.calculatePrice(
    //     from: orders,
    //     orderType: .sell,
    //     quantity: 1000,
    //     systemId: 30_000_142
    // )
    // if result.insufficientStock {
    //     print("库存不足，只能买到部分")
    // }
    //     // // 场景3: 获取整个星域的最高买价（不过滤星系）
    // let buyPrice = MarketOrdersUtil.calculatePrice(
    //     from: orders,
    //     orderType: .buy,
    //     quantity: nil,
    //     systemId: nil  // 不过滤星系
    // ).price
    // ```
    //     // - Parameters:
    //   - orders: 市场订单数组
    //   - orderType: 订单类型（.buy=买单, .sell=卖单）
    //   - quantity: 需求数量（nil表示只取最优价格，不考虑库存）
    //   - systemId: 过滤的星系ID（nil表示不过滤，考虑整个星域）
    // - Returns: (价格, 是否库存不足)
    //   - price: 计算出的价格（nil表示无订单）
    //   - insufficientStock: 是否库存不足（仅在quantity不为nil时有意义）
    static func calculatePrice(
        from orders: [MarketOrder],
        orderType: OrderType,
        quantity: Int64? = nil,
        systemId: Int? = nil,
        stationID: Int? = nil
    ) -> (price: Double?, insufficientStock: Bool) {
        guard !orders.isEmpty else { return (nil, true) }

        // 过滤订单类型和星系
        var filteredOrders = orders.filter { order in
            let matchesType = (orderType == .buy) ? order.isBuyOrder : !order.isBuyOrder
            if !matchesType {
                return false
            }
            let matchesSystem = (systemId == nil) || (order.systemId == systemId!)
            let matchesStation = (stationID == nil) || (order.locationId == stationID!)
            return matchesSystem && matchesStation
        }

        // 排序：买单从高到低，卖单从低到高
        filteredOrders.sort { order1, order2 in
            orderType == .buy ? order1.price > order2.price : order1.price < order2.price
        }

        guard !filteredOrders.isEmpty else { return (nil, true) }

        // 如果不考虑数量，直接返回最优价格
        guard let quantity = quantity else {
            return (filteredOrders.first?.price, false)
        }

        // 考虑订单数量的情况
        var remainingQuantity = quantity
        var totalPrice: Double = 0
        var availableQuantity: Int64 = 0

        for order in filteredOrders {
            if remainingQuantity <= 0 {
                break
            }

            let orderQuantity = min(remainingQuantity, Int64(order.volumeRemain))
            totalPrice += Double(orderQuantity) * order.price
            remainingQuantity -= orderQuantity
            availableQuantity += orderQuantity
        }

        // 库存不足
        if remainingQuantity > 0, availableQuantity > 0 {
            return (totalPrice / Double(availableQuantity), true)
        } else if remainingQuantity > 0 {
            return (nil, true)
        }

        // 库存充足
        return (totalPrice / Double(quantity), false)
    }

    // 计算平均价格（买卖价格的平均值）
    //     // 使用场景：
    // - 需要买卖价格的中间值作为参考
    // - 精炼结果展示：显示精炼产出的平均市场价值
    // - 建筑市场价格：计算建筑内订单的平均价格
    //     // 示例：
    // ```swift
    // // 计算Jita星系的平均价格
    // let avgPrice = MarketOrdersUtil.calculateAveragePrice(
    //     from: orders,
    //     systemId: 30_000_142  // 只考虑Jita本地订单
    // )
    //     // // 计算整个星域的平均价格
    // let regionAvgPrice = MarketOrdersUtil.calculateAveragePrice(
    //     from: orders,
    //     systemId: nil  // 考虑星域内所有订单
    // )
    // ```
    //     // 计算逻辑：
    // - 获取最高买单价格和最低卖单价格
    // - 返回两者的平均值
    // - 如果只有一种订单类型，返回该类型的价格
    //     // - Parameters:
    //   - orders: 市场订单数组
    //   - systemId: 星系ID（nil表示不过滤星系，考虑整个星域）
    // - Returns: 平均价格（如果无订单返回0.0）
    static func calculateAveragePrice(
        from orders: [MarketOrder],
        systemId: Int? = nil
    ) -> Double {
        guard !orders.isEmpty else { return 0.0 }

        // 分别获取买价和卖价
        let buyPrice = calculatePrice(from: orders, orderType: .buy, quantity: nil, systemId: systemId).price ?? 0.0
        let sellPrice = calculatePrice(from: orders, orderType: .sell, quantity: nil, systemId: systemId).price ?? 0.0

        // 如果只有一种订单类型，使用该类型的价格
        if buyPrice > 0 && sellPrice > 0 {
            return (buyPrice + sellPrice) / 2.0
        } else if sellPrice > 0 {
            return sellPrice
        } else if buyPrice > 0 {
            return buyPrice
        } else {
            return 0.0
        }
    }
}
