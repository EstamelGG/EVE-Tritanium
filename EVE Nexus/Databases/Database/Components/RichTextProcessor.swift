import SwiftSoup
import SwiftUI

struct RichTextView: View {
    let text: String
    @ObservedObject var databaseManager: DatabaseManager
    @State private var selectedItem: (itemID: Int, categoryID: Int)?
    @State private var showingSheet = false
    @State private var urlToConfirm: URL?
    @State private var showingURLAlert = false
    @State private var fittingToShow: LocalFitting?
    @State private var killReportToShow: Int?

    var body: some View {
        let processedResult = RichTextProcessor.processRichText(text)
        return richTextWithModifiers(processedResult)
    }

    private func richTextWithModifiers(_ result: RichTextProcessResult) -> some View {
        result.richText
            .environment(\.openURL, openURLAction)
            .contextMenu { copyContextMenu(result.plainText) }
            .sheet(item: itemSheetBinding) { item in itemSheetContent(item) }
            .alert(NSLocalizedString("Misc_OpenLink", comment: ""), isPresented: $showingURLAlert) {
                Button(NSLocalizedString("Common_Cancel", comment: ""), role: .cancel) {}
                Button(NSLocalizedString("Misc_Yes", comment: "")) {
                    if let url = urlToConfirm {
                        UIApplication.shared.open(url)
                    }
                }
            } message: {
                if let url = urlToConfirm {
                    Text(url.absoluteString)
                }
            }
            .sheet(item: fittingSheetBinding) { item in fittingSheetContent(item) }
            .sheet(item: killReportSheetBinding) { item in killReportSheetContent(item) }
    }

    private var openURLAction: OpenURLAction {
        OpenURLAction { url in
            if url.scheme == "showinfo",
               let itemID = Int(url.host ?? ""),
               let categoryID = databaseManager.getCategoryID(for: itemID)
            {
                selectedItem = (itemID, categoryID)
                DispatchQueue.main.async { showingSheet = true }
                return .handled
            } else if url.scheme == "fitting" {
                handleDNALink(url)
                return .handled
            } else if url.scheme == "killreport",
                      let killIdString = url.host,
                      let killId = Int(killIdString)
            {
                killReportToShow = killId
                return .handled
            } else if url.scheme == "externalurl",
                      let urlString = url.host?.removingPercentEncoding,
                      let externalURL = URL(string: urlString)
            {
                urlToConfirm = externalURL
                showingURLAlert = true
                return .handled
            }
            return .systemAction
        }
    }

    private func copyContextMenu(_ plain: String) -> some View {
        Button {
            UIPasteboard.general.string = plain
        } label: {
            Label(NSLocalizedString("Misc_Copy", comment: ""), systemImage: "doc.on.doc")
        }
    }

    private var itemSheetBinding: Binding<SheetItem?> {
        Binding(
            get: { selectedItem.map { SheetItem(itemID: $0.itemID, categoryID: $0.categoryID) } },
            set: {
                if $0 == nil {
                    selectedItem = nil
                }
            }
        )
    }

