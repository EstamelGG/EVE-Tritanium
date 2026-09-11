import SwiftUI

struct IndustryJobRow: View {
    let job: IndustryJob
    let blueprintName: String
    let blueprintIcon: String?
    let locationInfo: LocationInfoDetail?
    let currentTime: Date
    let showInstaller: Bool
    let installerName: String?
    let installerImage: UIImage?
    let isFromCorporation: Bool
    @StateObject private var databaseManager = DatabaseManager()
    @Environment(\.colorScheme) private var colorScheme

    /// 带颜色的状态文本结构体
    struct StatusText {
        let text: String
        let color: Color
    }

    /// 修改时间显示格式
    private func getTimeDisplay() -> String {
        let currentTime = Date()
        let dateStr = formatDate(job.end_date)

        // 如果已经完成，只显示完成时间
        if job.status == "delivered" || job.status == "ready" || currentTime >= job.end_date {
            return dateStr
        }

        // 如果是活动状态，添加剩余时间
        if job.status == "active" {
            return "\(dateStr)"
        }

        return dateStr
    }

    /// 获取活动状态文本和颜色
    private func getActivityStatus() -> StatusText {
        // 先检查特殊状态
        switch job.status {
        case "cancelled":
            return StatusText(
                text:
                "\(getActivityTypeText())·\(NSLocalizedString("Industry_Status_cancelled", comment: ""))",
                color: .red
            )
        case "revoked":
            return StatusText(
                text:
                "\(getActivityTypeText())·\(NSLocalizedString("Industry_Status_revoked", comment: ""))",
                color: .red
            )
        case "failed":
            return StatusText(
                text:
                "\(getActivityTypeText())·\(NSLocalizedString("Industry_Status_failed", comment: ""))",
                color: .red
            )
        case "delivered":
            let statusText = NSLocalizedString("Industry_Status_delivered", comment: "")
            var finalText = "\(getActivityTypeText())·\(statusText)"
            // 只针对发明类项目显示成功率数量
            if job.probability != nil && job.runs > 0 && job.activity_id == 8 {
                let successfulRuns = job.successful_runs ?? 0
                finalText = "\(getActivityTypeText())·\(statusText) (\(successfulRuns)/\(job.runs))"
            }
            return StatusText(text: finalText, color: .secondary)
        case "ready":
            return StatusText(
                text:
                "\(getActivityTypeText())·\(NSLocalizedString("Industry_Status_ready", comment: ""))",
                color: .green
            )
        default:
            // 检查是否已完成但未交付
            if Date() >= job.end_date {
                return StatusText(
                    text:
                    "\(getActivityTypeText())·\(NSLocalizedString("Industry_Status_ready", comment: ""))",
                    color: .green
                )
            }

            if job.status != "active" {
                return StatusText(
                    text: NSLocalizedString("Industry_Status_\(job.status)", comment: ""),
                    color: .secondary
                )
            }

            // 如果是活动状态，根据活动类型返回对应文本和颜色
            // https://sde.hoboleaks.space/tq/industryactivities.json
            switch job.activity_id {
            case 1:
                return StatusText(
                    text: getActivityTypeText(),
                    color: Color(red: 204 / 255, green: 153 / 255, blue: 0 / 255)
                )
            case 3:
                return StatusText(
                    text: getActivityTypeText(),
                    color: Color.blue
                )
            case 4:
                return StatusText(
                    text: getActivityTypeText(),
                    color: Color.blue
                )
            case 5:
                return StatusText(
                    text: getActivityTypeText(),
                    color: Color.blue
                )
            case 8:
                return StatusText(
                    text: getActivityTypeText(),
                    color: Color.blue
                )
            case 9:
                return StatusText(
                    text: getActivityTypeText(),
                    color: Color.cyan
                )
            default:
                return StatusText(
                    text: NSLocalizedString("Industry_Status_active", comment: ""),
                    color: .secondary
                )
            }
        }
    }

    /// 格式化日期
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    /// 获取活动类型文本（军团挂接任务会附加后缀）
    private func getActivityTypeText() -> String {
        let base: String
        switch job.activity_id {
        case 1:
            base = NSLocalizedString("Industry_Type_Manufacturing_Short", comment: "")
        case 3:
            base = NSLocalizedString("Industry_Type_Research_Time_Short", comment: "")
        case 4:
            base = NSLocalizedString("Industry_Type_Research_Material_Short", comment: "")
        case 5:
            base = NSLocalizedString("Industry_Type_Copying", comment: "")
        case 8:
            base = NSLocalizedString("Industry_Type_Invention", comment: "")
        case 9:
            base = NSLocalizedString("Industry_Type_Reaction", comment: "")
        default:
            base = ""
        }
        if isFromCorporation, !base.isEmpty {
            return base + NSLocalizedString("Industry_Job_Source_Corp_Suffix", comment: "")
        }
        return base
    }

