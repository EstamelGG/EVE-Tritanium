import Foundation
import UIKit

/// 应用图标配置
enum AppIconConfig {
    /// 硬编码的图标列表
    static let iconList = ["Tritanium_basic", "Tritanium", "TriDB", "OverseerBox", "HyperCore"]

    /// 硬编码的角标列表
    static let badgeList = ["T1", "T2", "T3", "Factions", "Deadspace", "Officers"]

    // UserDefaults 键
    static let selectedIconKey = "selectedAppIconName"
    static let selectedBadgeKey = "selectedAppIconBadge"

    /// 根据选择的图标和角标生成图标ID
    /// - Parameters:
    ///   - icon: 图标名称
    ///   - badge: 角标名称
    /// - Returns: 图标ID字符串
    static func getIconId(icon: String, badge: String) -> String? {
        if badge == "T1" {
            // T1角标对应无角标版本
            return icon
        } else {
            // 其他角标格式：IconName_BadgeName
            return "\(icon)_\(badge)"
        }
    }

    /// 从图标ID解析图标名称和角标
    /// - Parameter iconId: 图标ID
    /// - Returns: (图标名称, 角标名称)
    static func parseIconId(_ iconId: String?) -> (icon: String, badge: String) {
        guard let iconId = iconId, !iconId.isEmpty else {
            return ("Tritanium", "T1")
        }

        // 检查是否有下划线（表示有角标）
        if let underscoreIndex = iconId.lastIndex(of: "_") {
            let iconName = String(iconId[..<underscoreIndex])
            let badgeName = String(iconId[iconId.index(after: underscoreIndex)...])

            // 验证图标名称和角标是否有效
            if iconList.contains(iconName), badgeList.contains(badgeName) {
                return (iconName, badgeName)
            }
        }

        // 如果没有下划线，说明是基础图标（T1角标）
        if iconList.contains(iconId) {
            return (iconId, "T1")
        }

        // 默认值
        return ("Tritanium", "T1")
    }

    /// 获取当前选择的图标和角标
    /// - Returns: (图标名称, 角标名称)
    static func getCurrentIconAndBadge() -> (icon: String, badge: String) {
        // 优先从 UserDefaults 读取
        if let savedIcon = UserDefaults.standard.string(forKey: selectedIconKey),
           iconList.contains(savedIcon),
           let savedBadge = UserDefaults.standard.string(forKey: selectedBadgeKey),
           badgeList.contains(savedBadge)
        {
            return (savedIcon, savedBadge)
        }

        // 如果 UserDefaults 中没有，从 AppIconManager 解析
        if let currentIconId = AppIconManager.shared.currentIconName, !currentIconId.isEmpty {
            return parseIconId(currentIconId)
        }

        // 默认值
        return ("Tritanium", "T1")
    }

    /// 组合图标：将角标叠加在review图左上角
    /// - Returns: 组合后的图标图片
    static func composeAppIcon(icon: String? = nil, badge: String? = nil) -> UIImage? {
        let current = getCurrentIconAndBadge()
        let iconName = icon ?? current.icon
        let badgeName = badge ?? current.badge

        // Prefer the fully rendered alternate icon used by the app itself.
        if let iconID = getIconId(icon: iconName, badge: badgeName),
           let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let alternates = icons["CFBundleAlternateIcons"] as? [String: Any],
           let entry = alternates[iconID] as? [String: Any],
           let files = entry["CFBundleIconFiles"] as? [String]
        {
            for file in files.reversed() {
                if let image = UIImage(named: file) {
                    return image
                }
            }
        }

        // 加载review图（不带角标的母图）
        guard let baseImage = UIImage(named: iconName) else {
            // 如果review图不存在，尝试加载默认图标
            if let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
               let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
               let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
               let lastIcon = iconFiles.last,
               let defaultImage = UIImage(named: lastIcon)
            {
                return defaultImage
            }
            return UIImage(named: "DefaultAppIcon")
        }

        // 如果是T1角标，直接返回review图
        if badgeName == "T1" {
            return baseImage
        }

        // 加载角标图片
        guard let badgeImage = UIImage(named: badgeName) else {
            return baseImage
        }

        // 创建图形上下文
        let size = baseImage.size
        UIGraphicsBeginImageContextWithOptions(size, false, baseImage.scale)
        defer { UIGraphicsEndImageContext() }

        // 绘制母图
        baseImage.draw(in: CGRect(origin: .zero, size: size))

        // 计算角标尺寸（47.5%缩放）
        let badgeSize = CGSize(width: size.width * 0.475, height: size.height * 0.475)
        // 角标位置：左上角
        let badgeOrigin = CGPoint.zero

        // 绘制角标
        badgeImage.draw(in: CGRect(origin: badgeOrigin, size: badgeSize))

        // 获取组合后的图片
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}
