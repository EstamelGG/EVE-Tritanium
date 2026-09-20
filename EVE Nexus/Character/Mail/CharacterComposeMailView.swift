import SwiftUI

struct CharacterComposeMailView: View {
    let characterId: Int
    let initialRecipients: [MailRecipient]
    let initialSubject: String
    let initialBody: String
    let appendContent: String // 需要附加但不显示在输入框的内容

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = CharacterComposeMailViewModel()

    @State private var recipients: [MailRecipient]
    @State private var subject: String
    @State private var mailBody: String

    // HUD状态
    @State private var showHUD = false
    @State private var hudSuccess = true
    @State private var hudMessage = ""

    /// 使用枚举来管理 sheet 状态
    private enum SheetType: Identifiable {
        case recipientPicker
        case mailListPicker

        var id: Int {
            switch self {
            case .recipientPicker: return 1
            case .mailListPicker: return 2
            }
        }
    }

    @State private var activeSheet: SheetType?

    init(
        characterId: Int,
        initialRecipients: [MailRecipient] = [],
        initialSubject: String = "",
        initialBody: String = "",
        appendContent: String = ""
    ) {
        self.characterId = characterId
        self.initialRecipients = initialRecipients
        self.initialSubject = initialSubject
        self.initialBody = initialBody
        self.appendContent = appendContent

        let uniqueRecipients = Array(Set(initialRecipients))
        _recipients = State(initialValue: uniqueRecipients)
        _subject = State(initialValue: initialSubject)
        _mailBody = State(initialValue: initialBody)

        if !uniqueRecipients.isEmpty {
            Logger.debug("初始化邮件编辑视图 - 收件人: \(uniqueRecipients)")
        }
    }

    var body: some View {
        ZStack {
            Form {
                Section {
                    // 收件人列表
                    ForEach(recipients) { recipient in
                        HStack {
                            if recipient.type != .mailingList {
                                UniversePortrait(
                                    id: recipient.id, type: recipient.type, size: 64, displaySize: 32
                                )
                            }
                            VStack(alignment: .leading) {
                                Text(recipient.name)
                                Text(recipient.type.displayName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button {
                                recipients.removeAll(where: { $0.id == recipient.id })
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                    }

                    // 添加收件人按钮
                    Button {
                        activeSheet = .recipientPicker
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text(NSLocalizedString("Main_EVE_Mail_Add_Recipient", comment: ""))
                        }
                    }

                    // 添加邮件列表按钮
                    Button {
                        activeSheet = .mailListPicker
                    } label: {
                        HStack {
                            Image(systemName: "list.bullet.circle.fill")
                            Text(NSLocalizedString("Main_EVE_Mail_Add_Mailing_List", comment: ""))
                        }
                    }
                } header: {
                    Text(NSLocalizedString("Main_EVE_Mail_Recipients", comment: ""))
                }

                Section {
                    TextField(NSLocalizedString("Main_EVE_Mail_Subject", comment: ""), text: $subject)
                        .textInputAutocapitalization(.none)
                } header: {
                    Text(NSLocalizedString("Main_EVE_Mail_Subject", comment: ""))
                }

                Section {
                    TextEditor(text: $mailBody)
                        .frame(minHeight: 200)
                        .textInputAutocapitalization(.none)
                } header: {
                    Text(NSLocalizedString("Main_EVE_Mail_Body", comment: ""))
                }
            }
            .navigationTitle(NSLocalizedString("Main_EVE_Mail_New", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("Main_EVE_Mail_Cancel", comment: "")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Main_EVE_Mail_Send", comment: "")) {
                        Task {
                            // 将用户输入的内容和需要附加的内容拼接
                            let finalBody = appendContent.isEmpty ? mailBody : mailBody + appendContent
                            let success = await viewModel.sendMail(
                                characterId: characterId,
                                recipients: recipients,
                                subject: subject,
                                body: finalBody
                            )

                            // 显示结果HUD
                            hudSuccess = success
                            hudMessage = success
                                ? NSLocalizedString("Main_EVE_Mail_Send_Success", comment: "")
                                : NSLocalizedString("Main_EVE_Mail_Send_Failed", comment: "")

                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showHUD = true
                            }

                            // 延迟后关闭
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            dismiss()
                        }
                    }
                    .disabled(recipients.isEmpty || subject.isEmpty || mailBody.isEmpty || viewModel.isLoading)
                }
            }
            .sheet(item: $activeSheet) { sheetType in
                switch sheetType {
                case .recipientPicker:
                    RecipientPickerView(
                        characterId: characterId,
                        onSelect: { recipient in
                            if !recipients.contains(where: { $0.id == recipient.id }) {
                                recipients.append(recipient)
                            }
                            activeSheet = nil
                        }
                    )

                case .mailListPicker:
                    MailListPickerView(
                        characterId: characterId,
                        onSelect: { mailList in
                            if !recipients.contains(where: { $0.id == mailList.mailing_list_id }) {
                                recipients.append(
                                    MailRecipient(
                                        id: mailList.mailing_list_id,
                                        name: mailList.name,
                                        type: .mailingList
                                    )
                                )
                            }
                            activeSheet = nil
                        }
                    )
                }
            }

            // HUD显示
            if showHUD {
                MailSendHUDView(success: hudSuccess, message: hudMessage)
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(1)
            }
        }
    }
}

/// 邮件收件人数据结构
struct MailRecipient: Identifiable, Hashable {
    let id: Int
    let name: String
    let type: RecipientType

