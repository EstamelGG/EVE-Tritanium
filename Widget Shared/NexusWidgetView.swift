import SwiftUI
import WidgetKit

struct NexusWidgetView: View {
    let kind: NexusWidgetKind
    let entry: NexusWidgetEntry
    @Environment(\.widgetFamily) private var widgetFamily
    @Environment(\.locale) private var locale
    var previewFamily: WidgetFamily?

    private var family: WidgetFamily {
        previewFamily ?? widgetFamily
    }

    private var rowLimit: Int {
        family.nexusRowLimit
    }

    private var rowSpacing: CGFloat {
        family == .systemMedium ? 4 : 6
    }

    var body: some View {
        if entry.isPlaceholder {
            empty("Widget_Awaiting_Data")
                .unredacted()
        } else {
            widgetBody
        }
    }

    private var widgetBody: some View {
        GeometryReader { geometry in
            let sync = entry.snapshot?.lastSync(for: kind, rowLimit: rowLimit)
            let footerHeight: CGFloat = 28
            let size = CGSize(width: geometry.size.width, height: max(0, geometry.size.height - footerHeight))
            VStack(spacing: 0) {
                Group {
                    if let snapshot = entry.snapshot {
                        content(snapshot, size: size)
                    } else {
                        empty("Widget_Awaiting_Data")
                    }
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                footer(sync: sync)
                    .frame(width: size.width, height: footerHeight)
            }
        }
        .monospacedDigit()
        .widgetURL(kind.settingsURL)
    }

    private func footer(sync: Date?) -> some View {
        HStack(spacing: 8) {
            Link(destination: kind.settingsURL) {
                HStack(spacing: 3) {
                    Image(systemName: "pencil")
                        .imageScale(.small)
                        .accessibilityHidden(true)
                    Text("Widget_Edit", tableName: "Widgets")
                        .fontWeight(.medium)
                }
                .frame(minWidth: 44, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            syncStatus(sync)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.caption2)
        .foregroundStyle(.primary)
        .lineLimit(1)
        .dynamicTypeSize(...DynamicTypeSize.large)
    }

    @ViewBuilder
    private func syncStatus(_ sync: Date?) -> some View {
        if let sync {
            let date = sync.formatted(.dateTime.month(.abbreviated).day().locale(locale))
            let text = sync.formatted(Date.VerbatimFormatStyle(
                format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
                timeZone: .current,
                calendar: .current
            ))
            Text("Widget_Updated_At \(date) \(text)", tableName: "Widgets")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .minimumScaleFactor(0.85)
        }
    }

    @ViewBuilder
    private func content(_ snapshot: WidgetSnapshot, size: CGSize) -> some View {
        let rowHeight = min(52, max(0, size.height - rowSpacing * CGFloat(rowLimit - 1)) / CGFloat(rowLimit))
        let dataRows = WidgetRows(date: entry.date, locale: locale)
        switch kind {
        case .market:
            if snapshot.market.isEmpty {
                empty("Widget_Select_Market_Items")
            } else {
                rows(
                    snapshot.market,
                    height: rowHeight,
                    destination: { WidgetContentRoute.market($0.id).url }
                ) { item in
                    WidgetMarketRow(
                        item: item,
                        trendColors: entry.marketTrendColors,
                        chartWidth: min(92, size.width * 0.19),
                        quoteWidth: min(90, size.width * 0.25),
                        rowHeight: rowHeight
                    )
                }
            }
        case .skills:
            if snapshot.characters.isEmpty {
                empty("Widget_Select_Characters")
            } else {
                rows(
                    snapshot.characters,
                    height: rowHeight,
                    destination: { WidgetContentRoute.skills($0.id).url }
                ) { character in
                    let portrait = WidgetImageStore.read(.portrait, id: character.id)
                    return dataRows.skill(
                        character, height: rowHeight,
                        portrait: WidgetIcon(
                            data: portrait, symbol: "person.crop.circle.fill",
                            size: min(28, max(16, rowHeight - 6))
                        )
                        .clipShape(.circle)
                        .privacySensitive(portrait != nil),
                        name: Text(character.name).foregroundStyle(.secondary)
                    )
                }
            }
        case .planets:
            let characters = snapshot.planetRows
            if characters.isEmpty {
                empty("Widget_Select_Characters")
            } else {
                rows(
                    characters,
                    height: rowHeight,
                    destination: { WidgetContentRoute.planets($0.id).url }
                ) { character in
                    let iconSize = max(1, min(32, rowHeight - 6, (size.width - 30) / 7))
                    return HStack(spacing: 10) {
                        WidgetIcon(
                            data: WidgetImageStore.read(.portrait, id: character.id),
                            symbol: "person.crop.circle.fill",
                            size: iconSize
                        )
                        .clipShape(.circle)
                        .accessibilityLabel(character.name)
                        .privacySensitive()
                        if let planets = character.planets, !planets.isEmpty {
                            dataRows.planets(planets, size: iconSize)
                        } else {
                            let statusKey: LocalizedStringKey = if character.isTokenExpired {
                                "Widget_Token_Expired"
                            } else if character.planets == nil {
                                "Widget_Awaiting_Data"
                            } else {
                                "Widget_No_Planets"
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(character.name)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(statusKey, tableName: "Widgets")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .lineLimit(1)
                        }
                    }
                }
            }
        case .industryOverview, .industryList:
            let jobs = snapshot.jobs
            if snapshot.characters.isEmpty {
                empty("Widget_Select_Characters")
            } else if snapshot.characters.allSatisfy(\.isTokenExpired) {
                empty("Widget_Token_Expired")
            } else if !snapshot.characters.contains(where: { $0.jobs != nil }) {
                empty("Widget_Awaiting_Data")
            } else if kind == .industryOverview {
                Link(destination: WidgetContentRoute.industry(nil).url) {
                    dataRows.industryOverview(jobs, rowHeight: rowHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if jobs.isEmpty {
                empty("Widget_No_Jobs")
            } else {
                rows(jobs, height: rowHeight, destination: { WidgetContentRoute.industry($0.characterID).url }) { job in
                    dataRows.job(
                        job, icon: WidgetImageStore.read(.type, id: job.typeID), height: rowHeight
                    )
                }
            }
        }
    }

    private func rows<Item: Identifiable>(
        _ items: [Item], height: CGFloat, destination: ((Item) -> URL)? = nil, content: @escaping (Item) -> some View
    ) -> some View {
        let visible = items.prefix(rowLimit)
        return VStack(spacing: 0) {
            ForEach(visible) { item in
                let row = content(item)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: height)
                if let destination {
                    Link(destination: destination(item)) {
                        row.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    row
                }
                if item.id != visible.last?.id {
                    Color.clear
                        .frame(height: rowSpacing)
                        .overlay { Divider() }
                        .accessibilityHidden(true)
                }
            }
        }
        .dynamicTypeSize(...(height < 35 ? DynamicTypeSize.large : .xLarge))
    }

    private func empty(_ message: LocalizedStringKey) -> some View {
        Text(message, tableName: "Widgets")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct WidgetMarketRow: View {
    let item: WidgetMarketItem
    let trendColors: WidgetMarketTrendColors
    let chartWidth: CGFloat
    let quoteWidth: CGFloat
    let rowHeight: CGFloat
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var change: Double? {
        item.history.flatMap { MarketHistorySparkline.change(in: $0) }
    }

    private var trendColor: Color {
        trendColors.color(for: change)
    }

    var body: some View {
        HStack(spacing: 9) {
            WidgetIcon(data: WidgetImageStore.read(.type, id: item.id), symbol: "cube", size: min(25, rowHeight * 0.68))
                .clipShape(.rect(cornerRadius: 5))
                .accessibilityHidden(true)
            Text(item.name)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: rowHeight >= 38)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 3) {
                chart
                    .frame(width: chartWidth, height: min(29, rowHeight * 0.66))
                quote
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var quote: some View {
        VStack(alignment: .trailing, spacing: 1) {
            if let price = item.price {
                Text(CurrencyUnitStyle.current.format(price, locale: WidgetLocalization.locale))
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .minimumScaleFactor(0.7)
                    .accessibilityLabel(Text(price.formatted() + " ISK"))
            } else {
                Text(item.quotedAt == nil ? "Widget_Awaiting_Data" : "Widget_No_Price", tableName: "Widgets")
                    .font(.system(size: 12))
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.secondary)
            }
            if let change {
                HStack(spacing: 2) {
                    Text(
                        change,
                        format: .percent.sign(strategy: .always(includingZero: false))
                            .precision(.fractionLength(2))
                    )
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(colorSchemeContrast == .increased ? Color.primary : trendColor)
                }
                .minimumScaleFactor(0.7)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    Text("Widget_Three_Month_Change", tableName: "Widgets")
                        + Text(" ") + Text(change, format: .percent.precision(.fractionLength(2)))
                )
            } else if item.price != nil {
                Text(verbatim: "ISK")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .lineLimit(1)
        .frame(width: quoteWidth, alignment: .trailing)
    }

    @ViewBuilder
    private var chart: some View {
        if let points = item.history, points.count > 1 {
            MarketHistorySparkline(points: points, color: trendColor)
                .widgetAccentable()
                .accessibilityHidden(true)
        } else {
            Image(systemName: "minus")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityLabel(Text("Widget_No_History", tableName: "Widgets"))
        }
    }
}
