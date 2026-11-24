import Foundation

enum CompactNumber {
    private static let oneDecimal = formatter(maxFractionDigits: 1)
    private static let twoDecimals = formatter(maxFractionDigits: 2)

    static func format(_ value: Double, maxFractionDigits: Int) -> String {
        if value == 0 {
            return "0"
        }
        let (scaled, unit): (Double, String)
        switch value {
        case 1e12...: (scaled, unit) = (value / 1e12, "T")
        case 1e9...: (scaled, unit) = (value / 1e9, "B")
        case 1e6...: (scaled, unit) = (value / 1e6, "M")
        case 1e4...: (scaled, unit) = (value / 1e3, "k")
        default: (scaled, unit) = (value, "")
        }

        let numberFormatter: NumberFormatter
        switch maxFractionDigits {
        case 1: numberFormatter = oneDecimal
        case 2: numberFormatter = twoDecimals
        default: numberFormatter = formatter(maxFractionDigits: maxFractionDigits)
        }
        let number = numberFormatter.string(from: NSNumber(value: scaled))
            ?? String(format: "%.\(maxFractionDigits)f", scaled)
        return number + unit
    }

    private static func formatter(maxFractionDigits: Int) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maxFractionDigits
        formatter.groupingSeparator = ""
        formatter.decimalSeparator = "."
        return formatter
    }
}
