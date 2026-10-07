import Foundation

/// Current format: `new` contains type IDs; `modify` contains per-type differences.
/// Names, icons and catalog membership always come from the installed SDE.
struct SDEChangeReport: Decodable, Sendable {
    struct Modification: Decodable, Sendable {
        enum Kind: String, Decodable, Sendable { case item, blueprint }
        let kind: Kind
        let name: [String: SDETextChange]
        let description: [String: SDETextChange]
        let attributes: [String: SDEValueChange]
        let blueprint: [String: SDEChangeTree]

        init(kind: Kind, attributes: [String: SDEValueChange] = [:], blueprint: [String: SDEChangeTree] = [:]) {
            self.kind = kind
            name = [:]
            description = [:]
            self.attributes = attributes
            self.blueprint = blueprint
        }

        private enum CodingKeys: String, CodingKey { case kind, name, description, attributes, blueprint }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            kind = try container.decode(Kind.self, forKey: .kind)
            name = try container.decodeIfPresent([String: SDETextChange].self, forKey: .name) ?? [:]
            description = try container.decodeIfPresent([String: SDETextChange].self, forKey: .description) ?? [:]
            attributes = try container.decodeIfPresent([String: SDEValueChange].self, forKey: .attributes) ?? [:]
            blueprint = try container.decodeIfPresent([String: SDEChangeTree].self, forKey: .blueprint) ?? [:]
        }
    }

    let newTypeIDs: Set<Int>
    let modifications: [Int: Modification]
    var affectedTypeIDs: [Int] {
        newTypeIDs.union(modifications.keys).sorted()
    }

    private enum CodingKeys: String, CodingKey { case new, modify, schema_version }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.new) || container.contains(.modify) {
            let added = try Set(container.decode([Int].self, forKey: .new))
            newTypeIDs = added
            let entries = try container.decode([Int: Modification].self, forKey: .modify)
            // An added entity appears once and opens the ordinary item detail page.
            modifications = entries.filter { !added.contains($0.key) }
        } else {
            let legacy = try LegacyReport(from: decoder)
            guard legacy.schema_version == 1 else { throw ReportError.unsupportedSchema }
            var added = Set(legacy.new_items.keys.compactMap(Int.init))
            added.formUnion(legacy.new_ships.keys.compactMap(Int.init))
            var modified: [Int: Modification] = [:]
            for (id, blueprint) in legacy.blueprint_changes {
                guard let number = Int(id) else { continue }
                if blueprint.status == "added" {
                    added.insert(number)
                }
                if blueprint.status == "changed" {
                    modified[number] = Modification(kind: .blueprint, blueprint: blueprint.changes)
                }
            }
            for (id, attributes) in legacy.attribute_changes {
                guard let number = Int(id), !attributes.isEmpty else { continue }
                let blueprint = modified[number]?.blueprint ?? [:]
                modified[number] = Modification(kind: blueprint.isEmpty ? .item : .blueprint,
                                                attributes: attributes, blueprint: blueprint)
            }
            newTypeIDs = added
            modifications = modified.filter { !added.contains($0.key) }
        }
        guard affectedTypeIDs.allSatisfy({ $0 > 0 }) else { throw ReportError.invalidTypeID }
    }

    static func decode(_ data: Data) throws -> Self {
        try JSONDecoder().decode(Self.self, from: data)
    }

    enum ReportError: Error { case unsupportedSchema, invalidTypeID }

    /// Read installed older packages without depending on their removed presentation metadata.
    private struct LegacyReport: Decodable {
        struct Ignored: Decodable {}
        struct Blueprint: Decodable {
            let status: String
            let changes: [String: SDEChangeTree]
        }

        let schema_version: Int
        let new_items: [String: Ignored]
        let new_ships: [String: Ignored]
        let blueprint_changes: [String: Blueprint]
        let attribute_changes: [String: [String: SDEValueChange]]
    }
}

/// Language branches are independent. Preserve original HTML, whitespace and null values.
struct SDETextChange: Decodable, Sendable {
    let before: String?
    let after: String?
    var valueChange: SDEValueChange {
        SDEValueChange(old: before, new: after)
    }

    private enum CodingKeys: String, CodingKey { case before, after }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        before = try container.decodeNil(forKey: .before) ? nil : container.decode(String.self, forKey: .before)
        after = try container.decodeNil(forKey: .after) ? nil : container.decode(String.self, forKey: .after)
    }
}

/// Decode a repeated-material leaf without summing, deduplicating or pairing distinct records.
enum SDEMaterialRecords {
    static func decode(_ text: String) -> [String]? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let records: [[String: Any]]
        if let array = json as? [[String: Any]] {
            records = array
        } else if let object = json as? [String: Any] {
            records = [object]
        } else {
            return nil
        }
        return records.map { record in
            guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys, .withoutEscapingSlashes]),
                  let string = String(data: data, encoding: .utf8) else { return text }
            return string
        }
    }
}

struct SDEValueChange: Decodable, Sendable {
    let old: String?
    let new: String?

    init(old: String?, new: String?) {
        self.old = old
        self.new = new
    }

    private enum CodingKeys: String, CodingKey { case old, new }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Require both keys; missing keys are malformed, explicit null means absence.
        old = try container.decodeNil(forKey: .old) ? nil : container.decode(String.self, forKey: .old)
        new = try container.decodeNil(forKey: .new) ? nil : container.decode(String.self, forKey: .new)
    }
}

/// Preserve all blueprint activities and future nested field names without flattening paths.
indirect enum SDEChangeTree: Decodable, Sendable {
    case value(SDEValueChange)
    case fields([String: SDEChangeTree])

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? {
            nil
        }

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue _: Int) {
            return nil
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        if container.allKeys.contains(where: { $0.stringValue == "old" || $0.stringValue == "new" }) {
            self = try .value(SDEValueChange(from: decoder))
        } else {
            self = try .fields([String: SDEChangeTree](from: decoder))
        }
    }
}

/// A lossless leaf projection: UI can group by activity without making every JSON key a screen.
struct SDEBlueprintDifference: Identifiable, Sendable {
    let path: [String]
    let change: SDEValueChange
    var id: [String] {
        path
    }

    var activity: String? {
        path.count >= 3 && path[0] == "activities" ? path[1] : nil
    }

    var collection: String? {
        guard activity != nil, path.count >= 4,
              ["materials", "products", "skills"].contains(path[2]) else { return nil }
        return path[2]
    }

    var typeID: String? {
        collection == nil ? nil : path[3]
    }

    var fields: [String] {
        Array(path.dropFirst(collection != nil ? 4 : (activity != nil ? 2 : 0)))
    }

    static func flatten(_ fields: [String: SDEChangeTree], path: [String] = []) -> [Self] {
        fields.keys.sorted().flatMap { key -> [Self] in
            let next = path + [key]
            switch fields[key]! {
            case let .value(change): return [Self(path: next, change: change)]
            case let .fields(children): return flatten(children, path: next)
            }
        }
    }
}
