import Foundation

/// Allocate a name within one ship type, ignoring surrounding spaces and letter case.
enum FittingNamePolicy {
    static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    static func uniqueName(_ proposed: String, occupied: Set<String>) -> String {
        let trimmed = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? NSLocalizedString("Unnamed", comment: "") : trimmed
        guard occupied.contains(key(name)) else { return name }

        var base = name
        var number = 1
        if let range = name.range(of: #"\([0-9]+\)$"#, options: .regularExpression),
           let suffix = Int(name[range].dropFirst().dropLast()), suffix < Int.max
        {
            base = String(name[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            number = suffix + 1
        }
        while occupied.contains(key("\(base)(\(number))")) {
            // An unrepresentable suffix is treated as part of the name.
            if number == Int.max {
                base = "\(base)(\(number))"
                number = 1
            } else {
                number += 1
            }
        }
        return "\(base)(\(number))"
    }
}
