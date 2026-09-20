import Foundation
import SwiftUI

// MARK: - Quota parsing

/// 解析 `12000/15m` → 上限与窗口长度
struct RateLimitQuota: Hashable, Codable {
    let maxTokens: Int
    let windowSeconds: TimeInterval
    let raw: String

    var windowLabel: String {
        if windowSeconds >= 3600, windowSeconds.truncatingRemainder(dividingBy: 3600) == 0 {
            return "\(Int(windowSeconds / 3600))h"
        }
        if windowSeconds >= 60, windowSeconds.truncatingRemainder(dividingBy: 60) == 0 {
            return "\(Int(windowSeconds / 60))m"
        }
        return "\(Int(windowSeconds))s"
    }

    static func parse(_ limit: String?) -> RateLimitQuota? {
        guard let limit else { return nil }
        let parts = limit.split(separator: "/", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard parts.count == 2, let max = Int(parts[0]), max > 0,
              let seconds = parseDuration(parts[1]), seconds > 0
        else { return nil }
        return RateLimitQuota(maxTokens: max, windowSeconds: seconds, raw: limit)
    }

    /// 支持 `15m` / `15min` / `1h` / `60s` / 纯数字(秒)
    private static func parseDuration(_ text: String) -> TimeInterval? {
        let lower = text.lowercased()
        if let value = Double(lower) {
            return value
        }
        let number = Double(lower.prefix(while: { $0.isNumber || $0 == "." })) ?? 0
        guard number > 0 else { return nil }
        if lower.hasSuffix("ms") {
            return number / 1000
        }
        if lower.hasSuffix("min") {
            return number * 60
        }
        if lower.hasSuffix("h") {
            return number * 3600
        }
        if lower.hasSuffix("m") {
            return number * 60
        }
        if lower.hasSuffix("s") {
            return number
        }
        return nil
    }
}

/// 组级动态余额（限流按组共享，不按端点）
struct RateLimitBalance: Hashable {
    let remaining: Int
    let quota: RateLimitQuota
    let observedAt: Date

    var consumed: Int {
        max(0, quota.maxTokens - remaining)
    }

    var fraction: Double {
        min(1, max(0, Double(remaining) / Double(quota.maxTokens)))
    }
}

// MARK: - Records

struct RateLimitEndpointRecord: Identifiable, Codable, Hashable {
    var id: String {
        "\(group)|\(pathTemplate)"
    }

    let pathTemplate: String
    let group: String
    var lastSeen: Date
    var hitCount: Int
}

struct RateLimitGroupRecord: Identifiable, Codable, Hashable {
    var id: String {
        group
    }

    let group: String
    var limitRaw: String?
    var remaining: Int?
    var lastRequestCost: Int?
    var lastSeen: Date
    /// 已接受的最近一次请求发送时间：并发请求乱序到达时，仅接受发送时间最晚的响应的 remaining
    var lastAcceptedSendTime: Date?
}

struct RateLimitGroupSnapshot: Identifiable {
    var id: String {
        group
    }

    let group: String
    let balance: RateLimitBalance?
    let lastRequestCost: Int?
    let lastSeen: Date?
    let endpoints: [RateLimitEndpointRecord]
}

// MARK: - Path normalization

enum ESIPathNormalizer {
    static func template(for url: URL) -> String {
        let segments = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let normalized = segments.map { segment -> String in
            if segment.allSatisfy(\.isNumber) {
                return "{id}"
            }
            if UUID(uuidString: segment) != nil {
                return "{uuid}"
            }
            if isHashLike(segment) {
                return "{hash}"
            }
            return segment
        }
        return "/" + normalized.joined(separator: "/")
    }

    /// 检测 hash 样式的路径段（长十六进制串，如 killmail_hash）
    private static func isHashLike(_ segment: String) -> Bool {
        segment.count >= 32 && segment.allSatisfy { "0123456789abcdefABCDEF".contains($0) }
    }
}

// MARK: - Interceptor

enum ESIRateLimitInterceptor {
    static func intercept(url: URL, response: HTTPURLResponse, sendTime: Date) {
        let info = RateLimitInfo(from: response)
        guard let group = info.group, !group.isEmpty else { return }
        let path = ESIPathNormalizer.template(for: url)
        Task { @MainActor in
            ESIRateLimitMonitor.shared.record(
                pathTemplate: path,
                group: group,
                limit: info.limit,
                remaining: info.remaining,
                used: info.used,
                sendTime: sendTime
            )
        }
    }
}

// MARK: - Monitor

@MainActor
final class ESIRateLimitMonitor: ObservableObject {
    static let shared = ESIRateLimitMonitor()

    private static let endpointsKey = "ESIRateLimitMonitor_Records"
    private static let groupsKey = "ESIRateLimitMonitor_Groups"

    @Published private(set) var endpoints: [String: RateLimitEndpointRecord] = [:]
    @Published private(set) var groups: [String: RateLimitGroupRecord] = [:]

    private init() {
        load()
    }

