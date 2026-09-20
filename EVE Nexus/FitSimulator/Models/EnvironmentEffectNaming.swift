import Foundation
import SwiftUI

struct EnvironmentEffectItem: Identifiable {
    let id: Int
    let typeId: Int
    let enName: String
    let iconFileName: String
    let displayName: String
    let rowIconAssetName: String?

    init(
        typeId: Int,
        enName: String,
        iconFileName: String,
        displayName: String,
        rowIconAssetName: String? = nil
    ) {
        id = typeId
        self.typeId = typeId
        self.enName = enName
        self.iconFileName = iconFileName
        self.displayName = displayName
        self.rowIconAssetName = rowIconAssetName
    }

    func asDatabaseListItem() -> DatabaseListItem {
        DatabaseListItem(
            id: typeId,
            name: displayName,
            enName: enName,
            iconFileName: iconFileName,
            published: true,
            categoryID: 0
        )
    }
}

struct EnvironmentEffectSection: Identifiable {
    let id: String
    let title: String
    let sortOrder: Int
    let items: [EnvironmentEffectItem]
}

enum EnvironmentEffectNaming {
    enum AbyssalWeatherType: String, CaseIterable {
        case darkness
        case electricStorm = "electric_storm"
        case causticToxin = "caustic_toxin"
        case xenonGas = "xenon_gas"
        case infernal

        var sortOrder: Int {
            switch self {
            case .darkness: return 0
            case .electricStorm: return 1
            case .causticToxin: return 2
            case .xenonGas: return 3
            case .infernal: return 4
            }
        }

        var title: String {
            switch self {
            case .darkness:
                return NSLocalizedString("Environment_Abyssal_Type_Darkness", comment: "")
            case .electricStorm:
                return NSLocalizedString("Environment_Abyssal_Type_ElectricStorm", comment: "")
            case .causticToxin:
                return NSLocalizedString("Environment_Abyssal_Type_CausticToxin", comment: "")
            case .xenonGas:
                return NSLocalizedString("Environment_Abyssal_Type_XenonGas", comment: "")
            case .infernal:
                return NSLocalizedString("Environment_Abyssal_Type_Infernal", comment: "")
            }
        }

        var iconAssetName: String {
            switch self {
            case .darkness:
                return "dark"
            case .electricStorm:
                return "electrical"
            case .causticToxin:
                return "exotic"
            case .xenonGas:
                return "gamma"
            case .infernal:
                return "plasma"
            }
        }

        static func from(prefix: String) -> AbyssalWeatherType? {
            allCases.first { $0.rawValue == prefix }
        }
    }

    static func wormholeSections(from items: [EnvironmentEffectItem]) -> [EnvironmentEffectSection] {
        var grouped: [Int: [EnvironmentEffectItem]] = [:]
        var others: [EnvironmentEffectItem] = []

        for item in items {
            if let level = wormholeClassLevel(from: item.enName) {
                grouped[level, default: []].append(item)
            } else {
                others.append(item)
            }
        }

        var sections: [EnvironmentEffectSection] = []

        for level in 1 ... 6 {
            guard let levelItems = grouped[level], !levelItems.isEmpty else { continue }
            sections.append(
                EnvironmentEffectSection(
                    id: "wormhole-class-\(level)",
                    title: String(
                        format: NSLocalizedString(
                            "Environment_Wormhole_Class_Section",
                            comment: "%d级虫洞"
                        ),
                        level
                    ),
                    sortOrder: level,
                    items: levelItems.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
                )
            )
        }

        if !others.isEmpty {
            sections.append(
                EnvironmentEffectSection(
                    id: "wormhole-other",
                    title: NSLocalizedString("Environment_Wormhole_Other_Section", comment: "其他"),
                    sortOrder: 99,
                    items: others.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
                )
            )
        }

        return sections.sorted { $0.sortOrder < $1.sortOrder }
    }

