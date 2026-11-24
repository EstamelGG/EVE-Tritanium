import Foundation

enum NexusWidgetKind: String, CaseIterable {
    case market = "EVE.Market"
    case skills = "EVE.Skills"
    case planets = "EVE.Planets"
    case industryOverview = "EVE.IndustryOverview"
    case industryList = "EVE.IndustryList"

    var iconAsset: String {
        switch self {
        case .market: "market"
        case .skills: "skills"
        case .planets: "planets"
        case .industryOverview: "industry"
        case .industryList: "blueprints"
        }
    }

    var settingsURL: URL { WidgetSnapshot.settingsURL.appending(path: rawValue) }

    init?(settingsURL: URL) {
        guard settingsURL.scheme == WidgetSnapshot.settingsURL.scheme,
              settingsURL.host == WidgetSnapshot.settingsURL.host,
              settingsURL.pathComponents.count == 2
        else { return nil }
        self.init(rawValue: settingsURL.lastPathComponent)
    }

    var title: String {
        switch self {
        case .market: String(localized: "Widget_Market", table: "Widgets", bundle: WidgetLocalization.bundle)
        case .skills: String(localized: "Widget_Skills", table: "Widgets", bundle: WidgetLocalization.bundle)
        case .planets: String(localized: "Widget_Planets", table: "Widgets", bundle: WidgetLocalization.bundle)
        case .industryOverview: String(localized: "Widget_Industry_Overview", table: "Widgets", bundle: WidgetLocalization.bundle)
        case .industryList: String(localized: "Widget_Industry_List", table: "Widgets", bundle: WidgetLocalization.bundle)
        }
    }
}

enum WidgetContentRoute: Equatable {
    case market(Int)
    case skills(Int)
    case industry(Int?)
    case planets(Int)

    var url: URL {
        let root = WidgetSnapshot.settingsURL.appending(path: "open")
        switch self {
        case let .market(id): return root.appending(path: "market").appending(path: String(id))
        case let .skills(id): return root.appending(path: "skills").appending(path: String(id))
        case let .industry(id):
            let industry = root.appending(path: "industry")
            return id.map { industry.appending(path: String($0)) } ?? industry
        case let .planets(id): return root.appending(path: "planets").appending(path: String(id))
        }
    }

    init?(url: URL) {
        let path = url.pathComponents
        guard url.scheme == WidgetSnapshot.settingsURL.scheme,
              url.host == WidgetSnapshot.settingsURL.host,
              (3...4).contains(path.count), path[1] == "open"
        else { return nil }

        if path.count == 3, path[2] == "industry" {
            self = .industry(nil)
            return
        }
        guard path.count == 4, let id = Int(path[3]), id > 0 else { return nil }
        switch path[2] {
        case "market": self = .market(id)
        case "skills": self = .skills(id)
        case "industry": self = .industry(id)
        case "planets": self = .planets(id)
        default: return nil
        }
    }
}

struct WidgetSnapshot: Equatable {
    var market: [WidgetMarketItem] = []
    var characters: [WidgetCharacter] = []

    var jobs: [WidgetIndustryJob] {
        characters.flatMap { $0.jobs ?? [] }.sorted {
            if $0.end != $1.end { return $0.end < $1.end }
            return $0.id < $1.id
        }
    }

    var planetRows: [WidgetCharacter] {
        characters
    }

    func lastSync(for kind: NexusWidgetKind, rowLimit: Int) -> Date? {
        switch kind {
        case .market:
            return market.prefix(rowLimit).compactMap(\.quotedAt).min()
        case .skills:
            return characters.prefix(rowLimit).filter { !$0.isTokenExpired }.compactMap(\.skillsAt).min()
        case .planets:
            return planetRows.prefix(rowLimit).filter { !$0.isTokenExpired }.compactMap(\.planetsAt).min()
        case .industryOverview, .industryList:
            return characters.filter { !$0.isTokenExpired }.compactMap(\.jobsAt).min()
        }
    }

    static let settingsURL = URL(string: "evenexus://widgets")!
}