    private func itemSheetContent(_ item: SheetItem) -> some View {
        NavigationStack {
            ItemInfoMap.getItemInfoView(itemID: item.itemID, databaseManager: databaseManager)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(NSLocalizedString("Misc_back", comment: "")) {
                            selectedItem = nil
                            showingSheet = false
                        }
                    }
                }
        }
        .presentationDetents([.fraction(0.81)])
        .presentationDragIndicator(.visible)
    }

    private var fittingSheetBinding: Binding<FittingSheetItem?> {
        Binding(
            get: { fittingToShow.map { FittingSheetItem(fitting: $0) } },
            set: {
                if $0 == nil {
                    fittingToShow = nil
                }
            }
        )
    }

    private func fittingSheetContent(_ item: FittingSheetItem) -> some View {
        NavigationStack {
            ShipFittingView(temporaryFitting: item.fitting, databaseManager: databaseManager)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(NSLocalizedString("Misc_back", comment: "")) {
                            fittingToShow = nil
                        }
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var killReportSheetBinding: Binding<KillReportSheetItem?> {
        Binding(
            get: { killReportToShow.map { KillReportSheetItem(killId: $0) } },
            set: {
                if $0 == nil {
                    killReportToShow = nil
                }
            }
        )
    }

    private func killReportSheetContent(_ item: KillReportSheetItem) -> some View {
        NavigationStack {
            KillMailDetailLoaderView(killmailId: item.killId, character: nil)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(NSLocalizedString("Misc_back", comment: "")) {
                            killReportToShow = nil
                        }
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - DNA链接处理方法

    private func handleDNALink(_ url: URL) {
        Logger.info("处理DNA链接: \(url.absoluteString)")

        let dnaString = url.absoluteString
        let displayName = NSLocalizedString("DNA_Fitting_Link_Default_Name", comment: "")

        guard let dnaResult = DNAParser.parseDNA(dnaString, displayName: displayName) else {
            Logger.error("DNA解析失败: \(dnaString)")
            return
        }

        guard
            let localFitting = DNAParser.dnaResultToLocalFitting(
                dnaResult, databaseManager: databaseManager
            )
        else {
            Logger.error("DNA转换为LocalFitting失败")
            return
        }

        DispatchQueue.main.async {
            self.fittingToShow = localFitting
        }

        Logger.info("DNA装配已准备显示，不保存到文件，ID: \(localFitting.fitting_id)")
    }
}

/// 用于sheet的标识符类型
private struct SheetItem: Identifiable {
    let id = UUID()
    let itemID: Int
    let categoryID: Int
}

/// 用于装配sheet的标识符类型
private struct FittingSheetItem: Identifiable {
    let id = UUID()
    let fitting: LocalFitting
}

/// 用于战斗日志sheet的标识符类型
private struct KillReportSheetItem: Identifiable {
    let id = UUID()
    let killId: Int
}

/// 处理结果结构体
struct RichTextProcessResult {
    let richText: Text
    let plainText: String
}

/// HTML富文本处理器（基于 SwiftSoup）
///
/// 采用 DOM 解析 + Token 渲染两阶段架构：
/// 1. tokenize：用 SwiftSoup 解析 HTML 为 DOM，递归遍历生成 Token 序列
/// 2. render：使用样式栈将 Token 渲染为 AttributedString，支持嵌套标签
///
/// 设计取舍：
/// - 颜色标签（<font> 等）被静默丢弃，仅保留其内部文本内容
/// - 不支持的颜色/样式不影响文本理解
/// - 写邮件时不使用此处理器，仅使用最简单文本
/// - HTML 实体由 SwiftSoup 自动解码（含数字实体 `&#NN;`、命名实体 `&copy;` 等）
/// - 畸形 HTML 由 SwiftSoup 自动修复（未闭合标签、标签交叉等）
enum RichTextProcessor {
    /// 将HTML富文本转换为SwiftUI Text与纯文本
    static func processRichText(_ html: String) -> RichTextProcessResult {
        let tokens = tokenize(html)
        let (attributed, plain) = render(tokens)
        return RichTextProcessResult(richText: Text(attributed), plainText: plain)
    }

    /// 从HTML中提取纯文本（用于搜索、列表展示等场景）
    static func plainText(from html: String) -> String {
        let tokens = tokenize(html)
        return renderPlainText(tokens)
    }

    // MARK: - Token

    private enum Token {
        case text(String)
        case br
        case boldStart
        case boldEnd
        case linkStart(href: String, isURLTag: Bool)
        case linkEnd
    }

    /// 用 SwiftSoup 解析 HTML 并使用 NodeTraversor 遍历 DOM，生成 Token 序列
    /// - 颜色标签（font 等）静默丢弃，仅保留其内部文本
    /// - 注释、CDATA 等被自动跳过
    /// - 未闭合标签、标签交叉由 SwiftSoup 自动修复
    private static func tokenize(_ html: String) -> [Token] {
        guard let document = try? SwiftSoup.parse(html),
              let body = document.body()
        else {
            return [.text(html)]
        }

        let visitor = TokenBuildingVisitor()
        let traversor = NodeTraversor(visitor)
        try? traversor.traverse(body)
        return visitor.tokens
    }

    /// NodeVisitor 实现：head/tail 分别 emit 开标签 / 闭标签 Token
    /// 通过 NodeTraversor 访问 DOM，规避 childNodes 的可见性问题
    private final class TokenBuildingVisitor: NodeVisitor {
        private(set) var tokens: [Token] = []
        /// 标记 a 标签是否已 emit linkStart（无 href 时跳过开闭）
        private var linkEmitted = false

        func head(_ node: Node, _: Int) throws {
            if let textNode = node as? TextNode {
                let text = textNode.getWholeText()
                if !text.isEmpty {
                    tokens.append(.text(text))
                }
                return
            }

            guard let element = node as? Element else { return }
            let tagName = element.tagName().lowercased()

            switch tagName {
            case "br":
                tokens.append(.br)
            case "b", "strong":
                tokens.append(.boldStart)
            case "a":
                let href = (try? element.attr("href")) ?? ""
                if !href.isEmpty {
                    tokens.append(.linkStart(href: href, isURLTag: false))
                    linkEmitted = true
                } else {
                    linkEmitted = false
                }
            case "url":
                let href = extractURLTagHref(from: element)
                tokens.append(.linkStart(href: href, isURLTag: true))
                linkEmitted = true
            default:
                // 其他标签：静默丢弃标签本身，递归会处理子节点
                break
            }
        }

        func tail(_ node: Node, _: Int) throws {
            guard let element = node as? Element else { return }
            let tagName = element.tagName().lowercased()

            switch tagName {
            case "b", "strong":
                tokens.append(.boldEnd)
            case "a":
                if linkEmitted {
                    tokens.append(.linkEnd)
                    linkEmitted = false
                }
            case "url":
                if linkEmitted {
                    tokens.append(.linkEnd)
                    linkEmitted = false
                }
            default:
                break
            }
        }
    }

    /// 从 <url> 元素提取 href 值
    /// SwiftSoup 对非标准 `<url=xxx>` 的解析结果不固定，按以下优先级回退：
    /// 1. `href` 属性（标准 HTML 写法 `<url href="xxx">`）
    /// 2. 第一个非空属性值（`<url=xxx>` 被解析为 `<url xxx>`，xxx 是属性名）
    /// 3. 第一个属性名（兜底）
    private static func extractURLTagHref(from element: Element) -> String {
        // 1. 标准 href 属性
        if let href = try? element.attr("href"), !href.isEmpty {
            return href
        }

        // 2. 通过 asList() 遍历所有属性
        guard let attrs = element.getAttributes() else { return "" }
        let attrList = attrs.asList()

        for attr in attrList {
            if !attr.getValue().isEmpty {
                return attr.getValue()
            }
        }

        // 3. 兜底：取第一个属性名
        if let first = attrList.first {
            return first.getKey()
        }
        return ""
    }

    // MARK: - Render

    private enum Style {
        case bold
        case link(URL)
    }

    /// 将Token序列渲染为AttributedString和纯文本，使用样式栈支持嵌套
    /// 连续换行（来自 <br> 或文本中的 \n）最多保留 2 个（即 1 个空行）
    private static func render(_ tokens: [Token]) -> (AttributedString, String) {
        var attributed = AttributedString()
        var plain = ""
        var styles: [Style] = []
        var consecutiveNewlines = 0

        /// 追加一个换行符（若未达上限），并维护计数器
        func appendNewline() {
            consecutiveNewlines += 1
            if consecutiveNewlines <= 2 {
                plain += "\n"
                var chunk = AttributedString("\n")
                applyStyles(&chunk, styles)
                attributed.append(chunk)
            }
        }

        /// 追加普通文本，将其中的 \n 也纳入连续换行计数
        func appendText(_ s: String) {
            let parts = s.split(separator: "\n", omittingEmptySubsequences: false)
            for (index, part) in parts.enumerated() {
                if index > 0 {
                    appendNewline()
                }
                if !part.isEmpty {
                    consecutiveNewlines = 0
                    plain += part
                    var chunk = AttributedString(part)
                    applyStyles(&chunk, styles)
                    attributed.append(chunk)
                }
            }
        }

        for token in tokens {
            switch token {
            case let .text(s):
                appendText(s)
            case .br:
                appendNewline()
            case .boldStart:
                styles.append(.bold)
            case .boldEnd:
                if let last = styles.last, case .bold = last {
                    styles.removeLast()
                }
            case let .linkStart(href, isURLTag):
                if let url = resolveLink(href, isURLTag: isURLTag) {
                    styles.append(.link(url))
                }
            case .linkEnd:
                if let last = styles.last, case .link = last {
                    styles.removeLast()
                }
            }
        }

        let cleanedPlain = cleanWhitespace(plain)
        return (attributed, cleanedPlain)
    }

    /// 仅渲染纯文本（用于不需要富文本的场景）
    private static func renderPlainText(_ tokens: [Token]) -> String {
        var plain = ""
        for token in tokens {
            switch token {
            case let .text(s):
                plain += s
            case .br:
                plain += "\n"
            default:
                break
            }
        }
        return cleanWhitespace(plain)
    }

    /// 将样式栈中的所有样式应用到AttributedString片段
    private static func applyStyles(_ chunk: inout AttributedString, _ styles: [Style]) {
        for style in styles {
            switch style {
            case .bold:
                chunk.inlinePresentationIntent = .stronglyEmphasized
            case let .link(url):
                chunk.foregroundColor = .blue
                chunk.link = url
            }
        }
    }

    /// 收紧多余换行和空格，清理首尾空白
    private static func cleanWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: " +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Link Resolution

    /// 将EVE游戏的链接格式转换为app内部使用的URL scheme
    /// showinfo:1234 -> showinfo://1234
    /// killReport:1234:5678 -> killreport://1234（取第一个数字）
    /// fitting:dna:... -> 保留原样
    /// 其他链接：<a>标签保留原样走系统处理，<url>标签包装为externalurl://走确认弹窗
    private static func resolveLink(_ href: String, isURLTag: Bool) -> URL? {
        if href.hasPrefix("showinfo:") {
            let idString = String(href.dropFirst("showinfo:".count))
            if let itemID = Int(idString) {
                return URL(string: "showinfo://\(itemID)")
            }
            return nil
        }
        if href.hasPrefix("fitting:") {
            return URL(string: href)
        }
        if href.hasPrefix("killReport:") {
            let content = String(href.dropFirst("killReport:".count))
            let components = content.components(separatedBy: ":")
            if let killIdString = components.first, let killId = Int(killIdString) {
                return URL(string: "killreport://\(killId)")
            }
            return nil
        }
        // 其他链接：<url>标签包装为externalurl://走确认弹窗，<a>标签保留原样走系统处理
        if isURLTag {
            if let encoded = href.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) {
                return URL(string: "externalurl://\(encoded)")
            }
            return nil
        }
        return URL(string: href)
    }
}
