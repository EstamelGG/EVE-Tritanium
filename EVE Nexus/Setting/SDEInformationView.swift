import SwiftUI

struct SDEInformationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var installer = SDEUpdateManager.shared
    @ObservedObject private var checker = SDEUpdateChecker.shared
    @State private var version = AppConfiguration.Database.detailedVersionInfo?.fullVersion
    @State private var releaseDate = Self.installedMetadata?.releaseDate
    @State private var hasChanges = FileManager.default.fileExists(atPath: LocalSDELayout.whatsNewURL.path)
    @State private var showingChanges = false
    @State private var showingInstaller = false
    @State private var hadAvailableUpdate = SDEUpdateChecker.shared.updateStatus == .hasUpdate

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent(NSLocalizedString("SDE_Current_Version", comment: "")) {
                        Text(version ?? NSLocalizedString("Unknown", comment: ""))
                    }
                    LabeledContent(NSLocalizedString("SDE_Package_Release_Date", comment: "")) {
                        Text(displayReleaseDate).multilineTextAlignment(.trailing)
                    }
                    if hasChanges {
                        Button {
                            showingChanges = true
                        } label: {
                            HStack {
                                Label(NSLocalizedString("SDE_View_Changes", comment: ""), systemImage: "doc.text.magnifyingglass")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(minHeight: 32)
                        }
                    }
                } header: {
                    Text(NSLocalizedString("SDE_Installed_Section", comment: ""))
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                updatePanel
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: checker.updateStatus)
            .navigationTitle(NSLocalizedString("SDE_Info_Title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("SDE_Done", comment: "")) { dismiss() }
                }
            }
            .onChange(of: checker.updateStatus) { _, status in
                if status != .checking {
                    hadAvailableUpdate = status == .hasUpdate
                }
            }
            .task { await checker.checkForUpdates() }
            .sheet(isPresented: $showingChanges) { SDEChangesView() }
            .sheet(isPresented: $showingInstaller, onDismiss: reload) {
                DownloadProgressView(
                    iconsState: installer.iconsState,
                    sdeState: installer.sdeState,
                    iconsVersion: "v\(checker.latestIconVersion)",
                    sdeVersion: checker.latestSDEVersion,
                    hasError: installer.hasError,
                    isCompleted: installer.isCompleted,
                    onExit: {
                        showingInstaller = false
                        installer.reset()
                    }
                )
                .interactiveDismissDisabled()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SDEDataUpdated")).receive(on: RunLoop.main)) { _ in
                reload()
            }
        }
    }

    private var updatePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString("SDE_Update_Section", comment: ""))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 12) {
                updateStatusRow
                if checker.updateStatus == .hasUpdate || (isBusy && hadAvailableUpdate) {
                    if checker.currentSDEVersion != checker.latestSDEVersion {
                        LabeledContent(NSLocalizedString("SDE_Latest_Version", comment: ""), value: checker.latestSDEVersion)
                        if let date = checker.currentMetadata?.releaseDate, !date.isEmpty {
                            LabeledContent(NSLocalizedString("SDE_Package_Release_Date", comment: "")) {
                                Text(formattedReleaseDate(date)).multilineTextAlignment(.trailing)
                            }
                        }
                    }
                    if checker.latestIconVersion > checker.currentIconVersion {
                        LabeledContent(NSLocalizedString("SDE_Icon_Package", comment: ""), value: "v\(checker.currentIconVersion) → v\(checker.latestIconVersion)")
                    }
                }
                Button(action: performAction) {
                    stableText(actionTitle, alternatives: actionTitles, alignment: .center)
                        .multilineTextAlignment(.center)
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy || installer.isDownloading)
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            stableText(footerText, alternatives: [
                NSLocalizedString("SDE_Check_Unavailable", comment: ""),
                lastCheckedText,
            ])
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .accessibilityHidden(footerText.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .systemGroupedBackground))
        .overlay(alignment: .top) { Divider() }
        .transaction { $0.animation = nil }
    }

    /// Measure all possible labels at the current width and Dynamic Type size.
    /// Hidden labels reserve space without adding duplicate accessibility content.
    private func stableText(_ value: String, alternatives: [String], alignment: Alignment = .leading) -> some View {
        ZStack(alignment: alignment) {
            ForEach(alternatives, id: \.self) { text in
                Text(text).fixedSize(horizontal: false, vertical: true)
                    .hidden().accessibilityHidden(true)
            }
            Text(value).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actionTitles: [String] {
        [NSLocalizedString("SDE_Checking_Update", comment: ""),
         NSLocalizedString("SDE_Install_Update", comment: ""),
         NSLocalizedString("SDE_Retry_Check", comment: ""),
         NSLocalizedString("SDE_Check_Update", comment: "")]
    }

    private var statusTitles: [String] {
        [NSLocalizedString("SDE_Checking_Update", comment: ""),
         NSLocalizedString("SDE_Check_Failed_Title", comment: ""),
         NSLocalizedString("Main_About_Database_Update_Available", comment: ""),
         NSLocalizedString("SDE_Already_Latest", comment: ""),
         NSLocalizedString("SDE_Check_Ready", comment: "")]
    }

    private var lastCheckedText: String {
        NSLocalizedString("SDE_Last_Checked", comment: "") + " "
            + (checker.lastCheckTime ?? Date()).formatted(date: .abbreviated, time: .shortened)
    }

    private var footerText: String {
        if checker.checkFailed {
            return NSLocalizedString("SDE_Check_Unavailable", comment: "")
        }
        return checker.lastCheckTime == nil ? "" : lastCheckedText
    }

    private var isBusy: Bool {
        checker.isChecking || checker.isButtonDisabled
    }

    private var actionTitle: String {
        if isBusy {
            return NSLocalizedString("SDE_Checking_Update", comment: "")
        }
        if checker.updateStatus == .hasUpdate {
            return NSLocalizedString("SDE_Install_Update", comment: "")
        }
        if checker.checkFailed {
            return NSLocalizedString("SDE_Retry_Check", comment: "")
        }
        return NSLocalizedString("SDE_Check_Update", comment: "")
    }

    private var updateStatusRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Image(systemName: checker.checkFailed ? "exclamationmark.circle" : checker.updateStatus == .hasUpdate ? "arrow.down.circle.fill" : checker.updateStatus == .noUpdate ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                    .font(.title2)
                    .foregroundStyle(checker.checkFailed || checker.updateStatus == .hasUpdate ? Color.orange : checker.updateStatus == .noUpdate ? Color.green : Color.secondary)
                    .opacity(isBusy ? 0 : 1)
                ProgressView().opacity(isBusy ? 1 : 0)
            }
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
            stableText(statusTitle, alternatives: statusTitles)
                .font(.headline)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var statusTitle: String {
        if isBusy {
            return NSLocalizedString("SDE_Checking_Update", comment: "")
        }
        if checker.checkFailed {
            return NSLocalizedString("SDE_Check_Failed_Title", comment: "")
        }
        switch checker.updateStatus {
        case .hasUpdate: return NSLocalizedString("Main_About_Database_Update_Available", comment: "")
        case .noUpdate: return NSLocalizedString("SDE_Already_Latest", comment: "")
        case .checking: return NSLocalizedString("SDE_Checking_Update", comment: "")
        case .notChecked: return NSLocalizedString("SDE_Check_Ready", comment: "")
        }
    }

    private func performAction() {
        guard !isBusy, !installer.isDownloading else { return }
        if checker.updateStatus == .hasUpdate {
            showingInstaller = true
            installer.startUpdate()
        } else {
            Task { await checker.forceCheckForUpdates() }
        }
    }

    private static var installedMetadata: CloudKitMetadata? {
        if StaticResourceManager.shared.shouldUseBundleSDE() {
            return MetadataManager.shared.readMetadataFromBundle()
        }
        return MetadataManager.shared.readLocalMetadata()
    }

    private var displayReleaseDate: String {
        formattedReleaseDate(releaseDate)
    }

    private func formattedReleaseDate(_ releaseDate: String?) -> String {
        guard let releaseDate, !releaseDate.isEmpty else { return NSLocalizedString("Unknown", comment: "") }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: releaseDate) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        formatter.formatOptions.insert(.withFractionalSeconds)
        if let date = formatter.date(from: releaseDate) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return releaseDate
    }

    private func reload() {
        version = AppConfiguration.Database.detailedVersionInfo?.fullVersion
        releaseDate = Self.installedMetadata?.releaseDate
        hasChanges = FileManager.default.fileExists(atPath: LocalSDELayout.whatsNewURL.path)
    }
}
