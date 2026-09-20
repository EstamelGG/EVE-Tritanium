
//  JumpPathFinder.swift
//  EVE Nexus

//  Created by GG on 2025/4/1.

import Foundation

/// 跳跃连接结构，保存两个星系间的跳跃信息
struct JumpConnection {
    let sourceId: Int
    let destId: Int
    let distance: Double // 光年距离
}

/// 路径段结构，包含起点、终点和距离
struct PathSegment {
    let src: Int // 起点ID
    let dst: Int // 终点ID
    let range: Double // 距离
}

/// 路径结果结构，包含完整路径和详细信息
struct PathResult {
    let path: [Int] // 路径上的星系ID序列
    let segments: [PathSegment] // 路径段信息
    let totalDistance: Double // 总距离
}

class JumpPathFinder {
    /// 保存星系间的跳跃连接，键为源星系ID，值为可跳跃的目标星系及距离
    private var jumpConnections: [Int: [JumpConnection]] = [:]
    /// 保存星系ID到名称的映射，用于显示
    private var systemIdToName: [Int: String] = [:]
    /// 添加星系ID到安全等级的映射
    private var systemIdToSecurity: [Int: Double] = [:]

    /// 添加一个新的初始化方法，接收预加载的星系数据
    init(databaseManager _: DatabaseManager, preloadedSystems: [JumpSystemData]) {
        loadJumpMap()
        // 使用预加载的星系数据
        systemIdToName = JumpSystemData.getSystemIdToNameMap(from: preloadedSystems)
        systemIdToSecurity = JumpSystemData.getSystemIdToSecurityMap(from: preloadedSystems)

        Logger.info("已使用预加载的星系数据: \(preloadedSystems.count) 个星系")
    }