    var body: some View {
        NavigationLink(
            destination: ShowBluePrintInfo(
                blueprintID: job.blueprint_type_id, databaseManager: databaseManager
            )
        ) {
            VStack(alignment: .leading, spacing: 4) {
                // 第一行：蓝图图标、名称和状态
                HStack(spacing: 12) {
                    // 蓝图图标
                    if let iconFileName = blueprintIcon {
                        IconManager.shared.loadImage(for: iconFileName)
                            .resizable()
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 32, height: 32)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        // 蓝图名称和状态
                        HStack(spacing: 6) {
                            // 工业类型图标
                            if colorScheme == .light {
                                IconManager.shared.loadImage(
                                    for: getActivityTypeIcon(for: job.activity_id)
                                )
                                .resizable()
                                .frame(width: 14, height: 14)
                                .cornerRadius(2)
                                .colorInvert()
                            } else {
                                IconManager.shared.loadImage(
                                    for: getActivityTypeIcon(for: job.activity_id)
                                )
                                .resizable()
                                .frame(width: 14, height: 14)
                                .cornerRadius(2)
                            }

                            Text(blueprintName)
                                .font(.headline)
                                .lineLimit(1)

                            Spacer()

                            // 已完成可交付标记
                            if job.status == "ready" || (job.status == "active" && currentTime >= job.end_date) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 16))
                            }
                        }

                        // 数量信息
                        HStack {
                            Text(
                                job.activity_id == 5
                                    ? String(
                                        format: NSLocalizedString(
                                            "Industry_Runs_With_Copies_Format", comment: ""
                                        ),
                                        job.runs, job.licensed_runs ?? 1
                                    )
                                    : String(
                                        format: NSLocalizedString(
                                            "Industry_Runs_Format", comment: ""
                                        ), job.runs
                                    )
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                            Spacer()
                            if job.status == "active" {
                                IndustryCountdownView(endDate: job.end_date)
                            }
                        }
                    }
                }

                // 进度条
                IndustryProgressView(job: job)
                    .padding(.vertical, 4)

                // 第二行：位置信息和发起人信息
                if showInstaller && installerName != nil {
                    GeometryReader { geometry in
                        HStack(spacing: 8) {
                            // 左侧 2/3：位置信息
                            LocationInfoView(
                                stationName: locationInfo?.stationName,
                                solarSystemName: locationInfo?.solarSystemName,
                                security: locationInfo?.security,
                                font: .caption,
                                textColor: .secondary
                            )
                            .lineLimit(1)
                            .frame(width: geometry.size.width * 0.67, alignment: .leading)

                            Spacer()

                            // 右侧 1/3：发起人信息
                            if let installerName = installerName {
                                HStack(spacing: 4) {
                                    // 发起人头像
                                    if let installerImage = installerImage {
                                        Image(uiImage: installerImage)
                                            .resizable()
                                            .frame(width: 18, height: 18)
                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                    } else {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(width: 18, height: 18)
                                    }

                                    // 发起人名称
                                    Text(installerName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(width: geometry.size.width * 0.33 - 8, alignment: .trailing)
                            }
                        }
                    }
                    .frame(height: 16)
                } else {
                    // 单人模式：只显示位置信息
                    LocationInfoView(
                        stationName: locationInfo?.stationName,
                        solarSystemName: locationInfo?.solarSystemName,
                        security: locationInfo?.security,
                        font: .caption,
                        textColor: .secondary
                    )
                    .lineLimit(1)
                }
                HStack {
                    let statusInfo = getActivityStatus()
                    Text(statusInfo.text)
                        .font(.caption)
                        .foregroundColor(statusInfo.color)
                    Spacer()

                    // 根据完成状态显示不同的时间前缀
                    let isCompleted = job.status == "delivered" || job.status == "ready" || currentTime >= job.end_date
                    let timePrefix = isCompleted
                        ? NSLocalizedString("Industry_Completed_At", comment: "已完成于")
                        : NSLocalizedString("Finished_on", comment: "")

                    Text("\(timePrefix) \(getTimeDisplay())")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .contextMenu {
            // 复制发起人名称
            if showInstaller, let installerName = installerName {
                Button {
                    UIPasteboard.general.string = installerName
                } label: {
                    Label(
                        NSLocalizedString("Industry_Copy_Installer_Name", comment: "复制发起人名称: %@"),
                        systemImage: "person.crop.circle"
                    )
                }
            }

            // 复制地点信息
            if let locationInfo = locationInfo {
                let locationText =
                    !locationInfo.stationName.isEmpty
                        ? locationInfo.stationName : locationInfo.solarSystemName
                Button {
                    UIPasteboard.general.string = locationText
                } label: {
                    Label(
                        NSLocalizedString("Misc_Copy_Location", comment: "复制地点"),
                        systemImage: "doc.on.doc"
                    )
                }

                // 显示名与英文名不同时，追加复制英文名
                let englishText =
                    !locationInfo.stationName.isEmpty
                        ? locationInfo.stationEnglishName : locationInfo.solarSystemEnglishName
                if let enName = englishText, enName != locationText {
                    Button {
                        UIPasteboard.general.string = enName
                    } label: {
                        Label(
                            NSLocalizedString("Misc_Copy_Trans", comment: "复制翻译"),
                            systemImage: "translate"
                        )
                    }
                }
            }
        }
    }
}
