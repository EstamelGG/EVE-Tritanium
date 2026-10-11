import SwiftUI

/// 提取器设施视图
struct ExtractorFacilityView: View {
    @Environment(\.locale) private var displayLocale
    @Environment(\.timeZone) private var displayTimeZone
    let pin: PlanetaryPin
    let extractor: PlanetaryExtractor
    let typeNames: [Int: String]
    let typeIcons: [Int: String]
    let typeGroupIds: [Int: Int]
    let typeEnNames: [Int: String]
    let currentTime: Date
    var isLive: Bool = true

    /// 计算属性：判断采集器是否过期
    private var isExpired: Bool {
        guard let expiryTime = pin.expiryTime,
              let expiryDate = ExtractorYieldCalculator.parsedDate(expiryTime)
        else {
            return false
        }
        return currentTime >= expiryDate
    }

    /// 获取设施图标文件名
    /// 优先级：1. 根据 groupID 和 en_name 映射的图标 2. typeid 对应的图标（兜底）
    private func getFacilityIconName() -> String? {
        // 尝试使用映射规则获取图标
        if let groupId = typeGroupIds[pin.typeId] {
            let enName = typeEnNames[pin.typeId]
            let mappedIconName = PlanetaryUtils.getFacilityIconName(groupId: groupId, enName: enName)
            // 如果映射返回了有效的图标名称，使用它
            if !mappedIconName.isEmpty {
                return mappedIconName
            }
        }
        // 兜底：使用 typeid 对应的图标
        return typeIcons[pin.typeId]
    }

    var body: some View {
        // 提取器基本信息
        HStack(alignment: .center, spacing: 12) {
            if let iconName = getFacilityIconName() {
                IconManager.shared.loadImage(for: iconName)
                    .resizable()
                    .frame(width: 40, height: 40)
                    .cornerRadius(6)
            }

            VStack(alignment: .leading, spacing: 6) {
                // 设施名称
                Text(
                    typeNames[pin.typeId] ?? NSLocalizedString("Planet_Detail_Unknown_Type", comment: "")
                )
                .fontWeight(.semibold)
                .lineLimit(1)

                // 采集周期进度
                if let cycleTime = extractor.cycleTime, let installTime = pin.installTime {
                    let progress =
                        isExpired
                            ? 0
                            : calculateExtractorProgress(
                                installTime: installTime, cycleTime: cycleTime
                            )

                    VStack(alignment: .leading, spacing: 2) {
                        PulsingProgressBar(
                            progress: progress,
                            color: isExpired ? PlanetaryFacilityColors.extractorProgressExpired : PlanetaryFacilityColors.extractorProgressActive,
                            showPulse: isLive && !isExpired
                        )

                        // 显示当前周期时间
                        let elapsedTime =
                            isExpired
                                ? 0
                                : calculateElapsedTimeInCurrentCycle(
                                    installTime: installTime, cycleTime: cycleTime
                                )
                        let cycleText = "\(FormatUtil.formatElapsedClock(elapsedTime)) / \(FormatUtil.formatElapsedClock(TimeInterval(cycleTime)))"
                        Text(cycleText)
                            .modifier(NumericTimeTransition(text: cycleText, countsDown: false, isEnabled: isLive && !isExpired))
                            .foregroundColor(isExpired ? .gray : .secondary)
                            .font(.system(.footnote, design: .monospaced))
                    }
                }
            }
        }

        // 提取器产量图表
        if let installTime = pin.installTime {
            ExtractorYieldChartView(
                extractor: extractor,
                installTime: installTime,
                expiryTime: pin.expiryTime,
                currentTime: currentTime,
                isLive: isLive
            )
        }

        // 产出资源信息
        if let productTypeId = extractor.productTypeId, let qtyPerCycle = extractor.qtyPerCycle,
           let installTime = pin.installTime, let cycleTime = extractor.cycleTime
        {
            // 从ExtractorYieldCalculator获取当前周期的产出
            let currentCycle = ExtractorYieldCalculator.getCurrentCycle(
                installTime: installTime, expiryTime: pin.expiryTime ?? "", cycleTime: cycleTime, currentTime: currentTime
            )
            let calculator = ExtractorYieldCalculator(
                quantityPerCycle: qtyPerCycle, cycleTime: cycleTime
            )
            let currentYield =
                isExpired
                    ? 0 : (currentCycle >= 0 ? calculator.calculateYield(cycleIndex: currentCycle) : 0)

            NavigationLink(
                destination: ShowPlanetaryInfo(
                    itemID: productTypeId, databaseManager: DatabaseManager.shared
                )
            ) {
                HStack(alignment: .center, spacing: 12) {
                    if let iconName = typeIcons[productTypeId] {
                        Image(uiImage: IconManager.shared.loadUIImage(for: iconName))
                            .resizable()
                            .frame(width: 32, height: 32)
                            .cornerRadius(4)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(
                                NSLocalizedString("Factory_Output", comment: "")
                                    + " \(typeNames[productTypeId] ?? "")"
                            )
                            Spacer()
                            Text("× \(currentYield)")
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    /// 计算提取器当前周期的进度
    /// - Parameters:
    ///   - installTime: 安装时间
    ///   - cycleTime: 周期时间（秒）
    /// - Returns: 进度值（0-1）
    private func calculateExtractorProgress(installTime: String, cycleTime: Int) -> Double {
        guard let installDate = ExtractorYieldCalculator.parsedDate(installTime) else {
            return 0
        }

        let totalElapsedTime = currentTime.timeIntervalSince(installDate)
        let cycleTimeInterval = TimeInterval(cycleTime)

        // 计算当前周期内已经过去的时间
        let elapsedInCurrentCycle = totalElapsedTime.truncatingRemainder(
            dividingBy: cycleTimeInterval
        )

        // 计算进度
        return elapsedInCurrentCycle / cycleTimeInterval
    }

    /// 计算当前周期内已经过去的时间
    /// - Parameters:
    ///   - installTime: 安装时间
    ///   - cycleTime: 周期时间（秒）
    /// - Returns: 已经过去的时间（秒）
    private func calculateElapsedTimeInCurrentCycle(installTime: String, cycleTime: Int)
        -> TimeInterval
    {
        guard let installDate = ExtractorYieldCalculator.parsedDate(installTime) else {
            return 0
        }

        let totalElapsedTime = currentTime.timeIntervalSince(installDate)
        let cycleTimeInterval = TimeInterval(cycleTime)

        // 计算当前周期内已经过去的时间
        return totalElapsedTime.truncatingRemainder(dividingBy: cycleTimeInterval)
    }
}
