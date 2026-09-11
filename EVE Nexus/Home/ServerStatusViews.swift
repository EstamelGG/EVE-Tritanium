import Foundation
import SwiftUI

/// 优化 ServerStatusView
class ServerStatusViewModel: ObservableObject {
    @Published var status: ServerStatus?
    @Published var currentTime = Date()
    private var timer: Timer?
    private var statusTimer: Timer?

    /// 获取UTC时间的小时和分钟
    private var utcHourAndMinute: (hour: Int, minute: Int) {
        let calendar = Calendar.current
        let utc = TimeZone(identifier: "UTC")!
        let components = calendar.dateComponents(in: utc, from: currentTime)
        return (components.hour ?? 0, components.minute ?? 0)
    }

    /// 计算下一次更新的时间间隔
    private var nextUpdateInterval: TimeInterval {
        let (hour, minute) = utcHourAndMinute

        // 11:00 AM UTC
        if hour == 11 && minute == 0 {
            return 60 // 1分钟
        }
        // 11:00-11:30 AM UTC
        else if hour == 11 && minute < 30 {
            // 如果服务器已经在线，切换到2分钟间隔
            if let status = status, status.isOnline {
                return 120 // 2分钟
            }
            return 60 // 1分钟
        }
        // 11:30 AM UTC 之后
        else if hour == 11 && minute >= 30 {
            return 120 // 2分钟
        }
        // 11:00 AM UTC 之前
        else {
            return 1200 // 20分钟
        }
    }

    func startTimers() {
        // 停止现有的计时器
        stopTimers()

        // 创建时间更新计时器（每秒更新）
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let oldTime = self.currentTime
            self.currentTime = Date()

            // 检查是否跨越了整点或半点
            let oldHourMinute = self.getHourAndMinute(from: oldTime)
            let newHourMinute = self.getHourAndMinute(from: self.currentTime)

            // 在特定时间点立即刷新
            if self.shouldImmediatelyRefresh(oldTime: oldHourMinute, newTime: newHourMinute) {
                Task {
                    await self.refreshServerStatus()
                }
                // 重新设置状态更新计时器
                self.resetStatusTimer()
            }
        }

        // 设置状态更新计时器（这会自动触发第一次刷新）
        resetStatusTimer()
    }

    private func getHourAndMinute(from date: Date) -> (hour: Int, minute: Int) {
        let calendar = Calendar.current
        let utc = TimeZone(identifier: "UTC")!
        let components = calendar.dateComponents(in: utc, from: date)
        return (components.hour ?? 0, components.minute ?? 0)
    }

    private func shouldImmediatelyRefresh(
        oldTime: (hour: Int, minute: Int), newTime: (hour: Int, minute: Int)
    ) -> Bool {
        // 11:00 AM UTC
        if newTime.hour == 11 && newTime.minute == 0 && (oldTime.hour != 11 || oldTime.minute != 0) {
            return true
        }
        return false
    }

    private func resetStatusTimer() {
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: nextUpdateInterval, repeats: true) {
            [weak self] _ in
            Task {
                await self?.refreshServerStatus()
            }
        }
    }

    func stopTimers() {
        timer?.invalidate()
        timer = nil
        statusTimer?.invalidate()
        statusTimer = nil
    }

    private func refreshServerStatus(forceRefresh: Bool = false) async {
        do {
            let newStatus = try await ServerStatusAPI.shared.fetchServerStatus(
                forceRefresh: forceRefresh
            )
            await MainActor.run {
                self.status = newStatus

                // 如果在11:00-11:30之间且服务器已上线，重置计时器使用新的间隔
                let (hour, minute) = utcHourAndMinute
                if hour == 11, minute < 30, newStatus.isOnline {
                    resetStatusTimer()
                }
            }
        } catch {
            Logger.error("刷新服务器状态失败: \(error)")
        }
    }

    deinit {
        stopTimers()
    }
}

struct ServerStatusView: View {
    @StateObject private var viewModel = ServerStatusViewModel()
    @ObservedObject var mainViewModel: MainViewModel

    var body: some View {
        HStack(spacing: 4) {
            Text(formattedUTCDateTime)
                .font(.monospacedDigit(.caption)())
                .fixedSize()
            Text("-")
                .font(.caption)
            statusText
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .onAppear {
            viewModel.startTimers()
        }
        .onDisappear {
            viewModel.stopTimers()
        }
    }

    /// Tranquility 日期与时间同列，UTC，MM/dd HH:mm
    private var formattedUTCDateTime: String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: viewModel.currentTime)
    }

    private var statusText: Text {
        if let status = mainViewModel.serverStatus {
            if status.isOnline {
                let formattedPlayers = NumberFormatter.localizedString(
                    from: NSNumber(value: status.players),
                    number: .decimal
                )
                return Text(NSLocalizedString("Server_Status_Online", comment: ""))
                    .font(.caption.bold())
                    .foregroundColor(.green)
                    + Text(
                        String(
                            format: NSLocalizedString("Server_Status_Players", comment: ""),
                            formattedPlayers
                        )
                    )
                    .font(.caption)
            } else {
                return Text(NSLocalizedString("Server_Status_Offline", comment: ""))
                    .font(.caption.bold())
                    .foregroundColor(.red)
            }
        } else {
            return Text(NSLocalizedString("Server_Status_Checking", comment: ""))
                .font(.caption)
        }
    }
}

/// 冷却期间在首页显示的提示（使用 TimelineView 原生倒计时，与 CloneCountdownView 等保持一致）
struct RateLimitCooldownView: View {
    var body: some View {
        if let date = RateLimitAlertManager.cooldownEndDate {
            TimelineView(.periodic(from: Date(), by: 1.0)) { timeline in
                let now = timeline.date
                let remainingTime = date.timeIntervalSince(now)

                if remainingTime > 0 {
                    Text(
                        String(
                            format: NSLocalizedString("RateLimit_Cooldown_Home_Message", comment: ""),
                            formattedRemainingTime(remainingTime)
                        )
                    )
                    .font(.caption)
                    .foregroundColor(.orange)
                }
            }
        }
    }

    private func formattedRemainingTime(_ remainingTime: TimeInterval) -> String {
        let seconds = Int(ceil(remainingTime))
        let m = seconds / 60
        let s = seconds % 60
        if m > 0 {
            return String(format: NSLocalizedString("RateLimit_Cooldown_Time_MinSec", comment: ""), m, s)
        } else {
            return String(format: NSLocalizedString("RateLimit_Cooldown_Time_Sec", comment: ""), s)
        }
    }
}
