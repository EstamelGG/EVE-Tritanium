import Foundation

/// 仅比较文件中保存的内容；身份和列表排列不属于装配内容。
struct FittingSaveSnapshot: Equatable {
    private let content: Data

    init(_ fitting: LocalFitting) throws {
        let data = try JSONEncoder().encode(fitting)
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.coderInvalidValue)
        }
        object.removeValue(forKey: "fitting_id")
        for key in ["drones", "fighters", "cargo", "implants"] {
            if let values = object[key] as? [Any], values.isEmpty {
                object.removeValue(forKey: key)
            }
        }
        content = try Self.canonicalData(object)
    }

    private static func canonicalData(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: canonicalValue(value), options: [.sortedKeys, .fragmentsAllowed])
    }

    private static func canonicalValue(_ value: Any) throws -> Any {
        if let object = value as? [String: Any] {
            return try object.mapValues { try canonicalValue($0) }
        }
        if let array = value as? [Any] {
            // 槽位、无人机、货舱、植入体、舰载机和突变属性均按内容比较，保留重复项。
            return try array.map {
                let canonical = try canonicalValue($0)
                return try (JSONSerialization.data(withJSONObject: canonical, options: [.sortedKeys, .fragmentsAllowed]), canonical)
            }
            .sorted { $0.0.lexicographicallyPrecedes($1.0) }
            .map(\.1)
        }
        return value
    }
}

/// 管理编辑会话的保存基准和固定目标；只有写入成功才推进基准。
struct FittingSaveState {
    let targetID: UUID
    private var baseline: FittingSaveSnapshot?
    private var current: FittingSaveSnapshot?
    private(set) var localFileID: UUID?

    var hasUnsavedChanges: Bool {
        guard let baseline, let current else { return true }
        return current != baseline
    }

    init(input: SimulationInput, isExisting: Bool) {
        if case let .local(id) = input.fittingId {
            targetID = id
            localFileID = isExisting ? id : nil
        } else {
            targetID = UUID()
        }
        update(input)
        baseline = isExisting ? current : nil
    }

    mutating func update(_ input: SimulationInput) {
        current = try? FittingSaveSnapshot(document(for: input))
    }

    /// 编辑器唯一保存入口：转换、名称分配、原子写入、更新快照。
    mutating func save(_ input: SimulationInput, directory: URL?) throws -> LocalFitting {
        let fitting = document(for: input)
        // 编码失败时不触碰文件，也不推进保存状态。
        _ = try FittingSaveSnapshot(fitting)
        let saved = try FitConvert.saveLocalFitting(fitting, directory: directory)
        let snapshot = try FittingSaveSnapshot(saved)
        baseline = snapshot
        current = snapshot
        localFileID = saved.fitting_id
        return saved
    }

    private func document(for input: SimulationInput) -> LocalFitting {
        FitConvert.simulationInputToLocalFitting(input: input, fittingID: targetID)
    }
}
