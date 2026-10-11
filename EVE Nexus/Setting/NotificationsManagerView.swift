import SwiftUI
import UserNotifications

/// 统一通知管理视图
/// 显示应用所有类别的待发送通知（EVE 事件、技能队列到期等），支持单条取消
/// 通过设置页 NavigationLink push 进入，标题显示在导航栏中
struct NotificationsManagerView: View {
    @Environment(\.locale) private var displayLocale
    @Environment(\.timeZone) private var displayTimeZone
    @StateObject private var notificationManager = NotificationManager.shared

    /// 按类别分组后的通知
    @State private var groupedNotifications: [NotificationManager.NotificationCategory: [UNNotificationRequest]] = [:]
    @State private var isLoading = true
    /// 技能队列通知开关（与 NotificationManager 共享 UserDefaults key）
    @AppStorage("SkillQueueNotificationEnabled") private var isSkillQueueEnabled = true
    @State private var showSkillQueueInfo = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView(NSLocalizedString("Calendar_Loading", comment: "Loading"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 始终显示 List：技能队列 Section（含 Toggle）始终可见，
                // 其他类别仅在有通知时显示
                notificationListView
            }
        }
        .navigationTitle(NSLocalizedString("Notifications_Title", comment: "Notifications"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadNotifications()
        }
        .sheet(isPresented: $showSkillQueueInfo) {
            skillQueueInfoSheet
        }
    }

    // MARK: - 子视图

    private var skillQueueInfoSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(NSLocalizedString("Notifications_SkillQueue_Info_Title", comment: ""))
                    .font(.headline)
                Spacer()
                Button {
                    showSkillQueueInfo = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            Text(NSLocalizedString("Notifications_SkillQueue_Info_Body", comment: ""))
                .font(.body)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding()
        .presentationDetents([.height(280)])
    }

