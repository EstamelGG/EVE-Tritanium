import Foundation

extension FitConvert {
    /// 将在线配置JSON数据解析为本地配置模型
    static func online2local(jsonData: Data) throws -> [LocalFitting] {
        let decoder = JSONDecoder()
        let onlineFittings = try decoder.decode([OnlineFitting].self, from: jsonData)
        return onlineFittings.map { online in
            // 从items中提取无人机、货舱和舰载机信息
            let drones = online.items
                .filter { $0.flag == .droneBay }
                .map { Drone(type_id: $0.type_id, quantity: $0.quantity, active_count: 0, muta: nil) }

            let cargo = online.items
                .filter { $0.flag == .cargo }
                .map { CargoItem(type_id: $0.type_id, quantity: $0.quantity) }

            // 获取数据库管理器
            let databaseManager = DatabaseManager.shared

            // 从舰载机舱中筛选出舰载机
            let fighterBayItems = online.items.filter { $0.flag == .fighterBay }

            // 处理舰载机配置
            if AppConfiguration.Fitting.showDebug {
                Logger.info("准备处理舰载机配置，找到 \(fighterBayItems.count) 个舰载机物品")
            }
            let fighters = processFighters(
                shipTypeId: online.ship_type_id,
                fighterBayItems: fighterBayItems,
                databaseManager: databaseManager
            )
            if AppConfiguration.Fitting.showDebug {
                Logger.info("舰载机处理完成，生成了 \(fighters.count) 个FighterSquad")
            }

            // 过滤掉无人机、货舱和舰载机，只保留装备
            var equipmentItems = online.items.filter {
                $0.flag != .droneBay && $0.flag != .cargo && $0.flag != .fighterBay
            }

            // 检查是否为模式切换飞船，如果是则添加默认模式
            let shipTypeId = online.ship_type_id

            // 使用新的工具函数检查飞船是否支持模式切换
            if ModeSwitchingUtils.isModeSwitchingShip(
                shipTypeId: shipTypeId,
                databaseManager: databaseManager
            ) {
                // 获取默认模式ID
                if let defaultModeId = ModeSwitchingUtils.getDefaultModeId(
                    for: shipTypeId,
                    databaseManager: databaseManager
                ) {
                    // 将模式作为模块添加到装备列表中
                    let modeItem = FittingItem(
                        flag: .t3dModeSlot0,
                        quantity: 1,
                        type_id: defaultModeId
                    )

                    // 添加模式到装备列表
                    equipmentItems.append(modeItem)
                    if AppConfiguration.Fitting.showDebug {
                        Logger.info("在线配置导入: 为模式切换飞船(ID: \(shipTypeId))添加默认模式模块: \(defaultModeId)")
                    }
                }
            }

            return LocalFitting(
                description: online.description,
                fitting_id: UUID(),
                items: equipmentItems.map { item in
                    // 在线配置中没有弹药、突变和预热信息
                    LocalFittingItem(
                        flag: item.flag,
                        quantity: item.quantity,
                        type_id: item.type_id,
                        status: nil // 在线配置未提供启动状态，由加载器选择默认在线/激活状态
                    )
                },
                name: online.name,
                ship_type_id: online.ship_type_id,
                drones: drones.isEmpty ? nil : drones, // 如果没有无人机则为nil
                fighters: fighters.isEmpty ? nil : fighters, // 如果没有舰载机则为nil
                cargo: cargo.isEmpty ? nil : cargo // 如果没有货舱物品则为nil
                // 在线配置中没有植入体和环境信息
            )
        }
    }

    /// 将本地配置保存为JSON文件
    static func saveLocalFitting(_ fitting: LocalFitting) throws {
        // 获取文档目录
        guard
            let documentsDirectory = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first
        else {
            throw NSError(
                domain: "FitConvert", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法访问文档目录"]
            )
        }

        // 创建Fitting目录
        let fittingsDirectory = documentsDirectory.appendingPathComponent("Fitting")
        if !FileManager.default.fileExists(atPath: fittingsDirectory.path) {
            try FileManager.default.createDirectory(
                at: fittingsDirectory, withIntermediateDirectories: true
            )
        }

        // 创建文件路径
        let filePath = fittingsDirectory.appendingPathComponent(
            "local_fitting_\(fitting.fitting_id.uuidString).json"
        )

        // 将配置转换为JSON数据
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted // 美化输出格式
        let jsonData = try encoder.encode(fitting)

        // 写入文件
        try jsonData.write(to: filePath)

        Logger.info("配置已保存到: \(filePath.path)")
    }

