import SwiftUI

struct SDEChangesView: View {
    var previewFileName: String? = nil
    var previewCategory: String? = nil
    var previewItem: String? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var report: SDEChangeReport?
    @State private var sections: [SDEChangeNode] = []
    @State private var failed = false

    private var previewNode: SDEChangeNode? {
        if let previewItem {
            return sections.flatMap(\.children).flatMap(\.children).first { $0.id == previewItem }
        }
        return sections.first { $0.id == previewCategory }
    }

    var body: some View {
        NavigationStack {
            Group {
                if report != nil {
                    if let previewNode {
                        SDEChangeDestination(node: previewNode)
                    } else {
                        SDEChangeDirectoryView(
                            node: SDEChangeNode(id: "updates", title: sdeText("Title"), children: sections),
                            isPreview: previewFileName != nil
                        )
                    }
                } else if failed {
                    ContentUnavailableView(sdeText("Unavailable"), systemImage: "doc.badge.exclamationmark",
                                           description: Text(sdeText("ReadError")))
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(previewNode?.title ?? sdeText("Title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(sdeText("Done")) { dismiss() }
                }
            }
            .task {
                do {
                    let url: URL
                    if let previewFileName {
                        guard let bundledURL = Bundle.main.url(forResource: previewFileName, withExtension: "json") else {
                            throw CocoaError(.fileNoSuchFile)
                        }
                        url = bundledURL
                    } else {
                        url = LocalSDELayout.whatsNewURL
                    }
                    let loaded = try await Task.detached(priority: .userInitiated) {
                        try SDEChangeReport.decode(Data(contentsOf: url))
                    }.value
                    guard !Task.isCancelled else { return }
                    sections = SDEChangeNode.sections(for: loaded)
                    report = loaded
                } catch {
                    failed = true
                }
            }
        }
    }
}

private struct SDEChangeIcon: View {
    let filename: String?
    var symbol = "shippingbox"
    var size: CGFloat = 32

    var body: some View {
        Group {
            if let filename, !filename.isEmpty {
                IconManager.shared.loadImage(for: filename).resizable().scaledToFit()
            } else {
                Image(systemName: symbol).resizable().scaledToFit().padding(size * 0.15)
                    .foregroundStyle(.tint)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size > 32 ? 10 : 6))
        .accessibilityHidden(true)
    }
}

private struct SDEChangeDirectoryRow: View {
    let node: SDEChangeNode

    var body: some View {
        HStack(spacing: 12) {
            SDEChangeIcon(filename: node.icon, symbol: node.symbol)
            Text(verbatim: node.title).foregroundStyle(.primary)
            Spacer(minLength: 4)
            if node.isDetail {
                if let status = node.status {
                    SDEChangeStatus(status: status)
                }
            } else {
                Text(verbatim: String(node.count ?? node.children.count))
                    .monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct SDEChangeStatus: View {
    let status: String
    private var color: Color {
        status == "added" ? .green : (status == "removed" ? .red : .orange)
    }

    var body: some View {
        Text(sdeText(status)).font(.caption)
            .foregroundStyle(color).padding(.horizontal, 6).padding(.vertical, 3)
            .background(color.opacity(0.1), in: Capsule())
    }
}

private struct SDEChangeDestination: View {
    let node: SDEChangeNode

    var body: some View {
        if node.status == "added", let typeID = node.typeID {
            ItemInfoMap.getItemInfoView(itemID: typeID, databaseManager: DatabaseManager.shared)
        } else if node.isDetail {
            SDEChangeDetailView(node: node)
        } else {
            SDEChangeDirectoryView(node: node)
        }
    }
}

private struct SDEChangeDirectoryView: View {
    let node: SDEChangeNode
    var isPreview = false
    @State private var search = ""

    private func matches(_ item: SDEChangeNode) -> Bool {
        search.isEmpty || item.title.localizedStandardContains(search)
            || item.id.localizedStandardContains(search)
            || (item.subtitle?.localizedStandardContains(search) ?? false)
    }

    private func containsMatch(_ item: SDEChangeNode) -> Bool {
        matches(item) || item.children.contains(where: containsMatch)
    }

    private var visibleChildren: [SDEChangeNode] {
        node.children.filter(containsMatch)
    }

    var body: some View {
        List {
            if isPreview {
                Section { Text(sdeText("DemoNotice")).font(.footnote).foregroundStyle(.secondary) }
            }
            ForEach(visibleChildren) { child in
                if node.isCategory {
                    // Group headers replace a whole navigation level; items are visible immediately.
                    Section {
                        ForEach(child.children.filter { matches(child) || matches($0) }) { item in
                            destinationRow(item)
                        }
                        .listRowInsets(itemSectionRowInsets)
                    } header: {
                        HStack(spacing: 8) {
                            Text(verbatim: child.title)
                            Spacer()
                            Text(verbatim: String(child.count ?? child.children.count)).monospacedDigit()
                        }
                        .textCase(nil)
                    }
                } else {
                    destinationRow(child).listRowInsets(itemSectionRowInsets)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(node.title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: sdeText("Search"))
        .overlay {
            if visibleChildren.isEmpty {
                ContentUnavailableView(sdeText(search.isEmpty ? "Empty" : "NoResults"), systemImage: "doc.text.magnifyingglass")
            }
        }
    }

    private func destinationRow(_ item: SDEChangeNode) -> some View {
        NavigationLink {
            SDEChangeDestination(node: item)
        } label: {
            SDEChangeDirectoryRow(node: item)
        }
    }
}

private struct SDEChangeDetailView: View {
    let node: SDEChangeNode

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    SDEChangeIcon(filename: node.icon, size: 64)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: node.title).font(.headline).textSelection(.enabled)
                        if let subtitle = node.subtitle {
                            Text(verbatim: subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                        if let status = node.status {
                            SDEChangeStatus(status: status)
                        }
                    }
                }
                .padding(.vertical, 4)
                if let typeID = node.typeID, ItemInfoMap.typeInfo(for: typeID) != nil {
                    NavigationLink {
                        ItemInfoMap.getItemInfoView(itemID: typeID, databaseManager: DatabaseManager.shared)
                    } label: {
                        Label(sdeText("ViewItem"), systemImage: "info.circle").font(.subheadline)
                    }
                }
            }
            ForEach(node.details) { section in
                Section {
                    ForEach(section.rows) { row in
                        if row.layout != .inline, let change = row.change {
                            SDEMultilineDifference(row: row, change: change)
                        } else if let typeID = row.typeID, ItemInfoMap.typeInfo(for: typeID) != nil {
                            NavigationLink {
                                ItemInfoMap.getItemInfoView(itemID: typeID, databaseManager: DatabaseManager.shared)
                            } label: {
                                SDECompactChangeRow(row: row)
                            }
                        } else {
                            SDECompactChangeRow(row: row)
                        }
                    }
                    .listRowInsets(itemSectionRowInsets)
                } header: {
                    HStack(spacing: 6) {
                        if let icon = section.icon {
                            SDEChangeIcon(filename: icon, size: 20)
                        }
                        Text(verbatim: section.title)
                    }
                    .textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.defaultMinListRowHeight, 40)
        .navigationTitle(node.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SDECompactChangeRow: View {
    let row: SDEChangeRowData

    private var label: some View {
        HStack(spacing: 8) {
            if let icon = row.icon {
                SDEChangeIcon(filename: icon)
            }
            if let subtitle = row.subtitle {
                Text(verbatim: row.title).foregroundColor(.primary)
                    + Text(verbatim: " · " + subtitle).foregroundColor(.secondary)
            } else {
                Text(verbatim: row.title).foregroundStyle(.primary)
            }
        }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                label
                Spacer(minLength: 8)
                value.fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 6) {
                label
                value.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .font(.subheadline)
        .padding(.vertical, 3)
    }

    @ViewBuilder private var value: some View {
        if let change = row.change {
            SDEInlineDifference(change: change)
        } else if let text = row.text {
            Text(verbatim: text).foregroundStyle(.secondary)
        }
    }
}

private struct SDEInlineDifference: View {
    let change: SDEValueChange

    private func displayed(_ value: String?) -> String {
        value.map { $0.isEmpty ? sdeText("EmptyString") : $0 } ?? sdeText("Absent")
    }

    var body: some View {
        // Text concatenation wraps naturally for long values and accessibility sizes.
        Group {
            if let old = change.old, let new = change.new {
                Text(verbatim: displayed(old)).foregroundColor(.red).strikethrough()
                    + Text(" → ").foregroundColor(.secondary)
                    + Text(verbatim: displayed(new)).foregroundColor(.green)
            } else if let new = change.new {
                Text(verbatim: "+ " + displayed(new)).foregroundColor(.green)
            } else if let old = change.old {
                Text(verbatim: "− " + displayed(old)).foregroundColor(.red).strikethrough()
            } else {
                Text(sdeText("Absent")).foregroundColor(.secondary)
            }
        }
        .monospacedDigit()
        .textSelection(.enabled)
        .accessibilityLabel("\(sdeText("Old")): \(displayed(change.old)), \(sdeText("New")): \(displayed(change.new))")
    }
}

/// Text stays verbatim; material records are shown individually with their multiplicity intact.
private struct SDEMultilineDifference: View {
    let row: SDEChangeRowData
    let change: SDEValueChange
    @State private var expanded = false
    private let textDifference: SDETextDifference?

    init(row: SDEChangeRowData, change: SDEValueChange) {
        self.row = row
        self.change = change
        textDifference = row.layout == .text
            ? SDETextDifference(old: change.old ?? "", new: change.new ?? "") : nil
    }

    private var isLong: Bool {
        [change.old, change.new].compactMap { $0 }.contains {
            $0.count > 240 || $0.components(separatedBy: .newlines).count > 4
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let icon = row.icon {
                    SDEChangeIcon(filename: icon)
                }
                Text(verbatim: row.title).font(.subheadline.weight(.medium))
            }
            side(change.old, removed: true)
            side(change.new, removed: false)
            if let textDifference,
               SDETextDifference.compact(textDifference.old) != textDifference.old
               || SDETextDifference.compact(textDifference.new) != textDifference.new
            {
                Button(sdeText(expanded ? "Collapse" : "Expand")) { expanded.toggle() }
                    .font(.caption).buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 6)
    }

    private func highlightedText(_ segments: [SDETextDifference.Segment], removed: Bool) -> Text {
        let visible = expanded ? segments : SDETextDifference.compact(segments)
        var result = AttributedString()
        for segment in visible {
            var text = AttributedString(segment.text)
            text.foregroundColor = segment.changed ? (removed ? Color.red : Color.green) : Color.primary
            if segment.changed {
                text.backgroundColor = (removed ? Color.red : Color.green).opacity(0.14)
                if removed {
                    text.strikethroughStyle = .single
                }
            }
            result.append(text)
        }
        return Text(result)
    }

    private func side(_ value: String?, removed: Bool) -> some View {
        let records = row.layout == .materialRecords ? value.flatMap(SDEMaterialRecords.decode) : nil
        let color: Color = value == nil ? .secondary : (removed ? .red : .green)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(sdeText(removed ? "Old" : "New"))
                if let records {
                    Text(verbatim: "· \(records.count) " + sdeText("Records"))
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            Group {
                if let records {
                    if records.isEmpty {
                        Text(verbatim: "[]")
                    }
                    ForEach(Array(records.enumerated()), id: \.offset) { index, record in
                        Text(verbatim: "\(index + 1). \(record)")
                            .strikethrough(removed)
                    }
                } else if let textDifference, let value, !value.isEmpty {
                    highlightedText(removed ? textDifference.old : textDifference.new, removed: removed)
                } else {
                    Text(verbatim: value.map { $0.isEmpty ? sdeText("EmptyString") : $0 } ?? sdeText("Absent"))
                        .strikethrough(removed && value != nil)
                        .lineLimit(row.layout == .text && isLong && !expanded ? 4 : nil)
                }
            }
            .font(.system(.subheadline, design: .monospaced))
            .foregroundStyle(color)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

#if DEBUG
    #Preview("SDE · Demo 更新目录") {
        SDEChangesView(previewFileName: "whats_new_demo")
    }

    #Preview("SDE · Demo 分类与分组") {
        SDEChangesView(previewFileName: "whats_new_demo", previewCategory: "7")
    }

    #Preview("SDE · Demo 属性变更") {
        SDEChangesView(previewFileName: "whats_new_demo", previewItem: "56217")
    }

    #Preview("SDE · Demo 蓝图详情") {
        SDEChangesView(previewFileName: "whats_new_demo", previewItem: "88267")
    }

    #Preview("SDE · Demo 多语言文本") {
        SDEChangesView(previewFileName: "whats_new_demo", previewItem: "587")
    }

    #Preview("SDE · Demo 新增飞船") {
        SDEChangesView(previewFileName: "whats_new_demo", previewItem: "95741")
    }
#endif
