import Foundation
import SQLite3

/// 跨域共享的加载辅助（读全语种列，不依赖 TEMP VIEW 的当前 name）
extension SDEMemoryStore {
    static let nameColumns = """
    de_name, en_name, es_name, fr_name, ja_name, ko_name, ru_name, zh_name
    """

    /// 通用 LocalizedText 表加载：`SELECT <idCol>, 八语列 FROM <table>`（直读流式，无行字典临时对象）
    static func loadLocalizedTable(
        _ db: DatabaseManager, table: String, idColumn: String,
        estimatedCount: Int = 0, into target: inout [Int: LocalizedText]
    ) {
        var cache: [Int: LocalizedText] = [:]
        if estimatedCount > 0 {
            cache.reserveCapacity(estimatedCount)
        }
        db.executeQueryMapped(
            "SELECT \(idColumn), \(nameColumns) FROM \(table)",
            context: table
        ) { resolve in
            let iID = resolve.index(idColumn)
            let iNames = localizedIndexes(resolve)
            return { stmt in
                guard sqlite3_column_type(stmt, iID) != SQLITE_NULL else { return }
                cache[Int(sqlite3_column_int64(stmt, iID))] = localizedText(stmt, iNames)
            }
        }
        target = cache
    }

    /// SQLite 可能以 Double 或 Int 返回数值：优先 Double，否则尝试 Int
    static func doubleOrInt(_ row: [String: Any], _ key: String) -> Double? {
        (row[key] as? Double) ?? (row[key] as? Int).map(Double.init)
    }

    // MARK: - 直读（executeQueryMapped）共享辅助

    /// 直读 TEXT 列（NULL → ""）
    static func directText(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: c)
    }

    /// 直读 INTEGER 列（NULL → nil）
    static func directIntOrNil(_ stmt: OpaquePointer?, _ index: Int32) -> Int? {
        sqlite3_column_type(stmt, index) == SQLITE_NULL
            ? nil : Int(sqlite3_column_int64(stmt, index))
    }

    /// 直读数值列（NULL → nil；整型自动转 Double，等价 doubleOrInt）
    static func directDoubleOrNil(_ stmt: OpaquePointer?, _ index: Int32) -> Double? {
        sqlite3_column_type(stmt, index) == SQLITE_NULL
            ? nil : sqlite3_column_double(stmt, index)
    }

    /// 八语种列索引组：每列独立按名解析，不依赖 SELECT 中的相邻性与顺序
    struct LocalizedIndexes {
        let de: Int32, en: Int32, es: Int32, fr: Int32
        let ja: Int32, ko: Int32, ru: Int32, zh: Int32
    }

    /// 按名一一解析八语种列；suffix: "name" → de_name…，"description" → de_description…
    static func localizedIndexes(
        _ resolve: SQLiteColumnResolver, suffix: String = "name"
    ) -> LocalizedIndexes {
        LocalizedIndexes(
            de: resolve.index("de_\(suffix)"),
            en: resolve.index("en_\(suffix)"),
            es: resolve.index("es_\(suffix)"),
            fr: resolve.index("fr_\(suffix)"),
            ja: resolve.index("ja_\(suffix)"),
            ko: resolve.index("ko_\(suffix)"),
            ru: resolve.index("ru_\(suffix)"),
            zh: resolve.index("zh_\(suffix)")
        )
    }

    /// 按一一解析的索引组读取八语种文本
    static func localizedText(_ stmt: OpaquePointer?, _ idx: LocalizedIndexes) -> LocalizedText {
        LocalizedText(
            de: directText(stmt, idx.de),
            en: directText(stmt, idx.en),
            es: directText(stmt, idx.es),
            fr: directText(stmt, idx.fr),
            ja: directText(stmt, idx.ja),
            ko: directText(stmt, idx.ko),
            ru: directText(stmt, idx.ru),
            zh: directText(stmt, idx.zh)
        )
    }
}
