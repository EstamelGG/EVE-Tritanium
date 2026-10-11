import SwiftUI

// MARK: - 数据库语言数据模型

private struct DBLanguage: Identifiable {
    let code: String
    let name: String
    let englishName: String?
    var id: String {
        code
    }
}

private let allDBLanguages: [DBLanguage] = [
    DBLanguage(code: "en", name: "English", englishName: nil),
    DBLanguage(code: "zh-Hans", name: "中文", englishName: nil),
    DBLanguage(code: "de", name: "Deutsch", englishName: "German"),
    DBLanguage(code: "es", name: "Español", englishName: "Spanish"),
    DBLanguage(code: "fr", name: "Français", englishName: "French"),
    DBLanguage(code: "ja", name: "日本語", englishName: "Japanese"),
    DBLanguage(code: "ko", name: "한국어", englishName: "Korean"),
    DBLanguage(code: "ru", name: "Русский", englishName: "Russian"),
]

// MARK: - APP 语言选项

struct LanguageOptionView: View {
    let language: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        HStack {
            Text(language)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundColor(.accentColor)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .animation(.spring(response: 0.32, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - SelectLanguageView

struct SelectLanguageView: View {
    let appLanguages: [(code: String, name: String)] = [
        ("en", "English"),
        ("zh-Hans", "中文"),
        ("ru", "Русский (Beta)"),
    ]

    @AppStorage("selectedLanguage") private var selectedLanguage: String = "en"
    @AppStorage("selectedDatabaseLanguage") private var selectedDatabaseLanguage: String = "en"
    @ObservedObject var databaseManager: DatabaseManager
    @State private var switchingDatabaseLanguage: String? = nil

    var body: some View {
        List {
            Section {
                ForEach(appLanguages, id: \.code) { lang in
                    LanguageOptionView(
                        language: lang.name,
                        isSelected: selectedLanguage == lang.code,
                        onTap: {
                            if selectedLanguage != lang.code {
                                applyLanguageChange(code: lang.code)
                            }
                        }
                    )
                }
            } header: {
                Text("APP")
                    .font(.headline)
                    .foregroundColor(.primary)
            }

            Section {
                ForEach(allDBLanguages) { lang in
                    databaseLanguageRow(lang)
                }
            } header: {
                Text(NSLocalizedString("Main_Setting_Database_Language", comment: "数据库语言"))
                    .font(.headline)
                    .foregroundColor(.primary)
            }
        }
        .navigationTitle(NSLocalizedString("Main_Setting_Select_Language", comment: ""))
    }

    @ViewBuilder
    private func databaseLanguageRow(_ lang: DBLanguage) -> some View {
        let isSelected = selectedDatabaseLanguage == lang.code
        let isSwitching = switchingDatabaseLanguage == lang.code

        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(lang.name)
                    .foregroundColor(.primary)
                if let englishName = lang.englishName {
                    Text(englishName)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if isSwitching {
                ProgressView()
                    .controlSize(.small)
                    .transition(.scale.combined(with: .opacity))
            } else if isSelected {
                Image(systemName: "checkmark")
                    .foregroundColor(.accentColor)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: isSelected)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: isSwitching)
        .onTapGesture {
            guard !isSelected, switchingDatabaseLanguage == nil else { return }
            applyDatabaseLanguageChange(code: lang.code)
        }
    }

    private func applyLanguageChange(code: String) {
        selectedLanguage = code
        UserDefaults.standard.set([code], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()

        if let languageBundlePath = Bundle.main.path(forResource: code, ofType: "lproj"),
           Bundle(path: languageBundlePath) != nil
        {
            Bundle.setLanguage(code)
        }

        databaseManager.clearCache()
        databaseManager.loadDatabase()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NotificationCenter.default.post(
                name: NSNotification.Name("LanguageChanged"), object: nil
            )
        }
    }

    private func applyDatabaseLanguageChange(code: String) {
        switchingDatabaseLanguage = code
        Task { @MainActor in
            await Task.yield() // 先让对勾位显示加载指示器

            selectedDatabaseLanguage = code
            databaseManager.clearCache()
            databaseManager.loadDatabase()
            switchingDatabaseLanguage = nil

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(
                    name: NSNotification.Name("DatabaseLanguageChanged"), object: nil
                )
            }
        }
    }
}

// MARK: - Bundle 扩展

extension Bundle {
    private static var bundle: Bundle?

    static func setLanguage(_ language: String) {
        defer {
            object_setClass(Bundle.main, AnyLanguageBundle.self)
        }

        guard let path = Bundle.main.path(forResource: language, ofType: "lproj") else {
            bundle = nil
            return
        }

        bundle = Bundle(path: path)
    }

    static func localizedBundle() -> Bundle! {
        return bundle ?? Bundle.main
    }
}

@objc final class AnyLanguageBundle: Bundle, @unchecked Sendable {
    private static let fallbackLanguage = "en"

    override func localizedString(forKey key: String, value: String?, table tableName: String?)
        -> String
    {
        guard let bundle = Bundle.localizedBundle() else {
            return super.localizedString(forKey: key, value: value, table: tableName)
        }

        let fallbackValue = value ?? ""
        let result = bundle.localizedString(forKey: key, value: fallbackValue, table: tableName)
        // NSLocalizedString 默认 value 为空串，未找到时返回 ""；部分调用可能传 key。两种都视为未找到，回退英文
        let notFound = result.isEmpty || result == key
        if notFound, let enPath = Bundle.main.path(forResource: Self.fallbackLanguage, ofType: "lproj"),
           let enBundle = Bundle(path: enPath)
        {
            let enResult = enBundle.localizedString(forKey: key, value: key, table: tableName)
            if enResult != key {
                return enResult
            }
        }
        // 都未找到时：有 value 用 value，否则用 key，避免显示空
        return result.isEmpty ? (fallbackValue.isEmpty ? key : fallbackValue) : result
    }
}