    /// 实现 Hashable 协议
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(type)
    }

    /// 实现相等性比较
    static func == (lhs: MailRecipient, rhs: MailRecipient) -> Bool {
        return lhs.id == rhs.id && lhs.type == rhs.type
    }

    enum RecipientType {
        case character
        case corporation
        case alliance
        case mailingList

        /// 本地化显示名称（UI 使用）
        var displayName: String {
            switch self {
            case .character:
                return NSLocalizedString("Main_EVE_Mail_Recipient_Character", comment: "")
            case .corporation:
                return NSLocalizedString("Main_EVE_Mail_Recipient_Corporation", comment: "")
            case .alliance:
                return NSLocalizedString("Main_EVE_Mail_Recipient_Alliance", comment: "")
            case .mailingList:
                return NSLocalizedString("Main_EVE_Mail_Recipient_Mailing_List", comment: "")
            }
        }

        /// ESI API 字符串（网络请求使用）
        var apiValue: String {
            switch self {
            case .character: return "character"
            case .corporation: return "corporation"
            case .alliance: return "alliance"
            case .mailingList: return "mailing_list"
            }
        }
    }
}

struct RecipientPickerView: View {
    let characterId: Int
    let onSelect: (MailRecipient) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = RecipientPickerViewModel()
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                if searchText.isEmpty {
                    // 快速选择部分
                    Section(
                        header: Text(NSLocalizedString("Main_EVE_Mail_Quick_Select", comment: ""))
                    ) {
                        if viewModel.isLoadingQuickSelect {
                            ProgressView()
                        } else {
                            // 最近的收件人
                            ForEach(viewModel.recentRecipients) { recipient in
                                QuickSelectRow(
                                    recipient: recipient, onSelect: onSelect, dismiss: dismiss
                                )
                            }
                        }
                    }
                } else {
                    // 搜索结果部分
                    if viewModel.isSearching {
                        HStack {
                            Spacer()
                            ProgressView()
                            Text(viewModel.searchingStatus)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    } else if viewModel.error != nil {
                        HStack {
                            Spacer()
                            VStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.largeTitle)
                                    .foregroundColor(.red)
                                Text(NSLocalizedString("Main_EVE_Mail_Search_Failed", comment: ""))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                    } else if searchText.count <= 2 {
                        Text(NSLocalizedString("Main_EVE_Mail_Min_Search_Length", comment: ""))
                            .foregroundColor(.secondary)
                    } else if viewModel.searchResults.isEmpty {
                        Text(NSLocalizedString("Main_EVE_Mail_No_Results", comment: ""))
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(viewModel.searchResults) { result in
                            QuickSelectRow(recipient: result, onSelect: onSelect, dismiss: dismiss)
                        }
                    }
                }
            }
            .searchable(
                text: $searchText,
                prompt: NSLocalizedString("Main_EVE_Mail_Search_Recipients", comment: "")
            )
            .onChange(of: searchText) { _, _ in
                if searchText.isEmpty || searchText.count <= 2 {
                    viewModel.searchResults = []
                    if !searchText.isEmpty {
                        viewModel.error = nil
                        viewModel.isSearching = false
                    }
                } else {
                    viewModel.debounceSearch(characterId: characterId, searchText: searchText)
                }
            }
            .navigationTitle(NSLocalizedString("Main_EVE_Mail_Add_Recipient", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Misc_Done", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            // 重置状态
            searchText = ""
            viewModel.searchResults = []
            viewModel.error = nil
            viewModel.isSearching = false
            // 重新加载快速选择数据
            Task {
                await viewModel.loadQuickSelectRecipients(characterId: characterId)
            }
        }
    }
}

