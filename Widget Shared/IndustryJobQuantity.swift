import Foundation

enum IndustryJobQuantity {
    static func description(runs: Int, isCopying: Bool, licensedRuns: Int?) -> String {
        if isCopying {
            return String(
                format: NSLocalizedString("Industry_Runs_With_Copies_Format", tableName: "IndustryJobQuantity", bundle: WidgetLocalization.bundle, comment: ""),
                runs, licensedRuns ?? 1
            )
        }
        return String(
            format: NSLocalizedString("Industry_Runs_Format", tableName: "IndustryJobQuantity", bundle: WidgetLocalization.bundle, comment: ""),
            runs
        )
    }
}