    private var notificationListView: some View {
        List {
            ForEach(NotificationManager.NotificationCategory.allCases, id: \.rawValue) { category in
                let notifications = groupedNotifications[category] ?? []
                // 技能队列 Section 始终显示（Toggle 始终可用），其他类别仅在有通知时显示
                if category == .skillQueue || !notifications.isEmpty {
                    categorySection(category: category, notifications: notifications)
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
    }

    /// 单个类别的 Section：展示该类别下所有通知
    private func categorySection(
        category: NotificationManager.NotificationCategory,
        notifications: [UNNotificationRequest]
    ) -> some View {
        let sorted = sortedByTriggerTime(notifications)
        return Section {
            // 技能队列 Section 第一行：启用开关
            if category == .skillQueue {
                Toggle(
                    NSLocalizedString("Notifications_SkillQueue_Enable", comment: "Enable skill queue notifications"),
                    isOn: $isSkillQueueEnabled
                )
                .onChange(of: isSkillQueueEnabled) { _, newValue in
                    Task {
                        if newValue {
                            await notificationManager.rescheduleAllSkillQueueNotificationsFromCache()
                        } else {
                            await notificationManager.cancelAllNotifications(category: .skillQueue)
                        }
                        // 仅刷新技能队列 Section，不触发全屏 isLoading
                        let pending = await notificationManager.getPendingNotifications(category: .skillQueue)
                        await MainActor.run {
                            withAnimation {
                                groupedNotifications[.skillQueue] = pending.isEmpty ? nil : pending
                            }
                        }
                    }
                }
            }

            ForEach(sorted, id: \.identifier) { notification in
                NotificationRow(notification: notification, category: category) {
                    cancelNotification(notification)
                }
            }
        } header: {
            HStack(spacing: 8) {
                Image(category.themedIconName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                Text(category.displayName)
                    .fontWeight(.semibold)
                    .font(.system(size: 16))
                Spacer()
                if category == .skillQueue {
                    Button {
                        showSkillQueueInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Text("\(notifications.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
            }
            .textCase(nil)
        } footer: {
            // 技能队列：提示文本
            if category == .skillQueue {
                Text(NSLocalizedString("Notifications_SkillQueue_Footer_Hint", comment: "Skill queue footer hint"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - 数据加载与处理

    /// 加载所有支持类别的待发送通知
    private func loadNotifications() async {
        isLoading = true
        let grouped = await notificationManager.getPendingNotificationsGroupedByCategory()
        await MainActor.run {
            // 仅保留有通知的类别，避免空字典导致 isEmpty 误判
            groupedNotifications = grouped.filter { _, value in !value.isEmpty }
            isLoading = false
        }
    }

    /// 取消单条通知
    private func cancelNotification(_ notification: UNNotificationRequest) {
        notificationManager.cancelNotification(notification)

        // 从对应类别中移除
        for (category, list) in groupedNotifications {
            if list.contains(where: { $0.identifier == notification.identifier }) {
                var newList = list
                newList.removeAll { $0.identifier == notification.identifier }
                groupedNotifications[category] = newList.isEmpty ? nil : newList
                break
            }
        }
    }

    /// 按触发时间升序排序
    private func sortedByTriggerTime(_ notifications: [UNNotificationRequest]) -> [UNNotificationRequest] {
        notifications.sorted { lhs, rhs in
            guard let l = lhs.trigger as? UNCalendarNotificationTrigger,
                  let r = rhs.trigger as? UNCalendarNotificationTrigger,
                  let ld = l.nextTriggerDate(),
                  let rd = r.nextTriggerDate()
            else { return false }
            return ld < rd
        }
    }
}

/// 统一通知行视图：根据类别自适应渲染（EVE 事件 / 技能队列等）
/// 同时供 ScheduledNotificationsView（日历 sheet）和 NotificationsManagerView（设置 push）使用
struct NotificationRow: View {
    @Environment(\.locale) private var displayLocale
    @Environment(\.timeZone) private var displayTimeZone
    let notification: UNNotificationRequest
    let category: NotificationManager.NotificationCategory
    let onCancel: () -> Void

    private var triggerTime: Date? {
        guard let trigger = notification.trigger as? UNCalendarNotificationTrigger else {
            return nil
        }
        return trigger.nextTriggerDate()
    }

    /// EVE 事件通知的"事件时间"（区别于触发时间）
    private var eventTime: Date? {
        guard let interval = notification.content.userInfo["eventTime"] as? TimeInterval else {
            return nil
        }
        return Date(timeIntervalSince1970: interval)
    }

    /// 技能队列通知的"完成时间"
    private var skillQueueFinishDate: Date? {
        guard let interval = notification.content.userInfo["finishDate"] as? TimeInterval else {
            return nil
        }
        return Date(timeIntervalSince1970: interval)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 第一行：核心时间信息（最突出）
            switch category {
            case .eveEvent:
                if let eventTime = eventTime {
                    timeRow(
                        icon: "calendar",
                        color: .green,
                        text: formatDateTime(eventTime)
                    )
                }
            case .skillQueue:
                if let finishDate = skillQueueFinishDate {
                    timeRow(
                        icon: "clock",
                        color: .purple,
                        text: formatDateTime(finishDate)
                    )
                }
            }

            // 第二行：通知标题
            Text(notification.content.title)
                .font(.headline)
                .lineLimit(1)

            // 第三行及以后：其他信息
            if category == .eveEvent, let eventTime = eventTime, let triggerTime = triggerTime {
                let diff = eventTime.timeIntervalSince(triggerTime)
                Text(getNotificationStrategy(timeDifference: diff))
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            if !notification.content.body.isEmpty {
                Text(notification.content.body)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(NSLocalizedString("Calendar_Cancel_Notification", comment: "Cancel")) {
                onCancel()
            }
            .tint(.red)
        }
        .contextMenu {
            Button(
                NSLocalizedString("Calendar_Cancel_Notification", comment: "Cancel"),
                role: .destructive
            ) {
                onCancel()
            }
        }
    }

    // MARK: - 子视图与辅助

    /// 突出的时间行：图标 + 时间值（无 label 前缀，用主色调和加粗体现重要性）
    private func timeRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.subheadline.weight(.medium))
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundColor(color)
        }
    }

    private func formatDate(_ date: Date, dateStyle: DateFormatter.Style) -> String {
        return FormatUtil.formatDate(date, dateStyle: dateStyle, timeStyle: .short)
    }

    private func formatDateTime(_ date: Date) -> String {
        formatDate(date, dateStyle: .medium)
    }

    private func getNotificationStrategy(timeDifference: TimeInterval) -> String {
        // 按时间降序匹配，提升可读性
        let twoHours: TimeInterval = 7200
        let oneHour: TimeInterval = 3600
        let thirtyMinutes: TimeInterval = 1800
        let fifteenMinutes: TimeInterval = 900

        if abs(timeDifference - twoHours) < 60 {
            return NSLocalizedString("Calendar_Strategy_Two_Hours_Before", comment: "2 hours before")
        } else if abs(timeDifference - oneHour) < 60 {
            return NSLocalizedString("Calendar_Strategy_One_Hour_Before", comment: "1 hour before")
        } else if abs(timeDifference - thirtyMinutes) < 60 {
            return NSLocalizedString(
                "Calendar_Strategy_Thirty_Minutes_Before", comment: "30 minutes before"
            )
        } else if abs(timeDifference - fifteenMinutes) < 60 {
            return NSLocalizedString(
                "Calendar_Strategy_Fifteen_Minutes_Before", comment: "15 minutes before"
            )
        } else if abs(timeDifference) < 60 {
            return NSLocalizedString("Calendar_Strategy_At_Event_Time", comment: "At event time")
        } else {
            let minutes = Int(timeDifference / 60)
            return String(
                format: NSLocalizedString(
                    "Calendar_Strategy_Minutes_Before", comment: "%d minutes before"
                ), minutes
            )
        }
    }
}

/// 通知空状态视图（供 NotificationsManagerView 和 ScheduledNotificationsView 共享）
struct NotificationEmptyStateView: View {
    @Environment(\.locale) private var displayLocale
    @Environment(\.timeZone) private var displayTimeZone
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bell.slash")
                .font(.system(size: 50))
                .foregroundColor(.gray)

            Text(
                NSLocalizedString(
                    "Calendar_No_Scheduled_Notifications",
                    comment: "No Scheduled Notifications"
                )
            )
            .font(.headline)
            .foregroundColor(.primary)

            Text(
                NSLocalizedString(
                    "Calendar_No_Scheduled_Notifications_Description",
                    comment: "You haven't scheduled any event notifications yet"
                )
            )
            .font(.body)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
