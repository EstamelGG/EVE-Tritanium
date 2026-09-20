import Foundation

enum FormatUtil {
    /// 共享的 NumberFormatter 实例
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3 // 默认最大3位小数
        formatter.groupingSeparator = "," // 千位分隔符
        formatter.groupingSize = 3
        formatter.decimalSeparator = "."
        return formatter
    }()

    /// 用于毫秒精度的 NumberFormatter 实例
    private static let msFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumSignificantDigits = 1
        formatter.maximumSignificantDigits = 6 // 允许最多6位有效数字
        formatter.usesSignificantDigits = true // 启用有效数字模式
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        formatter.decimalSeparator = "."
        return formatter
    }()

    /// 用于UI显示的 NumberFormatter 实例（不使用千位分隔符）
    private static let uiFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1 // UI显示最多1位小数
        formatter.groupingSeparator = "" // 不使用千位分隔符
        formatter.decimalSeparator = "."
        return formatter
    }()

    /// 通用的数字格式化函数
    /// - Parameters:
    ///   - value: 要格式化的数值
    ///   - maxFractionDigits: 最大小数位数
    ///   - showDigit: 是否显示小数部分
    /// - Returns: 格式化后的字符串
    /// - Example:
    ///   ```
    ///   formatNumber(1234.567, maxFractionDigits: 2)  // "1,234.57"
    ///   formatNumber(1234.0, maxFractionDigits: 2)     // "1,234"
    ///   formatNumber(1234.567, maxFractionDigits: 0)   // "1,235"
    ///   ```
    private static func formatNumber(
        _ value: Double, maxFractionDigits: Int, showDigit: Bool = true
    ) -> String {
        if !showDigit || value.truncatingRemainder(dividingBy: 1) == 0 {
            formatter.maximumFractionDigits = 0
            return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
        }
        formatter.maximumFractionDigits = maxFractionDigits
        return formatter.string(from: NSNumber(value: value))
            ?? String(format: "%.\(maxFractionDigits)f", value)
    }

    /// 通用的单位格式化函数
    /// - Parameters:
    ///   - value: 要格式化的数值
    ///   - unit: 单位符号
    ///   - threshold: 单位阈值
    ///   - maxFractionDigits: 最大小数位数
    /// - Returns: 格式化后的字符串
    /// - Example:
    ///   ```
    ///   formatWithUnit(1500, unit: "K", threshold: 1000, maxFractionDigits: 1)  // "1.5K"
    ///   formatWithUnit(1200, unit: "K", threshold: 1000, maxFractionDigits: 1)  // "1.2K"
    ///   formatWithUnit(1000, unit: "K", threshold: 1000, maxFractionDigits: 1)  // "1K"
    ///   ```
    private static func formatWithUnit(
        _ value: Double, unit: String, threshold: Double, maxFractionDigits: Int
    ) -> String {
        if value >= threshold {
            let formatted = value / threshold
            if formatted.truncatingRemainder(dividingBy: 1) == 0 {
                return String(format: "%.0f\(unit)", formatted)
            }
            return String(format: "%.\(maxFractionDigits)f\(unit)", formatted)
        }
        return formatNumber(value, maxFractionDigits: 0)
    }

    /// 格式化数字：支持千位分隔符，最多3位有效小数
    /// - Parameters:
    ///   - value: 要格式化的数值
    ///   - showDigit: 是否显示小数部分
    ///   - maxFractionDigits: 最大小数位数（默认3位）
    /// - Returns: 格式化后的字符串
    /// - Example:
    ///   ```
    ///   format(1234.567)                // "1,234.567"
    ///   format(1234.0)                  // "1,234"
    ///   format(1234.567, false)         // "1,235"
    ///   format(1234.567, maxFractionDigits: 2)  // "1,234.57"
    ///   ```
    static func format(_ value: Double, _ showDigit: Bool = true, maxFractionDigits: Int = 3)
        -> String
    {
        return formatNumber(value, maxFractionDigits: maxFractionDigits, showDigit: showDigit)
    }

    /// 格式化数字（毫秒精度）：支持千位分隔符，最多3位有效小数，自动去除末尾的0
    /// - Parameter value: 要格式化的数值
    /// - Returns: 格式化后的字符串
    /// - Example:
    ///   ```
    ///   formatWithMillisecondPrecision(1.234)    // "1.234"
    ///   formatWithMillisecondPrecision(1.200)    // "1.2"
    ///   formatWithMillisecondPrecision(1.000)    // "1"
    ///   formatWithMillisecondPrecision(0.001)    // "0.001"
    ///   ```
    static func formatWithMillisecondPrecision(_ value: Double) -> String {
        return msFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.3g", value)
    }

    /// 格式化文件大小
    /// - Parameter size: 文件大小（字节）
    /// - Returns: 格式化后的文件大小字符串
    /// - Example:
    ///   ```
    ///   formatFileSize(1024)        // "1 KB"
    ///   formatFileSize(1024 * 1024) // "1 MB"
    ///   formatFileSize(1500)        // "1.46 KB"
    ///   formatFileSize(999)         // "999 bytes"
    ///   ```
    static func formatFileSize(_ size: Int64) -> String {
        let units = ["bytes", "KB", "MB", "GB"]
        var size = Double(size)
        var unitIndex = 0

        while size >= 1024 && unitIndex < units.count - 1 {
            size /= 1024
            unitIndex += 1
        }

        // 根据大小使用不同的小数位数
        let formattedSize: String
        if unitIndex == 0 {
            formattedSize = String(format: "%.0f", size) // 字节不显示小数
        } else if size >= 100 {
            formattedSize = String(format: "%.0f", size) // 大于100时不显示小数
        } else if size >= 10 {
            formattedSize = String(format: "%.1f", size) // 大于10时显示1位小数
        } else {
            formattedSize = String(format: "%.2f", size) // 其他情况显示2位小数
        }

        return "\(formattedSize) \(units[unitIndex])"
    }

    /// 格式化 ISK 货币
    /// - Parameter value: ISK 数值
    /// - Returns: 格式化后的 ISK 字符串
    /// - Example:
    ///   ```
    ///   formatISK(1200)     // "1.2K ISK"
    ///   formatISK(1200000)  // "1.2M ISK"
    ///   formatISK(1200000000) // "1.2B ISK"
    ///   formatISK(1200000000000) // "1.2T ISK"
    ///   formatISK(999)      // "999 ISK"
    ///   ```
    static func formatISK(_ value: Double) -> String {
        let trillion = 1_000_000_000_000.0
        let billion = 1_000_000_000.0
        let million = 1_000_000.0
        let thousand = 1000.0

        // 处理负数：转为正数格式化，然后添加负号
        let isNegative = value < 0
        let absoluteValue = abs(value)

        let formattedValue: String
        if absoluteValue >= trillion {
            formattedValue = formatWithUnit(
                absoluteValue, unit: "T ISK", threshold: trillion, maxFractionDigits: 2
            )
        } else if absoluteValue >= billion {
            formattedValue = formatWithUnit(
                absoluteValue, unit: "B ISK", threshold: billion, maxFractionDigits: 2
            )
        } else if absoluteValue >= million {
            formattedValue = formatWithUnit(
                absoluteValue, unit: "M ISK", threshold: million, maxFractionDigits: 2
            )
        } else if absoluteValue >= thousand {
            formattedValue = formatWithUnit(
                absoluteValue, unit: "K ISK", threshold: thousand, maxFractionDigits: 2
            )
        } else {
            formattedValue = formatNumber(absoluteValue, maxFractionDigits: 1) + " ISK"
        }

        return isNegative ? "-\(formattedValue)" : formattedValue
    }

    /// 格式化时间（保留毫秒精度）
    /// - Parameter milliseconds: 时间（毫秒）
    /// - Returns: 格式化后的时间字符串
    /// - Example:
    ///   ```
    ///   formatTimeWithMillisecondPrecision(1000)    // "1s"
    ///   formatTimeWithMillisecondPrecision(1500)    // "1.5s"
    ///   formatTimeWithMillisecondPrecision(61000)   // "1m 1s"
    ///   formatTimeWithMillisecondPrecision(3661000) // "1h 1m 1s"
    ///   formatTimeWithMillisecondPrecision(0.5)     // "1ms"
    ///   ```
    static func formatTimeWithMillisecondPrecision(_ milliseconds: Double) -> String {
        let seconds = milliseconds / 1000.0
        if seconds < 1 {
            return "\(formatWithMillisecondPrecision(milliseconds))ms"
        }
        return formatEnglishDurationCore(totalSeconds: seconds, formatRemainingSeconds: formatWithMillisecondPrecision)
    }

    /// 格式化时间（保留精度版本）
    /// - Parameter totalSeconds: 总秒数（浮点数，保留原始精度）
    /// - Returns: 格式化后的时间字符串
    /// - Example:
    ///   ```
    ///   formatTimeWithPrecision(1.5)    // "1.5s"
    ///   formatTimeWithPrecision(61.5)   // "1m 1.5s"
    ///   formatTimeWithPrecision(3661.5) // "1h 1m 1.5s"
    ///   formatTimeWithPrecision(0.5)    // "0.5s"
    ///   ```
    static func formatTimeWithPrecision(_ totalSeconds: Double) -> String {
        if totalSeconds < 1 {
            return "\(format(totalSeconds))s"
        }
        return formatEnglishDurationCore(totalSeconds: totalSeconds, formatRemainingSeconds: { format($0) })
    }

    /// 格式化数字用于UI显示：不使用千位分隔符，自动去除末尾的0
    /// - Parameters:
    ///   - value: 要格式化的数值
    ///   - maxFractionDigits: 最大小数位数（默认1位）
    /// - Returns: 格式化后的字符串
    /// - Example:
    ///   ```
    ///   formatForUI(1234.5)                    // "1234.5"
    ///   formatForUI(1000.0)                    // "1000"
    ///   formatForUI(1500000000000)             // "1.5T"
    ///   formatForUI(1500000000)                // "1.5B"
    ///   formatForUI(1500000)                   // "1.5M"
    ///   formatForUI(12500)                     // "12.5k"
    ///   formatForUI(1234.567, maxFractionDigits: 2)  // "1234.57"
    ///   ```
    static func formatForUI(_ value: Double, maxFractionDigits: Int = 1) -> String {
        // 临时设置formatter的小数位数
        let originalMaxFractionDigits = uiFormatter.maximumFractionDigits
        uiFormatter.maximumFractionDigits = maxFractionDigits

        defer {
            // 恢复原始设置
            uiFormatter.maximumFractionDigits = originalMaxFractionDigits
        }

        if value == 0 {
            return "0"
        } else if value >= 1_000_000_000_000 {
            let formattedValue = value / 1_000_000_000_000
            let numberString =
                uiFormatter.string(from: NSNumber(value: formattedValue))
                    ?? String(format: "%.\(maxFractionDigits)f", formattedValue)
            return numberString + "T"
        } else if value >= 1_000_000_000 {
            let formattedValue = value / 1_000_000_000
            let numberString =
                uiFormatter.string(from: NSNumber(value: formattedValue))
                    ?? String(format: "%.\(maxFractionDigits)f", formattedValue)
            return numberString + "B"
        } else if value >= 1_000_000 {
            let formattedValue = value / 1_000_000
            let numberString =
                uiFormatter.string(from: NSNumber(value: formattedValue))
                    ?? String(format: "%.\(maxFractionDigits)f", formattedValue)
            return numberString + "M"
        } else if value >= 10000 {
            let formattedValue = value / 1000
            let numberString =
                uiFormatter.string(from: NSNumber(value: formattedValue))
                    ?? String(format: "%.\(maxFractionDigits)f", formattedValue)
            return numberString + "k"
        } else {
            return uiFormatter.string(from: NSNumber(value: value))
                ?? String(format: "%.\(maxFractionDigits)f", value)
        }
    }

    // MARK: - 日期格式化功能

    /// 通用的UTC日期解析器
    private static let utcDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")!
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// 备用UTC日期解析器（支持带时区的格式）
    private static let utcDateFormatterWithZ: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        formatter.timeZone = TimeZone(identifier: "UTC")!
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// ISO8601日期解析器
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// UTC日期解析器（仅日期格式 yyyy-MM-dd）
    private static let utcDateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")!
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// 本地时间显示格式器（短格式）
    private static let localDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// 本地时间显示格式器（带星期）
    private static let localDateFormatterWithWeekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd EEEE HH:mm"
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    /// 本地日期显示格式器（仅日期）
    private static let localDateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// 本地时间显示格式器（仅时间）
    private static let localTimeOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.timeZone = TimeZone.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    // 将UTC日期字符串转换为Date对象
    // - Parameter utcDateString: UTC格式的日期字符串
    // - Returns: Date对象，如果解析失败返回nil
    // - Example:
    //   ```
    //   parseUTCDate("2024-01-15T10:30:00Z")     // Date对象
    //   parseUTCDate("2024-01-15T10:30:00+0000") // Date对象
    //   parseUTCDate("2024-01-15")               // Date对象（仅日期格式）
    //   ```
    static func parseUTCDate(_ utcDateString: String) -> Date? {
        // 首先尝试标准格式
        if let date = utcDateFormatter.date(from: utcDateString) {
            return date
        }

        // 尝试带时区的格式
        if let date = utcDateFormatterWithZ.date(from: utcDateString) {
            return date
        }

        // 尝试ISO8601格式
        if let date = iso8601Formatter.date(from: utcDateString) {
            return date
        }

        // 尝试仅日期格式（yyyy-MM-dd）
        if let date = utcDateOnlyFormatter.date(from: utcDateString) {
            return date
        }

        return nil
    }

    // 将UTC日期字符串转换为本地时间字符串（短格式）
    // - Parameter utcDateString: UTC格式的日期字符串
    // - Returns: 本地时间字符串，格式：yyyy-MM-dd HH:mm
    // - Example:
    //   ```
    //   formatUTCToLocalTime("2024-01-15T10:30:00Z") // "2024-01-15 18:30" (假设本地时区为+8)
    //   ```
    static func formatUTCToLocalTime(_ utcDateString: String) -> String {
        formatUTCString(utcDateString, format: .dateTime)
    }

    // 将UTC日期字符串转换为本地时间字符串（带星期）
    // - Parameter utcDateString: UTC格式的日期字符串
    // - Returns: 本地时间字符串，格式：yyyy-MM-dd EEEE HH:mm
    // - Example:
    //   ```
    //   formatUTCToLocalTimeWithWeekday("2024-01-15T10:30:00Z") // "2024-01-15 Monday 18:30"
    //   ```
    static func formatUTCToLocalTimeWithWeekday(_ utcDateString: String) -> String {
        formatUTCString(utcDateString, format: .dateTimeWithWeekday)
    }

    // 将UTC日期字符串转换为本地时间字符串（仅时间）
    // - Parameter utcDateString: UTC格式的日期字符串
    // - Returns: 本地时间字符串，格式：HH:mm:ss
    // - Example:
    //   ```
    //   formatUTCToLocalTimeOnly("2024-01-15T10:30:00Z") // "18:30:00" (假设本地时区为+8)
    //   ```
    static func formatUTCToLocalTimeOnly(_ utcDateString: String) -> String {
        formatUTCString(utcDateString, format: .timeOnly)
    }

    /// 将Date对象格式化为本地时间字符串（短格式）
    /// - Parameter date: Date对象
    /// - Returns: 本地时间字符串，格式：yyyy-MM-dd HH:mm
    static func formatDateToLocalTime(_ date: Date) -> String {
        formatLocalDate(date, format: .dateTime)
    }

    /// 将Date对象格式化为本地日期字符串（仅日期）
    /// - Parameter date: Date对象
    /// - Returns: 本地日期字符串，格式：yyyy-MM-dd
    static func formatDateToLocalDate(_ date: Date) -> String {
        formatLocalDate(date, format: .dateOnly)
    }

    // MARK: - 整数 / 加载时间

    /// 整数千位分隔（等价于 `format(Double, maxFractionDigits: 0)`）
    static func formatInteger(_ value: Int) -> String {
        format(Double(value), false, maxFractionDigits: 0)
    }

    /// 本地化百分比（`fraction` 为 0–1 比例，如 0.85 → 85%）
    static func formatPercent(_ fraction: Double, fractionDigits: Int = 1) -> String {
        let formatter = fractionDigits == 0 ? percentFormatter0 : percentFormatter1
        return formatter.string(from: NSNumber(value: fraction)) ?? ""
    }

    /// 本地化百分比（`value` 为 0–100 数值，如 85 → 85%）
    static func formatPercentFrom100(_ value: Double, fractionDigits: Int = 1) -> String {
        formatPercent(value / 100, fractionDigits: fractionDigits)
    }

    /// 带符号的本地化百分比（`value` 为 0–100 数值，如 +7.5 → +7.5%）
    static func formatSignedPercentFrom100(_ value: Double, fractionDigits: Int = 1) -> String {
        let formatted = formatPercentFrom100(abs(value), fractionDigits: fractionDigits)
        if value > 0 {
            return "+\(formatted)"
        }
        if value < 0 {
            return "-\(formatted)"
        }
        return formatted
    }

    private static let loadTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        formatter.locale = Locale.current
        return formatter
    }()

    /// 数据加载时间等：`MM/dd HH:mm`
    static func formatLoadTimestamp(_ date: Date) -> String {
        loadTimestampFormatter.string(from: date)
    }

    // MARK: - 市场价格

    /// 市场价格：`1.23B (1,234,567,890.00 ISK)` 或完整 ISK
    static func formatMarketPrice(_ price: Double) -> String {
        let billion = 1_000_000_000.0
        let million = 1_000_000.0
        let formattedFullPrice = formatDecimal(price)

        if price >= billion {
            return String(format: "%.2fB (%@ ISK)", price / billion, formattedFullPrice)
        }
        if price >= million {
            return String(format: "%.2fM (%@ ISK)", price / million, formattedFullPrice)
        }
        return "\(formattedFullPrice) ISK"
    }

    /// 精确 ISK 价格（2 位小数 + 千位分隔）
    static func formatPreciseISK(_ price: Double) -> String {
        formatDecimal(price)
    }

    // MARK: - 履历 / 搜索详情

    private static let historyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter
    }()

    static func formatHistoryDateRange(start: Date, end: Date?) -> String {
        let startStr = historyDateFormatter.string(from: start)
        if let end {
            return "\(startStr) - \(historyDateFormatter.string(from: end))"
        }
        return "\(startStr) - \(NSLocalizedString("Misc_Now", comment: "now"))"
    }

    static func formatHistoryDuration(start: Date, end: Date?) -> String {
        let components = Calendar.current.dateComponents([.day, .hour], from: start, to: end ?? Date())
        let days = components.day ?? 0
        let hours = components.hour ?? 0
        if days == 0 {
            return "(\(String.localizedStringWithFormat(NSLocalizedString("Time_Hours_Long", comment: ""), hours)))"
        }
        return "(\(String.localizedStringWithFormat(NSLocalizedString("Time_Days_Long", comment: ""), days)))"
    }

    // MARK: - 相对时间

    /// 「X 分钟前更新」类文案（仅分钟粒度）
    static func formatMinutesSinceUpdate(
        _ minutes: Int, justUpdated: String, minutesAgoFormat: String
    ) -> String {
        if minutes < 1 {
            return justUpdated
        }
        return String.localizedStringWithFormat(minutesAgoFormat, minutes)
    }

    /// 相对过去：天/时/分/秒逐级（ESI 状态等）
    static func formatRelativeAgoShort(since date: Date, now: Date = Date()) -> String {
        formatIntervalDuration(now.timeIntervalSince(date), style: .relativePastShort)
    }

    /// 相对过去：最多两个单位（行星殖民地更新等）
    static func formatRelativeAgo(since date: Date, now: Date = Date()) -> String {
        formatRelativeAgo(interval: now.timeIntervalSince(date))
    }

    static func formatRelativeAgo(interval: TimeInterval) -> String {
        formatIntervalDuration(interval, style: .relativePast)
    }

    /// 剩余时间：最多两个单位，不带「前」后缀
    static func formatRemainingDuration(_ interval: TimeInterval) -> String {
        formatIntervalDuration(interval, style: .remaining)
    }

    /// 由 SP 与训练速度推算时长
    static func formatTrainingDuration(skillPoints: Int, skillPointsPerHour: Double) -> String {
        guard skillPointsPerHour > 0 else {
            return NSLocalizedString("Main_Database_Not_Available", comment: "N/A")
        }
        return formatCompactDuration(TimeInterval(skillPoints) / skillPointsPerHour * 3600)
    }

    /// 蓝图/行星周期：紧凑展示（最多 2 个单位）
    static func formatBlueprintDuration(_ totalSeconds: Int) -> String {
        formatCompactDuration(TimeInterval(totalSeconds))
    }

    // MARK: - 紧凑式时长

    enum CompactDurationRounding {
        /// 截断（系统 `DateComponentsFormatter`）
        case truncate
        /// 向上取整到秒，余量向粗单位进位（技能剩余/队列）
        case ceil
    }

    /// 紧凑本地化时长：默认最多 2 单位、截断（如 `1小时30分钟`）
    static func formatCompactDuration(
        _ interval: TimeInterval,
        maximumUnitCount: Int = 2,
        rounding: CompactDurationRounding = .truncate
    ) -> String {
        switch rounding {
        case .ceil:
            return formatCompactDurationCeil(interval)
        case .truncate:
            let value = max(0, interval)
            let formatter = maximumUnitCount == 1 ? compactDurationFormatter1 : compactDurationFormatter2
            return formatter.string(from: value)
                ?? String.localizedStringWithFormat(NSLocalizedString("Time_Seconds", comment: ""), Int(value))
        }
    }

    /// PI 周期/剩余（同 `formatCompactDuration`）
    static func formatClockDuration(_ interval: TimeInterval) -> String {
        formatCompactDuration(interval)
    }

    /// PI 周期进度（同 `formatCompactDuration`）
    static func formatElapsedClock(_ interval: TimeInterval) -> String {
        formatCompactDuration(interval)
    }

    /// 蓝图工业计算（同 `formatCompactDuration`）
    static func formatIndustrialDuration(_ seconds: TimeInterval) -> String {
        formatCompactDuration(seconds)
    }

    /// PI 工厂剩余（单单位紧凑，如 `2分钟` / `1小时`）
    static func formatSimulatedDuration(_ interval: TimeInterval) -> String {
        formatCompactDuration(abs(interval), maximumUnitCount: 1)
    }

    private static let compactDurationFormatter2: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.year, .month, .day, .hour, .minute, .second]
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 2
        formatter.zeroFormattingBehavior = .dropAll
        return formatter
    }()

    private static let compactDurationFormatter1: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 1
        formatter.zeroFormattingBehavior = .dropAll
        return formatter
    }()

    /// 剩余时长向上取整（最多 2 单位，有秒则向粗单位进位）
    private static func formatCompactDurationCeil(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(ceil(max(0, interval)))
        let days = totalSeconds / (24 * 3600)
        let remainingSeconds = totalSeconds % (24 * 3600)
        let hours = remainingSeconds / (60 * 60)
        let remainingAfterHours = remainingSeconds % (60 * 60)
        let minutes = remainingAfterHours / 60
        let seconds = remainingAfterHours % 60

        if days > 0 {
            if hours > 0 || minutes > 0 || seconds > 0 {
                let adjustedHours = (minutes > 0 || seconds > 0) ? hours + 1 : hours
                if adjustedHours > 0 {
                    return String(format: NSLocalizedString("Time_Days_Hours", comment: ""), days, adjustedHours)
                }
            }
            if minutes > 0 || seconds > 0 {
                let adjustedMinutes = seconds > 0 ? minutes + 1 : minutes
                if adjustedMinutes > 0 {
                    return String(format: NSLocalizedString("Time_Days_Minutes", comment: ""), days, adjustedMinutes)
                }
            }
            if seconds > 0 {
                return String(format: NSLocalizedString("Time_Days_Seconds", comment: ""), days, seconds)
            }
            return String.localizedStringWithFormat(NSLocalizedString("Time_Days", comment: ""), days)
        }
        if hours > 0 {
            if minutes > 0 || seconds > 0 {
                let adjustedMinutes = seconds > 0 ? minutes + 1 : minutes
                if adjustedMinutes > 0 {
                    return String(format: NSLocalizedString("Time_Hours_Minutes", comment: ""), hours, adjustedMinutes)
                }
            }
            if seconds > 0 {
                return String(format: NSLocalizedString("Time_Hours_Seconds", comment: ""), hours, seconds)
            }
            return String.localizedStringWithFormat(NSLocalizedString("Time_Hours", comment: ""), hours)
        }
        if minutes > 0 {
            if seconds > 0 {
                return String(format: NSLocalizedString("Time_Minutes_Seconds", comment: ""), minutes, seconds)
            }
            return String.localizedStringWithFormat(NSLocalizedString("Time_Minutes", comment: ""), minutes)
        }
        return String.localizedStringWithFormat(NSLocalizedString("Time_Seconds", comment: ""), seconds)
    }

    // MARK: - Private 参数化核心

    private enum DurationDisplayStyle {
        case relativePastShort
        case relativePast
        case remaining
    }

    private enum LocalDateFormat {
        case dateTime
        case dateTimeWithWeekday
        case timeOnly
        case dateOnly
    }

    private static let preciseDecimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static let percentFormatter0: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        formatter.locale = Locale.current
        return formatter
    }()

    private static let percentFormatter1: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.locale = Locale.current
        return formatter
    }()

    private static func formatDecimal(_ value: Double) -> String {
        preciseDecimalFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    private static func formatUTCString(_ utcDateString: String, format: LocalDateFormat) -> String {
        guard let date = parseUTCDate(utcDateString) else { return utcDateString }
        return formatLocalDate(date, format: format)
    }

    private static func formatLocalDate(_ date: Date, format: LocalDateFormat) -> String {
        switch format {
        case .dateTime:
            return localDateFormatter.string(from: date)
        case .dateTimeWithWeekday:
            localDateFormatterWithWeekday.locale = Locale(
                identifier: NSLocalizedString("Language_Identifier", comment: "语言标识符")
            )
            return localDateFormatterWithWeekday.string(from: date)
        case .timeOnly:
            return localTimeOnlyFormatter.string(from: date)
        case .dateOnly:
            return localDateOnlyFormatter.string(from: date)
        }
    }

    private static func formatEnglishDurationCore(
        totalSeconds: Double,
        formatRemainingSeconds: (Double) -> String
    ) -> String {
        let totalSecondsInt = Int(totalSeconds)
        let days = totalSecondsInt / 86400
        let hours = (totalSecondsInt % 86400) / 3600
        let minutes = (totalSecondsInt % 3600) / 60
        let remainingSeconds = totalSeconds - Double(days * 86400 + hours * 3600 + minutes * 60)

        var result = ""
        if days > 0 {
            result += "\(days)d "
        }
        if hours > 0 || (days > 0 && (minutes > 0 || remainingSeconds > 0)) {
            result += "\(hours)h "
        }
        if minutes > 0 || (hours > 0 && remainingSeconds > 0) {
            result += "\(minutes)m "
        }
        if remainingSeconds > 0 || result.isEmpty {
            result += "\(formatRemainingSeconds(remainingSeconds))s"
        } else {
            result = String(result.dropLast())
        }
        return result
    }

    private static func formatIntervalDuration(_ interval: TimeInterval, style: DurationDisplayStyle) -> String {
        switch style {
        case .relativePastShort:
            if interval < 0 {
                return NSLocalizedString("Time_Just_Now", comment: "")
            }
            let days = Int(interval / (24 * 3600))
            if days > 0 {
                return String.localizedStringWithFormat(NSLocalizedString("Time_Days_Ago_short", comment: ""), days)
            }
            let hours = Int(interval / 3600)
            if hours > 0 {
                return String.localizedStringWithFormat(NSLocalizedString("Time_Hours_Ago_short", comment: ""), hours)
            }
            let minutes = Int(interval / 60)
            if minutes > 0 {
                return String.localizedStringWithFormat(NSLocalizedString("Time_Minutes_Ago_short", comment: ""), minutes)
            }
            let seconds = Int(interval)
            if seconds > 0 {
                return String.localizedStringWithFormat(NSLocalizedString("Time_Seconds_Ago_short", comment: ""), seconds)
            }
            return NSLocalizedString("Time_Just_Now", comment: "")

        case .relativePast, .remaining:
            if interval < 0 {
                return style == .remaining ? "" : NSLocalizedString("Time_Just_Now", comment: "刚刚")
            }
            let totalSeconds = Int(interval)
            let days = totalSeconds / (24 * 3600)
            let hours = totalSeconds / 3600 % 24
            let minutes = totalSeconds / 60 % 60
            let isPast = style == .relativePast

            if days > 0 {
                if hours > 0 {
                    if isPast {
                        return String.localizedStringWithFormat(
                            NSLocalizedString("Time_Days_Hours_Ago", comment: ""), days, hours
                        )
                    }
                    return String.localizedStringWithFormat(
                        NSLocalizedString("Time_Days_Hours", comment: ""), days, hours
                    )
                }
                if isPast {
                    return String.localizedStringWithFormat(
                        NSLocalizedString("Time_Days_Ago", comment: ""), days
                    )
                }
                return String.localizedStringWithFormat(
                    NSLocalizedString("Time_Days", comment: ""), days
                )
            }
            if hours > 0 {
                if minutes > 0 {
                    if isPast {
                        return String.localizedStringWithFormat(
                            NSLocalizedString("Time_Hours_Minutes_Ago", comment: ""), hours, minutes
                        )
                    }
                    return String.localizedStringWithFormat(
                        NSLocalizedString("Time_Hours_Minutes", comment: ""), hours, minutes
                    )
                }
                if isPast {
                    return String.localizedStringWithFormat(
                        NSLocalizedString("Time_Hours_Ago", comment: ""), hours
                    )
                }
                return String.localizedStringWithFormat(
                    NSLocalizedString("Time_Hours", comment: ""), hours
                )
            }
            if minutes > 0 {
                if isPast {
                    return String.localizedStringWithFormat(
                        NSLocalizedString("Time_Minutes_Ago", comment: ""), minutes
                    )
                }
                return String.localizedStringWithFormat(
                    NSLocalizedString("Time_Minutes", comment: ""), minutes
                )
            }
            return NSLocalizedString("Time_Just_Now", comment: "刚刚")
        }
    }
}
