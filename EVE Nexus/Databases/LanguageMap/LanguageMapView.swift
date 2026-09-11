import SwiftUI

struct LanguageMapView: View {
    // State 属性
    @State private var exactMatchResults: [(id: Int, names: [String: String])] = [] // 完全匹配结果
    @State private var prefixMatchResults: [(id: Int, names: [String: String])] = [] // 前缀匹配结果
    @State private var fuzzyMatchResults: [(id: Int, names: [String: String])] = [] // 模糊匹配结果
    @State private var searchText = ""
    @State private var isSearchActive = false
    @State private var hasTypeIdMatch = false
    @State private var showingSettings = false
    @State private var selectedLanguages: [String] = LanguageMapConstants
        .languageMapDefaultLanguages

    let availableLanguages = LanguageMapConstants.availableLanguages

    var body: some View {
        VStack {
            // 搜索结果或提示信息
            if exactMatchResults.isEmpty && prefixMatchResults.isEmpty && fuzzyMatchResults.isEmpty {
                // 显示提示信息
                VStack(spacing: 16) {
                    Text(
                        NSLocalizedString(
                            "Main_Language_Map_Supported_Search_Objects", comment: "支持的搜索对象："
                        )
                    )
                    .font(.headline)
                    .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(
                            NSLocalizedString(
                                "Main_Language_Map_Search_Object_1", comment: "1. 物品（舰船、装备、空间实体等）"
                            )
                        )
                        .foregroundColor(.secondary)
                        Text(
                            NSLocalizedString(
                                "Main_Language_Map_Search_Object_2", comment: "2. 星系、星座、星域名"
                            )
                        )
                        .foregroundColor(.secondary)
                        Text(
                            NSLocalizedString(
                                "Main_Language_Map_Search_Object_3", comment: "3. NPC势力名、军团名"
                            )
                        )
                        .foregroundColor(.secondary)
                        Text(
                            NSLocalizedString(
                                "Main_Language_Map_Search_Object_4", comment: "4. 物品 TypeID"
                            )
                        )
                        .foregroundColor(.secondary)
                        Text(
                            NSLocalizedString(
                                "Main_Language_Map_Search_Object_5", comment: "5. 物品目录名"
                            )
                        )
                        .foregroundColor(.secondary)
                        Text(
                            NSLocalizedString(
                                "Main_Language_Map_Search_Object_6", comment: "6. 物品组名"
                            )
                        )
                        .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                // 搜索结果列表
                List {
                    // 完全匹配结果
                    if !exactMatchResults.isEmpty {
                        Section(
                            header: Text(
                                NSLocalizedString("Main_Language_Map_Exact_Match", comment: "完全匹配")
                            )
                        ) {
                            ForEach(exactMatchResults, id: \.id) { result in
                                ResultRow(result: result, availableLanguages: availableLanguages)
                            }
                        }
                    }

                    // 前缀匹配结果
                    if !prefixMatchResults.isEmpty {
                        Section(
                            header: Text(
                                NSLocalizedString("Main_Language_Map_Prefix_Match", comment: "前缀匹配")
                            )
                        ) {
                            ForEach(prefixMatchResults, id: \.id) { result in
                                ResultRow(result: result, availableLanguages: availableLanguages)
                            }
                        }
                    }

                    // 模糊匹配结果
                    if !fuzzyMatchResults.isEmpty {
                        Section(
                            header: Text(
                                NSLocalizedString("Main_Language_Map_Fuzzy_Match", comment: "模糊匹配")
                            )
                        ) {
                            ForEach(fuzzyMatchResults, id: \.id) { result in
                                ResultRow(result: result, availableLanguages: availableLanguages)
                            }
                        }
                    }
                }
            }
        }
        .searchable(
            text: $searchText,
            isPresented: $isSearchActive,
            // placement: .navigationBarDrawer(displayMode: .always),
            prompt: NSLocalizedString("Main_Database_Search", comment: "")
        )
        .onSubmit(of: .search) {
            // 点击小键盘搜索按钮时执行搜索
            performSearch()
        }
        .onChange(of: searchText) { _, newValue in
            // 当搜索文本清空时，清除结果
            if newValue.isEmpty {
                exactMatchResults = []
                prefixMatchResults = []
                fuzzyMatchResults = []
                hasTypeIdMatch = false
            }
        }
        .navigationTitle(NSLocalizedString("Main_Language_Map", comment: ""))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingSettings = true
                }) {
                    Image(systemName: "gear")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            LanguageMapSettingsView()
        }
        .onAppear {
            // 从UserDefaults读取选中的语言
            selectedLanguages =
                UserDefaults.standard.stringArray(forKey: LanguageMapConstants.languageMapDefaultsKey)
                    ?? LanguageMapConstants.languageMapDefaultLanguages
        }
    }

    /// 提取结果行视图为单独的组件
    private struct ResultRow: View {
        let result: (id: Int, names: [String: String])
        let availableLanguages: [String: String]
        @State private var selectedLanguages: [String] = LanguageMapConstants
            .languageMapDefaultLanguages

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(selectedLanguages.sorted(), id: \.self) { langCode in
                    if let name = result.names[langCode] {
                        HStack {
                            Text("\(availableLanguages[langCode] ?? langCode):")
                                .foregroundColor(.gray)
                                .frame(width: 80, alignment: .trailing)
                            Text(name)
                                .contextMenu {
                                    // 为每种选中的语言提供单独的复制按钮
                                    ForEach(selectedLanguages.sorted(), id: \.self) { lang in
                                        if let text = result.names[lang] {
                                            Button {
                                                UIPasteboard.general.string = text
                                            } label: {
                                                Label(
                                                    "\(NSLocalizedString("Misc_Copy", comment: "")) \(availableLanguages[lang] ?? lang)",
                                                    systemImage: "doc.on.doc"
                                                )
                                            }
                                        }
                                    }

                                    Divider()

                                    Button {
                                        // 构建所有选中语言的文本
                                        let allLanguagesText = selectedLanguages.sorted().compactMap { lang in
                                            if let text = result.names[lang] {
                                                return
                                                    "\(availableLanguages[lang] ?? lang): \(text)"
                                            }
                                            return nil
                                        }.joined(separator: "\n")

                                        UIPasteboard.general.string = allLanguagesText
                                    } label: {
                                        Label(
                                            NSLocalizedString(
                                                "Misc_Copy_All_Languages", comment: "复制所有语言"
                                            ),
                                            systemImage: "doc.on.doc.fill"
                                        )
                                    }
                                }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .onAppear {
                // 从UserDefaults读取选中的语言
                selectedLanguages =
                    UserDefaults.standard.stringArray(forKey: LanguageMapConstants.languageMapDefaultsKey)
                        ?? LanguageMapConstants.languageMapDefaultLanguages
            }
        }
    }

    private func performSearch() {
        guard !searchText.isEmpty else {
            exactMatchResults = []
            prefixMatchResults = []
            fuzzyMatchResults = []
            hasTypeIdMatch = false
            return
        }

        var exact: [(id: Int, names: [String: String])] = []
        var prefix: [(id: Int, names: [String: String])] = []
        var fuzzy: [(id: Int, names: [String: String])] = []

        hasTypeIdMatch = false
        let typeIdToSearch = Int(searchText)

        // 1) 物品（types）：支持 typeID 精确匹配分支
        searchLocalizedTable(
            tableName: "types", idColumn: "type_id", searchText: searchText,
            typeIdMatch: typeIdToSearch, exact: &exact, prefix: &prefix, fuzzy: &fuzzy
        )
        if typeIdToSearch != nil, !exact.isEmpty { hasTypeIdMatch = true }

        // 2) 星系 / 星座 / 星域（内存 LocalizedText 字典遍历）
        appendLocalizedMatches(
            from: SDEMemoryStore.solarSystemNames,
            searchText: searchText, exact: &exact, prefix: &prefix, fuzzy: &fuzzy
        )
        appendLocalizedMatches(
            from: SDEMemoryStore.constellationNames,
            searchText: searchText, exact: &exact, prefix: &prefix, fuzzy: &fuzzy
        )
        appendLocalizedMatches(
            from: SDEMemoryStore.regionNames,
            searchText: searchText, exact: &exact, prefix: &prefix, fuzzy: &fuzzy
        )

        // 3) 势力 / NPC 军团 / 目录 / 组（SQL LIKE，无 typeID 精确匹配分支）
        searchLocalizedTable(
            tableName: "factions", idColumn: "id", searchText: searchText,
            typeIdMatch: nil, exact: &exact, prefix: &prefix, fuzzy: &fuzzy
        )
        searchLocalizedTable(
            tableName: "npcCorporations", idColumn: "corporation_id", searchText: searchText,
            typeIdMatch: nil, exact: &exact, prefix: &prefix, fuzzy: &fuzzy
        )
        searchLocalizedTable(
            tableName: "categories", idColumn: "category_id", searchText: searchText,
            typeIdMatch: nil, exact: &exact, prefix: &prefix, fuzzy: &fuzzy
        )
        searchLocalizedTable(
            tableName: "groups", idColumn: "group_id", searchText: searchText,
            typeIdMatch: nil, exact: &exact, prefix: &prefix, fuzzy: &fuzzy
        )

        exactMatchResults = exact
        prefixMatchResults = prefix
        fuzzyMatchResults = fuzzy
    }

    /// 通用 SQL LIKE 搜索模板（8 语种 + 可选 typeID 精确匹配）
    private func searchLocalizedTable(
        tableName: String,
        idColumn: String,
        searchText: String,
        typeIdMatch: Int?,
        exact: inout [(id: Int, names: [String: String])],
        prefix: inout [(id: Int, names: [String: String])],
        fuzzy: inout [(id: Int, names: [String: String])]
    ) {
        let typeIDClause = (typeIdMatch != nil) ? "\(idColumn) = \(typeIdMatch!) OR " : ""
        let query = """
            SELECT DISTINCT \(idColumn), \(LocalizedText.typeLangNameColumns.joined(separator: ", ")),
                   LENGTH(en_name) as name_length
            FROM \(tableName)
            WHERE \(typeIDClause)
                  (de_name LIKE ? OR en_name LIKE ? OR es_name LIKE ? OR fr_name LIKE ?
                   OR ja_name LIKE ? OR ko_name LIKE ? OR ru_name LIKE ? OR zh_name LIKE ?)
            ORDER BY name_length, en_name
            LIMIT 200
        """
        let params = Array(repeating: "%\(searchText)%", count: 8)

        guard case let .success(rows) = DatabaseManager.shared.executeQuery(
            query, parameters: params, useCache: false
        ) else { return }

        for row in rows {
            guard let id = row[idColumn] as? Int else { continue }
            let names = localizedNamesDict(row: row)
            let result = (id: id, names: names)

            if typeIdMatch != nil, id == typeIdMatch! {
                exact.append(result)
            } else if isExactNameMatch(names: names, searchText: searchText) {
                exact.append(result)
            } else if isPrefixNameMatch(names: names, searchText: searchText) {
                prefix.append(result)
            } else {
                fuzzy.append(result)
            }
        }
    }

    /// 从 SQL 行字典中提取 8 语种名称
    private func localizedNamesDict(row: [String: Any]) -> [String: String] {
        var names: [String: String] = [:]
        for lang in ["de", "en", "es", "fr", "ja", "ko", "ru", "zh"] {
            if let value = row["\(lang)_name"] as? String, !value.isEmpty {
                names[lang] = value
            }
        }
        return names
    }

    private func localizedNamesDict(_ text: LocalizedText) -> [String: String] {
        [
            "de": text.de, "en": text.en, "es": text.es, "fr": text.fr,
            "ja": text.ja, "ko": text.ko, "ru": text.ru, "zh": text.zh,
        ].filter { !$0.value.isEmpty }
    }

    private func appendLocalizedMatches(
        from source: [Int: LocalizedText],
        searchText: String,
        exact: inout [(id: Int, names: [String: String])],
        prefix: inout [(id: Int, names: [String: String])],
        fuzzy: inout [(id: Int, names: [String: String])],
        limit: Int = 200
    ) {
        var matches: [(id: Int, names: [String: String], enLen: Int)] = []
        for (id, text) in source {
            guard text.matchesSearch(searchText) else { continue }
            matches.append((id, localizedNamesDict(text), text.en.count))
        }
        matches.sort {
            if $0.enLen != $1.enLen { return $0.enLen < $1.enLen }
            return ($0.names["en"] ?? "").localizedStandardCompare($1.names["en"] ?? "")
                == .orderedAscending
        }
        for match in matches.prefix(limit) {
            let result = (id: match.id, names: match.names)
            if isExactNameMatch(names: match.names, searchText: searchText) {
                exact.append(result)
            } else if isPrefixNameMatch(names: match.names, searchText: searchText) {
                prefix.append(result)
            } else {
                fuzzy.append(result)
            }
        }
    }

    /// 判断是否为名称完全匹配
    private func isExactNameMatch(names: [String: String], searchText: String) -> Bool {
        let lowercaseSearchText = searchText.lowercased()
        return names.values.contains { $0.lowercased() == lowercaseSearchText }
    }

    /// 判断是否为名称前缀匹配
    private func isPrefixNameMatch(names: [String: String], searchText: String) -> Bool {
        let lowercaseSearchText = searchText.lowercased()
        return names.values.contains { $0.lowercased().hasPrefix(lowercaseSearchText) }
    }
}
