import Foundation

enum CompactDuration {
    enum Rounding {
        /// 截断到允许的最小单位。
        case truncate
        /// 向上取整到显示的最小单位（技能剩余/队列）。
        case ceil
    }

    /// 显示最高的两个相邻单位，不补前导零；小组件可隐藏秒。
    static func format(
        _ interval: TimeInterval,
        rounding: Rounding = .truncate,
        showsSeconds: Bool = true,
        locale: Locale = WidgetLocalization.locale
    ) -> String {
        let interval = interval.isFinite ? max(0, interval) : 0
        let unit: Double = showsSeconds ? 1 : 60
        var seconds = (interval / unit).rounded(.down) * unit
        if rounding == .ceil {
            seconds = ceil(interval / unit) * unit
            if seconds >= 86400 {
                seconds = ceil(seconds / 3600) * 3600
            } else if seconds >= 3600 {
                seconds = ceil(seconds / 60) * 60
            }
        }
        // 避免异常时长转换为 Int 时溢出。
        let total = Int(min(seconds, Double(Int.max / 2)))
        return compactDurationText(seconds: total, showsSeconds: showsSeconds, locale: locale)
    }

    private static func compactDurationText(seconds: Int, showsSeconds: Bool, locale: Locale) -> String {
        let values = [seconds / 86400, seconds / 3600 % 24, seconds / 60 % 60, seconds % 60]
        let bundle = Bundle.main.url(forResource: locale.identifier, withExtension: "lproj")
            .flatMap(Bundle.init(url:)) ?? WidgetLocalization.bundle
        let templates = [
            NSLocalizedString(
                "Time_Compact_Days",
                tableName: "CompactDuration",
                bundle: bundle,
                comment: "Compact duration days"
            ),
            NSLocalizedString(
                "Time_Compact_Hours",
                tableName: "CompactDuration",
                bundle: bundle,
                comment: "Compact duration hours"
            ),
            NSLocalizedString(
                "Time_Compact_Minutes",
                tableName: "CompactDuration",
                bundle: bundle,
                comment: "Compact duration minutes"
            ),
            NSLocalizedString(
                "Time_Compact_Seconds",
                tableName: "CompactDuration",
                bundle: bundle,
                comment: "Compact duration seconds"
            ),
        ]
        let last = showsSeconds ? 3 : 2
        let first = values[...last].firstIndex(where: { $0 > 0 }) ?? last
        // 保留相邻低位的零，避免 8时0分17秒跳成 8时17秒。
        let indices = first ... min(first + 1, last)
        let parts = indices.map { String(format: templates[$0], Int64(values[$0])) }
        let joinTemplate = NSLocalizedString(
            "Time_Compact_Join",
            tableName: "CompactDuration",
            bundle: bundle,
            comment: "Join duration components"
        )
        return parts.dropFirst().reduce(parts[0]) { String(format: joinTemplate, $0, $1) }
    }
}
