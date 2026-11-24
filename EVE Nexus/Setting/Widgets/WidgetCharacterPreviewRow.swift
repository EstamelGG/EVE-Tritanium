import SwiftUI

struct WidgetCharacterPreviewRow: View {
    let kind: NexusWidgetKind
    let characterID: Int
    let name: String
    let isExpired: Bool

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale
    @ObservedObject private var service = WidgetRefreshService.shared
    @State private var industryCapacity: IndustrySlotCounts?

    private var preview: WidgetCharacter {
        guard !isExpired else { return WidgetCharacter(id: characterID, name: name, needsLogin: true) }
        return service.snapshot.characters.first { $0.id == characterID } ?? WidgetCharacter(id: characterID, name: name)
    }

    private var portrait: some View {
        CharacterPortraitView(characterId: characterID)
    }

    private var characterName: some View {
        CharacterNameText(characterId: characterID, name: name)
    }

    var body: some View {
        let views = WidgetRows(date: .now)
        let character = preview
        Group {
            switch kind {
            case .skills:
                views.skill(
                    character, height: 44, portrait: portrait, name: characterName,
                    emptyTitle: "Widget_Awaiting_Data",
                    nameFirst: true
                )
            case .planets:
                HStack(spacing: 8) {
                    portrait.accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        characterName
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if let planets = character.planets, !planets.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(planets.prefix(6)) { planet in
                                    views.planetIcon(planet, size: 20, showsProgress: false)
                                }
                            }
                        } else {
                            status(character.planets == nil ? "Widget_Awaiting_Data" : "Widget_No_Planets")
                        }
                    }
                }
            case .industryOverview, .industryList:
                HStack(spacing: 8) {
                    portrait.accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        characterName
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        let used = character.jobs.map { jobs in
                            IndustrySlotCounts.used(by: jobs.lazy
                                .filter { $0.status == .active || $0.status == .ready }
                                .map { $0.activity == .reactionLegacy ? 9 : $0.activity.rawValue })
                        }
                        industrySlots(used)
                    }
                }
            case .market:
                EmptyView()
            }
        }
        .padding(.vertical, 4)
        .task(id: !isExpired && scenePhase == .active) {
            guard !isExpired, scenePhase == .active else { return }
            await service.refreshPreview(characterID: characterID, kind: kind)
        }
        .task(id: isExpired) {
            guard kind == .industryOverview || kind == .industryList else { return }
            if isExpired {
                industryCapacity = nil
                return
            }
            guard industryCapacity == nil else { return }
            let skills = try? await CharacterSkillsAPI.shared.fetchCharacterSkills(characterId: characterID)
            let capacity = skills.map { IndustrySlotCounts.capacity(for: $0.skillsMap, bonuses: IndustrySlotCounts.skillBonuses(in: .shared)) }
            if !Task.isCancelled {
                industryCapacity = capacity
            }
        }
    }

    private func industrySlots(_ used: IndustrySlotCounts?) -> some View {
        let capacity = isExpired ? nil : industryCapacity
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 0, alignment: .topLeading), count: 3)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 0) {
            slotLabel("Widget_Manufacturing", used: used?.manufacturing, capacity: capacity?.manufacturing,
                      activity: .manufacturing)
            slotLabel("Widget_Research", used: used?.research, capacity: capacity?.research,
                      activity: .materialResearch, separated: true)
            slotLabel("Widget_Reaction", used: used?.reaction, capacity: capacity?.reaction,
                      activity: .reaction, separated: true)
        }
    }

    private func slotLabel(
        _ title: LocalizedStringKey, used: Int?, capacity: Int?, activity: WidgetIndustryActivity,
        separated: Bool = false
    ) -> some View {
        let numerator = used.map(String.init) ?? "—"
        let denominator = capacity.map { String(max(used ?? 0, $0)) } ?? "—"
        return VStack(alignment: .leading, spacing: 2) {
            Text(title, tableName: "Widgets")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(verbatim: "\(numerator)/\(denominator)")
                .font(.caption.weight(.medium))
                .foregroundStyle((used ?? 0) > 0 ? activity.progressColor : Color.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, separated ? 8 : 0)
        .padding(.trailing, 4)
        .overlay(alignment: .leading) {
            if separated {
                Rectangle()
                    .fill(Color(uiColor: .separator))
                    .frame(width: 1 / displayScale)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func status(_ key: LocalizedStringKey) -> some View {
        Text(key, tableName: "Widgets")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
