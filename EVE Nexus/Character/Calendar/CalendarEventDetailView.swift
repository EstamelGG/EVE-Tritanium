import SwiftUI

struct CalendarEventDetailView: View {
    @Environment(\.locale) private var displayLocale
    @Environment(\.timeZone) private var displayTimeZone
    let characterId: Int
    let eventId: Int
    let databaseManager: DatabaseManager

    @StateObject private var viewModel = CalendarEventDetailViewModel()
    @StateObject private var notificationManager = NotificationManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingReminderAlert = false
    @State private var reminderSuccess = false
    @State private var showingNotificationTimePicker = false
    @State private var selectedNotificationTime: NotificationTime = .oneHour

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if viewModel.isLoading {
                    ProgressView(NSLocalizedString("Calendar_Loading", comment: "Loading"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                } else if let eventDetail = viewModel.eventDetail {
                    List {
                        // 基本信息部分
                        Section(
                            NSLocalizedString("Calendar_Event_Basic_Info", comment: "Basic Info")
                        ) {
                            HStack {
                                Text(NSLocalizedString("Calendar_Event_Date", comment: "Date"))
                                Spacer()
                                Text(formatEventDate(eventDetail.eventDate))
                                    .foregroundColor(.secondary)
                            }

                            HStack {
                                Text(
                                    NSLocalizedString(
                                        "Calendar_Event_Duration", comment: "Duration"
                                    )
                                )
                                Spacer()
                                Text(formatDuration(eventDetail.durationInMinutes))
                                    .foregroundColor(.secondary)
                            }

                            HStack {
                                Text(
                                    NSLocalizedString(
                                        "Calendar_Event_Response", comment: "Response"
                                    )
                                )
                                Spacer()
                                Text(formatResponse(eventDetail.response))
                                    .foregroundColor(.secondary)
                            }
                        }

                        // 组织者信息部分
                        Section(NSLocalizedString("Calendar_Event_Organizer", comment: "Organizer")) {
                            HStack(spacing: 12) {
                                UniversePortrait(
                                    id: eventDetail.owner_id,
                                    type: eventDetail.ownerType,
                                    size: 64,
                                    displaySize: 40,
                                    cornerRadius: 6
                                )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(eventDetail.owner_name)
                                        .font(.subheadline)
                                        .fontWeight(.medium)

                                    Text(formatOwnerType(eventDetail.owner_type))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }

                        // 事件描述部分 - 使用RichTextView处理HTML内容
                        if !eventDetail.text.isEmpty {
                            Section(
                                NSLocalizedString(
                                    "Calendar_Event_Description", comment: "Description"
                                )
                            ) {
                                RichTextView(
                                    text: eventDetail.text, databaseManager: databaseManager
                                )
                                .font(.body)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        // 添加提醒按钮
                        Button(action: {
                            showingNotificationTimePicker = true
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.white)
                                Text(
                                    NSLocalizedString(
                                        "Calendar_Add_Notification", comment: "Add Notification"
                                    )
                                )
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.blue)
                            .cornerRadius(10)
                        }
                        .disabled(viewModel.isLoading)
                        .buttonStyle(PlainButtonStyle())
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(InsetGroupedListStyle())
                } else if viewModel.showError {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)

                        Text(NSLocalizedString("Calendar_Error", comment: "Error"))
                            .font(.headline)

                        Text(viewModel.errorMessage)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button(NSLocalizedString("Calendar_Retry", comment: "Retry")) {
                            Task {
                                await viewModel.loadEventDetail(
                                    characterId: characterId, eventId: eventId
                                )
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(
                viewModel.eventDetail?.title
                    ?? NSLocalizedString("Calendar_Event_Detail", comment: "Event Detail")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Common_Done", comment: "Done")) {
                        dismiss()
                    }
                }
            }
            .alert(
                NSLocalizedString("Calendar_Notification_Alert_Title", comment: "Notification"),
                isPresented: $showingReminderAlert
            ) {
                Button(NSLocalizedString("Calendar_OK", comment: "OK")) {}
            } message: {
                Text(
                    reminderSuccess
                        ? NSLocalizedString(
                            "Calendar_Notification_Success",
                            comment: "Notification scheduled successfully"
                        )
                        : NSLocalizedString(
                            "Calendar_Notification_Failed",
                            comment: "Failed to schedule notification, please check permissions"
                        )
                )
            }
            .sheet(isPresented: $showingNotificationTimePicker) {
                NotificationTimePickerView(
                    eventTime: viewModel.eventDetail?.eventDate ?? Date(),
                    onTimeSelected: { notificationTime in
                        selectedNotificationTime = notificationTime
                        showingNotificationTimePicker = false
                        Task {
                            await addNotification(with: notificationTime)
                        }
                    }
                )
            }
        }
        .task {
            await viewModel.loadEventDetail(characterId: characterId, eventId: eventId)
        }
    }

    /// 添加通知的方法
    private func addNotification(with notificationTime: NotificationTime) async {
        guard let eventDetail = viewModel.eventDetail else { return }
        guard let eventDate = eventDetail.eventDate else {
            await MainActor.run {
                reminderSuccess = false
                showingReminderAlert = true
            }
            return
        }

        let success = await notificationManager.scheduleEventNotificationWithCustomTime(
            eventId: eventDetail.event_id,
            title: eventDetail.title,
            eventTime: eventDate,
            organizer: eventDetail.owner_name,
            organizerType: formatOwnerType(eventDetail.owner_type),
            duration: eventDetail.durationInMinutes,
            description: eventDetail.cleanText.isEmpty ? nil : eventDetail.cleanText,
            notificationTime: notificationTime
        )

        await MainActor.run {
            reminderSuccess = success
            showingReminderAlert = true
        }
    }

    private func formatEventDate(_ date: Date?) -> String {
        guard let date = date else {
            return NSLocalizedString("Calendar_Unknown_Time", comment: "Unknown time")
        }

        return FormatUtil.formatDate(date, dateStyle: .full, timeStyle: .short)
    }

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

    private func formatResponse(_ response: String) -> String {
        switch response {
        case "accepted":
            return NSLocalizedString("Calendar_Response_Accepted", comment: "Accepted")
        case "declined":
            return NSLocalizedString("Calendar_Response_Declined", comment: "Declined")
        case "tentative":
            return NSLocalizedString("Calendar_Response_Tentative", comment: "Tentative")
        default:
            return NSLocalizedString("Calendar_Response_Not_Responded", comment: "Not responded")
        }
    }

    private func formatOwnerType(_ ownerType: String) -> String {
        switch ownerType.lowercased() {
        case "character":
            return NSLocalizedString("Calendar_Owner_Character", comment: "Character")
        case "corporation":
            return NSLocalizedString("Calendar_Owner_Corporation", comment: "Corporation")
        case "alliance":
            return NSLocalizedString("Calendar_Owner_Alliance", comment: "Alliance")
        default:
            return ownerType.capitalized
        }
    }
}

@MainActor
class CalendarEventDetailViewModel: ObservableObject {
    @Published var eventDetail: CalendarEventDetail?
    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage = ""

    func loadEventDetail(characterId: Int, eventId: Int) async {
        isLoading = true
        showError = false
        errorMessage = ""

        do {
            let detail = try await CharacterCalendarDetailAPI.shared.fetchEventDetail(
                characterId: characterId,
                eventId: eventId
            )
            eventDetail = detail
        } catch {
            errorMessage = String(
                format: NSLocalizedString(
                    "Calendar_Load_Detail_Failed", comment: "Failed to load event detail"
                ),
                error.localizedDescription
            )
            showError = true
            Logger.error("加载事件详情失败: \(error)")
        }

        isLoading = false
    }
}

struct NotificationTimePickerView: View {
    @Environment(\.locale) private var displayLocale
    @Environment(\.timeZone) private var displayTimeZone
    let eventTime: Date
    let onTimeSelected: (NotificationTime) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTime: NotificationTime = .oneHour

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 事件信息头部
                VStack(spacing: 8) {
                    Text(NSLocalizedString("Calendar_Event_Time", comment: "Event Time"))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(formatEventTime(eventTime))
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                .padding()

                // 时间选项列表
                List {
                    Section(
                        header: Text(
                            NSLocalizedString(
                                "Calendar_Notification_Time_Options",
                                comment: "Notification Time Options"
                            )
                        )
                    ) {
                        ForEach(availableTimeOptions, id: \.self) { timeOption in
                            NotificationTimeRow(
                                timeOption: timeOption,
                                eventTime: eventTime,
                                isSelected: selectedTime == timeOption
                            ) {
                                selectedTime = timeOption
                            }
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
            .navigationTitle(
                NSLocalizedString(
                    "Calendar_Select_Notification_Time", comment: "Select Notification Time"
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("Common_Cancel", comment: "Cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Common_Confirm", comment: "Confirm")) {
                        onTimeSelected(selectedTime)
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    /// 根据事件时间过滤可用的通知选项
    private var availableTimeOptions: [NotificationTime] {
        let now = Date()
        _ = eventTime.timeIntervalSince(now)

        return NotificationTime.allCases.filter { timeOption in
            let triggerTime = eventTime.addingTimeInterval(timeOption.timeInterval)
            return triggerTime > now
        }
    }

    private func formatEventTime(_ date: Date) -> String {
        return FormatUtil.formatDate(date, dateStyle: .full, timeStyle: .short)
    }
}

struct NotificationTimeRow: View {
    @Environment(\.locale) private var displayLocale
    @Environment(\.timeZone) private var displayTimeZone
    let timeOption: NotificationTime
    let eventTime: Date
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(timeOption.displayName)
                    .font(.body)
                    .foregroundColor(.primary)

                Text(notificationTimeDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
            } else {
                Image(systemName: "circle")
                    .foregroundColor(.gray)
                    .font(.title2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }

    private var notificationTimeDescription: String {
        let triggerTime = eventTime.addingTimeInterval(timeOption.timeInterval)
        let triggerTimeText = FormatUtil.formatDate(triggerTime, dateStyle: .none, timeStyle: .short)

        if timeOption == .atEventTime {
            return NSLocalizedString(
                "Calendar_Notification_At_Event_Start", comment: "At event start"
            )
                + " (\(triggerTimeText))"
        } else {
            return NSLocalizedString("Calendar_Notification_At", comment: "At")
                + " \(triggerTimeText)"
        }
    }
}

#Preview {
    CalendarEventDetailView(
        characterId: 2_112_343_155, eventId: 3_101_668, databaseManager: DatabaseManager.shared
    )
}
