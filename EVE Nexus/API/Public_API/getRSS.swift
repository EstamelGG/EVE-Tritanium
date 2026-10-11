import Foundation

// MARK: - RSS数据模型

struct RSSItem: Identifiable, Codable {
    let id: UUID
    let title: String
    let description: String
    let pubDate: Date?
    let link: String
    let guid: String

    init(title: String, description: String, pubDate: Date?, link: String, guid: String) {
        id = UUID()
        self.title = title
        self.description = description
        self.pubDate = pubDate
        self.link = link
        self.guid = guid
    }

    /// 格式化的发布日期
    var formattedDate: String {
        guard let date = pubDate else { return "未知时间" }
        return FormatUtil.formatDate(date, dateStyle: .medium, timeStyle: .short)
    }

    /// 清理HTML标签的描述文本
    var cleanDescription: String {
        return description
            // 先处理换行标签
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
            // 处理段落标签
            .replacingOccurrences(of: "</p>", with: "\n\n")
            .replacingOccurrences(of: "<p[^>]*>", with: "", options: .regularExpression)
            // 处理其他换行相关的标签
            .replacingOccurrences(of: "</div>", with: "\n")
            .replacingOccurrences(of: "<div[^>]*>", with: "", options: .regularExpression)
            // 移除其他HTML标签
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            // 处理HTML实体
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            // 清理多余的空行和空格
            .replacingOccurrences(of: "\\n\\s*\\n", with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: "^\\s+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
    }
}

// MARK: - 使用原生XMLParser的RSS解析器（更稳定）

class RSSParser: NSObject, XMLParserDelegate {
    private var currentElement = ""
    private var currentItem: [String: String] = [:]
    private var items: [RSSItem] = []
    private var currentText = ""
    private var isInsideItem = false

    func parseRSS(data: Data) -> [RSSItem] {
        items = []
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return items
    }

    // MARK: - XMLParserDelegate

    func parser(_: XMLParser, didStartElement elementName: String, namespaceURI _: String?, qualifiedName _: String?, attributes _: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""

        if elementName == "item" {
            isInsideItem = true
            currentItem = [:]
        }
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_: XMLParser, didEndElement elementName: String, namespaceURI _: String?, qualifiedName _: String?) {
        if isInsideItem, !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            currentItem[elementName] = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if elementName == "item" {
            isInsideItem = false
            if let title = currentItem["title"],
               let description = currentItem["description"],
               let pubDateString = currentItem["pubDate"],
               let link = currentItem["link"],
               let guid = currentItem["guid"]
            {
                // 解析日期
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
                dateFormatter.locale = Locale(identifier: "en_US_POSIX")
                let pubDate = dateFormatter.date(from: pubDateString)

                let item = RSSItem(
                    title: title,
                    description: description,
                    pubDate: pubDate,
                    link: link,
                    guid: guid
                )
                items.append(item)
            }
            currentItem = [:]
        }
    }

    func parser(_: XMLParser, parseErrorOccurred parseError: Error) {
        Logger.error("RSS解析错误: \(parseError.localizedDescription)")
    }
}

// MARK: - RSS API管理器

class EVEStatusRSSManager: ObservableObject {
    static let shared = EVEStatusRSSManager()

    @Published var incidents: [RSSItem] = []
    @Published var isLoading = false
    @Published var lastUpdateTime: Date?

    private let rssURL = "https://status.eveonline.com/history.rss"
    private let maxItems = 20

    private init() {}

    func fetchIncidents() async {
        await MainActor.run {
            isLoading = true
        }

        do {
            guard let url = URL(string: rssURL) else {
                throw URLError(.badURL)
            }

            let (data, _) = try await URLSession.shared.data(from: url)

            let parser = RSSParser()
            let allItems = parser.parseRSS(data: data)

            // 按时间排序并取最近20条
            let sortedItems = allItems
                .sorted { item1, item2 in
                    guard let date1 = item1.pubDate,
                          let date2 = item2.pubDate
                    else {
                        return false
                    }
                    return date1 > date2
                }
                .prefix(maxItems)
                .map { $0 }

            await MainActor.run {
                self.incidents = Array(sortedItems)
                self.lastUpdateTime = Date()
                self.isLoading = false
            }

            Logger.success("成功获取 \(incidents.count) 条EVE状态事件")

        } catch {
            Logger.error("获取EVE状态RSS失败: \(error.localizedDescription)")
            await MainActor.run {
                self.isLoading = false
            }
        }
    }

    func refreshIncidents() async {
        await fetchIncidents()
    }
}
