import SwiftUI

struct CharacterCalendarView: View {
    @Environment(\.locale) private var displayLocale
    @Environment(\.timeZone) private var displayTimeZone
    @StateObject private var viewModel: CalendarViewModel
    let characterId: Int
    let databaseManager: DatabaseManager

    @State private var showScheduledNotifications = false

    init(characterId: Int, databaseManager: DatabaseManager = DatabaseManager.shared) {
        self.characterId = characterId
        self.databaseManager = databaseManager
        _viewModel = StateObject(wrappedValue: CalendarViewModel(characterId: characterId))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.isLoading {
                    ProgressView(
                        NSLocalizedString("Calendar_Loading", comment: "Loading calendar data")
                    )
                    .progressViewStyle(CircularProgressViewStyle())
                    .padding()
                } else {
                    CalendarGridView(
                        events: viewModel.events,
                        viewModel: viewModel,
                        databaseManager: databaseManager
                    )
                }
            }
            .navigationTitle(NSLocalizedString("Main_Calendar", comment: "Calendar"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showScheduledNotifications = true
                    }) {
                        Image(systemName: "bell.badge")
                            .foregroundColor(.blue)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        viewModel.refreshCalendar()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.blue)
                    }
                }
            }
            .alert(
                NSLocalizedString("Calendar_Error", comment: "Error"),
                isPresented: $viewModel.showError
            ) {
                Button(NSLocalizedString("Calendar_OK", comment: "OK")) {}
            } message: {
                Text(viewModel.errorMessage)
            }
            .sheet(isPresented: $showScheduledNotifications) {
                ScheduledNotificationsView()
            }
        }
    }
}

struct CalendarGridView: View {
    @Environment(\.locale) private var displayLocale
    @Environment(\.timeZone) private var displayTimeZone
    let events: [CalendarEvent]
    let viewModel: CalendarViewModel
    let databaseManager: DatabaseManager

    @State private var selectedDate = Date()
    @State private var currentMonth = Date()

    /// 按日期分组事件
    private var eventsByDate: [String: [CalendarEvent]] {
        var grouped: [String: [CalendarEvent]] = [:]
        for event in events {
            if let date = event.date {
                let dateString = FormatUtil.displayDateKey(date)
                if grouped[dateString] == nil {
                    grouped[dateString] = []
                }
                grouped[dateString]?.append(event)
            }
        }
        return grouped
    }

    var body: some View {
        VStack(spacing: 16) {
            // 月份导航
            MonthNavigationView(
                currentMonth: $currentMonth,
                onMonthChanged: { newMonth in
                    Task {
                        // 当月份变化时，检查是否需要加载更多数据
                        await viewModel.checkDataForMonth(newMonth)
                    }
                }
            )

            // 星期标题
            WeekdayHeaderView()

            // 日历网格
            CalendarDaysGrid(
                currentMonth: currentMonth,
                eventsByDate: eventsByDate,
                selectedDate: $selectedDate,
                onDateSelected: { date in
                    selectedDate = date
                }
            )

            // 选中日期的事件列表
            Divider()
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(selectedDateString)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    if !eventsForSelectedDate.isEmpty {
                        Text(
                            "\(eventsForSelectedDate.count) "
                                + NSLocalizedString("Calendar_Events_Count", comment: "events")
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)

                if !eventsForSelectedDate.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(eventsForSelectedDate) { event in
                                CalendarEventRow(
                                    event: event, characterId: viewModel.characterId,
                                    databaseManager: databaseManager
                                )
                                .padding(.horizontal)
                            }
                        }
                        .padding(.bottom, 16) // 底部添加一些间距
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack {
                        Spacer()
                        Text(
                            NSLocalizedString(
                                "Calendar_No_Events_On_Date", comment: "No events on this date"
                            )
                        )
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
            }
        }
    }

    private var eventsForSelectedDate: [CalendarEvent] {
        let selectedDateString = FormatUtil.displayDateKey(selectedDate)
        return eventsByDate[selectedDateString] ?? []
    }

