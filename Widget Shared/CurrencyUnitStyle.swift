import Foundation

enum CurrencyUnitStyle: String, CaseIterable {
    case localized
    case english

    static let key = "currencyUnitStyle"
    static let defaultStyle: Self = .english

    static var current: Self {
        WidgetMarketWatchlist.defaults?.string(forKey: key)
            .flatMap(Self.init(rawValue:)) ?? defaultStyle
    }

    func format(_ value: Double, locale: Locale, maxFractionDigits: Int = 2) -> String {
        value.formatted(
            .number
                .locale(self == .english ? Locale(identifier: "en_US") : locale)
                .notation(.compactName)
                .precision(.fractionLength(0...maxFractionDigits))
        )
    }
}
