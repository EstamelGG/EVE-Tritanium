import Foundation

actor AppDataRequests<Key: Hashable & Sendable, Value: Sendable> {
    private var pending: [Key: Task<Value, Error>] = [:]

    func run(_ key: Key, operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        if let task = pending[key] {
            return try await task.value
        }
        let task = Task { try await operation() }
        pending[key] = task
        defer { pending[key] = nil }
        return try await task.value
    }
}

extension URL {
    var cacheModificationDate: Date? {
        (try? resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}

enum AppDataUpdate: Sendable {
    static let notification = Notification.Name("AppDataDidUpdate")

    case marketOrders(typeID: Int, regionID: Int, orders: [MarketOrder], at: Date)
    case marketHistory(typeID: Int, regionID: Int, history: [MarketHistory], at: Date)
    case industry(characterID: Int, jobs: [CharacterIndustryAPI.IndustryJob], at: Date)
    case skills(characterID: Int, sample: CharacterSkillQueueSample)
    case colonies(characterID: Int, colonies: [CharacterPlanetaryInfo], at: Date)
    case colony(characterID: Int, planetID: Int, detail: PlanetaryDetail, at: Date)

    @MainActor
    func publish() {
        NotificationCenter.default.post(name: Self.notification, object: self)
    }
}