    private var selectedDateString: String {
        return FormatUtil.formatDate(selectedDate, dateStyle: .long, timeStyle: .none)
    }
}

struct MonthNavigationView: View {
    @Environment(\.locale) private var displayLocale
    @Environment(\.timeZone) private var displayTimeZone
    @Binding var currentMonth: Date
    let onMonthChanged: (Date) -> Void

    var body: some View {
        HStack {
            Button(action: previousMonth) {
                Image(systemName: "chevron.left")
                    .foregroundColor(.blue)
                    .font(.title2)
            }

            Spacer()

            Text(monthYearString)
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            Button(action: nextMonth) {
                Image(systemName: "chevron.right")
                    .foregroundColor(.blue)
                    .font(.title2)
            }
        }
        .padding(.horizontal)
    }

    private var monthYearString: String {
        FormatUtil.formatDate(currentMonth, pattern: "MMMM yyyy")
    }

    private func previousMonth() {
        let newMonth =
            FormatUtil.appCalendar.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
        currentMonth = newMonth
        onMonthChanged(newMonth)
    }

    private func nextMonth() {
        let newMonth =
            FormatUtil.appCalendar.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
        currentMonth = newMonth
        onMonthChanged(newMonth)
    }
}

struct WeekdayHeaderView: View {
    @Environment(\.locale) private var displayLocale
    @Environment(\.timeZone) private var displayTimeZone
    private var weekdays: [String] {
        var calendar = FormatUtil.appCalendar
        calendar.firstWeekday = 2 // 1 = Sunday, 2 = Monday

        // 重新排列星期标题以匹配 firstWeekday 设置
        let symbols = calendar.shortWeekdaySymbols
        let firstWeekdayIndex = calendar.firstWeekday - 1 // firstWeekday 是 1-based

        // 重新排列数组，让周一成为第一天
        return Array(symbols[firstWeekdayIndex...] + symbols[..<firstWeekdayIndex])
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(weekdays, id: \.self) { weekday in
                Text(weekday)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
    }
}

struct CalendarDaysGrid: View {
    @Environment(\.locale) private var displayLocale
    @Environment(\.timeZone) private var displayTimeZone
    let currentMonth: Date
    let eventsByDate: [String: [CalendarEvent]]
    @Binding var selectedDate: Date
    let onDateSelected: (Date) -> Void

    private var calendar: Calendar {
        var cal = FormatUtil.appCalendar
        cal.firstWeekday = 2 // 1 = Sunday, 2 = Monday
        return cal
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
            ForEach(daysInMonth, id: \.self) { date in
                CalendarDayView(
                    date: date,
                    isCurrentMonth: calendar.isDate(
                        date, equalTo: currentMonth, toGranularity: .month
                    ),
                    isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                    isToday: calendar.isDateInToday(date),
                    eventCount: eventCount(for: date),
                    hasImportantEvents: hasImportantEvents(for: date)
                )
                .onTapGesture {
                    selectedDate = date
                    onDateSelected(date)
                }
            }
        }
        .padding(.horizontal)
    }

    private var daysInMonth: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth) else {
            return []
        }

        let monthStart = monthInterval.start
        _ = monthInterval.end

        // 找到本月第一天是星期几（周一为1）
        let weekdayOfFirstDay = calendar.component(.weekday, from: monthStart)

        // 计算需要显示的第一天（可能是上个月的某几天）
        let daysFromPreviousMonth = (weekdayOfFirstDay - calendar.firstWeekday + 7) % 7
        guard
            let calendarStart = calendar.date(
                byAdding: .day, value: -daysFromPreviousMonth, to: monthStart
            )
        else {
            return []
        }

        // 生成日期直到能填满整个日历网格（42天 = 6周 × 7天）
        var dates: [Date] = []
        var currentDate = calendarStart

        for _ in 0 ..< 42 {
            dates.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }

        return dates
    }

    private func eventCount(for date: Date) -> Int {
        let dateString = FormatUtil.displayDateKey(date)
        return eventsByDate[dateString]?.count ?? 0
    }

    private func hasImportantEvents(for date: Date) -> Bool {
        let dateString = FormatUtil.displayDateKey(date)
        return eventsByDate[dateString]?.contains { $0.importance > 0 } ?? false
    }
}

