import Foundation

/// 市场位置：星域市场或玩家建筑市场
///
/// 历史原因，市场位置在持久化和既有 API 签名中以「虚拟 regionID」编码：
/// 正数表示星域 ID，负数表示建筑 ID 的相反数（-structureID）。
/// 本类型是该编码的唯一权威定义，业务代码应通过语义化属性访问，不再自行判断正负。
enum MarketLocation: Equatable, Codable {
    case region(Int)
    case structure(Int64)

    /// 从虚拟 regionID 解析：负数为建筑，正数为星域
    init(virtualRegionID: Int) {
        if virtualRegionID < 0 {
            self = .structure(Int64(-virtualRegionID))
        } else {
            self = .region(virtualRegionID)
        }
    }

    /// 编码为虚拟 regionID（负数表示建筑），用于持久化和既有 API 签名
    var virtualRegionID: Int {
        switch self {
        case let .region(id): return id
        case let .structure(id): return -Int(id)
        }
    }

    var isStructure: Bool {
        if case .structure = self {
            return true
        }
        return false
    }

    /// 建筑 ID（仅建筑市场有值）
    var structureID: Int64? {
        if case let .structure(id) = self {
            return id
        }
        return nil
    }

    /// 从持久化字符串解析（兼容旧格式 "region_id:-103..."，负数同样解析为建筑）
    init?(persistedString: String) {
        let components = persistedString.split(separator: "_")
        guard components.count == 3, components[1] == "id" else { return nil }
        if components[0] == "region", let id = Int(components[2]) {
            self.init(virtualRegionID: id)
        } else if components[0] == "structure", let id = Int64(components[2]) {
            self = .structure(id)
        } else {
            return nil
        }
    }

    // MARK: - Codable（编码为虚拟 regionID 整数，与既有 JSON 格式完全兼容）

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(virtualRegionID: container.decode(Int.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(virtualRegionID)
    }
}

/// 市场地点类型：星域 / 星系 / 建筑
/// 从单一 locationID 推断类型，无需额外存储类型信息
enum MarketLocationType {
    case region(Int)
    case system(Int, Int) // systemID, regionID
    case structure(Int64)

    /// 从 locationID 推断类型：
    /// - 负数 → 建筑（虚拟 ID）
    /// - 在 solarSystemNames 中 → 星系
    /// - 在 regionNames 中 → 星域
    static func from(id: Int) -> MarketLocationType? {
        if id < 0 {
            return .structure(Int64(-id))
        }
        if SDEMemoryStore.solarSystemNames[id] != nil,
           let regionID = SDEMemoryStore.systemRegionIDs[id]
        {
            return .system(id, regionID)
        }
        if SDEMemoryStore.regionNames[id] != nil {
            return .region(id)
        }
        return nil
    }

    /// ESI 查询用的星域 ID（星系返回其所属星域，建筑返回虚拟 ID）
    var regionID: Int {
        switch self {
        case let .region(id): return id
        case let .system(_, regionID): return regionID
        case let .structure(id): return -Int(id)
        }
    }

    /// 星系 ID（仅星系有值，用于订单过滤）
    var systemID: Int? {
        if case let .system(id, _) = self {
            return id
        }
        return nil
    }

    /// 显示名称
    var displayName: String {
        switch self {
        case let .region(id):
            return SDEMemoryStore.regionName(for: id) ?? "Region \(id)"
        case let .system(id, _):
            return SDEMemoryStore.solarSystemName(for: id) ?? "System \(id)"
        case let .structure(id):
            return MarketStructureManager.shared.structures
                .first { $0.structureId == Int(id) }?.structureName ?? "Structure"
        }
    }
}
