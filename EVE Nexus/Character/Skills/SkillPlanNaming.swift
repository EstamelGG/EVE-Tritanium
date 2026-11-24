import Foundation

enum SkillPlanNaming {
    enum ValidationError: LocalizedError, Equatable {
        case emptyName
        case duplicateName

        var errorDescription: String? {
            switch self {
            case .emptyName:
                return NSLocalizedString("Main_Skills_Plan_Name_Required", comment: "")
            case .duplicateName:
                return NSLocalizedString("Main_Skills_Plan_Name_Duplicate", comment: "")
            }
        }
    }

    static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func validate(
        _ name: String, planID: UUID, existingPlans: [(id: UUID?, name: String)]
    ) throws {
        if let error = validationError(for: name, excludingPlanID: planID, existingPlans: existingPlans) {
            throw error
        }
    }

    static func validationError(
        for name: String, excludingPlanID: UUID? = nil, existingPlans: [(id: UUID?, name: String)]
    ) -> ValidationError? {
        let name = normalized(name)
        guard !name.isEmpty else { return .emptyName }
        if existingPlans.contains(where: {
            (excludingPlanID == nil || $0.id != excludingPlanID) && normalized($0.name) == name
        }) {
            return .duplicateName
        }
        return nil
    }

    static func uniqueNames(for names: [String]) -> [String] {
        var reserved = Set(names.map(normalized))
        var seen: Set<String> = []
        return names.map { name in
            let base = normalized(name)
            guard !seen.insert(base).inserted else { return name }
            var suffix = 1
            var candidate = "\(base)（\(suffix)）"
            while reserved.contains(candidate) {
                suffix += 1
                candidate = "\(base)（\(suffix)）"
            }
            reserved.insert(candidate)
            seen.insert(candidate)
            return candidate
        }
    }
}