    /// 从JSON文件加载跳跃地图数据
    private func loadJumpMap() {
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let jumpMapFile = documentsPath.appendingPathComponent("jump_map/jump_map.json")

        if fileManager.fileExists(atPath: jumpMapFile.path) {
            do {
                let data = try Data(contentsOf: jumpMapFile)
                if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    processJumpConnections(jsonArray)
                }
            } catch {
                Logger.error("加载跳跃地图数据失败: \(error.localizedDescription)")
            }
        } else {
            Logger.error("跳跃地图文件不存在")
        }
    }

    /// 处理JSON数据，构建跳跃连接图
    private func processJumpConnections(_ jsonArray: [[String: Any]]) {
        for connection in jsonArray {
            guard let sourceId = connection["s_id"] as? Int,
                  let destId = connection["d_id"] as? Int,
                  let distance = connection["ly"] as? Double
            else {
                continue
            }

            // 添加双向连接
            addConnection(sourceId: sourceId, destId: destId, distance: distance)
            addConnection(sourceId: destId, destId: sourceId, distance: distance)
        }

        // JSON 中的连接顺序不影响同等代价路线的选择。
        for systemId in Array(jumpConnections.keys) {
            jumpConnections[systemId]?.sort {
                ($0.destId, $0.distance) < ($1.destId, $1.distance)
            }
        }

        Logger.info("已加载跳跃连接: \(jumpConnections.count) 个星系")
    }

    /// 添加一个连接到图中
    private func addConnection(sourceId: Int, destId: Int, distance: Double) {
        let connection = JumpConnection(sourceId: sourceId, destId: destId, distance: distance)

        if jumpConnections[sourceId] == nil {
            jumpConnections[sourceId] = []
        }
        jumpConnections[sourceId]?.append(connection)
    }

    /// 检查星系是否满足安全等级要求
    private func isSystemSecurityValid(systemId: Int, isStartPoint: Bool = false) -> Bool {
        // 如果是起点，允许任何安全等级
        if isStartPoint {
            return true
        }

        // 获取星系安全等级
        guard let security = systemIdToSecurity[systemId] else {
            Logger.warning("无法获取星系 \(systemId) 的安全等级信息")
            return false
        }

        // 检查安全等级是否小于0.5
        return security < 0.5
    }

    /// 使用 Dijkstra 算法寻找最少跳数、其次最短距离的路径
    func findPath(
        from startSystemId: Int,
        to destinationSystemIds: [Int],
        shipTypeId: Int,
        skillLevel: Int,
        avoidSystems: [Int] = [],
        avoidIncursions: Bool,
        incursionSystems: [Int] = []
    ) -> [PathResult] {
        // 计算飞船的最大跳跃范围
        let maxJumpRange = calculateMaxJumpRange(shipTypeId: shipTypeId, skillLevel: skillLevel)

        // 记录最大跳跃范围
        Logger.info("计算路径: 最大跳跃范围 \(maxJumpRange) 光年")

        // 处理需要避开的星系
        var combinedAvoidSystems = Set(avoidSystems)

        // 如果需要避开入侵星系，将入侵星系添加到避开列表中
        // 但是不包括起点和目标点
        if avoidIncursions, !incursionSystems.isEmpty {
            // 创建一个用户路径点集合，包括起点和所有目标点
            let userPathPoints = Set([startSystemId] + destinationSystemIds)

            // 过滤入侵星系列表，移除用户选择的路径点
            let filteredIncursionSystems = incursionSystems.filter { !userPathPoints.contains($0) }

            if filteredIncursionSystems.count < incursionSystems.count {
                let skippedSystems = incursionSystems.count - filteredIncursionSystems.count
                Logger.info("用户路径中包含 \(skippedSystems) 个入侵星系，这些星系将不会被规避")
            }

            Logger.info("添加 \(filteredIncursionSystems.count) 个入侵星系到避开列表")
            combinedAvoidSystems = combinedAvoidSystems.union(filteredIncursionSystems)
        }

        if !combinedAvoidSystems.isEmpty {
            Logger.info("总计需避开 \(combinedAvoidSystems.count) 个星系")
        }

        // 存储所有路径结果
        var allPaths: [PathResult] = []

        // 创建集合保存已探索的节点
        var currentSystemId = startSystemId

        // 为每个目标点计算路径
        for destinationId in destinationSystemIds {
            // 检查目标是否在图中
            if !jumpConnections.keys.contains(destinationId) {
                Logger.error("目标星系 \(destinationId) 不在跳跃图中")
                continue
            }

            // 对每个新目的地，从当前位置开始搜索
            let (path, segments, totalDistance) = dijkstraSearch(
                from: currentSystemId,
                to: destinationId,
                maxJumpRange: maxJumpRange,
                avoidSystems: combinedAvoidSystems
            )

            // 如果找到路径，将当前节点更新为最后到达的节点
            if !path.isEmpty {
                allPaths.append(
                    PathResult(path: path, segments: segments, totalDistance: totalDistance)
                )
                currentSystemId = destinationId // 下次从当前终点继续寻路

                // 记录找到的路径
                let pathNames = path.compactMap { systemIdToName[$0] }.joined(separator: " -> ")
                Logger.info("找到路径: \(pathNames), 总距离: \(String(format: "%.2f", totalDistance)) 光年")
            } else {
                // 如果无法找到路径，记录错误
                let startName = systemIdToName[currentSystemId] ?? "未知起点"
                let destName = systemIdToName[destinationId] ?? "未知终点"
                Logger.error(
                    "无法找到从 \(startName)(\(currentSystemId)) 到 \(destName)(\(destinationId)) 的路径"
                )
            }
        }

        return allPaths
    }

    /// 根据飞船类型和技能等级计算最大跳跃范围
    private func calculateMaxJumpRange(shipTypeId: Int, skillLevel: Int) -> Double {
        // 查询飞船基础跳跃范围 (attribute_id 867 表示跳跃范围，内存索引)
        var baseRange = 5.0 // 默认值为5光年

        if let jumpRange = SDEMemoryStore.typeAttributeValue(for: shipTypeId, attributeID: 867) {
            baseRange = jumpRange
            Logger.info("获取到飞船ID \(shipTypeId) 的基础跳跃范围: \(baseRange) 光年")
        } else {
            Logger.warning("未找到飞船ID \(shipTypeId) 的跳跃范围信息，使用默认值 \(baseRange) 光年")
        }

        // 技能等级影响 (每级增加20%)
        let skillMultiplier = 1.0 + Double(skillLevel) * 0.2

        return baseRange * skillMultiplier
    }

    /// Dijkstra 算法核心实现；同等代价按星系 ID 决定处理顺序。
    private func dijkstraSearch(
        from startSystemId: Int,
        to destinationSystemId: Int,
        maxJumpRange: Double,
        avoidSystems: Set<Int>
    ) -> ([Int], [PathSegment], Double) {
        // 如果起点和终点相同，直接返回
        if startSystemId == destinationSystemId {
            return ([startSystemId], [], 0.0)
        }

        // 检查起点和终点是否在连接图中
        guard jumpConnections.keys.contains(startSystemId),
              jumpConnections.keys.contains(destinationSystemId)
        else {
            return ([], [], 0.0)
        }

        // 检查终点是否满足安全等级要求
        guard isSystemSecurityValid(systemId: destinationSystemId) else {
            Logger.error("目标星系 \(destinationSystemId) 不满足安全等级要求")
            return ([], [], 0.0)
        }

        // 定义优先队列（使用数组模拟）
        // 元素格式: (实际跳跃次数, 实际总距离, 节点ID)
        var openQueue: [(jumps: Double, distance: Double, systemId: Int)] = []
        var closedSet = Set<Int>()

        // 记录来源节点，用于重建路径
        var cameFrom: [Int: Int] = [:]

        // g_score存储从起点到当前节点的实际代价 (跳跃次数, 总距离)
        var gScore: [Int: (jumps: Double, distance: Double)] = [startSystemId: (0, 0)]

        // 记录节点间距离
        var nodeDistances: [Int: Double] = [:]

        // 初始化优先队列
        openQueue.append((0, 0, startSystemId))

        while !openQueue.isEmpty {
            // 获取优先级最高的节点（跳跃次数最少，在跳跃次数相同的情况下总距离最短）
            openQueue.sort { ($0.jumps, $0.distance, $0.systemId) < ($1.jumps, $1.distance, $1.systemId) }
            let current = openQueue.removeFirst()
            let currentId = current.systemId

            // 如果到达目标，重建路径并返回
            if currentId == destinationSystemId {
                return reconstructPathWithDistances(
                    cameFrom: cameFrom, end: currentId, gScore: gScore, nodeDistances: nodeDistances
                )
            }

            // 将当前节点加入已访问集合
            closedSet.insert(currentId)

            // 获取当前节点的所有连接
            guard let connections = jumpConnections[currentId] else {
                continue
            }

            // 遍历所有可能的下一跳
            for connection in connections {
                let neighborId = connection.destId

                // 跳过已经处理过的节点和需要避开的星系
                if closedSet.contains(neighborId) || avoidSystems.contains(neighborId) {
                    continue
                }

                // 检查跳跃范围
                if connection.distance > maxJumpRange {
                    continue
                }

                // 检查安全等级要求（除了起点）
                if !isSystemSecurityValid(
                    systemId: neighborId, isStartPoint: neighborId == startSystemId
                ) {
                    continue
                }

                // 计算从起点经过当前节点到邻居节点的跳跃次数和距离
                let currentJumps = gScore[currentId]!.jumps
                let currentDistance = gScore[currentId]!.distance
                let tentativeJumps = currentJumps + 1 // 每次跳跃加1
                let tentativeDistance = currentDistance + connection.distance

                // 如果邻居节点尚未被评估或找到了更好的路径
                let isNewPath = !gScore.keys.contains(neighborId)
                let isBetterPath =
                    !isNewPath
                        && (tentativeJumps < gScore[neighborId]!.jumps
                            || (tentativeJumps == gScore[neighborId]!.jumps
                                && tentativeDistance < gScore[neighborId]!.distance))

                if isNewPath || isBetterPath {
                    // 更新来源节点
                    cameFrom[neighborId] = currentId

                    // 更新g_score
                    gScore[neighborId] = (tentativeJumps, tentativeDistance)

                    // 记录节点间距离
                    nodeDistances[neighborId] = connection.distance

                    // 如果这是新路径或者是更好的路径，添加到优先队列
                    if isNewPath {
                        openQueue.append((tentativeJumps, tentativeDistance, neighborId))
                    } else {
                        // 移除旧的评估，添加新的评估
                        openQueue.removeAll { $0.systemId == neighborId }
                        openQueue.append((tentativeJumps, tentativeDistance, neighborId))
                    }
                }
            }
        }

        // 如果执行到这里，说明没有找到路径
        return ([], [], 0.0)
    }

    /// 使用距离信息重建路径
    private func reconstructPathWithDistances(
        cameFrom: [Int: Int],
        end: Int,
        gScore: [Int: (jumps: Double, distance: Double)],
        nodeDistances: [Int: Double]
    ) -> ([Int], [PathSegment], Double) {
        var path: [Int] = []
        var segments: [PathSegment] = []
        var current = end

        // 从终点回溯到起点
        while let parent = cameFrom[current] {
            path.append(current)
            if let distance = nodeDistances[current] {
                segments.append(PathSegment(src: parent, dst: current, range: distance))
            }
            current = parent
        }

        // 添加起点
        path.append(current)

        // 反转路径和段以获得从起点到终点的顺序
        path.reverse()
        segments.reverse()

        // 返回路径、段和总距离
        return (path, segments, gScore[end]?.distance ?? 0.0)
    }
}