    var snapshots: [RateLimitGroupSnapshot] {
        let byGroup = Dictionary(grouping: endpoints.values) { $0.group }
        let names = Set(groups.keys).union(byGroup.keys)
        let unsorted = names.map { name in
            let record = groups[name]
            let endpoints = (byGroup[name] ?? []).sorted { $0.pathTemplate < $1.pathTemplate }
            let quota = RateLimitQuota.parse(record?.limitRaw)
            let balance: RateLimitBalance? = {
                guard let quota, let remaining = record?.remaining, let at = record?.lastSeen else {
                    return nil
                }
                // 窗口已过期：配额已重置，归零显示
                if Date().timeIntervalSince(at) >= quota.windowSeconds {
                    return RateLimitBalance(remaining: quota.maxTokens, quota: quota, observedAt: at)
                }
                return RateLimitBalance(remaining: remaining, quota: quota, observedAt: at)
            }()
            return RateLimitGroupSnapshot(
                group: name,
                balance: balance,
                lastRequestCost: record?.lastRequestCost,
                lastSeen: record?.lastSeen ?? endpoints.map(\.lastSeen).max(),
                endpoints: endpoints
            )
        }
        // 按已用比例降序：接近超额的排最前，无余额数据的排最后
        return unsorted.sorted { lhs, rhs in
            let lhsUsed = lhs.balance.map { 1 - $0.fraction } ?? -1
            let rhsUsed = rhs.balance.map { 1 - $0.fraction } ?? -1
            return lhsUsed > rhsUsed
        }
    }

    var isEmpty: Bool {
        endpoints.isEmpty && groups.isEmpty
    }

    func record(
        pathTemplate: String,
        group: String,
        limit: String?,
        remaining: Int?,
        used: Int?,
        sendTime: Date
    ) {
        let now = Date()
        let endpointKey = "\(group)|\(pathTemplate)"
        var endpoint = endpoints[endpointKey] ?? RateLimitEndpointRecord(
            pathTemplate: pathTemplate,
            group: group,
            lastSeen: now,
            hitCount: 0
        )
        endpoint.lastSeen = now
        endpoint.hitCount += 1
        endpoints[endpointKey] = endpoint

        var groupRecord = groups[group] ?? RateLimitGroupRecord(
            group: group,
            limitRaw: limit,
            remaining: remaining,
            lastRequestCost: used,
            lastSeen: now,
            lastAcceptedSendTime: sendTime
        )
        groupRecord.limitRaw = limit ?? groupRecord.limitRaw
        if let newRemaining = remaining {
            // 仅接受发送时间 >= 已接受时间的响应：并发请求乱序到达时，最后发送的请求的响应最准确
            if let lastAccepted = groupRecord.lastAcceptedSendTime, sendTime < lastAccepted {
                // 此请求发送较早，其 remaining 是过期值，跳过
            } else {
                groupRecord.remaining = newRemaining
                groupRecord.lastAcceptedSendTime = sendTime
            }
        }
        groupRecord.lastRequestCost = used ?? groupRecord.lastRequestCost
        groupRecord.lastSeen = now
        groups[group] = groupRecord
        persist()
    }

    func clear() {
        endpoints.removeAll()
        groups.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.endpointsKey)
        UserDefaults.standard.removeObject(forKey: Self.groupsKey)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(Array(endpoints.values)) {
            UserDefaults.standard.set(data, forKey: Self.endpointsKey)
        }
        if let data = try? JSONEncoder().encode(Array(groups.values)) {
            UserDefaults.standard.set(data, forKey: Self.groupsKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.endpointsKey),
           let list = try? JSONDecoder().decode([RateLimitEndpointRecord].self, from: data)
        {
            endpoints = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        }
        if let data = UserDefaults.standard.data(forKey: Self.groupsKey),
           let list = try? JSONDecoder().decode([RateLimitGroupRecord].self, from: data)
        {
            groups = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        }
        // 兼容旧版仅 endpoints 且带 remaining 的存储
        if groups.isEmpty {
            migrateLegacyIfNeeded()
        }
    }

    private func migrateLegacyIfNeeded() {
        struct Legacy: Codable {
            let pathTemplate: String
            let group: String
            var limit: String?
            var remaining: Int?
            var used: Int?
            var lastSeen: Date
            var hitCount: Int
        }
        guard let data = UserDefaults.standard.data(forKey: Self.endpointsKey),
              let list = try? JSONDecoder().decode([Legacy].self, from: data)
        else { return }
        for item in list {
            let key = "\(item.group)|\(item.pathTemplate)"
            endpoints[key] = RateLimitEndpointRecord(
                pathTemplate: item.pathTemplate,
                group: item.group,
                lastSeen: item.lastSeen,
                hitCount: item.hitCount
            )
            var g = groups[item.group] ?? RateLimitGroupRecord(
                group: item.group,
                limitRaw: item.limit,
                remaining: item.remaining,
                lastRequestCost: item.used,
                lastSeen: item.lastSeen
            )
            if item.lastSeen >= g.lastSeen {
                g.limitRaw = item.limit ?? g.limitRaw
                g.remaining = item.remaining ?? g.remaining
                g.lastRequestCost = item.used ?? g.lastRequestCost
                g.lastSeen = item.lastSeen
            }
            groups[item.group] = g
        }
        persist()
    }
}