    static func abyssalSections(from items: [EnvironmentEffectItem]) -> [EnvironmentEffectSection] {
        var grouped: [AbyssalWeatherType: [EnvironmentEffectItem]] = [:]

        for item in items {
            if let (weatherType, _) = abyssalTypeAndLevel(from: item.enName) {
                grouped[weatherType, default: []].append(item)
            }
        }

        return AbyssalWeatherType.allCases.compactMap { weatherType -> EnvironmentEffectSection? in
            guard let typeItems = grouped[weatherType], !typeItems.isEmpty else { return nil }

            return EnvironmentEffectSection(
                id: "abyssal-\(weatherType.rawValue)",
                title: weatherType.title,
                sortOrder: weatherType.sortOrder,
                items: typeItems.sorted {
                    let leftLevel = abyssalTypeAndLevel(from: $0.enName)?.level ?? 0
                    let rightLevel = abyssalTypeAndLevel(from: $1.enName)?.level ?? 0
                    return leftLevel < rightLevel
                }
            )
        }
    }

    static func makeItem(
        typeId: Int,
        enName: String,
        localName: String,
        iconFileName: String,
        category: EnvironmentOptions.Category
    ) -> EnvironmentEffectItem {
        let displayName: String
        let rowIconAssetName: String?

        switch category {
        case .wormhole:
            displayName = localName
            rowIconAssetName = wormholeClassLevel(from: enName) != nil ? "wormhole" : nil
        case .abyssal:
            displayName = abyssalItemDisplayName(enName: enName)
            rowIconAssetName = abyssalTypeAndLevel(from: enName)?.weatherType.iconAssetName
        case .other:
            displayName = localName
            rowIconAssetName = nil
        }

        return EnvironmentEffectItem(
            typeId: typeId,
            enName: enName,
            iconFileName: iconFileName,
            displayName: displayName,
            rowIconAssetName: rowIconAssetName
        )
    }

    static func displayName(
        typeId _: Int,
        enName: String,
        fallbackName: String,
        category: EnvironmentOptions.Category
    ) -> String {
        switch category {
        case .wormhole:
            return fallbackName
        case .abyssal:
            if abyssalTypeAndLevel(from: enName) != nil {
                return abyssalItemDisplayName(enName: enName)
            }
            return fallbackName
        case .other:
            return fallbackName
        }
    }

    static func category(for typeId: Int) -> EnvironmentOptions.Category? {
        let options = EnvironmentOptions.shared
        if options.wormhole.contains(typeId) {
            return .wormhole
        }
        if options.abyssal.contains(typeId) {
            return .abyssal
        }
        if options.other.contains(typeId) {
            return .other
        }
        return nil
    }

    private static func wormholeClassLevel(from enName: String) -> Int? {
        let pattern = #"^Class\s+(\d+)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(
                  in: enName,
                  range: NSRange(enName.startIndex..., in: enName)
              ),
              let levelRange = Range(match.range(at: 1), in: enName),
              let level = Int(enName[levelRange]),
              (1 ... 6).contains(level)
        else {
            return nil
        }
        return level
    }

    private typealias AbyssalTypeAndLevel = (weatherType: AbyssalWeatherType, level: Int)

    private static func abyssalTypeAndLevel(from enName: String) -> AbyssalTypeAndLevel? {
        let parts = enName.lowercased().split(separator: "_").map(String.init)
        guard parts.count >= 3,
              parts[parts.count - 2] == "weather",
              let level = Int(parts.last ?? ""),
              (1 ... 3).contains(level)
        else {
            return nil
        }

        let prefix = parts.dropLast(2).joined(separator: "_")
        guard let weatherType = AbyssalWeatherType.from(prefix: prefix) else {
            return nil
        }

        return (weatherType, level)
    }

    private static func abyssalItemDisplayName(enName: String) -> String {
        guard let (weatherType, level) = abyssalTypeAndLevel(from: enName) else {
            return enName
        }

        let typeName = weatherType.title
        let levelName = abyssalLevelName(level)
        return String(
            format: NSLocalizedString("Environment_Abyssal_Item_Name_Format", comment: "%@ - %@"),
            typeName,
            levelName
        )
    }

    private static func abyssalLevelName(_ level: Int) -> String {
        switch level {
        case 1:
            return NSLocalizedString("Environment_Abyssal_Level_Basic", comment: "初级")
        case 2:
            return NSLocalizedString("Environment_Abyssal_Level_Medium", comment: "中级")
        case 3:
            return NSLocalizedString("Environment_Abyssal_Level_Advanced", comment: "高级")
        default:
            return "\(level)"
        }
    }
}
