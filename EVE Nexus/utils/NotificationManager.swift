import Foundation
import UserNotifications

/// 通知时间选项
enum NotificationTime: CaseIterable {
    case twoHours
    case oneHour
    case thirtyMinutes
    case fifteenMinutes
    case atEventTime

    var displayName: String {
        switch self {
        case .twoHours:
            return NSLocalizedString(
                "Calendar_Notification_Two_Hours_Before", comment: "2 hours before"
            )
        case .oneHour:
            return NSLocalizedString(
                "Calendar_Notification_One_Hour_Before", comment: "1 hour before"
            )
        case .thirtyMinutes:
            return NSLocalizedString(
                "Calendar_Notification_Thirty_Minutes_Before", comment: "30 minutes before"
            )
        case .fifteenMinutes:
            return NSLocalizedString(
                "Calendar_Notification_Fifteen_Minutes_Before", comment: "15 minutes before"
            )
        case .atEventTime:
            return NSLocalizedString(
                "Calendar_Notification_At_Event_Time", comment: "At event time"
            )
        }
    }

    var timeInterval: TimeInterval {
        switch self {
        case .twoHours:
            return -7200 // -2小时
        case .oneHour:
            return -3600 // -1小时
        case .thirtyMinutes:
            return -1800 // -30分钟
        case .fifteenMinutes:
            return -900 // -15分钟
        case .atEventTime:
            return 0 // 事件开始时
        }
    }

