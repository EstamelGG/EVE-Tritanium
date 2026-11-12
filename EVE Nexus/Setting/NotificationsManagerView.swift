import SwiftUI
import UserNotifications

/// 通知偏好与实际待发送提醒分开呈现，技能队列按角色合并。
struct NotificationsManagerView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.timeZone) private var displayTimeZone
    @StateObject private var notificationManager = NotificationManager.shared
    @State private var groupedNotifications: [NotificationManager.NotificationCategory: [UNNotificationRequest]] = [:]
    @State private var isLoading = true
    @State private var isUpdating = false
    @AppStorage("SkillQueueNotificationEnabled") private var isSkillQueueEnabled = true

    private var skillQueueGroups: [SkillQueueNotificationGroup] {
        SkillQueueNotificationGroup.group(groupedNotifications[.skillQueue] ?? [])
    }

    private var authorizationLabel: String {
        switch notificationManager.authorizationStatus {
        case .authorized: return NSLocalizedString("Notifications_Permission_Allowed", comment: "")
        case .provisional, .ephemeral: return NSLocalizedString("Notifications_Permission_Quiet", comment: "")
        case .denied: return NSLocalizedString("Notifications_Permission_Denied", comment: "")
        default: return NSLocalizedString("Notifications_Permission_NotRequested", comment: "")
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView(NSLocalizedString("Calendar_Loading", comment: ""))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                notificationListView
            }
        }
        .navigationTitle(NSLocalizedString("Notifications_Settings_Title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await loadNotifications()
        }
    }

    private var notificationListView: some View {
        List {
            Section {
                Button {
                    if notificationManager.authorizationStatus == .notDetermined {
                        Task {
                            _ = await notificationManager.requestPermission()
                            if isSkillQueueEnabled {
                                await updateSkillQueueNotifications()
                            }
                        }
                    } else if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    HStack {
                        Text(NSLocalizedString("Notifications_System", comment: ""))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(authorizationLabel).foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(isUpdating)
            } footer: {
                if notificationManager.authorizationStatus == .denied {
                    Text(NSLocalizedString("Notifications_Permission_Hint", comment: ""))
                }
            }

            Section {
                Toggle(NSLocalizedString("Notifications_SkillQueue_Toggle", comment: ""), isOn: $isSkillQueueEnabled)
                    .disabled(isUpdating)
                    .onChange(of: isSkillQueueEnabled) { _, _ in
                        Task { await updateSkillQueueNotifications() }
                    }
                if isUpdating {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }

            if isSkillQueueEnabled {
                if skillQueueGroups.isEmpty {
                    Section {
                        Text(NSLocalizedString("Notifications_SkillQueue_Empty", comment: ""))
                            .foregroundStyle(.secondary)
                    } header: { pendingHeader } footer: { skillQueueFooter }
                } else {
                    ForEach(Array(skillQueueGroups.enumerated()), id: \.element.id) { index, group in
                        Section {
                            skillQueueCard(group)
                        } header: {
                            if index == 0 {
                                pendingHeader
                            }
                        } footer: {
                            if index == skillQueueGroups.count - 1 {
                                skillQueueFooter
                            }
                        }
                    }
                }
            } else {
                Section {
                    Text(NSLocalizedString("Notifications_SkillQueue_Disabled", comment: ""))
                        .foregroundStyle(.secondary)
                } footer: { skillQueueFooter }
            }

            let events = sortedByTriggerTime(groupedNotifications[.eveEvent] ?? [])
            if !events.isEmpty {
                Section(NotificationManager.NotificationCategory.eveEvent.displayName) {
                    ForEach(events, id: \.identifier) { notification in
                        NotificationRow(notification: notification, category: .eveEvent) {
                            cancelNotification(notification)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await loadNotifications() }
    }

    private var skillQueueFooter: some View {
        Text(NSLocalizedString("Notifications_SkillQueue_Footer_Hint", comment: ""))
    }

    private var pendingHeader: some View {
        HStack {
            Text(NSLocalizedString("Notifications_Pending", comment: ""))
            Spacer()
            Text(UserDefaults.standard.string(forKey: "selectedTimeZone") == "utc"
                ? "UTC" : NSLocalizedString("Notifications_LocalTime", comment: ""))
                .font(.caption2)
        }
        .textCase(nil)
    }

    private func skillQueueCard(_ group: SkillQueueNotificationGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image("skills")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                Text(characterName(for: group)).font(.headline)
            }
            if let finishDate = group.finishDate {
                Text(String(format: NSLocalizedString("Notifications_ExpectedFinish", comment: ""),
                            FormatUtil.formatDate(finishDate, timeZone: displayTimeZone)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(group.notifications, id: \.identifier) { notification in
                Divider()
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(SkillQueueNotificationGroup.reminderLabel(for: notification))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if let date = notification.scheduledTriggerDate {
                        Text(FormatUtil.formatDate(date, timeZone: displayTimeZone))
                            .multilineTextAlignment(.trailing)
                    }
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .contextMenu {
                    Button(NSLocalizedString("Calendar_Cancel_Notification", comment: ""), role: .destructive) {
                        cancelNotification(notification)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func characterName(for group: SkillQueueNotificationGroup) -> String {
        if let characterId = group.characterId,
           let auth = EVELogin.shared.loadCharacters().first(where: { $0.character.CharacterID == characterId })
        {
            return auth.character.CharacterName
        }
        if let name = group.notifications.first?.content.userInfo["characterName"] as? String {
            return name
        }
        return group.characterId.map(String.init) ?? NSLocalizedString("Notifications_UnknownCharacter", comment: "")
    }

    @MainActor
    private func updateSkillQueueNotifications() async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        if isSkillQueueEnabled {
            await notificationManager.rescheduleAllSkillQueueNotificationsFromCache()
        } else {
            await notificationManager.cancelAllNotifications(category: .skillQueue)
        }
        await loadNotifications()
    }

    @MainActor
    private func loadNotifications() async {
        await notificationManager.refreshAuthorizationStatus()
        groupedNotifications = await notificationManager.getPendingNotificationsGroupedByCategory()
        isLoading = false
    }

    private func cancelNotification(_ notification: UNNotificationRequest) {
        notificationManager.cancelNotification(notification)
        for (category, list) in groupedNotifications {
            groupedNotifications[category] = list.filter { $0.identifier != notification.identifier }
        }
    }

    private func sortedByTriggerTime(_ notifications: [UNNotificationRequest]) -> [UNNotificationRequest] {
        notifications.sorted {
            ($0.scheduledTriggerDate ?? .distantFuture) < ($1.scheduledTriggerDate ?? .distantFuture)
        }
    }
}

private extension UNNotificationRequest {
    var scheduledTriggerDate: Date? {
        if let trigger = trigger as? UNCalendarNotificationTrigger {
            return trigger.nextTriggerDate()
        }
        if let trigger = trigger as? UNTimeIntervalNotificationTrigger {
            return trigger.nextTriggerDate()
        }
        return nil
    }
}

/// 用稳定的角色 ID 合并提醒，兼容未保存角色名及规则字段的旧通知。
struct SkillQueueNotificationGroup: Identifiable {
    let id: String
    let characterId: Int?
    let notifications: [UNNotificationRequest]

    var finishDate: Date? {
        notifications.compactMap { $0.content.userInfo["finishDate"] as? TimeInterval }
            .max().map { Date(timeIntervalSince1970: $0) }
    }

    static func group(_ notifications: [UNNotificationRequest]) -> [Self] {
        Dictionary(grouping: notifications) { request in
            (request.content.userInfo["characterId"] as? Int).map(String.init) ?? request.identifier
        }.map { id, requests in
            Self(id: id, characterId: requests.first?.content.userInfo["characterId"] as? Int,
                 notifications: requests.sorted {
                     ($0.scheduledTriggerDate ?? .distantFuture) < ($1.scheduledTriggerDate ?? .distantFuture)
                 })
        }.sorted {
            let lhs = $0.notifications.first?.scheduledTriggerDate ?? .distantFuture
            let rhs = $1.notifications.first?.scheduledTriggerDate ?? .distantFuture
            return lhs == rhs ? $0.id < $1.id : lhs < rhs
        }
    }

    static func reminderLabel(for request: UNNotificationRequest) -> String {
        let reminder = request.content.userInfo["reminder"] as? String
        if reminder == "threeDaysBefore" || (reminder == nil && request.identifier.hasSuffix("_3day")) {
            return NSLocalizedString("Notifications_Reminder_ThreeDays", comment: "")
        }
        if reminder == "dueDay" || (reminder == nil && request.identifier.hasSuffix("_due")) {
            return NSLocalizedString("Notifications_Reminder_DueDay", comment: "")
        }
        return NSLocalizedString("Notifications_Reminder", comment: "")
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
