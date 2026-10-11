import Foundation

/// 展示环境的原始加成；不包含具体装配的叠加惩罚和最终属性。
enum EnvironmentEffectSummary {
    static func descriptions(typeIds: [Int], databaseManager: DatabaseManager) -> [Int: String] {
        guard !typeIds.isEmpty else { return [:] }
        var definitions: [Int: [String]] = [:]
        for typeId in typeIds {
            definitions[typeId] = SDEMemoryStore.typeEffects(forType: typeId)
                .sorted { $0.effectID < $1.effectID }
                .compactMap { SDEMemoryStore.dogmaEffect(for: $0.effectID)?.modifierInfo }
        }

        // 深渊天气使用按 type_id 区分的 dbuff 定义，与模拟器 Step1 的来源一致。
        let placeholders = Array(repeating: "?", count: typeIds.count).joined(separator: ",")
        let query = """
        SELECT type_id, modifier_info FROM dbuffCollection
        WHERE type_id IN (\(placeholders)) ORDER BY type_id, dbuff_id
        """
        if case let .success(rows) = databaseManager.executeQuery(query, parameters: typeIds) {
            for row in rows {
                if let typeId = row["type_id"] as? Int, let json = row["modifier_info"] as? String {
                    definitions[typeId, default: []].append(json)
                }
            }
        }

        return Dictionary(uniqueKeysWithValues: typeIds.map { typeId in
            let attributes = SDEMemoryStore.typeAttributes(for: typeId)
            var lines: [String] = []
            var seen: Set<String> = []
            for json in definitions[typeId] ?? [] {
                guard let data = json.data(using: .utf8),
                      let modifiers = try? JSONDecoder().decode([ModifierInfo].self, from: data)
                else { continue }
                for modifier in modifiers {
                    guard let line = description(modifier: modifier, attributes: attributes),
                          seen.insert(line).inserted else { continue }
                    lines.append(line)
                }
            }
            return (typeId, lines.joined(separator: "\n"))
        })
    }

    /// 倍率先转为相对变化；抗性共振描述为所受伤害变化，不能当作抗性百分点。
    static func relativePercent(operation: Int, value: Double) -> Double? {
        guard value.isFinite else { return nil }
        let percent: Double
        switch OperationType(rawValue: operation) {
        case .preMul, .postMul: percent = (value - 1) * 100
        case .preDiv, .postDiv:
            guard value != 0 else { return nil }
            percent = (1 / value - 1) * 100
        case .postPercent: percent = value
        default: return nil
        }
        return percent.isFinite && abs(percent) > 0.000001 ? percent : nil
    }

    private static func description(modifier: ModifierInfo, attributes: [Int: Double]) -> String? {
        guard let targetId = modifier.modifiedAttributeID,
              let sourceId = modifier.modifyingAttributeID,
              let operation = modifier.operation,
              let value = attributes[sourceId],
              let percent = relativePercent(operation: operation, value: value),
              let attribute = SDEMemoryStore.dogmaAttribute(for: targetId),
              let name = attribute.displayName,
              let scope = scope(modifier)
        else { return nil }

        let change = FormatUtil.formatSignedPercentFrom100(percent)
        let detail: String
        if attribute.name.lowercased().contains("damageresonance") {
            detail = String(format: NSLocalizedString("Environment_Effect_Resonance", comment: ""), name, change)
        } else {
            detail = "\(name) \(change)"
        }
        return scope.isEmpty ? detail : "\(scope) · \(detail)"
    }

    private static func scope(_ modifier: ModifierInfo) -> String? {
        switch modifier.func {
        case "ItemModifier" where modifier.domain == "shipID":
            return ""
        case "LocationGroupModifier":
            guard let id = modifier.groupID else { return nil }
            return SDEMemoryStore.group(for: id)?.name
        case "LocationRequiredSkillModifier", "OwnerRequiredSkillModifier":
            guard let id = modifier.skillTypeID, let name = SDEMemoryStore.type(for: id)?.name else { return nil }
            return String(format: NSLocalizedString("Environment_Effect_Requires_Skill", comment: ""), name)
        case "LocationModifier":
            return NSLocalizedString("Environment_Effect_Fitted_Items", comment: "")
        default:
            return nil
        }
    }
}