struct WidgetMarketItem: Codable, Equatable, Identifiable {
    let id: Int
    var name: String
    var price: Double?
    var quotedAt: Date?
    var history: [WidgetMarketPoint]?
    var historyAt: Date?

}

struct WidgetMarketPoint: Codable, Equatable {
    let date: Date
    let average: Double

    static func recent(_ points: [Self], through now: Date) -> [Self] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .month, value: -3, to: today) ?? today
        var byDay: [Date: Self] = [:]
        var latestBeforeWindow: Self?

        for point in points where point.date <= now && point.average.isFinite && point.average > 0 {
            let day = calendar.startOfDay(for: point.date)
            if day < start {
                if latestBeforeWindow.map({ day >= $0.date }) ?? true {
                    latestBeforeWindow = Self(date: day, average: point.average)
                }
            } else {
                byDay[day] = Self(date: day, average: point.average)
            }
        }

        if byDay[start] == nil, let carry = latestBeforeWindow {
            byDay[start] = Self(date: start, average: carry.average)
        }

        var result = byDay.values.sorted { $0.date < $1.date }
        if let last = result.last, last.date < today {
            result.append(Self(date: today, average: last.average))
        }
        return result
    }
}

enum WidgetSyncSource: String, Codable, CaseIterable {
    case quotes
    case history
    case skills
    case planets
    case industry
    var interval: TimeInterval {
        switch self {
        case .quotes, .skills, .industry: 30 * 60
        case .history: 4 * 60 * 60
        case .planets: 60 * 60
        }
    }

    var widgets: Set<NexusWidgetKind> {
        switch self {
        case .quotes, .history: [.market]
        case .skills: [.skills]
        case .planets: [.planets]
        case .industry: [.industryOverview, .industryList]
        }
    }
}

struct WidgetCharacter: Codable, Equatable, Identifiable {
    let id: Int
    var name: String
    var skills: [WidgetSkill]?
    var planets: [WidgetPlanet]?
    var jobs: [WidgetIndustryJob]?
    var skillsAt: Date?
    var planetsAt: Date?
    var jobsAt: Date?
    var needsLogin = false

    var isTokenExpired: Bool { needsLogin }

    func displayedSkill(at date: Date) -> WidgetSkill? {
        skills?.first { $0.isTraining(at: date) }
            ?? skills?.first(where: \.isPaused)
            ?? skills?.first { $0.start.map { $0 > date } ?? false }
    }

    var skillQueueExpiresAt: Date? {
        skillsAt?.addingTimeInterval(24 * 3600)
    }

}

struct WidgetSkill: Codable, Equatable {
    let typeID: Int
    var name: String?
    let level: Int
    let start: Date?
    let finish: Date?
    var trainingStartSP: Int?
    var levelStartSP: Int?
    var levelEndSP: Int?

    var isPaused: Bool { start == nil || finish == nil }

    var initialProgress: Double {
        guard let trainingStartSP, let levelStartSP, let levelEndSP, levelEndSP > levelStartSP else { return 0 }
        let progress = (Double(trainingStartSP) - Double(levelStartSP)) / (Double(levelEndSP) - Double(levelStartSP))
        return min(1, max(0, progress))
    }

    var progressInterval: ClosedRange<Date>? {
        guard let start, let finish, finish > start, initialProgress < 1 else { return nil }
        let totalDuration = finish.timeIntervalSince(start) / (1 - initialProgress)
        guard totalDuration.isFinite, totalDuration > 0, totalDuration <= 100 * 365 * 86_400 else { return nil }
        let lower = finish.addingTimeInterval(-totalDuration)
        guard lower < finish else { return nil }
        return lower...finish
    }

    func progress(at date: Date) -> Double {
        guard isTraining(at: date), let progressInterval else { return initialProgress }
        return progressInterval.fraction(at: date)
    }

    func isTraining(at date: Date) -> Bool {
        guard let start, let finish else { return false }
        return start <= date && date < finish
    }
}

struct WidgetPlanet: Codable, Equatable, Identifiable {
    private static let knownPlanetTypes: Set<String> = [
        "temperate", "ice", "gas", "oceanic", "lava", "barren", "storm", "plasma",
    ]

