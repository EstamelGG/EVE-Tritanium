import Foundation
import SwiftUI
import WidgetKit

struct WidgetChoice: Codable, Equatable {
    let id: Int
    let name: String

    static var defaultMarket: [Self] {
        [44992, 40520, 45635, 40519, 46375, 34, 35, 36, 37].map { id in
            Self(id: id, name: WidgetLocalization.previewTypeName(id))
        }
    }
}

extension WidgetFamily {
    var nexusRowLimit: Int {
        switch self {
        case .systemLarge:
            6
        case .systemExtraLargePortrait:
            9
        default:
            3
        }
    }
}

extension NexusWidgetKind {
    var supportedFamilies: [WidgetFamily] {
        guard self != .industryOverview else { return [.systemMedium] }
        if #available(iOS 27, macOS 27, *) {
            return [.systemMedium, .systemLarge, .systemExtraLargePortrait]
        }
        return [.systemMedium, .systemLarge]
    }
}

extension WidgetSnapshot {
    func selection(
        for kind: NexusWidgetKind, rowLimit: Int, marketWatchlist: [WidgetChoice],
        characterIDs: [Int]?
    ) -> Self {
        var result = self
        if kind == .market {
            let rows = Dictionary(uniqueKeysWithValues: market.map { ($0.id, $0) })
            result.market = marketWatchlist.prefix(rowLimit).map {
                rows[$0.id] ?? WidgetMarketItem(id: $0.id, name: $0.name)
            }
            result.characters = []
        } else {
            let ids = Set(characterIDs ?? characters.map(\.id))
            result.characters = characters.filter { ids.contains($0.id) }
            result.market = []
        }
        return result
    }

}

enum WidgetMarketWatchlist {
    static let key = "widgetMarketWatchlist"
    static let maximumItems = 9
    static let stationID = 60_003_760
    static let jitaSystemID = 30_000_142
    static let defaults = UserDefaults(suiteName: WidgetStore.appGroup)

    static func read() -> [WidgetChoice] {
        decode(defaults?.data(forKey: key))
    }

    static func decode(_ data: Data?) -> [WidgetChoice] {
        guard let data, let choices = try? JSONDecoder().decode([WidgetChoice].self, from: data)
        else { return WidgetChoice.defaultMarket }
        return limited(choices)
    }

    static func limited(_ choices: [WidgetChoice]) -> [WidgetChoice] {
        var seen = Set<Int>()
        return Array(choices.filter { seen.insert($0.id).inserted }.prefix(maximumItems))
    }
}

enum WidgetMarketTrendColors: String {
    case greenUp
    case redUp

    static let key = "widgetMarketTrendColors"

    static func defaultStyle(for language: String?) -> Self {
        language?.lowercased().hasPrefix("zh") == true ? .redUp : .greenUp
    }

    static var defaultStyle: Self {
        defaultStyle(for: WidgetLocalization.language ?? Locale.preferredLanguages.first)
    }

    static var current: Self {
        WidgetMarketWatchlist.defaults?.string(forKey: key)
            .flatMap(Self.init(rawValue:)) ?? defaultStyle
    }

    func color(for change: Double?) -> Color {
        guard let change, abs(change) >= 0.00005 else { return .secondary }
        return (change > 0) == (self == .greenUp) ? .green : .red
    }
}

enum WidgetCharacterPreferences {
    private static let key = "widgetCharacterSelections"

    static func settingsKey(for kind: NexusWidgetKind) -> String {
        switch kind {
        case .industryOverview, .industryList: "EVE.Industry"
        default: kind.rawValue
        }
    }

    static func selectedIDs(for kind: NexusWidgetKind, in selections: [String: [Int]]) -> [Int]? {
        selections[settingsKey(for: kind)]
    }

    static var selections: [String: [Int]] {
        get { WidgetMarketWatchlist.defaults?.dictionary(forKey: key) as? [String: [Int]] ?? [:] }
        set { WidgetMarketWatchlist.defaults?.set(newValue, forKey: key) }
    }
}

enum WidgetLocalization {
    static let languageKey = "widgetInterfaceLanguage"

    static var language: String? {
        WidgetMarketWatchlist.defaults?.string(forKey: languageKey)
    }

    static var locale: Locale { language.map(Locale.init(identifier:)) ?? .autoupdatingCurrent }

    static func previewTypeName(_ id: Int) -> String {
        bundle.localizedString(forKey: "Widget_Preview_Type_\(id)", value: String(id), table: "Widgets")
    }

    static var bundle: Bundle {
        guard let language,
              let url = Bundle.main.url(forResource: language, withExtension: "lproj"),
              let bundle = Bundle(url: url) else { return .main }
        return bundle
    }
}
