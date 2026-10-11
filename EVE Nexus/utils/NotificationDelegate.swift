import Foundation
import UserNotifications

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    override private init() {
        super.init()
    }

    /// 当应用在前台时收到通知的处理
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
        @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Logger.info("收到前台通知: \(notification.request.identifier)")

        // 在前台也显示通知横幅、声音和角标
        completionHandler([.banner, .sound, .badge])
    }

    /// 用户点击通知时的处理
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Logger.info("用户点击了通知: \(response.notification.request.identifier)")

        let notification = response.notification
        let userInfo = notification.request.content.userInfo

        // 检查是否是EVE事件通知
        if let type = userInfo["type"] as? String, type == "eveEvent" {
            Logger.info("处理EVE事件通知点击")

            // 这里可以添加导航到相关页面的逻辑
            // 例如：导航到日历页面或事件详情页面

            // 发送通知让应用知道用户点击了EVE事件通知
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("EVEEventNotificationTapped"),
                    object: nil,
                    userInfo: userInfo
                )
            }
        }

        completionHandler()
    }

    /// 通知投递失败时的处理
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        openSettingsFor _: UNNotification?
    ) {
        Logger.info("用户打开了通知设置")

        // 这里可以引导用户到应用的通知设置页面
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("OpenNotificationSettings"),
                object: nil
            )
        }
    }
}
