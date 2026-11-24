import SwiftUI
import WidgetKit

struct WidgetRows {
    let date: Date
    var locale = WidgetLocalization.locale

    func skill(
        _ character: WidgetCharacter, height: CGFloat, portrait: some View, name: some View,
        emptyTitle: LocalizedStringKey? = nil, nameFirst: Bool = false
    ) -> some View {
        let isExpiredToken = character.isTokenExpired
        let isStale = !isExpiredToken && (character.skillQueueExpiresAt.map { $0 <= date } ?? false)
        let skill = (isExpiredToken || isStale) ? nil : character.displayedSkill(at: date)
        let isTraining = skill?.isTraining(at: date) == true
        let fallbackTitle: LocalizedStringKey = if isExpiredToken {
            "Widget_Token_Expired"
        } else if isStale {
            "Widget_Skill_Queue_Stale"
        } else if character.skills == nil {
            emptyTitle ?? "Widget_Awaiting_Data"
        } else {
            "Widget_Queue_Empty"
        }
        let title = skillTitle(skill, emptyTitle: fallbackTitle)
            .privacySensitive(skill != nil)
        return HStack(spacing: 8) {
            portrait
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Group {
                        if nameFirst {
                            name.privacySensitive()
                        } else {
                            title
                        }
                    }
                    .font((height < 40 ? Font.caption : .subheadline).weight(.semibold))
                    Spacer(minLength: 2)
                    if let skill {
                        if isTraining, let finish = skill.finish {
                            countdown(to: finish)
                        } else {
                            Text(skill.isPaused ? "Widget_Paused" : "Widget_Queued", tableName: "Widgets")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .privacySensitive()
                        }
                    }
                }
                HStack(spacing: 8) {
                    if nameFirst {
                        title.font(.caption).foregroundStyle(.secondary)
                    } else {
                        name.font(.caption2).privacySensitive()
                    }
                    Spacer(minLength: 2)
                    if let skill {
                        progressBar(skill.progress(at: date), color: .blue, isPaused: skill.isPaused)
                            .frame(maxWidth: 76)
                            .privacySensitive()
                    }
                }
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    private func skillTitle(_ skill: WidgetSkill?, emptyTitle: LocalizedStringKey) -> Text {
        guard let skill else {
            return Text(emptyTitle, tableName: "Widgets")
        }
        let levels = ["I", "II", "III", "IV", "V"]
        let level = levels.indices.contains(skill.level - 1) ? levels[skill.level - 1] : String(skill.level)
        return Text("\(skill.name ?? String(skill.typeID)) \(level)")
    }

    func planets(_ planets: [WidgetPlanet], size: CGFloat) -> some View {
        HStack(spacing: 4) {
            ForEach(0 ..< 6) { index in
                Group {
                    if index < planets.count {
                        planetIcon(planets[index], size: size)
                    } else {
                        Circle()
                            .strokeBorder(
                                .secondary.opacity(0.35),
                                style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])
                            )
                            .frame(width: max(1, size - 2), height: max(1, size - 2))
                            .frame(width: size, height: size)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    func planetIcon(_ planet: WidgetPlanet, size: CGFloat, showsProgress: Bool = true) -> some View {
        let cycle = planet.cycle(at: date)
        let progress = planet.extractorProgress(at: date)
        let isExpired = progress == 1
        let iconSize = showsProgress ? max(1, size - 6) : size
        let activeCycle = cycle.flatMap { $0.duration > 0 && !isExpired ? $0 : nil }
        let accessibilityValue: Text = if showsProgress, planet.hasExtractor, let activeCycle {
            Text(
                .dateRange(endingAt: activeCycle.end),
                format: .components(style: .narrow, fields: [.day, .hour, .minute])
            )
        } else if showsProgress, planet.hasExtractor, isExpired {
            Text(1, format: .percent)
        } else {
            Text("")
        }
        return ZStack {
            WidgetIcon(
                data: nil,
                symbol: "globe",
                size: iconSize,
                fallbackAsset: planet.iconAsset ?? NexusWidgetKind.planets.iconAsset
            )
            .clipShape(.circle)
            if showsProgress, let progress {
                let stroke = StrokeStyle(lineWidth: 2, lineCap: .round)
                ringSegment(0, 1, lineWidth: 2)
                    .stroke(.secondary.opacity(0.2), style: stroke)
                ringSegment(0, progress, lineWidth: 2)
                    .stroke(
                        PlanetaryExtractorProgressColors.fill(
                            isExpired: isExpired, remainingFraction: 1 - progress
                        ),
                        style: stroke
                    )
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable(progress >= 0.9)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(planet.name ?? String(planet.id))
        .accessibilityValue(accessibilityValue)
        .privacySensitive()
    }

    func industryOverview(_ jobs: [WidgetIndustryJob], rowHeight: CGFloat) -> some View {
        let ready = jobs.count { $0.isReady(at: date) }
        let soon = jobs.count { $0.isSoon(at: date) }
        let total = jobs.count
        let ringSize = min(84, rowHeight * 2.75)
        return HStack(spacing: 16) {
            industryRing(ready: ready, soon: soon, total: total, size: ringSize)
                .frame(width: ringSize, height: ringSize)
                .accessibilityHidden(true)
                .privacySensitive()
                .overlay {
                    Image(NexusWidgetKind.industryOverview.iconAsset)
                        .resizable()
                        .widgetAccentedRenderingMode(.desaturated)
                        .scaledToFit()
                        .frame(width: ringSize * 0.36, height: ringSize * 0.36)
                        .clipShape(.rect(cornerRadius: 5))
                        .accessibilityHidden(true)
                }
            VStack(spacing: 2) {
                metric("Widget_Ready", count: ready, color: .green, accent: true)
                Divider().accessibilityHidden(true)
                metric("Widget_Soon", count: soon, color: .blue, accent: false, striped: true)
                Divider().accessibilityHidden(true)
                metric("Widget_Total", count: total, color: .blue, accent: false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    private func industryRing(ready: Int, soon: Int, total: Int, size: CGFloat) -> some View {
        let segments = [
            (start: 0, count: ready, color: Color.green, accent: true, striped: false),
            (start: ready, count: soon, color: Color.blue, accent: false, striped: true),
            (start: ready + soon, count: total - ready - soon, color: Color.blue, accent: false, striped: false),
        ].filter { $0.count > 0 }
        let lineWidth: CGFloat = 8
        let circumference = Double.pi * Double(size - lineWidth)
        // 为圆头预留一个线宽，再留出 2 点间隙。
        let gap = segments.count > 1
            ? min(Double(lineWidth + 2) / max(1, circumference), 0.5 / Double(segments.count))
            : 0
        let sweepPerJob = (1 - gap * Double(segments.count)) / Double(max(1, total))
        let stroke = StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        return ZStack {
            if segments.isEmpty {
                ringSegment(0, 1, lineWidth: lineWidth)
                    .stroke(.secondary.opacity(0.25), lineWidth: lineWidth)
            } else {
                ForEach(segments.indices, id: \.self) { index in
                    let segment = segments[index]
                    let offset = (Double(index) + 0.5) * gap
                    let start = offset + Double(segment.start) * sweepPerJob
                    let end = offset + Double(segment.start + segment.count) * sweepPerJob
                    let arc = ringSegment(start, end, lineWidth: lineWidth)
                    arc.stroke(segment.color, style: stroke)
                        .overlay {
                            if segment.striped {
                                industryStripes.mask { arc.stroke(style: stroke) }
                            }
                        }
                        .widgetAccentable(segment.accent)
                }
            }
        }
        .rotationEffect(.degrees(-90))
    }

    private func ringSegment(_ start: Double, _ end: Double, lineWidth: CGFloat) -> some Shape {
        Circle().inset(by: lineWidth / 2).trim(from: start, to: end)
    }

    private var industryStripes: some View {
        IndustryProgressStripes().stroke(.white.opacity(0.65), lineWidth: 1)
    }

    private func metric(
        _ title: LocalizedStringKey, count: Int, color: Color, accent: Bool, striped: Bool = false
    ) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .overlay {
                    if striped {
                        industryStripes.clipShape(RoundedRectangle(cornerRadius: 2))
                    }
                }
                .frame(width: 10, height: 10)
                .widgetAccentable(accent)
                .accessibilityHidden(true)
            Text(title, tableName: "Widgets")
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 2)
            Text(count, format: .number)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .privacySensitive()
        }
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    func job(_ job: WidgetIndustryJob, icon: Data?, height: CGFloat) -> some View {
        let ready = job.isReady(at: date)
        let color = ready ? Color.green : job.activity.progressColor
        return HStack(spacing: 8) {
            WidgetIcon(
                data: icon, symbol: "doc", size: min(28, max(16, height - 6)),
                fallbackAsset: NexusWidgetKind.industryList.iconAsset
            )
            .clipShape(.rect(cornerRadius: 5))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(job.name ?? String(job.typeID))
                        .font((height < 40 ? Font.caption : .subheadline).weight(.semibold))
                    Spacer(minLength: 2)
                    if ready {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(color)
                            .accessibilityLabel(Text("Widget_Ready", tableName: "Widgets"))
                    } else if job.status == .paused {
                        Text("Widget_Paused", tableName: "Widgets")
                            .foregroundStyle(.secondary)
                            .font(.caption2)
                    } else {
                        countdown(to: job.end)
                    }
                }
                HStack(spacing: 5) {
                    Image(industryActivityIconAsset(for: job.activity.rawValue))
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(job.activity.accessibilityTitle)
                    if let runs = job.runs {
                        Text(IndustryJobQuantity.description(
                            runs: runs, isCopying: job.activity == .copying, licensedRuns: job.licensedRuns
                        ))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 3)
                    progressBar(job.progress(at: date), color: color)
                        .frame(maxWidth: 76)
                }
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .privacySensitive()
    }

    private func countdown(to end: Date) -> some View {
        countdownText(to: end)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.trailing)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: 76, alignment: .trailing)
            .privacySensitive()
    }

    private func countdownText(to end: Date) -> Text {
        Text(verbatim: CompactDuration.format(
            end.timeIntervalSince(date), rounding: .ceil, showsSeconds: false, locale: locale
        ))
    }

    private func progressBar(_ progress: Double, color: Color, isPaused: Bool = false) -> some View {
        let clamped = progress.isFinite ? min(1, max(0, progress)) : 0
        let trackColor = isPaused ? Color.primary.opacity(0.16) : Color.secondary.opacity(0.16)
        let fillColor = isPaused ? Color.primary.opacity(0.55) : color
        return SegmentedProgressBar(segments: [
            .init(value: clamped, color: fillColor),
            .init(value: 1 - clamped, color: trackColor),
        ])
        .widgetAccentable(!isPaused)
        .accessibilityElement(children: .ignore)
        .accessibilityValue(Text(clamped, format: .percent.precision(.fractionLength(0))))
    }
}

private struct IndustryProgressStripes: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            for x in stride(from: rect.minX - rect.height, through: rect.maxX, by: 4) {
                path.move(to: CGPoint(x: x, y: rect.maxY))
                path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            }
        }
    }
}

struct WidgetIcon: View {
    let data: Data?
    let symbol: String
    let size: CGFloat
    var fallbackAsset: String?

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .widgetAccentedRenderingMode(.desaturated)
                    .scaledToFit()
            } else if let fallbackAsset {
                Image(fallbackAsset)
                    .resizable()
                    .widgetAccentedRenderingMode(.desaturated)
                    .scaledToFit()
            } else {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.72))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

extension WidgetIndustryActivity {
    var progressColor: Color {
        switch self {
        case .manufacturing: Color(red: 0.8, green: 0.6, blue: 0)
        case .materialResearch, .timeResearch, .copying, .invention: .blue
        case .reaction, .reactionLegacy: .cyan
        }
    }

    fileprivate var accessibilityTitle: Text {
        switch self {
        case .manufacturing: Text("Widget_Manufacturing", tableName: "Widgets")
        case .materialResearch, .timeResearch, .copying, .invention: Text("Widget_Research", tableName: "Widgets")
        case .reaction, .reactionLegacy: Text("Widget_Reaction", tableName: "Widgets")
        }
    }
}