/// 快速选择行视图
private struct QuickSelectRow: View {
    let recipient: RecipientPickerViewModel.SearchResult
    let onSelect: (MailRecipient) -> Void
    let dismiss: DismissAction

    var body: some View {
        Button {
            onSelect(MailRecipient(id: recipient.id, name: recipient.name, type: recipient.type))
            dismiss()
        } label: {
            HStack(spacing: 8) {
                UniversePortrait(id: recipient.id, type: recipient.type, size: 64, displaySize: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(recipient.name)
                    if recipient.type == .character {
                        if let corpName = recipient.corporationName {
                            HStack(spacing: 4) {
                                Text(corpName)
                                if let allianceName = recipient.allianceName {
                                    Text("•")
                                        .foregroundColor(.secondary)
                                    Text(allianceName)
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    } else {
                        Text(recipient.type.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
        }
        .foregroundColor(.primary)
    }
}

/// 邮件列表选择视图
struct MailListPickerView: View {
    let characterId: Int
    let onSelect: (EVEMailList) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = MailListPickerViewModel()

    var body: some View {
        NavigationStack {
            List {
                if viewModel.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Text(NSLocalizedString("Main_EVE_Mail_Loading", comment: ""))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else if viewModel.error != nil {
                    HStack {
                        Spacer()
                        VStack {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                                .foregroundColor(.red)
                            Text(NSLocalizedString("Main_EVE_Mail_Error", comment: ""))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                } else if viewModel.mailLists.isEmpty {
                    Text(NSLocalizedString("Main_EVE_Mail_No_Mailing_Lists", comment: ""))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.mailLists, id: \.mailing_list_id) { mailList in
                        Button {
                            onSelect(mailList)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading) {
                                Text(mailList.name)
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Main_EVE_Mail_Select_Mailing_List", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Misc_Done", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            // 重置状态
            viewModel.mailLists = []
            viewModel.error = nil
            // 重新加载数据
            Task {
                await viewModel.fetchMailLists(characterId: characterId)
            }
        }
    }
}

@MainActor
class MailListPickerViewModel: ObservableObject {
    @Published var mailLists: [EVEMailList] = []
    @Published var isLoading = false
    @Published var error: Error?

    func fetchMailLists(characterId: Int) async {
        isLoading = true
        defer { isLoading = false }

        do {
            mailLists = try await CharacterMailAPI.shared.fetchMailLists(characterId: characterId)
            Logger.success("成功获取 \(mailLists.count) 个邮件列表")
        } catch {
            Logger.error("获取邮件列表失败: \(error)")
            self.error = error
        }
    }
}

/// 搜索响应数据结构
private struct SearchResponse: Codable {
    let character: [Int]?
    let corporation: [Int]?
    let alliance: [Int]?
}

@MainActor
class RecipientPickerViewModel: ObservableObject {
    @Published var searchResults: [SearchResult] = []
    @Published var isSearching = false
    @Published var error: Error?
    @Published var searchingStatus = ""

    // 快速选择相关
    @Published var isLoadingQuickSelect = false
    @Published var recentRecipients: [SearchResult] = []

    // 用于防抖的任务
    private var searchTask: Task<Void, Never>?
    private var corporationNames: [Int: String] = [:]
    private var allianceNames: [Int: String] = [:]

    struct SearchResult: Identifiable {
        let id: Int
        let name: String
        let type: MailRecipient.RecipientType
        var corporationName: String?
        var allianceName: String?
    }

    /// 加载快速选择收件人
    func loadQuickSelectRecipients(characterId: Int) async {
        isLoadingQuickSelect = true
        defer { isLoadingQuickSelect = false }

        do {
            // 获取最近的邮件
            let recentMails = try await CharacterMailAPI.shared.fetchLatestMails(
                characterId: characterId
            )

            // 创建一个字典来存储每个联系人的最近邮件时间
            var recipientLastContact: [Int: Date] = [:]

            // 收集联系人ID和他们最近的联系时间
            for mail in recentMails {
                guard let mailDate = FormatUtil.parseUTCDate(mail.timestamp) else { continue }

                // 处理发件人
                if mail.from != characterId {
                    // 如果这个联系人还没有记录时间，或者这个邮件更新，更新时间
                    if recipientLastContact[mail.from] == nil
                        || mailDate > recipientLastContact[mail.from]!
                    {
                        recipientLastContact[mail.from] = mailDate
                    }
                }

                // 处理收件人
                for recipient in mail.recipients where recipient.recipient_type != "mailing_list" {
                    let id = recipient.recipient_id
                    if id != characterId {
                        if recipientLastContact[id] == nil || mailDate > recipientLastContact[id]! {
                            recipientLastContact[id] = mailDate
                        }
                    }
                }
            }

            // 将联系人按最近联系时间排序
            let sortedRecipients = recipientLastContact.sorted { $0.value > $1.value }

            // 获取前10个联系人的ID
            let topRecipientIds = sortedRecipients.prefix(10).map { $0.key }

            // 获取这些ID的名称信息
            let names = try await UniverseAPI.shared.getNamesWithFallback(
                ids: Array(topRecipientIds)
            )

            // 转换为SearchResult数组，保持时间排序
            recentRecipients = topRecipientIds.compactMap { id in
                guard let info = names[id] else { return nil }
                return SearchResult(
                    id: id,
                    name: info.name,
                    type: info.category == "character"
                        ? .character : info.category == "corporation" ? .corporation : .alliance
                )
            }

        } catch {
            Logger.error("加载快速选择收件人失败: \(error)")
        }
    }

    func debounceSearch(characterId: Int, searchText: String) {
        // 取消之前的搜索任务
        searchTask?.cancel()

        // 创建新的搜索任务，延迟500毫秒
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

            // 如果任务被取消了，就直接返回
            if Task.isCancelled {
                return
            }

            // 执行实际的搜索
            await search(characterId: characterId, searchText: searchText)
        }
    }

    func search(characterId: Int, searchText: String) async {
        guard !searchText.isEmpty else {
            searchResults = []
            return
        }

        guard !isSearching else { return }

        isSearching = true
        searchingStatus = NSLocalizedString("Main_Search_Status_Searching", comment: "")
        defer { isSearching = false }

        do {
            error = nil
            searchResults = []
            corporationNames = [:]
            allianceNames = [:]

            // 使用新的搜索API
            searchingStatus = NSLocalizedString(
                "Main_Search_Status_Finding_Characters", comment: ""
            )
            let data = try await CharacterSearchAPI.shared.search(
                characterId: characterId,
                categories: [.character, .corporation, .alliance],
                searchText: searchText
            )

            if Task.isCancelled {
                return
            }

            // 解析搜索结果
            let searchResponse = try JSONDecoder().decode(SearchResponse.self, from: data)
            var results: [SearchResult] = []

            // 获取所有需要查询的ID
            var allIds: Set<Int> = []
            if let characters = searchResponse.character {
                allIds.formUnion(characters)
            }
            if let corporations = searchResponse.corporation {
                allIds.formUnion(corporations)
            }
            if let alliances = searchResponse.alliance {
                allIds.formUnion(alliances)
            }

            // 一次性获取所有名称
            searchingStatus = NSLocalizedString("Main_Search_Status_Loading_Names", comment: "")
            let names = try await UniverseAPI.shared.getNamesWithFallback(ids: Array(allIds))

            if Task.isCancelled {
                return
            }

            // 处理角色搜索结果
            if let characters = searchResponse.character {
                // 获取角色的军团和联盟信息
                searchingStatus = NSLocalizedString(
                    "Main_Search_Status_Loading_Details", comment: ""
                )
                let affiliations = try await CharacterAffiliationAPI.shared
                    .fetchAffiliationsInBatches(characterIds: characters)

                // 收集所有需要查询的军团和联盟ID
                var corpIds = Set<Int>()
                var allianceIds = Set<Int>()

                for affiliation in affiliations {
                    corpIds.insert(affiliation.corporation_id)
                    if let allianceId = affiliation.alliance_id {
                        allianceIds.insert(allianceId)
                    }
                }

                // 获取军团名称
                searchingStatus = NSLocalizedString("Main_Search_Status_Loading_Corps", comment: "")
                corporationNames = try await UniverseAPI.shared.getNamesWithFallback(
                    ids: Array(corpIds)
                )
                .mapValues { $0.name }

                // 获取联盟名称
                if !allianceIds.isEmpty {
                    searchingStatus = NSLocalizedString(
                        "Main_Search_Status_Loading_Alliances", comment: ""
                    )
                    allianceNames = try await UniverseAPI.shared.getNamesWithFallback(
                        ids: Array(allianceIds)
                    )
                    .mapValues { $0.name }
                }

                // 创建角色搜索结果
                for character in characters {
                    if let info = names[character] {
                        var result = SearchResult(id: character, name: info.name, type: .character)
                        if let affiliation = affiliations.first(where: {
                            $0.character_id == character
                        }) {
                            result.corporationName = corporationNames[affiliation.corporation_id]
                            if let allianceId = affiliation.alliance_id {
                                result.allianceName = allianceNames[allianceId]
                            }
                        }
                        results.append(result)
                    }
                }
            }

            // 处理军团搜索结果
            if let corporations = searchResponse.corporation {
                results.append(
                    contentsOf: corporations.compactMap { id in
                        guard let info = names[id] else { return nil }
                        return SearchResult(id: id, name: info.name, type: .corporation)
                    }
                )
            }

            // 处理联盟搜索结果
            if let alliances = searchResponse.alliance {
                results.append(
                    contentsOf: alliances.compactMap { id in
                        guard let info = names[id] else { return nil }
                        return SearchResult(id: id, name: info.name, type: .alliance)
                    }
                )
            }

            if Task.isCancelled {
                return
            }

            // 按名称排序结果
            results.sort { $0.name < $1.name }

            searchResults = results
            Logger.info("搜索完成，找到 \(results.count) 个结果")

        } catch {
            if error is CancellationError {
                Logger.debug("搜索任务被取消")
                return
            }
            Logger.error("搜索收件人失败: \(error)")
            self.error = error
        }
        searchingStatus = ""
    }
}

@MainActor
class CharacterComposeMailViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var error: Error?

    func sendMail(characterId: Int, recipients: [MailRecipient], subject: String, body: String)
        async -> Bool
    {
        isLoading = true
        defer { isLoading = false }

        do {
            // 转换收件人格式
            let recipientsList = recipients.map { recipient in
                EVEMailRecipient(
                    recipient_id: recipient.id,
                    recipient_type: recipient.type.apiValue
                )
            }

            try await CharacterMailAPI.shared.sendMail(
                characterId: characterId,
                recipients: recipientsList,
                subject: subject,
                body: body
            )
            Logger.info("邮件发送成功")
            return true
        } catch {
            Logger.error("发送邮件失败: \(error)")
            self.error = error
            return false
        }
    }
}

/// 邮件发送HUD视图
struct MailSendHUDView: View {
    let success: Bool
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 60))

            Text(message)
                .font(.headline)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
        .shadow(radius: 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.2))
    }
}
