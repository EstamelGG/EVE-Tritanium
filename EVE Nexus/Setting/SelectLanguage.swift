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
    private enum CheckFeedback: Equatable {
        case idle, checking, upToDate
    }

    let appLanguages: [(code: String, name: String)] = [
        ("en", "English"),
        ("zh-Hans", "中文"),
        ("ru", "Русский (Beta)"),
    ]

    @AppStorage("selectedLanguage") private var selectedLanguage: String = "en"
    @AppStorage("selectedDatabaseLanguage") private var selectedDatabaseLanguage: String = "en"
    @ObservedObject var databaseManager: DatabaseManager
    @StateObject private var updateChecker = SDEUpdateChecker.shared
    @State private var showingSDEUpdateSheet = false
    @State private var checkFeedback: CheckFeedback = .idle
    @State private var checkIconBounce = 0
    @State private var successPulse = false
    @State private var switchingDatabaseLanguage: String? = nil

    var body: some View {
        List {
            Section {
                checkUpdateRow
            }

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
        .animation(.easeInOut(duration: 0.25), value: updateChecker.updateStatus)
        .animation(.spring(response: 0.35, dampingFraction: 0.78), value: checkFeedback)
        .sheet(isPresented: $showingSDEUpdateSheet) {
            SDEUpdateDetailView()
        }
        .sensoryFeedback(.success, trigger: checkFeedback) { _, new in
            new == .upToDate
        }
    }

    private var checkUpdateRow: some View {
        Button {
            Task { await checkSDEUpdate() }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(checkIconBackground)
                        .frame(width: 36, height: 36)
                        .scaleEffect(successPulse ? 1.08 : 1)

                    Group {
                        switch checkFeedback {
                        case .checking:
                            ProgressView()
                                .controlSize(.small)
                        case .upToDate:
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.green)
                                .symbolEffect(.bounce, value: checkIconBounce)
                        case .idle:
                            Image(systemName: updateChecker.updateStatus == .hasUpdate
                                ? "arrow.down.circle.fill"
                                : "arrow.triangle.2.circlepath")
                                .font(.title3)
                                .foregroundStyle(updateChecker.updateStatus == .hasUpdate ? Color.orange : Color.accentColor)
                                .symbolEffect(.rotate, options: .nonRepeating, value: checkIconBounce)
                        }
                    }
                    .id(checkFeedback)
                    .transition(.scale.combined(with: .opacity))
                }
                .animation(.spring(response: 0.34, dampingFraction: 0.62), value: successPulse)

                VStack(alignment: .leading, spacing: 3) {
                    Text(checkTitle)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())

                    Text(checkSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }

                Spacer(minLength: 8)

                trailingBadge
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(checkFeedback == .checking || updateChecker.isButtonDisabled)
    }

    private var checkIconBackground: Color {
        switch checkFeedback {
        case .upToDate: return Color.green.opacity(0.12)
        case .checking: return Color.accentColor.opacity(0.1)
        case .idle:
            return updateChecker.updateStatus == .hasUpdate
                ? Color.orange.opacity(0.12)
                : Color.accentColor.opacity(0.1)
        }
    }

    private var checkTitle: String {
        switch checkFeedback {
        case .checking:
            return NSLocalizedString("SDE_Checking_Update", comment: "正在检查更新...")
        case .upToDate:
            return NSLocalizedString("SDE_Already_Latest", comment: "")
        case .idle:
            return updateChecker.updateStatus == .hasUpdate
                ? String(localized: "SDE_View_Update", defaultValue: "查看可用更新")
                : NSLocalizedString("SDE_Check_Update", comment: "检查 SDE 更新")
        }
    }

    private var checkSubtitle: String {
        switch checkFeedback {
        case .checking:
            return String(localized: "SDE_Checking_Subtitle", defaultValue: "正在连接 CloudKit…")
        case .upToDate:
            return String(localized: "SDE_Already_Latest_Hint", defaultValue: "数据包已是最新")
        case .idle:
            if let last = updateChecker.lastCheckTime {
                return String(
                    format: String(localized: "SDE_Last_Checked", defaultValue: "上次检查：%@"),
                    last.formatted(date: .abbreviated, time: .shortened)
                )
            }
            return String(localized: "SDE_Check_Hint", defaultValue: "点按检查数据包与图标更新")
        }
    }

    @ViewBuilder
    private var trailingBadge: some View {
        switch checkFeedback {
        case .upToDate:
            Text(String(localized: "SDE_Status_Latest", defaultValue: "最新"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.12), in: Capsule())
                .transition(.scale.combined(with: .opacity))
        case .idle where updateChecker.updateStatus == .hasUpdate:
            Text(String(localized: "SDE_Status_Update", defaultValue: "可更新"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.12), in: Capsule())
                .transition(.scale.combined(with: .opacity))
        case .checking, .idle:
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
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

    private func checkSDEUpdate() async {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            checkFeedback = .checking
        }
        checkIconBounce += 1

        await updateChecker.forceCheckForUpdates()

        if updateChecker.updateStatus == .hasUpdate {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                checkFeedback = .idle
            }
            showingSDEUpdateSheet = true
            return
        }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.68)) {
            checkFeedback = .upToDate
            successPulse = true
        }
        checkIconBounce += 1

        try? await Task.sleep(nanoseconds: 2_200_000_000)

        withAnimation(.easeInOut(duration: 0.28)) {
            successPulse = false
            checkFeedback = .idle
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
