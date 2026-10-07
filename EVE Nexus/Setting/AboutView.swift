import SwiftUI

struct AboutView: View {
    private var appIcon: UIImage? {
        return AppIconConfig.composeAppIcon()
    }

    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? "Tritanium"
    }

    @State private var databaseVersionInfo: AppConfiguration.Database.VersionInfo?
    @State private var showingSDEInfo = false
    @ObservedObject private var updateChecker = SDEUpdateChecker.shared
    @State private var sdeSource: String?

    private func reloadSDESource() {
        sdeSource = MetadataManager.shared.readLocalMetadata()?.source
    }

    private var otherAboutItems: [AboutItem] {
        [
            AboutItem(
                title: NSLocalizedString("Main_About_Author", comment: ""),
                value: "iDea Center",
                icon: "person.fill",
                characterId: 96_873_368
            ),
            AboutItem(
                title: NSLocalizedString("Main_About_Github", comment: ""),
                value: "https://github.com/EstamelGG/EVE-Nexus",
                icon: "link",
                url: URL(string: "https://github.com/EstamelGG/EVE-Nexus")
            ),
            AboutItem(
                title: NSLocalizedString("Main_About_Report_Bug", comment: ""),
                value: "tritanium_support@icloud.com",
                icon: "envelope.fill",
                url: URL(string: "mailto:tritanium_support@icloud.com")
            ),
            AboutItem(
                title: NSLocalizedString("Main_About_copyright_Title", comment: ""),
                value: "Copyright.md",
                icon: "link",
                url: URL(
                    string:
                    "https://raw.githubusercontent.com/EstamelGG/EVE-Nexus/refs/heads/main/Copyright.md"
                )
            ),
            AboutItem(
                title: NSLocalizedString("Main_About_Acknowledgement", comment: ""),
                value: NSLocalizedString("Main_About_Acknowledgement_Text", comment: ""),
                icon: "person.fill",
                characterId: 2_119_399_734
            ),
        ]
    }

    var body: some View {
        List {
            // App Logo Section
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        if let icon = appIcon {
                            Image(uiImage: icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 80, height: 80)
                                .cornerRadius(20)
                                .shadow(color: Color.primary, radius: 5)
                        }

                        Text(appName)
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("v\(AppConfiguration.Version.fullVersion)")
                            .font(.system(.body, design: .monospaced))
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .padding(.vertical, 5)
            }

            // Database Version Section
            Section {
                if updateChecker.updateStatus == .hasUpdate {
                    Button {
                        showingSDEInfo = true
                    } label: {
                        DatabaseVersionRow(versionInfo: databaseVersionInfo, sdeSource: sdeSource)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    DatabaseVersionRow(versionInfo: databaseVersionInfo, sdeSource: sdeSource)
                }
            } footer: {
                Button {
                    showingSDEInfo = true
                } label: {
                    Label(NSLocalizedString("SDE_Info_View", comment: ""), systemImage: "info.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            // Information Section
            Section {
                ForEach(otherAboutItems) { item in
                    if let url = item.url {
                        Link(destination: url) {
                            AboutItemRow(item: item)
                        }
                    } else {
                        AboutItemRow(item: item)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .sheet(isPresented: $showingSDEInfo, onDismiss: {
            databaseVersionInfo = AppConfiguration.Database.detailedVersionInfo
            reloadSDESource()
        }) {
            SDEInformationView()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SDEDataUpdated")).receive(on: RunLoop.main)) { _ in
            databaseVersionInfo = AppConfiguration.Database.detailedVersionInfo
            reloadSDESource()
        }
        .task { await SDEUpdateChecker.shared.checkForUpdates() }
        .onAppear {
            databaseVersionInfo = AppConfiguration.Database.detailedVersionInfo
            reloadSDESource()
        }
    }
}

/// 数据库版本显示组件
struct DatabaseVersionRow: View {
    let versionInfo: AppConfiguration.Database.VersionInfo?
    var sdeSource: String?

    @StateObject private var updateChecker = SDEUpdateChecker.shared
    private var hasUpdate: Bool {
        updateChecker.updateStatus == .hasUpdate
    }

    private var isUsingBuiltInDatabase: Bool {
        StaticResourceManager.shared.shouldUseBundleSDE()
    }

    #if DEBUG
        /// SDE 安装来源 tag（仅 Debug 构建显示，用于区分 GitHub / CloudKit / 内置）
        @ViewBuilder
        private var sdeSourceTag: some View {
            if sdeSource == CloudKitMetadata.sourceGitHub {
                Text(NSLocalizedString("SDE_Source_GitHub", comment: "GitHub"))
                    .font(.system(size: 11))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.purple)
                    .cornerRadius(4)
            } else if sdeSource == CloudKitMetadata.sourceBundle {
                Text(NSLocalizedString("Main_About_Database_BuiltIn", comment: ""))
                    .font(.system(size: 11))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(red: 0.4, green: 0.7, blue: 1.0))
                    .cornerRadius(4)
            } else {
                Text(NSLocalizedString("SDE_Source_CloudKit", comment: "CloudKit"))
                    .font(.system(size: 11))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue)
                    .cornerRadius(4)
            }
        }
    #endif

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "server.rack")
                .foregroundColor(.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(NSLocalizedString("Main_About_Database_Version", comment: ""))
                        .font(.system(size: 15))
                        .foregroundColor(.primary)

                    if isUsingBuiltInDatabase {
                        Text(NSLocalizedString("Main_About_Database_BuiltIn", comment: ""))
                            .font(.system(size: 11))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(red: 0.4, green: 0.7, blue: 1.0))
                            .cornerRadius(4)
                    }
                    #if DEBUG
                        if !isUsingBuiltInDatabase {
                            sdeSourceTag
                        }
                    #endif

                    if hasUpdate {
                        Text(NSLocalizedString("Main_About_Database_Update_Available", comment: ""))
                            .font(.system(size: 13))
                            .foregroundColor(.orange)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: hasUpdate)

                if let info = versionInfo {
                    Text("\(NSLocalizedString("Main_About_Build_Number", comment: "")): \(info.fullVersion)")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)

                    if info.isPatchVersion, let patchNumber = info.patchNumber {
                        Text("\(NSLocalizedString("Main_About_Patch_Number", comment: "")): \(patchNumber)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text(NSLocalizedString("Unknown", comment: ""))
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                }
            }

            Spacer()
        }
        .padding(.vertical, 6)
    }
}