    /// 从JSON文件加载本地配置
    static func loadLocalFitting(fittingId: UUID) throws -> LocalFitting {
        // 获取文档目录
        guard
            let documentsDirectory = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first
        else {
            throw NSError(
                domain: "FitConvert", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法访问文档目录"]
            )
        }

        // 创建文件路径
        let filePath = documentsDirectory.appendingPathComponent(
            "Fitting/local_fitting_\(fittingId.uuidString).json"
        )

        // 读取文件数据
        let jsonData = try Data(contentsOf: filePath)

        // 解码JSON数据
        let decoder = JSONDecoder()
        return try decoder.decode(LocalFitting.self, from: jsonData)
    }

    /// 本地装配加载结果：正常装配 + 无法解析的装配（仅元数据）
    struct LocalFittingLoadResult {
        let fittings: [LocalFitting]
        let unreadable: [UnreadableFitting]
    }

    /// 从JSON文件加载所有本地配置。
    /// 坏文件处理：尝试抢救装配名与飞船ID——两者皆无法取得则删除文件，否则保留并标记为无法解析
    static func loadAllLocalFittings() throws -> LocalFittingLoadResult {
        // 获取文档目录
        guard
            let documentsDirectory = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first
        else {
            throw NSError(
                domain: "FitConvert", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法访问文档目录"]
            )
        }

        // 创建Fitting目录路径
        let fittingsDirectory = documentsDirectory.appendingPathComponent("Fitting")

        // 检查目录是否存在
        guard FileManager.default.fileExists(atPath: fittingsDirectory.path) else {
            return LocalFittingLoadResult(fittings: [], unreadable: [])
        }

        // 获取目录中的所有文件
        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: fittingsDirectory, includingPropertiesForKeys: nil
        )

        // 过滤出配置文件并加载（顺带迁移旧版时间戳文件到 UUID 文件）
        var fittings: [LocalFitting] = []
        var unreadable: [UnreadableFitting] = []
        for fileURL in fileURLs
            where fileURL.lastPathComponent.hasPrefix("local_fitting_")
            && fileURL.pathExtension == "json"
        {
            let fileName = fileURL.lastPathComponent
            do {
                let jsonData = try Data(contentsOf: fileURL)
                let decoder = JSONDecoder()
                let fitting = try decoder.decode(LocalFitting.self, from: jsonData)

                // 旧版文件名为时间戳、JSON 内 fitting_id 为 Int（解码时已生成新 UUID）：
                // 文件名与 ID 不一致即需迁移——写入 UUID 新文件并删除旧文件
                let expectedName = "local_fitting_\(fitting.fitting_id.uuidString).json"
                if fileName != expectedName {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = .prettyPrinted
                    let newData = try encoder.encode(fitting)
                    try newData.write(to: fittingsDirectory.appendingPathComponent(expectedName))
                    try? FileManager.default.removeItem(at: fileURL)
                    Logger.info(
                        "旧版装配文件已迁移到 UUID: \(fileName) -> \(expectedName)"
                    )
                }

                fittings.append(fitting)
            } catch {
                // 完整解码失败：仅抢救装配名与飞船ID（不解析装配内容）
                let meta = salvageMetadata(fromFile: fileURL)
                if meta.name == nil && meta.shipTypeId == nil {
                    // 连基本信息都无法取得，视为彻底损坏，删除文件
                    try? FileManager.default.removeItem(at: fileURL)
                    Logger.warning("装配文件完全无法解析，已删除: \(fileName)")
                } else {
                    Logger.warning(
                        "装配文件解析失败，保留并标记为无法解析: \(fileName) - \(error.localizedDescription)"
                    )
                    unreadable.append(
                        UnreadableFitting(
                            fileName: fileName, name: meta.name, shipTypeId: meta.shipTypeId
                        )
                    )
                }
            }
        }

        return LocalFittingLoadResult(fittings: fittings, unreadable: unreadable)
    }

    /// 抢救解析：仅从原始 JSON 提取装配名与飞船ID，兼容数字被序列化为 Double/字符串的情况
    private static func salvageMetadata(fromFile fileURL: URL) -> (name: String?, shipTypeId: Int?) {
        guard let data = try? Data(contentsOf: fileURL),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return (nil, nil) }

        let name = obj["name"] as? String
        let shipTypeId = (obj["ship_type_id"] as? Int)
            ?? (obj["ship_type_id"] as? Double).map(Int.init)
            ?? (obj["ship_type_id"] as? String).flatMap(Int.init)
        return (name, shipTypeId)
    }
}
