
//  ThemeColorExtractor.swift
//  EVE Nexus

//  Created on 2025/01/XX.
//  主题色提取工具，用于从图像中计算主要颜色

import SwiftUI
import UIKit

// MARK: - 主题色结构体

/// 从图像中提取的主题色信息
struct ThemeColor {
    /// 主要颜色（出现频率最高的颜色）
    let primary: UIColor

    /// 次要颜色（可选）
    let secondary: UIColor?

    /// 背景颜色（可选）
    let background: UIColor?

    // MARK: - SwiftUI 支持

    /// 主要颜色（SwiftUI）
    var primaryColor: Color {
        Color(primary)
    }
}

// MARK: - 主题色计算函数

/// 从图像中提取主题色（取中心15x15区域的平均颜色）
/// - Parameter image: 输入的 UIImage
/// - Returns: 提取的主题色信息，如果提取失败则返回 nil
func extractThemeColor(from image: UIImage) -> ThemeColor? {
    guard let cgImage = image.cgImage else { return nil }

    let width = cgImage.width
    let height = cgImage.height

    // 如果图像太小，直接返回 nil
    guard width >= 15, height >= 15 else { return nil }

    let bytesPerPixel = 4
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    guard let context = CGContext(data: nil,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: width * bytesPerPixel,
                                  space: colorSpace,
                                  bitmapInfo: bitmapInfo),
        let data = context.data
    else { return nil }

    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    let ptr = data.bindMemory(to: UInt8.self, capacity: width * height * bytesPerPixel)

    // 计算中心15x15区域的起始位置
    let centerX = width / 2
    let centerY = height / 2
    let startX = centerX - 7 // 中心向左偏移7个像素
    let startY = centerY - 7 // 中心向上偏移7个像素

    var totalR: Double = 0
    var totalG: Double = 0
    var totalB: Double = 0
    var validPixelCount = 0

    // 遍历中心15x15区域
    for y in startY ..< (startY + 15) {
        for x in startX ..< (startX + 15) {
            let offset = (y * width + x) * bytesPerPixel

            guard offset + 3 < width * height * bytesPerPixel else { continue }

            let r = Double(ptr[offset])
            let g = Double(ptr[offset + 1])
            let b = Double(ptr[offset + 2])
            let a = Double(ptr[offset + 3])

            // 忽略透明像素
            if a < 25 {
                continue
            }

            totalR += r
            totalG += g
            totalB += b
            validPixelCount += 1
        }
    }

    // 如果没有有效像素，返回 nil
    guard validPixelCount > 0 else { return nil }

    // 计算平均颜色
    let avgR = totalR / Double(validPixelCount)
    let avgG = totalG / Double(validPixelCount)
    let avgB = totalB / Double(validPixelCount)

    let primaryColor = UIColor(
        red: CGFloat(avgR) / 255.0,
        green: CGFloat(avgG) / 255.0,
        blue: CGFloat(avgB) / 255.0,
        alpha: 1.0
    )

    return ThemeColor(primary: primaryColor, secondary: nil, background: nil)
}

// MARK: - UIImage 扩展

extension UIImage {
    /// 计算图像的主题色
    /// - Returns: 提取的主题色信息，如果提取失败则返回 nil
    func computeThemeColor() -> ThemeColor? {
        return extractThemeColor(from: self)
    }
}