    let id: Int
    var name: String?
    var planetType: String?
    let hasExtractor: Bool
    let cycles: [DateInterval]

    var iconAsset: String? {
        guard let planetType = planetType?.lowercased(), Self.knownPlanetTypes.contains(planetType) else {
            return nil
        }
        return "Planet_\(planetType)"
    }

    /// 返回最早到期的采集周期：若存在已过期采集器则优先暴露过期状态，避免被其他仍在运行的采集器掩盖。
    func cycle(at date: Date) -> DateInterval? {
        cycles.min { $0.end < $1.end }
    }

    func extractorProgress(at date: Date) -> Double? {
        guard hasExtractor else { return nil }
        guard let cycle = cycle(at: date), cycle.duration > 0 else { return 1 }
        return min(1, max(0, date.timeIntervalSince(cycle.start) / cycle.duration))
    }
}

enum WidgetIndustryActivity: Int, Codable {
    case manufacturing = 1
    case materialResearch = 4
    case timeResearch = 3
    case copying = 5
    case invention = 8
    case reaction = 9
    case reactionLegacy = 11
}

struct WidgetIndustryJob: Codable, Equatable, Identifiable {
    enum Status: String, Codable {
        case active
        case paused
        case ready
    }

    static let soonInterval: TimeInterval = 8 * 3600

    let id: Int
    let typeID: Int
    var name: String?
    let activity: WidgetIndustryActivity
    let status: Status
    let end: Date
    var start: Date?
    var duration: TimeInterval?
    var pausedAt: Date?
    var runs: Int?
    var characterID: Int?
    var licensedRuns: Int?

    var activeProgressInterval: ClosedRange<Date>? {
        guard status == .active, let start, start < end else { return nil }
        return start...end
    }

    func progress(at date: Date) -> Double {
        if isReady(at: date) { return 1 }
        if status == .active { return activeProgressInterval?.fraction(at: date) ?? 0 }
        guard let start, let duration, duration > 0, end > start else { return 0 }
        let interval = start...start.addingTimeInterval(duration)
        return interval.fraction(at: pausedAt ?? start)
    }

    func isReady(at date: Date) -> Bool {
        status == .ready || (status == .active && end <= date)
    }

    func isSoon(at date: Date) -> Bool {
        status == .active && date < end && end.timeIntervalSince(date) <= Self.soonInterval
    }
}

private extension ClosedRange where Bound == Date {
    func fraction(at date: Date) -> Double {
        let duration = upperBound.timeIntervalSince(lowerBound)
        guard duration > 0 else { return 0 }
        return Swift.min(1, Swift.max(0, date.timeIntervalSince(lowerBound) / duration))
    }
}

enum WidgetImageStore {
    enum Kind: String {
        case portrait
        case type
    }

    static var directoryURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetStore.appGroup)?
            .appendingPathComponent("WidgetImages", isDirectory: true)
    }

    static func fileURL(for kind: Kind, id: Int) -> URL? {
        directoryURL?.appendingPathComponent("\(kind.rawValue)_\(id).img")
    }

    static func exists(_ kind: Kind, id: Int) -> Bool {
        guard let url = fileURL(for: kind, id: id) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func read(_ kind: Kind, id: Int) -> Data? {
        guard let url = fileURL(for: kind, id: id) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func write(_ data: Data, kind: Kind, id: Int) {
        guard let dir = directoryURL, let url = fileURL(for: kind, id: id) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func prune(_ kind: Kind, keeping ids: Set<Int>) {
        guard let dir = directoryURL,
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }
        let prefix = "\(kind.rawValue)_"
        for url in files {
            let name = url.lastPathComponent
            guard name.hasPrefix(prefix), name.hasSuffix(".img") else { continue }
            let idText = name.dropFirst(prefix.count).dropLast(4)
            if let id = Int(idText), !ids.contains(id) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    static func removeAll() {
        guard let dir = directoryURL, FileManager.default.fileExists(atPath: dir.path) else { return }
        try? FileManager.default.removeItem(at: dir)
    }
}
