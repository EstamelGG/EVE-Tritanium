import XCTest
import UserNotifications
@testable import EVE_Nexus

final class SkillQueueNotificationGroupTests: XCTestCase {
    private func request(_ identifier: String, characterId: Int?, offset: TimeInterval,
                         reminder: String? = nil) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.userInfo = ["finishDate": Date.distantFuture.timeIntervalSince1970]
        if let characterId { content.userInfo["characterId"] = characterId }
        if let reminder { content.userInfo["reminder"] = reminder }
        let date = Date().addingTimeInterval(offset)
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return UNNotificationRequest(identifier: identifier, content: content,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
    }

    func testGroupsByCharacterAndOrdersByActualReminderTime() {
        let later = request("skill_queue_1_due", characterId: 1, offset: 400_000)
        let earlier = request("skill_queue_1_3day", characterId: 1, offset: 100_000)
        let other = request("skill_queue_2_due", characterId: 2, offset: 200_000)
        let groups = SkillQueueNotificationGroup.group([later, other, earlier])
        XCTAssertEqual(groups.map(\.characterId), [1, 2])
        XCTAssertEqual(groups[0].notifications.map(\.identifier), [earlier.identifier, later.identifier])
        XCTAssertEqual(groups[0].finishDate, Date.distantFuture)
    }

    func testLegacyRequestsUseIdentifierForRuleWithoutDisplayingDeliveryTitle() {
        let legacy = request("skill_queue_1_3day", characterId: 1, offset: 100_000)
        XCTAssertEqual(SkillQueueNotificationGroup.reminderLabel(for: legacy),
                       NSLocalizedString("Notifications_Reminder_ThreeDays", comment: ""))
        let due = request("skill_queue_1_due", characterId: 1, offset: 200_000)
        XCTAssertEqual(SkillQueueNotificationGroup.reminderLabel(for: due),
                       NSLocalizedString("Notifications_Reminder_DueDay", comment: ""))
        let explicit = request("custom", characterId: 1, offset: 300_000, reminder: "dueDay")
        XCTAssertEqual(SkillQueueNotificationGroup.reminderLabel(for: explicit),
                       SkillQueueNotificationGroup.reminderLabel(for: due))
    }

    func testMissingCharacterIDsDoNotMergeUnrelatedReminders() {
        let groups = SkillQueueNotificationGroup.group([
            request("unknown_a", characterId: nil, offset: 100_000),
            request("unknown_b", characterId: nil, offset: 200_000),
        ])
        XCTAssertEqual(groups.count, 2)
    }
}
