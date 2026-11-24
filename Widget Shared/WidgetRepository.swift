import Foundation

actor WidgetRepository {
    static let shared = WidgetRepository()
    private let session: URLSession
    private let store: WidgetStore
    private let snapshotLoader: @Sendable (NexusWidgetKind, Int) -> WidgetSnapshot
    private let tokenProvider: @Sendable (Int, String?, Date) async throws -> String
    private var activeRequests = 0

    init(
        session: URLSession? = nil, store: WidgetStore = .shared,
        snapshotLoader: @escaping @Sendable (NexusWidgetKind, Int) -> WidgetSnapshot = {
            WidgetPresentation.load(kind: $0, rowLimit: $1)
        },
        tokenProvider: @escaping @Sendable (Int, String?, Date) async throws -> String = {
            try await WidgetAuthorization.shared.accessToken(for: $0, rejecting: $1, deadline: $2)
        }
    ) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpMaximumConnectionsPerHost = 3
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 20
        self.session = session ?? URLSession(configuration: configuration)
        self.store = store
        self.snapshotLoader = snapshotLoader
        self.tokenProvider = tokenProvider
    }

    func refresh(kind: NexusWidgetKind, rowLimit: Int, force: Bool = false, characterID: Int? = nil) async {
        let deadline = Date().addingTimeInterval(20)
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshTargets(
                kind: kind,
                rowLimit: rowLimit,
                force: force,
                characterID: characterID,
                deadline: deadline
            ) }
            group.addTask { try? await Task.sleep(for: .seconds(20)) }
            await group.next()
            group.cancelAll()
        }
    }

    func skillQueue(
        for id: Int,
        maxAge: TimeInterval,
        force: Bool,
        afterCompletion: Bool
    ) async throws -> CharacterSkillQueueSample {
        if !force, let sample = store.skillQueue(for: id),
           !sample.needsRefresh(at: Date(), maxAge: maxAge, afterSkillFinishes: afterCompletion)
        {
            return sample
        }
        await refresh(kind: .skills, rowLimit: 1, force: true, characterID: id)
        try Task.checkCancellation()
        let record = store.read(.init(source: .skills, id: id))
        if record?.failure == .needsLogin {
            throw WidgetAuthorizationError.needsLogin
        }
        guard record?.failure == nil,
              let sample = store.skillQueue(for: id) else { throw URLError(.cannotLoadFromNetwork) }
        return sample
    }

    private func refreshTargets(
        kind: NexusWidgetKind,
        rowLimit: Int,
        force: Bool,
        characterID: Int?,
        deadline: Date
    ) async {
        let targets = characterID.map { [WidgetResource(source: kind.refreshSource, id: $0)] }
            ?? WidgetPresentation.targets(in: snapshotLoader(kind, rowLimit), kind: kind, rowLimit: rowLimit)
        let due = targets
            .filter { $0.isDue(at: Date(), record: store.read($0), force: force) }
        await withTaskGroup(of: Void.self) { group in
            var pending = due.makeIterator()
            for _ in 0 ..< 3 {
                if let target = pending.next() {
                    group.addTask { await self.refresh(
                        target,
                        force: force,
                        deadline: deadline
                    ) }
                }
            }
            for await _ in group {
                if !Task.isCancelled, Date() < deadline, let target = pending.next() {
                    group.addTask { await self.refresh(
                        target,
                        force: force,
                        deadline: deadline
                    ) }
                }
            }
        }
    }

    private func refresh(
        _ target: WidgetResource, force: Bool, deadline: Date
    ) async {
        do {
            let lock = try await WidgetFileLock.acquire(target.key, timeout: max(0, deadline.timeIntervalSinceNow))
            defer { withExtendedLifetime(lock) {} }
            var record = store.read(target)
                ?? WidgetRecord(attemptedAt: .distantPast, retryAfter: .distantPast)
            guard target.isDue(at: Date(), record: record, force: force) else { return }
            do {
                let value = try await load(target, deadline: deadline)
                record = value
            } catch {
                guard !Task.isCancelled else { return }
                record.attemptedAt = Date()
                record.retryAfter = Date().addingTimeInterval(force ? 60 : 5 * 60)
                record.failure = .unavailable
                if case WidgetAuthorizationError.needsLogin = error {
                    record.failure = .needsLogin
                    record.retryAfter = Date().addingTimeInterval(15 * 60)
                } else if let failure = error as? HTTPFailure {
                    if failure.status == 403 {
                        record.failure = .missingPermission
                    }
                    record.retryAfter = max(record.retryAfter, failure.retryAfter ?? .distantPast)
                }
            }
            try store.write(record, for: target)
            NSLog("Widget source %@: %@", target.key, record.failure?.rawValue ?? "updated")
        } catch {
            NSLog("Widget refresh could not commit %@: %@", target.key, String(describing: type(of: error)))
        }
    }

    private func load(
        _ target: WidgetResource, deadline: Date
    ) async throws -> WidgetRecord {
        let id = target.id
        let catalog = store.catalog
        let value: WidgetValue
        var serverExpiry: Date?
        switch target.source {
        case .industry:
            let response = try await request(
                "characters/\(id)/industry/jobs/?include_completed=false",
                characterID: id,
                deadline: deadline
            )
            let jobs = try decoder().decode([ESIIndustryJob].self, from: response.data)
            let names = await names(
                for: Set(jobs.map(\.blueprint_type_id)),
                known: catalog.typeNames,
                deadline: deadline
            )
            value = .industry(jobs.compactMap { $0.widgetJob(characterID: id, name: names[$0.blueprint_type_id]) })
            serverExpiry = response.expires
        case .skills:
            let response = try await request("characters/\(id)/skillqueue/", characterID: id, deadline: deadline)
            let queue = try decoder().decode([SkillQueueItem].self, from: response.data)
            let names = await names(for: Set(queue.map(\.skill_id)), known: catalog.typeNames, deadline: deadline)
            let stamp = Date()
            value = .skills(CharacterSkillQueueSample(queue: queue, fetchedAt: stamp, names: names))
            serverExpiry = response.expires
        case .planets:
            let response = try await request("characters/\(id)/planets/", characterID: id, deadline: deadline)
            let colonies = try decoder().decode([Colony].self, from: response.data)
                .sorted { $0.planet_id < $1.planet_id }.prefix(6)
            var planets: [WidgetPlanet] = []
            let names = await names(for: Set(colonies.map(\.planet_id)), known: catalog.planetNames, deadline: deadline)
            for colony in colonies {
                let detail = try await request(
                    "characters/\(id)/planets/\(colony.planet_id)/",
                    characterID: id,
                    deadline: deadline
                )
                let pins = try decoder().decode(ColonyDetail.self, from: detail.data).pins
                planets.append(Self.planet(colony, pins: pins, name: names[colony.planet_id]))
                serverExpiry = max(serverExpiry ?? .distantPast, detail.expires ?? .distantPast)
            }
            // Commit only a complete colony set; failures retain the previous sample and timestamp.
            value = .planets(planets)
            serverExpiry = max(serverExpiry ?? .distantPast, response.expires ?? .distantPast)
        case .quotes:
            let region = id == 44992 ? 19_000_001 : 10_000_002
            var price: Double?
            var page = 1
            var pages = 1
            repeat {
                let response = try await request(
                    "markets/\(region)/orders/?order_type=sell&type_id=\(id)&page=\(page)",
                    deadline: deadline
                )
                let orders = try decoder().decode([MarketOrder].self, from: response.data)
                for order in orders where !order.is_buy_order && order.price.isFinite && order.price > 0
                    && (id == 44992 || order.location_id == WidgetMarketWatchlist.stationID)
                {
                    price = min(price ?? order.price, order.price)
                }
                pages = response.pages
                serverExpiry = max(serverExpiry ?? .distantPast, response.expires ?? .distantPast)
                page += 1
                guard pages <= 30 else { throw URLError(.dataLengthExceedsMaximum) }
            } while page <= pages
            value = .quote(price)
        case .history:
            let region = id == 44992 ? 19_000_001 : 10_000_002
            let response = try await request("markets/\(region)/history/?type_id=\(id)", deadline: deadline)
            let history = try JSONDecoder().decode([HistoryPoint].self, from: response.data)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            value = .history(WidgetMarketPoint.recent(history.compactMap { point in
                formatter.date(from: point.date).map { WidgetMarketPoint(date: $0, average: point.average) }
            }, through: Date()))
            serverExpiry = response.expires
        }
        return WidgetRecord(
            value: value, fetchedAt: Date(), attemptedAt: Date(),
            retryAfter: max(Date().addingTimeInterval(60), serverExpiry ?? .distantPast)
        )
    }

    private func names(for ids: Set<Int>, known: [Int: String], deadline: Date) async -> [Int: String] {
        let missing = ids.subtracting(known.keys)
        guard !missing.isEmpty, missing.count <= 1000,
              let body = try? JSONEncoder().encode(missing.sorted()),
              let response = try? await request("universe/names/", body: body, deadline: deadline),
              let values = try? JSONDecoder().decode([Name].self, from: response.data) else { return known }
        return known.merging(Dictionary(values.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })) { a, _ in a }
    }

    private struct Response {
        let data: Data
        let expires: Date?
        let pages: Int
    }

    private struct HTTPFailure: Error {
        let status: Int
        var retryAfter: Date?
    }

    private func request(
        _ path: String, characterID: Int? = nil, body: Data? = nil, deadline: Date
    ) async throws -> Response {
        try Task.checkCancellation()
        guard Date() < deadline else { throw URLError(.timedOut) }
        let defaults = WidgetMarketWatchlist.defaults
        if let until = defaults?.object(forKey: "widgetESIRetryAfter") as? Date, until > Date() {
            throw HTTPFailure(status: 429, retryAfter: until)
        }
        var request = URLRequest(url: URL(string: "https://esi.evetech.net/latest/" + path)!)
        request.setValue("Tritanium Widgets; tritanium_support@icloud.com", forHTTPHeaderField: "User-Agent")
        if let body {
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        var token: String?
        if let characterID {
            token = try await tokenProvider(characterID, nil, deadline)
        }
        for attempt in 0 ..< 2 {
            try Task.checkCancellation()
            guard Date() < deadline else { throw URLError(.timedOut) }
            request.timeoutInterval = min(8, max(1, deadline.timeIntervalSinceNow))
            if let token {
                request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            }
            let (data, response) = try await send(request, deadline: deadline)
            guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if response.statusCode == 401, attempt == 0, let characterID {
                token = try await tokenProvider(characterID, token, deadline)
                continue
            }
            if response.statusCode == 420 || response.statusCode == 429 {
                let seconds = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
                    ?? response.value(forHTTPHeaderField: "X-Esi-Error-Limit-Reset").flatMap(Double.init) ?? 300
                let until = Date().addingTimeInterval(max(60, seconds))
                defaults?.set(until, forKey: "widgetESIRetryAfter")
                throw HTTPFailure(status: response.statusCode, retryAfter: until)
            }
            guard response.statusCode == 200 else { throw HTTPFailure(status: response.statusCode) }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .gmt
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
            return Response(
                data: data,
                expires: response.value(forHTTPHeaderField: "Expires").flatMap(formatter.date(from:)),
                pages: max(1, response.value(forHTTPHeaderField: "X-Pages").flatMap(Int.init) ?? 1)
            )
        }
        throw HTTPFailure(status: 401)
    }

    private func send(_ request: URLRequest, deadline: Date) async throws -> (Data, URLResponse) {
        while activeRequests >= 3 {
            try Task.checkCancellation()
            guard Date() < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(50))
        }
        try Task.checkCancellation()
        activeRequests += 1
        defer { activeRequests -= 1 }
        return try await session.data(for: request)
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    struct Colony: Decodable { let planet_id: Int
        let planet_type: String
    }

    struct ColonyDetail: Decodable { let pins: [Pin] }
    struct Pin: Decodable {
        let extractor_details: Extractor?
        let install_time: Date?
        let expiry_time: Date?
    }

    struct Extractor: Decodable {}
    private struct MarketOrder: Decodable { let is_buy_order: Bool
        let location_id: Int
        let price: Double
    }

    private struct HistoryPoint: Decodable { let date: String
        let average: Double
    }

    private struct Name: Decodable { let id: Int
        let name: String
    }

    static func planet(_ colony: Colony, pins: [Pin], name: String?) -> WidgetPlanet {
        let extractors = pins.filter { $0.extractor_details != nil }
        let cycles = extractors.compactMap { pin -> DateInterval? in
            guard let start = pin.install_time, let end = pin.expiry_time, end > start else { return nil }
            return DateInterval(start: start, end: end)
        }
        return WidgetPlanet(
            id: colony.planet_id,
            name: name,
            planetType: colony.planet_type,
            hasExtractor: !extractors.isEmpty,
            cycles: cycles
        )
    }
}
