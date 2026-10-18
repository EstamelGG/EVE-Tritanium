import Foundation

extension FitConvert {
    private static let fittingPersistenceLock = NSRecursiveLock()

    private static func fittingDirectory(_ directory: URL?) throws -> URL {
        if let directory {
            return directory
        }
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "FitConvert", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法访问文档目录"])
        }
        return documents.appendingPathComponent("Fitting")
    }

    /// 原子替换必须沿用磁盘上的实际文件名，避免大小写别名触发 File exists。
    private static func existingFittingFileURL(fittingId: UUID, directory: URL) throws -> URL {
        let expectedName = "local_fitting_\(fittingId.uuidString).json"
        let expectedURL = directory.appendingPathComponent(expectedName)
        let candidates = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        if let exact = candidates.first(where: { $0.lastPathComponent == expectedName }) {
            return exact
        }
        return candidates.first { $0.lastPathComponent.caseInsensitiveCompare(expectedName) == .orderedSame }
            ?? expectedURL
    }

    /// Loading, saving and deleting must resolve UUID filename casing in the same way.
    static func localFittingFileURL(fittingId: UUID, directory: URL? = nil) throws -> URL {
        fittingPersistenceLock.lock()
        defer { fittingPersistenceLock.unlock() }
        return try existingFittingFileURL(fittingId: fittingId, directory: fittingDirectory(directory))
    }

    private static func writeFitting(_ fitting: LocalFitting, directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        try encoder.encode(fitting).write(
            to: existingFittingFileURL(fittingId: fitting.fitting_id, directory: directory),
            options: .atomic
        )
    }

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

    /// 唯一写入入口：迁移旧名称，排除自身 ID 后分配名称，再原子写入。
    @discardableResult
    static func saveLocalFitting(_ fitting: LocalFitting, directory: URL? = nil) throws -> LocalFitting {
        fittingPersistenceLock.lock()
        defer { fittingPersistenceLock.unlock() }
        let directory = try fittingDirectory(directory)
        let existing = try loadAllLocalFittings(directory: directory)
        let names = existing.fittings.filter {
            $0.ship_type_id == fitting.ship_type_id && $0.fitting_id != fitting.fitting_id
        }.map(\.name) + existing.unreadable.filter {
            $0.shipTypeId == fitting.ship_type_id
        }.compactMap(\.name)
        let saved = fitting.renamed(FittingNamePolicy.uniqueName(
            fitting.name, occupied: Set(names.map(FittingNamePolicy.key))
        ))
        try writeFitting(saved, directory: directory)
        return saved
    }

    /// 从JSON文件加载本地配置
    static func loadLocalFitting(fittingId: UUID, directory: URL? = nil) throws -> LocalFitting {
        fittingPersistenceLock.lock()
        defer { fittingPersistenceLock.unlock() }
        let directory = try fittingDirectory(directory)
        let filePath = try existingFittingFileURL(fittingId: fittingId, directory: directory)

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

    /// 同一路径可能只有大小写不同。迁移后不能把仍指向目标文件的源路径删除。
    private static func isSameFittingFile(_ first: URL, _ second: URL) throws -> Bool {
        if first == second {
            return true
        }
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: first.path), fileManager.fileExists(atPath: second.path) else {
            return false
        }
        let firstAttributes = try fileManager.attributesOfItem(atPath: first.path)
        let secondAttributes = try fileManager.attributesOfItem(atPath: second.path)
        guard let firstNumber = firstAttributes[.systemFileNumber] as? NSNumber,
              let secondNumber = secondAttributes[.systemFileNumber] as? NSNumber,
              let firstSystem = firstAttributes[.systemNumber] as? NSNumber,
              let secondSystem = secondAttributes[.systemNumber] as? NSNumber else { return false }
        return firstNumber == secondNumber && firstSystem == secondSystem
    }

    /// 先完整读取，再规划身份与名称，最后写入；加载失败的文件始终保留供用户处理。
    static func loadAllLocalFittings(directory: URL? = nil) throws -> LocalFittingLoadResult {
        fittingPersistenceLock.lock()
        defer { fittingPersistenceLock.unlock() }
        let fittingsDirectory = try fittingDirectory(directory)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fittingsDirectory.path) else {
            return LocalFittingLoadResult(fittings: [], unreadable: [])
        }

        let fileURLs = try fileManager.contentsOfDirectory(at: fittingsDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("local_fitting_") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var snapshots: [(url: URL, data: Data, fitting: LocalFitting)] = []
        var unreadable: [UnreadableFitting] = []
        for fileURL in fileURLs {
            do {
                let data = try Data(contentsOf: fileURL)
                let fitting = try JSONDecoder().decode(LocalFitting.self, from: data)
                snapshots.append((fileURL, data, fitting))
            } catch {
                let meta = salvageMetadata(fromFile: fileURL)
                unreadable.append(UnreadableFitting(
                    fileName: fileURL.lastPathComponent, name: meta.name, shipTypeId: meta.shipTypeId
                ))
                Logger.warning("装配文件无法加载，保留原文件: \(fileURL.lastPathComponent) - \(error.localizedDescription)")
            }
        }

        // Prefer the canonical file when multiple hand-written files contain the same JSON UUID.
        snapshots.sort {
            let firstCanonical = $0.url.lastPathComponent == "local_fitting_\($0.fitting.fitting_id.uuidString).json"
            let secondCanonical = $1.url.lastPathComponent == "local_fitting_\($1.fitting.fitting_id.uuidString).json"
            if firstCanonical != secondCanonical {
                return firstCanonical
            }
            return $0.url.lastPathComponent < $1.url.lastPathComponent
        }
        var reservedIDs = Set(snapshots.map { $0.fitting.fitting_id })
        var usedIDs: Set<UUID> = []
        var occupiedNames: [Int: Set<String>] = [:]
        var seenNames: [Int: Set<String>] = [:]
        for snapshot in snapshots {
            occupiedNames[snapshot.fitting.ship_type_id, default: []].insert(FittingNamePolicy.key(snapshot.fitting.name))
        }
        for item in unreadable {
            guard let shipTypeId = item.shipTypeId, let name = item.name else { continue }
            let key = FittingNamePolicy.key(name)
            occupiedNames[shipTypeId, default: []].insert(key)
            seenNames[shipTypeId, default: []].insert(key)
        }
        var plans: [(source: URL, data: Data, fitting: LocalFitting, target: URL, migratesFile: Bool, changed: Bool)] = []
        for snapshot in snapshots {
            var fitting = snapshot.fitting
            let targetName = "local_fitting_\(fitting.fitting_id.uuidString).json"
            let collidesWithUnreadable = unreadable.contains {
                $0.fileName.caseInsensitiveCompare(targetName) == .orderedSame
            }
            if usedIDs.contains(fitting.fitting_id) || collidesWithUnreadable {
                var newID = UUID()
                while reservedIDs.contains(newID) || fileManager.fileExists(
                    atPath: fittingsDirectory.appendingPathComponent("local_fitting_\(newID.uuidString).json").path
                ) {
                    newID = UUID()
                }
                fitting = fitting.duplicated(newId: newID, name: fitting.name)
                reservedIDs.insert(newID)
            }
            usedIDs.insert(fitting.fitting_id)
            if !seenNames[fitting.ship_type_id, default: []].insert(FittingNamePolicy.key(fitting.name)).inserted {
                let name = FittingNamePolicy.uniqueName(fitting.name, occupied: occupiedNames[fitting.ship_type_id, default: []])
                fitting = fitting.renamed(name)
                occupiedNames[fitting.ship_type_id, default: []].insert(FittingNamePolicy.key(name))
            }
            let canonicalTarget = try existingFittingFileURL(fittingId: fitting.fitting_id, directory: fittingsDirectory)
            let migratesFile = try !isSameFittingFile(snapshot.url, canonicalTarget)
            let target = migratesFile ? canonicalTarget : snapshot.url
            plans.append((snapshot.url, snapshot.data, fitting, target, migratesFile,
                          migratesFile || fitting.fitting_id != snapshot.fitting.fitting_id
                              || fitting.name != snapshot.fitting.name))
        }

        // Keep original bytes before any filename/identity migration can replace another source path.
        // Backups are outside the catalog and are never automatically removed.
        if plans.contains(where: { $0.migratesFile }) {
            let backup = fittingsDirectory.appendingPathComponent("MigrationBackups", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try fileManager.createDirectory(at: backup, withIntermediateDirectories: true)
            for snapshot in snapshots {
                try snapshot.data.write(to: backup.appendingPathComponent(snapshot.url.lastPathComponent), options: .atomic)
            }
        }
        for plan in plans where plan.changed {
            // Change only identity and name; preserve unrecognized fields in hand-written files.
            guard var json = try JSONSerialization.jsonObject(with: plan.data) as? [String: Any] else {
                throw NSError(domain: "FitConvert", code: 2, userInfo: [NSLocalizedDescriptionKey: "装配文件必须是 JSON 对象"])
            }
            json["fitting_id"] = plan.fitting.fitting_id.uuidString
            json["name"] = plan.fitting.name
            try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
                .write(to: plan.target, options: .atomic)
        }

        // All targets are durable before obsolete source names are cleaned up.
        let targetNames = Set(plans.map { $0.target.lastPathComponent })
        let targetsByCase = Dictionary(grouping: plans.map(\.target)) { $0.lastPathComponent.lowercased() }
        for plan in plans where !targetNames.contains(plan.source.lastPathComponent) {
            let candidates = targetsByCase[plan.source.lastPathComponent.lowercased()] ?? []
            let stillReferencesTarget = try candidates.contains { try isSameFittingFile(plan.source, $0) }
            if !stillReferencesTarget && fileManager.fileExists(atPath: plan.source.path) {
                try fileManager.removeItem(at: plan.source)
            }
        }
        return LocalFittingLoadResult(fittings: plans.map(\.fitting), unreadable: unreadable)
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
