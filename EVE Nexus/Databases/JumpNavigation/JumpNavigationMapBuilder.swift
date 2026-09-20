import Foundation

class JumpNavigationHandler {
    /// 建图规则变更时递增，使旧连接缓存失效。
    static let cacheVersion = 2

    /// 光年转换常量
    private static let LY_CONVERSION: Double = 1.0 / 9_460_000_000_000_000.0

    /// 计算两点之间的距离（光年）
    static func calculateDistanceLY(
        x1: Double, y1: Double, z1: Double, x2: Double, y2: Double, z2: Double
    ) -> Double {
        // 计算欧几里得距离
        let distanceM = sqrt(pow(x1 - x2, 2) + pow(y1 - y2, 2) + pow(z1 - z2, 2))

        // 转换为光年
        return distanceM * LY_CONVERSION
    }

    /// 获取所有符合条件的星系对
    static func getNearbySystems(
        databaseManager: DatabaseManager, progressUpdate: ((String, Double) -> Void)? = nil
    ) -> [[String: Any]] {
        // 加载所有跳跃星系数据
        let jumpSystems = JumpSystemData.loadAllJumpSystems(databaseManager: databaseManager)

        // 调用使用预加载星系数据的方法
        return getNearbySystems(preloadedSystems: jumpSystems, progressUpdate: progressUpdate)
    }

    /// 获取所有符合条件的星系对，使用预加载的星系数据
    static func getNearbySystems(
        preloadedSystems: [JumpSystemData], progressUpdate: ((String, Double) -> Void)? = nil
    ) -> [[String: Any]] {
        // 通知进度：开始查询 - 执行SQL和星系过滤占进度1%
        progressUpdate?("Jump_Navigation_Preparing_Jump_Data", 0.005)

        // 使用传入的预加载星系数据
        let jumpSystems = preloadedSystems.sorted { $0.id < $1.id }

        var nearbyPairs: [[String: Any]] = []

        // 通知进度：开始计算距离 - 计算过程占进度98%
        progressUpdate?(
            NSLocalizedString("Jump_Navigation_Processing_System_Data", comment: ""), 0.01
        )

        // 创建星系数据的简化版本，仅包含计算所需的字段
        let filteredSystems = jumpSystems.map { system in
            (solarsystem_id: system.id, x: system.x, y: system.y, z: system.z, sec: system.security)
        }

        // 通知进度：开始计算距离 - 计算过程占进度98%
        progressUpdate?(
            NSLocalizedString("Jump_Navigation_Calculating_Jump_Distance", comment: ""), 0.01
        )
        let totalPairs = (filteredSystems.count * (filteredSystems.count - 1)) / 2
        var processedPairs = 0

        // 计算所有星系对之间的距离
        for i in 0 ..< filteredSystems.count {
            for j in (i + 1) ..< filteredSystems.count {
                let sys1 = filteredSystems[i]
                let sys2 = filteredSystems[j]

                // 检查安全等级要求：至少有一个星系的安全等级小于0.5
                if sys1.sec >= 0.5, sys2.sec >= 0.5 {
                    processedPairs += 1
                    continue
                }

                let distanceLY = calculateDistanceLY(
                    x1: sys1.x, y1: sys1.y, z1: sys1.z,
                    x2: sys2.x, y2: sys2.y, z2: sys2.z
                )

                processedPairs += 1
                // 计算过程占总进度的98%（0.01-0.99）
                let progress = 0.01 + (Double(processedPairs) / Double(totalPairs)) * 0.98

                // 每处理500对星系更新一次进度，不显示详细计算信息
                if processedPairs % 500 == 0 {
                    progressUpdate?(
                        NSLocalizedString("Jump_Navigation_Calculating_Jump_Distance", comment: ""),
                        progress
                    )
                }

                if distanceLY <= 10 {
                    // j > i 已保证每对星系只处理一次；输入按 ID 排序。
                    nearbyPairs.append([
                        "s_id": sys1.solarsystem_id,
                        "d_id": sys2.solarsystem_id,
                        "ly": distanceLY,
                    ])
                }
            }
        }

        Logger.info("计算完成：总共处理了 \(processedPairs) 对星系，找到 \(nearbyPairs.count) 对可跳跃星系")
        return nearbyPairs
    }

    /// 保存数据到JSON文件
    static func saveToJSON(data: [[String: Any]]) {
        if data.isEmpty {
            Logger.info("没有数据需要保存")
            return
        }

        // 获取Documents目录
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let jumpMapPath = documentsPath.appendingPathComponent("jump_map")

        // 创建输出目录
        try? fileManager.createDirectory(at: jumpMapPath, withIntermediateDirectories: true)

        // 保存到JSON文件
        let filename = jumpMapPath.appendingPathComponent("jump_map.json")
        do {
            let jsonData = try JSONSerialization.data(
                withJSONObject: data, options: [.prettyPrinted]
            )
            try jsonData.write(to: filename)
            Logger.info("数据已保存到: \(filename.path)")
        } catch {
            Logger.error("保存JSON文件时出错: \(error.localizedDescription)")
        }
    }

    /// 处理跳跃导航数据，可以使用预加载的星系数据
    static func processJumpNavigationData(
        databaseManager: DatabaseManager,
        preloadedSystems: [JumpSystemData]? = nil,
        progressUpdate: ((String, Double) -> Void)? = nil
    ) {
        // 获取结果
        let results: [[String: Any]]
        if let preloadedSystems = preloadedSystems {
            // 使用预加载的星系数据
            results = getNearbySystems(
                preloadedSystems: preloadedSystems, progressUpdate: progressUpdate
            )
        } else {
            // 使用常规方法加载星系数据
            results = getNearbySystems(
                databaseManager: databaseManager, progressUpdate: progressUpdate
            )
        }

        // 通知进度：保存数据 - 保存文件占进度1%
        progressUpdate?(NSLocalizedString("Jump_Navigation_Save_Jump_Map", comment: ""), 0.99)

        // 保存到JSON文件
        saveToJSON(data: results)

        // 通知处理完成
        progressUpdate?(NSLocalizedString("Misc_Done", comment: ""), 1.0)
    }
}