struct CalendarDayView: View {
    @Environment(\.locale) private var displayLocale
    @Environment(\.timeZone) private var displayTimeZone
    let date: Date
    let isCurrentMonth: Bool
    let isSelected: Bool
    let isToday: Bool
    let eventCount: Int
    let hasImportantEvents: Bool

    private var dayNumber: String {
        FormatUtil.formatDate(date, pattern: "d")
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(borderColor, lineWidth: isSelected ? 2 : (isToday ? 1 : 0))
                )

            VStack(spacing: 2) {
                Text(dayNumber)
                    .font(.system(size: 16, weight: isToday ? .bold : .medium))
                    .foregroundColor(textColor)

                if eventCount > 0 {
                    ZStack {
                        Circle()
                            .fill(eventCount > 9 ? .orange : .blue)
                            .frame(width: 16, height: 16)

                        Text(eventCount > 9 ? "9+" : "\(eventCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                } else {
                    Spacer()
                        .frame(height: 16)
                }
            }
        }
        .frame(height: 44)
        .opacity(isCurrentMonth ? 1.0 : 0.3)
    }

    private var backgroundColor: Color {
        if isSelected {
            return .blue.opacity(0.1)
        } else if isToday {
            return .blue.opacity(0.05)
        } else if hasImportantEvents {
            return .red.opacity(0.08)
        } else {
            return .clear
        }
    }

    private var borderColor: Color {
        if isSelected {
            return .blue
        } else if isToday {
            return .blue.opacity(0.5)
        } else {
            return .clear
        }
    }

    private var textColor: Color {
        if isSelected {
            return .blue
        } else if isToday {
            return .blue
        } else {
            return .primary
        }
    }
}

struct CalendarEventRow: View {
    @Environment(\.locale) private var displayLocale
    @Environment(\.timeZone) private var displayTimeZone
    let event: CalendarEvent
    let characterId: Int
    let databaseManager: DatabaseManager

    @State private var showEventDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(event.title)
                .font(.headline)
                .lineLimit(2)

            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.secondary)

                Text(formatTime(event.date))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                ResponseBadge(response: event.event_response)
            }

            if event.importance > 0 {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)

                    Text(NSLocalizedString("Calendar_Importance", comment: "Importance"))
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(event.importance > 0 ? Color.red.opacity(0.1) : Color(.systemGray6))
        .cornerRadius(8)
        .onTapGesture {
            showEventDetail = true
        }
        .sheet(isPresented: $showEventDetail) {
            CalendarEventDetailView(
                characterId: characterId, eventId: event.event_id, databaseManager: databaseManager
            )
        }
    }

    private func formatTime(_ date: Date?) -> String {
        guard let date = date else {
            return NSLocalizedString("Calendar_Unknown_Time", comment: "Unknown time")
        }

        return FormatUtil.formatDate(date, dateStyle: .none, timeStyle: .short)
    }
}

struct ResponseBadge: View {
    @Environment(\.locale) private var displayLocale
    @Environment(\.timeZone) private var displayTimeZone
    let response: String

    private var badgeColor: Color {
        switch response {
        case "accepted":
            return .green
        case "declined":
            return .red
        case "tentative":
            return .orange
        default:
            return .gray
        }
    }

    private var badgeText: String {
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

    var body: some View {
        Text(badgeText)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.2))
            .foregroundColor(badgeColor)
            .cornerRadius(4)
    }
}

@MainActor
class CalendarViewModel: ObservableObject {
    @Published var events: [CalendarEvent] = []
    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage = ""

    let characterId: Int
    private var loadTask: Task<Void, Never>?
    private var allLoadedEvents: [CalendarEvent] = []
    private var maxEventId: Int = 0

    init(characterId: Int) {
        self.characterId = characterId
        isLoading = true

        // 在初始化时立即开始加载数据
        loadTask = Task {
            await loadInitialCalendar()
        }
    }