    var strategyDescription: String {
        switch self {
        case .twoHours:
            return NSLocalizedString(
                "Calendar_Strategy_Two_Hours_Before", comment: "2 hours before"
            )
        case .oneHour:
            return NSLocalizedString("Calendar_Strategy_One_Hour_Before", comment: "1 hour before")
        case .thirtyMinutes:
            return NSLocalizedString(
                "Calendar_Strategy_Thirty_Minutes_Before", comment: "30 minutes before"
            )
        case .fifteenMinutes:
            return NSLocalizedString(
                "Calendar_Strategy_Fifteen_Minutes_Before", comment: "15 minutes before"
            )
        case .atEventTime:
            return NSLocalizedString("Calendar_Strategy_At_Event_Time", comment: "At event time")
        }
    }
}

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private init() {
        updateAuthorizationStatus()
    }

    /// 更新授权状态
    private func updateAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.authorizationStatus = settings.authorizationStatus
            }
        }
    }

    /// 请求通知权限
    func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            await MainActor.run {
                updateAuthorizationStatus()
            }
            return granted
        } catch {
            Logger.error("请求通知权限失败: \(error)")
            return false
        }
    }

    /// 创建EVE事件通知（使用自定义时间）
    func scheduleEventNotificationWithCustomTime(
        eventId: Int,
        title: String,
        eventTime: Date,
        organizer: String,
        organizerType: String,
        duration: Int,
        description: String?,
        notificationTime: NotificationTime
    ) async -> Bool {
        let triggerDate = eventTime.addingTimeInterval(notificationTime.timeInterval)

        return await createNotification(
            eventId: eventId,
            title: title,
            eventTime: eventTime,
            organizer: organizer,
            organizerType: organizerType,
            duration: duration,
            description: description,
            triggerDate: triggerDate,
            strategy: notificationTime.strategyDescription
        )
    }

    /// 通用的通知创建方法
    private func createNotification(
        eventId: Int,
        title: String,
        eventTime: Date,
        organizer: String,
        organizerType: String,
        duration: Int,
        description: String?,
        triggerDate: Date,
        strategy: String
    ) async -> Bool {
        // 检查权限
        guard authorizationStatus == .authorized else {
            let granted = await requestPermission()
            if !granted {
                Logger.error("用户拒绝了通知权限")
                return false
            }
            // 如果获得了权限，继续执行
            return await createNotification(
                eventId: eventId,
                title: title,
                eventTime: eventTime,
                organizer: organizer,
                organizerType: organizerType,
                duration: duration,
                description: description,
                triggerDate: triggerDate,
                strategy: strategy
            )
        }

        // 创建通知内容
        let content = UNMutableNotificationContent()
        content.title =
            NSLocalizedString("Calendar_Reminder_Title_Prefix", comment: "EVE Event: ") + title
        content.sound = .default

        // 格式化事件时间
        let eventTimeString = formatEventDate(eventTime)
        let durationString = formatDuration(duration)

        // 设置通知正文
        let bodyText = """
        \(NSLocalizedString("Calendar_Reminder_Event_Time", comment: "Event Time: "))\(eventTimeString)
        \(NSLocalizedString("Calendar_Reminder_Organizer", comment: "Organizer: "))\(organizer) (\(organizerType))
        \(NSLocalizedString("Calendar_Reminder_Duration", comment: "Duration: "))\(durationString)
        """

        content.body = bodyText

        // 设置用户信息，用于后续处理
        content.userInfo = [
            "eventId": eventId,
            "eventTime": eventTime.timeIntervalSince1970,
            "type": "eveEvent",
        ]

        // 检查是否还需要设置通知
        guard triggerDate > Date() else {
            Logger.info("事件时间已过或过于接近，无法设置通知")
            return false
        }

        // 创建触发器
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute], from: triggerDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)

        // 创建通知请求
        let identifier = "eve_event_\(eventId)_\(Int(eventTime.timeIntervalSince1970))"
        let request = UNNotificationRequest(
            identifier: identifier, content: content, trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            Logger.success("成功创建EVE事件通知 - 事件ID: \(eventId), 通知时间: \(triggerDate), 策略: \(strategy)")
            return true
        } catch {
            Logger.error("创建通知失败: \(error)")
            return false
        }
    }

    /// 获取所有待发送的通知
    func getPendingNotifications() async -> [UNNotificationRequest] {
        return await UNUserNotificationCenter.current().pendingNotificationRequests()
    }

    // MARK: - 统一通知管理

    /// 通知类别：用于按类别查询、过滤和取消通知
    /// 与通知 userInfo 中的 "type" 字段一一对应
    enum NotificationCategory: String, CaseIterable {
        case eveEvent
        case skillQueue

        /// 显示名（用于设置和通知中心 UI）
        var displayName: String {
            switch self {
            case .eveEvent:
                return NSLocalizedString("Notifications_Category_EVEEvent", comment: "")
            case .skillQueue:
                return NSLocalizedString("Notifications_Category_SkillQueue", comment: "")
            }
        }

        /// EVE 主题自定义图标名（用于 Section header 等大尺寸场景）
        var themedIconName: String {
            switch self {
            case .eveEvent:
                return "calendar"
            case .skillQueue:
                return "skills"
            }
        }
    }

    /// 按类别获取待发送通知
    func getPendingNotifications(category: NotificationCategory) async -> [UNNotificationRequest] {
        let all = await getPendingNotifications()
        return all.filter { request in
            if let type = request.content.userInfo["type"] as? String {
                return type == category.rawValue
            }
            return false
        }
    }

    /// 获取所有支持类别的待发送通知，按类别分组返回
    func getPendingNotificationsGroupedByCategory() async -> [NotificationCategory: [UNNotificationRequest]] {
        let all = await getPendingNotifications()
        var grouped: [NotificationCategory: [UNNotificationRequest]] = [:]
        for category in NotificationCategory.allCases {
            grouped[category] = all.filter { request in
                (request.content.userInfo["type"] as? String) == category.rawValue
            }
        }
        return grouped
    }

    /// 取消指定类别的所有通知
    func cancelAllNotifications(category: NotificationCategory) async {
        let pending = await getPendingNotifications(category: category)
        let identifiers = pending.map(\.identifier)
        guard !identifiers.isEmpty else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        Logger.info("已取消 \(identifiers.count) 条 \(category.rawValue) 类通知")
    }

    /// 取消单条待发送通知
    func cancelNotification(_ notification: UNNotificationRequest) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [notification.identifier]
        )
        Logger.info("已取消通知: \(notification.identifier)")
    }

    // MARK: - 技能队列到期提醒

    /// UserDefaults key：技能队列通知开关
    private static let skillQueueNotificationEnabledKey = "SkillQueueNotificationEnabled"

    /// 技能队列通知是否启用（默认 true）
    var isSkillQueueNotificationEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.skillQueueNotificationEnabledKey) as? Bool ?? true
    }

    /// 从缓存重新安排所有角色的技能队列通知（开启开关或手动刷新时调用）
    /// 缓存命中直接使用，缓存未命中则回退到网络获取；并行处理多角色
    func rescheduleAllSkillQueueNotificationsFromCache() async {
        let characters = EVELogin.shared.loadCharacters()
        Logger.info("从缓存重新安排技能队列通知，共 \(characters.count) 个角色")

        await withTaskGroup(of: Void.self) { group in
            for auth in characters {
                let characterId = auth.character.CharacterID
                let characterName = auth.character.CharacterName
                group.addTask {
                    // scheduleReminder: false 避免内部重复调度，由下方统一调度
                    guard let queue = try? await CharacterSkillsAPI.shared.fetchSkillQueue(
                        characterId: characterId, forceRefresh: false, scheduleReminder: false
                    ) else {
                        return
                    }
                    await self.scheduleSkillQueueNotifications(
                        characterId: characterId, characterName: characterName, queue: queue
                    )
                }
            }
        }
    }

    /// 技能队列通知标识符前缀
    private static let skillQueueIdentifierPrefix = "skill_queue_"
    private static let skillQueue3DaySuffix = "_3day"
    private static let skillQueueDueSuffix = "_due"

    private func skillQueue3DayIdentifier(characterId: Int) -> String {
        "\(Self.skillQueueIdentifierPrefix)\(characterId)\(Self.skillQueue3DaySuffix)"
    }

    private func skillQueueDueIdentifier(characterId: Int) -> String {
        "\(Self.skillQueueIdentifierPrefix)\(characterId)\(Self.skillQueueDueSuffix)"
    }

    /// 为技能队列安排到期提醒：到期前3天和到期当天分别发送一条通知
    /// - 每次调用会先取消该角色的旧通知，再根据最新队列重新安排
    func scheduleSkillQueueNotifications(
        characterId: Int,
        characterName: String,
        queue: [SkillQueueItem]
    ) async {
        // 开关关闭时不安排新通知
        guard isSkillQueueNotificationEnabled else {
            Logger.debug("技能队列通知已关闭，跳过安排 - 角色ID: \(characterId)")
            return
        }

        let identifiers = [
            skillQueue3DayIdentifier(characterId: characterId),
            skillQueueDueIdentifier(characterId: characterId),
        ]
        // 1. 取消该角色旧的技能队列通知，避免重复
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: identifiers
        )

        // 2. 找出队列最后一项的完成时间（即整个队列的完成时间）
        guard let finishDate = queue.compactMap(\.finish_date).max() else {
            Logger.debug("技能队列为空或无完成时间，跳过通知安排 - 角色ID: \(characterId)")
            return
        }

        // 3. 队列已完成则不安排
        let now = Date()
        guard finishDate > now else {
            Logger.debug("技能队列已完成，跳过通知安排 - 角色ID: \(characterId)")
            return
        }

        // 4. 检查权限
        if authorizationStatus != .authorized {
            let granted = await requestPermission()
            if !granted {
                Logger.error("用户拒绝了通知权限，无法安排技能队列提醒")
                return
            }
        }

        // 5. 安排到期前3天通知（finish_date - 3天，相同时刻）
        let threeDayBefore = finishDate.addingTimeInterval(-3 * 24 * 60 * 60)
        if threeDayBefore > now {
            await scheduleSkillQueueNotification(
                identifier: identifiers[0],
                characterId: characterId,
                characterName: characterName,
                finishDate: finishDate,
                triggerDate: threeDayBefore,
                isDueDay: false
            )
        } else {
            Logger.debug("3天前时间已过，跳过3天前通知 - 角色ID: \(characterId)")
        }

        // 6. 安排到期当天通知（到期日 9:00；若9:00已过或晚于完成时刻则用完成时刻本身）
        let calendar = Calendar.current
        var dueDayComponents = calendar.dateComponents([.year, .month, .day], from: finishDate)
        dueDayComponents.hour = 9
        dueDayComponents.minute = 0
        var dueDayTrigger = calendar.date(from: dueDayComponents) ?? finishDate
        if dueDayTrigger < now || dueDayTrigger > finishDate {
            dueDayTrigger = finishDate
        }
        if dueDayTrigger > now {
            await scheduleSkillQueueNotification(
                identifier: identifiers[1],
                characterId: characterId,
                characterName: characterName,
                finishDate: finishDate,
                triggerDate: dueDayTrigger,
                isDueDay: true
            )
        }
    }

    /// 取消指定角色的所有技能队列通知（在角色被移除时调用）
    func cancelSkillQueueNotifications(characterId: Int) {
        let identifiers = [
            skillQueue3DayIdentifier(characterId: characterId),
            skillQueueDueIdentifier(characterId: characterId),
        ]
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: identifiers
        )
        Logger.info("已取消角色 \(characterId) 的技能队列通知")
    }

    private func scheduleSkillQueueNotification(
        identifier: String,
        characterId: Int,
        characterName: String,
        finishDate: Date,
        triggerDate: Date,
        isDueDay: Bool
    ) async {
        let content = UNMutableNotificationContent()
        content.sound = .default

        let finishDateString = formatSkillQueueDate(finishDate)

        if isDueDay {
            content.title = NSLocalizedString("SkillQueue_Due_Title", comment: "")
            content.body = String(
                format: NSLocalizedString("SkillQueue_Due_Body", comment: ""),
                characterName, finishDateString
            )
        } else {
            content.title = NSLocalizedString("SkillQueue_3Day_Title", comment: "")
            content.body = String(
                format: NSLocalizedString("SkillQueue_3Day_Body", comment: ""),
                characterName, finishDateString
            )
        }

        content.userInfo = [
            "type": "skillQueue",
            "characterId": characterId,
            "finishDate": finishDate.timeIntervalSince1970,
        ]

        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute], from: triggerDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier, content: content, trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            Logger.success(
                "已安排技能队列通知 - 角色ID: \(characterId), 触发时间: \(triggerDate), 当天到期: \(isDueDay)"
            )
        } catch {
            Logger.error("安排技能队列通知失败: \(error)")
        }
    }

    private func formatSkillQueueDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = FormatUtil.appLocale
        return formatter.string(from: date)
    }

    /// 格式化事件时间
    private func formatEventDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        formatter.locale = FormatUtil.appLocale
        return formatter.string(from: date)
    }

    /// 格式化持续时间
    private func formatDuration(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) " + NSLocalizedString("Calendar_Minutes", comment: "minutes")
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return "\(hours) " + NSLocalizedString("Calendar_Hours", comment: "hours")
            } else {
                return "\(hours) " + NSLocalizedString("Calendar_Hours", comment: "hours")
                    + " \(remainingMinutes) "
                    + NSLocalizedString("Calendar_Minutes", comment: "minutes")
            }
        }
    }
}
