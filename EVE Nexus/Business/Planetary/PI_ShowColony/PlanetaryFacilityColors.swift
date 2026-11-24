import Foundation
import SwiftUI

/// 行星设施颜色配置
/// 集中管理所有设施、图表、图标的颜色，便于后续微调
enum PlanetaryFacilityColors {
    // MARK: - 工厂设施颜色

    /// 工厂进度条 - 高科技工厂（High-Tech）
    static let factoryProgressHighTech = Color(hex: "96BD2A")

    /// 工厂进度条 - 高级工厂（Advanced）
    static let factoryProgressAdvanced = Color(hex: "D5C52F")

    /// 工厂进度条 - 默认工厂
    static let factoryProgressDefault = Color(hex: "A06337")

    /// 工厂进度条 - 非活跃状态
    static let factoryProgressInactive = Color.gray

    /// 工厂输入物品图标 - 深色底色
    static let factoryInputIconBackgroundDark = Color(red: 47 / 255.0, green: 28 / 255.0, blue: 10 / 255.0)

    /// 工厂输入物品图标 - 浅色覆盖（根据库存占比显示）
    static let factoryInputIconBackgroundLight = Color(red: 237 / 255.0, green: 153 / 255.0, blue: 53 / 255.0)

    // MARK: - 存储设施颜色

    /// 存储进度条 - 正常状态（容量 < 90%）
    static let storageProgressNormal = Color.blue

    /// 存储进度条 - 接近满状态（容量 >= 90% 且 < 100%）
    static let storageProgressNearFull = Color.orange

    /// 存储进度条 - 已满状态（容量 >= 100%）
    static let storageProgressFull = Color.red

    // MARK: - 图表颜色

    /// 提取器产量图表 - 当前周期柱状图
    static let extractorChartCurrentCycle = Color.teal

    /// 提取器产量图表 - 其他周期柱状图
    static let extractorChartOtherCycle = Color.gray.opacity(0.6)

    /// 存储变化图表 - 正常状态（容量 < 90%）
    static let storageChartNormal = Color.blue

    /// 存储变化图表 - 接近满状态（容量 >= 90% 且 < 100%）
    static let storageChartNearFull = Color.orange

    /// 存储变化图表 - 超容量状态（容量 >= 100%）
    static let storageChartExceeded = Color.red

    /// 存储变化图表 - 当前时间垂直线
    static let storageChartCurrentTimeLine = Color.blue
}

// MARK: - Color Extension for Hex Support

extension Color {
    /// 从十六进制字符串创建颜色
    /// - Parameter hex: 十六进制颜色字符串（如 "96BD2A" 或 "#96BD2A"）
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Factory Type Classification

/// 工厂类型枚举
enum FactoryType {
    case highTech // 高科技工厂
    case advanced // 高级工厂
    case `default` // 默认工厂
}

/// 工厂类型识别工具
enum FactoryTypeClassifier {
    /// 根据英文名称识别工厂类型
    /// - Parameter enName: 工厂的英文名称
    /// - Returns: 工厂类型
    static func classifyFactory(enName: String?) -> FactoryType {
        guard let enName = enName else {
            return .default
        }

        let lowercased = enName.lowercased()

        if lowercased.contains("high-tech") {
            return .highTech
        } else if lowercased.contains("advanced") {
            return .advanced
        } else {
            return .default
        }
    }

    /// 根据工厂类型获取对应的进度条颜色
    /// - Parameters:
    ///   - factoryType: 工厂类型
    ///   - isActive: 是否处于活跃状态
    /// - Returns: 进度条颜色
    static func getProgressColor(for factoryType: FactoryType, isActive: Bool) -> Color {
        guard isActive else {
            return PlanetaryFacilityColors.factoryProgressInactive
        }

        switch factoryType {
        case .highTech:
            return PlanetaryFacilityColors.factoryProgressHighTech
        case .advanced:
            return PlanetaryFacilityColors.factoryProgressAdvanced
        case .default:
            return PlanetaryFacilityColors.factoryProgressDefault
        }
    }
}