    deinit {
        loadTask?.cancel()
    }

    func refreshCalendar() {
        // 取消之前的任务
        loadTask?.cancel()

        // 开始新的加载任务
        loadTask = Task {
            await loadInitialCalendar()
        }
    }

    /// 当月份变化时，检查是否需要加载更多数据
    func checkDataForMonth(_ month: Date) async {
        let calendar = FormatUtil.appCalendar
        _ = calendar.dateInterval(of: .month, for: month)?.start ?? month
        let monthEnd = calendar.dateInterval(of: .month, for: month)?.end ?? month

        // 检查是否有事件的日期晚于当前显示月份的最后一天
        let hasEventsBeyondMonth = allLoadedEvents.contains { event in
            guard let eventDate = event.date else { return false }
            return eventDate > monthEnd
        }

        // 如果没有超出当前月份的事件，且当前最大eventId > 0，则需要加载更多数据
        if !hasEventsBeyondMonth, maxEventId > 0 {
            await loadMoreEventsForMonth(monthEnd: monthEnd)
        }
    }

    private func loadInitialCalendar() async {
        isLoading = true
        allLoadedEvents = []
        maxEventId = 0

        do {
            let fetchedEvents = try await CharacterCalendarAPI.shared.fetchCharacterCalendar(
                characterId: characterId, fromEventId: nil
            )

            // 检查任务是否被取消
            if Task.isCancelled {
                return
            }

            allLoadedEvents = fetchedEvents
            updateMaxEventId()
            updateDisplayedEvents()

        } catch {
            // 如果任务被取消，不显示错误
            if !Task.isCancelled {
                errorMessage = String(
                    format: NSLocalizedString(
                        "Calendar_Load_Failed", comment: "Failed to load calendar"
                    ),
                    error.localizedDescription
                )
                showError = true
                Logger.error("加载日历失败: \(error)")
            }
        }

        if !Task.isCancelled {
            isLoading = false
        }
    }

    private func loadMoreEventsForMonth(monthEnd: Date) async {
        // 防止重复加载
        guard !isLoading, maxEventId > 0 else { return }

        var shouldContinueLoading = true
        var currentMaxEventId = maxEventId

        while shouldContinueLoading, currentMaxEventId > 0 {
            do {
                let moreEvents = try await CharacterCalendarAPI.shared.fetchCharacterCalendar(
                    characterId: characterId,
                    fromEventId: currentMaxEventId
                )

                // 检查任务是否被取消
                if Task.isCancelled {
                    return
                }

                // 如果没有获取到新事件，停止加载
                if moreEvents.isEmpty {
                    currentMaxEventId = 0
                    break
                }

                // 添加新事件到列表
                allLoadedEvents.append(contentsOf: moreEvents)

                // 更新最大事件ID
                if let newMaxId = moreEvents.map(\.event_id).max() {
                    currentMaxEventId = newMaxId
                } else {
                    currentMaxEventId = 0
                }

                // 检查是否有事件的日期晚于当前显示月份的最后一天
                let hasEventsBeyondMonth = moreEvents.contains { event in
                    guard let eventDate = event.date else { return false }
                    return eventDate > monthEnd
                }

                // 如果找到了超出当前月份的事件，或者没有更多事件，则停止加载
                if hasEventsBeyondMonth || moreEvents.count < 50 {
                    shouldContinueLoading = false
                }

                Logger.info("加载了更多日历事件: \(moreEvents.count)个, 当前总数: \(allLoadedEvents.count)")

            } catch {
                Logger.error("加载更多日历事件失败: \(error)")
                shouldContinueLoading = false
            }
        }

        // 更新最大事件ID和显示的事件
        maxEventId = currentMaxEventId
        updateDisplayedEvents()
    }

    private func updateMaxEventId() {
        maxEventId = allLoadedEvents.map(\.event_id).max() ?? 0
    }

    private func updateDisplayedEvents() {
        events = allLoadedEvents.sorted { event1, event2 in
            guard let date1 = event1.date, let date2 = event2.date else {
                return false
            }
            return date1 < date2
        }
    }
}
