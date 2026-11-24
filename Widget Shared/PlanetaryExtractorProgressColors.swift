import SwiftUI

enum PlanetaryExtractorProgressColors {
    static func fill(isExpired: Bool, remainingFraction: Double = 1) -> Color {
        if isExpired { return .red }
        return remainingFraction <= 0.1 ? .orange : Color(red: 0, green: 0.6, blue: 0.3)
    }
}
