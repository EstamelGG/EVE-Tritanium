import Foundation

enum WidgetRefreshFailure: String, Codable {
    case unavailable, needsLogin, missingPermission
}

enum WidgetValue: Codable, Equatable {
    case quote(Double?)
    case history([WidgetMarketPoint])
    case skills(CharacterSkillQueueSample)
    case planets([WidgetPlanet])
    case industry([WidgetIndustryJob])

    var source: WidgetSyncSource {
        switch self {
        case .quote: .quotes
        case .history: .history
        case .skills: .skills
        case .planets: .planets
        case .industry: .industry
        }
    }
}

struct WidgetRecord: Codable {
    var value: WidgetValue?
    var fetchedAt: Date?
    var attemptedAt: Date
    var retryAfter: Date
    var failure: WidgetRefreshFailure?
}

struct WidgetResource: Hashable {
    let source: WidgetSyncSource
    let id: Int
    var key: String {
        "\(source.rawValue)-\(id)"
    }

    func isDue(at date: Date, record: WidgetRecord?, force: Bool) -> Bool {
        guard let record else { return true }
        if record.retryAfter > date {
            return false
        }
        return record.fetchedAt.map { date.timeIntervalSince($0) >= (force ? 60 : source.interval) } ?? true
    }
}

/// Only the app writes account and localized display metadata. Network samples
/// have separate resource files shared by the app and extension.
struct WidgetCatalog: Codable, Equatable {
    struct Account: Codable, Equatable {
        let id: Int
        let name: String
        var needsLogin: Bool
    }

    var accounts: [Account] = []
    var typeNames: [Int: String] = [:]
    var planetNames: [Int: String] = [:]
}

struct WidgetStore {
    static let appGroup = "group.secgg.EVE-Nexus"
    let directory: URL?
    var samplesDirectory: URL? {
        directory?.appendingPathComponent("Samples", isDirectory: true)
    }

    static var shared: Self {
        Self(directory: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("WidgetResources", isDirectory: true))
    }

