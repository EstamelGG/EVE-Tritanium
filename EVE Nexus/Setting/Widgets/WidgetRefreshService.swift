import Foundation
import UIKit
import WidgetKit

/// App-only adapter for account metadata, localized assets and SwiftUI observation.
@MainActor
final class WidgetRefreshService: ObservableObject {
    static let shared = WidgetRefreshService()
    @Published private(set) var characterSelections = WidgetCharacterPreferences.selections
    @Published private(set) var snapshot = WidgetSnapshot()
    @Published private(set) var storageError = false
    private var refreshTask: Task<Void, Never>?
    private var observer: NSObjectProtocol?

    var characters: [EVECharacterInfo] {
        EVELogin.shared.loadCharacters().map(\.character)
    }

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: AppDataUpdate.notification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let update = note.object as? AppDataUpdate else { return }
            Task { @MainActor [weak self] in await self?.accept(update) }
        }
        reconcileCharacters()
    }

    func selectedIDs(for kind: NexusWidgetKind) -> Set<Int> {
        Set(WidgetCharacterPreferences.selectedIDs(for: kind, in: characterSelections) ?? characters.map(\.CharacterID))
    }

    func setSelectedIDs(_ ids: Set<Int>, for kind: NexusWidgetKind) {
        let ids = ids.intersection(characters.map(\.CharacterID))
        guard kind != .market, ids != selectedIDs(for: kind) else { return }
        characterSelections[WidgetCharacterPreferences.settingsKey(for: kind)] = ids.sorted()
        WidgetCharacterPreferences.selections = characterSelections
        preferencesDidChange(for: kind)
    }

    func reconcileCharacters() {
        let accounts = characters
        let ids = Set(accounts.map(\.CharacterID))
        characterSelections = characterSelections.mapValues { $0.filter { ids.contains($0) } }
        WidgetCharacterPreferences.selections = characterSelections
        var catalog = WidgetStore.shared.catalog
        let previous = catalog.accounts
        catalog.accounts = accounts.map { .init(
            id: $0.CharacterID,
            name: $0.CharacterName,
            needsLogin: $0.refreshTokenExpired
        ) }
        saveCatalog(catalog)
        snapshot = WidgetStore.shared.snapshot()
        if previous != catalog.accounts {
            reload(Set(NexusWidgetKind.allCases))
        }
        WidgetImageStore.prune(.portrait, keeping: ids)
    }

    func preferencesDidChange(for kind: NexusWidgetKind) {
        snapshot = WidgetStore.shared.snapshot()
        reload(kind.refreshSource.widgets)
        Task { await refresh(foreground: true) }
    }

    func refresh(foreground: Bool = false) async {
        if let refreshTask {
            await refreshTask.value
            return
        }
        let task = Task {
            reconcileCharacters()
            let installed = await (try? WidgetCenter.shared.currentConfigurations()) ?? []
            var limits: [NexusWidgetKind: Int] = [:]
            for info in installed {
                guard let kind = NexusWidgetKind(rawValue: info.kind) else { continue }
                limits[kind] = max(limits[kind] ?? 0, info.family.nexusRowLimit)
            }
            await withTaskGroup(of: Void.self) { group in
                for (kind, limit) in limits {
                    group.addTask { await WidgetRepository.shared.refresh(kind: kind, rowLimit: limit) }
                }
            }
            guard !Task.isCancelled else { return }
            await relocalize(reloading: false)
            if foreground {
                await cacheImages()
            }
            reload(Set(limits.keys))
        }
        refreshTask = task
        let backgroundID = foreground
            ? UIApplication.shared.beginBackgroundTask(withName: "Widget refresh") { task.cancel() }
            : .invalid
        defer {
            if backgroundID != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundID)
            }
        }
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        refreshTask = nil
    }

    func refreshPreview(characterID: Int, kind: NexusWidgetKind) async {
        await WidgetRepository.shared.refresh(kind: kind, rowLimit: 9, characterID: characterID)
        guard !Task.isCancelled else { return }
        await relocalize(reloading: false)
        reload(kind.refreshSource.widgets)
    }

    func relocalize(reloading: Bool = true) async {
        let current = WidgetStore.shared.snapshot()
        var catalog = WidgetStore.shared.catalog
        let typeIDs = Set(current.market.map(\.id)
            + current.characters.flatMap { ($0.skills ?? []).map(\.typeID) + ($0.jobs ?? []).map(\.typeID) })
        catalog.typeNames = typeIDs.reduce(into: [:]) { $0[$1] = ItemInfoMap.typeName(for: $1) }
        catalog.planetNames = DatabaseManager.shared.getCelestialNames(
            itemIDs: current.characters.flatMap { ($0.planets ?? []).map(\.id) }
        )
        saveCatalog(catalog)
        snapshot = WidgetStore.shared.snapshot()
        if reloading {
            reload(Set(NexusWidgetKind.allCases))
        }
    }

    private func saveCatalog(_ catalog: WidgetCatalog) {
        do {
            if catalog != WidgetStore.shared.catalog {
                try WidgetStore.shared.saveCatalog(catalog)
            }
            storageError = false
        } catch {
            storageError = true
            Logger.error("无法保存小组件配置: \(error)")
        }
    }

    private func reload(_ kinds: Set<NexusWidgetKind>) {
        for kind in kinds {
            WidgetCenter.shared.reloadTimelines(ofKind: kind.rawValue)
        }
    }

    private func accept(_ update: AppDataUpdate) async {
        let value: WidgetValue
        let id: Int
        let date: Date
        switch update {
        case let .marketOrders(typeID, region, orders, stamp):
            guard matchesMarket(typeID, region: region) else { return }
            id = typeID
            date = stamp
            value = .quote(MarketOrdersUtil.calculatePrice(
                from: orders,
                orderType: .sell,
                stationID: id == MarketManager.plexTypeID ? nil : WidgetMarketWatchlist.stationID
            ).price)
        case let .marketHistory(typeID, region, history, stamp):
            guard matchesMarket(typeID, region: region) else { return }
            id = typeID
            date = stamp
            value = .history(WidgetMarketPoint.recent(history: history, through: stamp))
        case let .skills(characterID, sample):
            id = characterID
            date = sample.fetchedAt
            value = .skills(sample)
        case let .industry(characterID, jobs, stamp):
            id = characterID
            date = stamp
            value = .industry(jobs.compactMap { $0.widgetJob(
                characterID: id,
                name: ItemInfoMap.typeName(for: $0.blueprint_type_id)
            ) })
        case let .colonies(characterID, _, _), let .colony(characterID, _, _, _):
            id = characterID
            guard let colonies = CharacterPlanetaryAPI.cachedColonies(characterID: id),
                  let listDate = CharacterPlanetaryAPI.cachedColoniesAt(characterID: id) else { return }
            var planets: [WidgetPlanet] = []
            var stamps = [listDate]
            let formatter = ISO8601DateFormatter()
            for colony in colonies.sorted(by: { $0.planetId < $1.planetId }).prefix(6) {
                guard let detail = CharacterPlanetaryAPI.cachedColony(
                    characterID: id,
                    planetID: colony.planetId,
                    allowExpired: false
                ),
                    let stamp = CharacterPlanetaryAPI.cachedColonyAt(characterID: id, planetID: colony.planetId)
                else { return }
                let pins = detail.pins.map { pin in
                    WidgetRepository.Pin(
                        extractor_details: pin.extractorDetails != nil || ItemInfoMap.typeInfo(for: pin.typeId)?
                            .groupID == 1063 ? .init() : nil,
                        install_time: pin.installTime.flatMap(formatter.date(from:)),
                        expiry_time: pin.expiryTime.flatMap(formatter.date(from:))
                    )
                }
                planets.append(WidgetRepository.planet(
                    .init(planet_id: colony.planetId, planet_type: colony.planetType),
                    pins: pins,
                    name: nil
                ))
                stamps.append(stamp)
            }
            date = stamps.min()!
            value = .planets(planets)
        }
        if value.source != .quotes, value.source != .history {
            guard characters.contains(where: { $0.CharacterID == id && !$0.refreshTokenExpired }) else { return }
        }
        do {
            _ = try await WidgetStore.shared.accept(value, id: id, at: date)
            await relocalize(reloading: false)
            reload(value.source.widgets)
        } catch {
            storageError = true
            Logger.error("无法保存小组件资源: \(error)")
        }
    }

    private func matchesMarket(_ id: Int, region: Int) -> Bool {
        WidgetMarketWatchlist.read().contains { $0.id == id }
            && region ==
            (id == MarketManager.plexTypeID ? MarketManager.globalPlexRegionID : MarketManager.theForgeRegionID)
    }

    private func cacheImages() async {
        let types = Set(snapshot.market.map(\.id) + snapshot.characters.flatMap { ($0.jobs ?? []).map(\.typeID) })
        for id in types where !WidgetImageStore.exists(.type, id: id) {
            guard !Task.isCancelled else { return }
            if let info = ItemInfoMap.typeInfo(for: id) {
                let image = IconManager.shared.loadUIImage(for: info.iconFilename)
                if let data = image.preparingThumbnail(of: CGSize(width: 64, height: 64))?.pngData() {
                    WidgetImageStore.write(data, kind: .type, id: id)
                }
            }
        }
        let portraitIDs = Set([NexusWidgetKind.skills, .planets].flatMap { kind in
            snapshot.characters.filter { selectedIDs(for: kind).contains($0.id) }.prefix(9).map(\.id)
        })
        for account in snapshot.characters where portraitIDs.contains(account.id) && !WidgetImageStore.exists(
            .portrait,
            id: account.id
        ) {
            guard !Task.isCancelled else { return }
            if let image = try? await CharacterAPI.shared.fetchCharacterPortrait(characterId: account.id),
               let data = image.preparingThumbnail(of: CGSize(width: 64, height: 64))?
               .jpegData(compressionQuality: 0.85)
            {
                WidgetImageStore.write(data, kind: .portrait, id: account.id)
            }
        }
        WidgetImageStore.prune(.type, keeping: types)
    }
}
