import Foundation

enum WidgetTimelinePlan {
    static let horizon: TimeInterval = 24 * 3600
    static let maximumEntries = 64

    static func dates(in snapshot: WidgetSnapshot, kind: NexusWidgetKind, rowLimit: Int, at now: Date) -> [Date] {
        let changes: [Date] = switch kind {
        case .market: []
        case .skills:
            snapshot.characters.prefix(rowLimit).flatMap { row in
                let expiry = row.skillQueueExpiresAt ?? .distantFuture
                return (row.skills ?? []).flatMap { [$0.start, $0.finish].compactMap(\.self) }
                    .filter { $0 <= expiry } + [expiry]
            }
        case .planets:
            snapshot.planetRows.prefix(rowLimit).flatMap { $0.planets ?? [] }
                .compactMap { $0.cycle(at: now) }
                .flatMap { [$0.start.addingTimeInterval($0.duration * 0.9), $0.end] }
        case .industryOverview:
            snapshot.jobs.filter { $0.status == .active }.flatMap {
                [$0.end.addingTimeInterval(-WidgetIndustryJob.soonInterval), $0.end]
            }
        case .industryList:
            snapshot.jobs.prefix(rowLimit).filter { $0.status == .active }.map(\.end)
        }
        let future = changes
            .filter { $0 > now && $0 <= now.addingTimeInterval(horizon) }.sorted()
        let step: TimeInterval = kind == .skills || kind == .industryList ? 60 : 300
        var dates = [now]
        // Round changes forward, never mark a job ready before its actual end.
        for date in future {
            let slot = ceil(date.timeIntervalSince(now) / step) * step
            let next = kind == .planets ? date : now.addingTimeInterval(slot)
            if dates.last != next {
                dates.append(next)
            }
            if dates.count == maximumEntries {
                break
            }
        }
        let progressEnd: Date? = switch kind {
        case .skills:
            snapshot.characters.prefix(rowLimit).flatMap { $0.skills ?? [] }
                .filter { !$0.isPaused }.compactMap(\.finish).max()
        case .industryList:
            snapshot.jobs.prefix(rowLimit).filter { $0.status == .active }.map(\.end).max()
        case .planets:
            snapshot.planetRows.prefix(rowLimit).flatMap { $0.planets ?? [] }
                .compactMap { $0.cycle(at: now)?.end }.max()
        default: nil
        }
        if let progressEnd {
            // Pre-render local progress and text; advancing entries does not fetch data.
            for index in 1 ..< maximumEntries {
                let next = now.addingTimeInterval(Double(index) * step)
                guard next < progressEnd else { break }
                dates.append(next)
            }
        }
        return Array(Set(dates).sorted().prefix(maximumEntries))
    }

    static func reloadDate(
        in snapshot: WidgetSnapshot, kind: NexusWidgetKind, rowLimit: Int, at now: Date
    ) -> Date {
        let targets = WidgetPresentation.targets(in: snapshot, kind: kind, rowLimit: rowLimit)
        let next = targets.map { resource in
            let stamp = kind == .market
                ? snapshot.market.first { $0.id == resource.id }
                .flatMap { resource.source == .quotes ? $0.quotedAt : $0.historyAt }
                : snapshot.characters.first { $0.id == resource.id }?.syncDate(for: resource.source)
            return (stamp ?? now).addingTimeInterval(resource.source.interval)
        }.min()
            ?? now.addingTimeInterval(3600)
        return max(now.addingTimeInterval(15 * 60), next)
    }
}