struct AboutItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let icon: String
    let url: URL?
    let characterId: Int?

    init(
        title: String,
        value: String,
        icon: String,
        url: URL? = nil,
        characterId: Int? = nil
    ) {
        self.title = title
        self.value = value
        self.icon = icon
        self.url = url
        self.characterId = characterId
    }
}

struct AboutItemRow: View {
    let item: AboutItem
    @State private var portrait: UIImage?
    @State private var isLoadingPortrait = true

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: item.icon)
                .foregroundColor(.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 15))
                Text(item.value)
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = item.value
                        } label: {
                            Label(
                                NSLocalizedString("Misc_Copy", comment: ""),
                                systemImage: "doc.on.doc"
                            )
                        }
                    }
            }

            if item.characterId != nil {
                Spacer()
                if let portrait = portrait {
                    Image(uiImage: portrait)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 42, height: 42)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 42, height: 42)
                        .overlay {
                            if isLoadingPortrait {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                }
            }
        }
        .padding(.vertical, 6)
        .task {
            if let characterId = item.characterId {
                do {
                    portrait = try await CharacterAPI.shared.fetchCharacterPortrait(
                        characterId: characterId
                    )
                } catch {
                    Logger.error("加载角色头像失败: \(error)")
                }
                isLoadingPortrait = false
            }
        }
    }
}