    private func read<Value: Decodable>(_ name: String, as _: Value.Type) -> Value? {
        guard let url = directory?.appendingPathComponent(name + ".json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    private func write(_ value: some Encodable, name: String) throws {
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        let file = directory.appendingPathComponent(name + ".json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(
            to: file,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    var catalog: WidgetCatalog {
        read("catalog", as: WidgetCatalog.self) ?? WidgetCatalog()
    }

    func saveCatalog(_ catalog: WidgetCatalog) throws {
        try write(catalog, name: "catalog")
    }

    func read(_ resource: WidgetResource) -> WidgetRecord? {
        read("Samples/" + resource.key, as: WidgetRecord.self)
    }

    func skillQueue(for id: Int) -> CharacterSkillQueueSample? {
        guard case let .skills(sample) = read(.init(source: .skills, id: id))?.value else { return nil }
        return sample
    }

    /// Callers hold the resource lock for the entire read / request / commit operation.
    func write(_ record: WidgetRecord, for resource: WidgetResource) throws {
        try write(record, name: "Samples/" + resource.key)
    }

    @discardableResult
    func accept(_ value: WidgetValue, id: Int, at date: Date) async throws -> Bool {
        let resource = WidgetResource(source: value.source, id: id)
        let lock = try await WidgetFileLock.acquire(resource.key)
        defer { withExtendedLifetime(lock) {} }
        if value.source != .quotes, value.source != .history,
           !catalog.accounts.contains(where: { $0.id == id && !$0.needsLogin })
        {
            return false
        }
        if let current = read(resource)?.fetchedAt, current >= date {
            return false
        }
        try write(WidgetRecord(
            value: value,
            fetchedAt: date,
            attemptedAt: date,
            retryAfter: date.addingTimeInterval(60)
        ), for: resource)
        return true
    }

    func removeCharacter(_ id: Int) async throws {
        for source in [WidgetSyncSource.skills, .planets, .industry] {
            let resource = WidgetResource(source: source, id: id)
            let lock = try await WidgetFileLock.acquire(resource.key)
            defer { withExtendedLifetime(lock) {} }
            if let url = samplesDirectory?.appendingPathComponent(resource.key + ".json"),
               FileManager.default.fileExists(atPath: url.path)
            {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    func snapshot(kind: NexusWidgetKind? = nil, rowLimit: Int = 9, characterIDs: [Int]? = nil) -> WidgetSnapshot {
        let catalog = catalog
        let choices = kind == nil || kind == .market ? Array(WidgetMarketWatchlist.read().prefix(rowLimit)) : []
        let market = choices.map { choice in
            var item = WidgetMarketItem(id: choice.id, name: catalog.typeNames[choice.id] ?? choice.name)
            let quote = read(.init(source: .quotes, id: choice.id))
            let history = read(.init(source: .history, id: choice.id))
            if case let .quote(price) = quote?.value {
                item.price = price
                item.quotedAt = quote?.fetchedAt
            }
            if case let .history(points) = history?.value {
                item.history = points
                item.historyAt = history?.fetchedAt
            }
            return item
        }
        let selected = catalog.accounts.filter { characterIDs?.contains($0.id) ?? true }
        let accounts = kind == .market ? [] :
            (kind == .skills || kind == .planets ? Array(selected.prefix(rowLimit)) : selected)
        let sources: [WidgetSyncSource] = kind.map { [$0.refreshSource] } ?? [.skills, .planets, .industry]
        let characters = accounts.map { account in
            var row = WidgetCharacter(id: account.id, name: account.name, needsLogin: account.needsLogin)
            guard !account.needsLogin else { return row }
            for source in sources {
                guard let record = read(.init(source: source, id: account.id)) else { continue }
                switch record.value {
                case let .skills(sample):
                    row.skills = sample.relocalized { catalog.typeNames[$0] }.widgetSkills()
                    row.skillsAt = record.fetchedAt
                case let .planets(planets):
                    row.planets = planets.map { var p = $0
                        p.name = catalog.planetNames[p.id] ?? p.name
                        return p
                    }
                    row.planetsAt = record.fetchedAt
                case let .industry(jobs):
                    row.jobs = jobs.map { var j = $0
                        j.name = catalog.typeNames[j.typeID] ?? j.name
                        return j
                    }
                    row.jobsAt = record.fetchedAt
                default: break
                }
            }
            return row
        }
        return WidgetSnapshot(market: market, characters: characters)
    }
}

extension NexusWidgetKind {
    var refreshSource: WidgetSyncSource {
        switch self {
        case .market: .quotes
        case .skills: .skills
        case .planets: .planets
        case .industryOverview, .industryList: .industry
        }
    }
}

extension WidgetCharacter {
    func syncDate(for source: WidgetSyncSource) -> Date? {
        switch source {
        case .skills: skillsAt
        case .planets: planetsAt
        case .industry: jobsAt
        default: nil
        }
    }
}

enum WidgetPresentation {
    static func load(kind: NexusWidgetKind, rowLimit: Int) -> WidgetSnapshot {
        WidgetStore.shared.snapshot(
            kind: kind,
            rowLimit: rowLimit,
            characterIDs: WidgetCharacterPreferences.selectedIDs(
                for: kind,
                in: WidgetCharacterPreferences.selections
            )
        )
    }

    static func targets(in snapshot: WidgetSnapshot, kind: NexusWidgetKind, rowLimit: Int) -> [WidgetResource] {
        if kind == .market {
            return snapshot.market.prefix(rowLimit).flatMap { item in
                [WidgetResource(source: .quotes, id: item.id), WidgetResource(source: .history, id: item.id)]
            }
        }
        let rows = kind == .skills || kind == .planets ? Array(snapshot.characters.prefix(rowLimit)) : snapshot
            .characters
        return rows.filter { !$0.isTokenExpired }.map { .init(source: kind.refreshSource, id: $0.id) }
    }
}
