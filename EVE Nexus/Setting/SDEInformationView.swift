import SwiftUI

struct SDEInformationView: View {
    @Environment(\.timeZone) private var displayTimeZone
    @AppStorage("selectedLanguage") private var selectedLanguage = "en"
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var installer = SDEUpdateManager.shared
    @ObservedObject private var checker = SDEUpdateChecker.shared
    @State private var version = AppConfiguration.Database.detailedVersionInfo?.fullVersion
    @State private var releaseDate = Self.installedMetadata?.releaseDate
    @State private var hasChanges = FileManager.default.fileExists(atPath: LocalSDELayout.whatsNewURL.path)
    @State private var showingChanges = false
    @State private var showingInstaller = false
    @State private var awaitingInitialCheck = true
    @State private var successPulse = false
    @State private var hadAvailableUpdate = SDEUpdateChecker.shared.updateStatus == .hasUpdate

    var body: some View {
        NavigationStack {
            List {
                Section {
                    informationRow(NSLocalizedString("SDE_Current_Version", comment: ""), value: version ?? NSLocalizedString("Unknown", comment: ""))
                    informationRow(NSLocalizedString("SDE_Package_Release_Date", comment: ""), value: displayReleaseDate)
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
                Section {
                    updatePanel
                } header: {
                    Text(NSLocalizedString("SDE_Update_Section", comment: ""))
                } footer: {
                    Text(footerText)
                        .font(.caption)
                        .accessibilityHidden(footerText.isEmpty)
                }
            }
            .listStyle(.insetGrouped)
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
            .onChange(of: isBusy) { old, busy in
                successPulse = old && !busy && !checker.checkFailed && checker.updateStatus == .noUpdate
            }
            .task(id: successPulse) {
                guard successPulse else { return }
                try? await Task.sleep(for: .seconds(1.2))
                guard !Task.isCancelled else { return }
                successPulse = false
            }
            .sensoryFeedback(.success, trigger: successPulse) { _, new in new }
            .task {
                // Render the sheet and finish its entrance before starting the automatic check.
                do { try await Task.sleep(for: .milliseconds(350)) }
                catch { return }
                await checker.checkForUpdates()
                awaitingInitialCheck = false
            }
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
        VStack(alignment: .leading, spacing: 18) {
            updateStatusRow
            if checker.updateStatus == .hasUpdate || (isBusy && hadAvailableUpdate) {
                if checker.currentSDEVersion != checker.latestSDEVersion {
                    informationRow(NSLocalizedString("SDE_Latest_Version", comment: ""), value: checker.latestSDEVersion)
                    if let date = checker.currentMetadata?.releaseDate, !date.isEmpty {
                        informationRow(NSLocalizedString("SDE_Package_Release_Date", comment: ""), value: formattedReleaseDate(date))
                    }
                }
                if checker.latestIconVersion > checker.currentIconVersion {
                    informationRow(NSLocalizedString("SDE_Icon_Package", comment: ""), value: "v\(checker.currentIconVersion) → v\(checker.latestIconVersion)")
                }
            }
            Button(action: performAction) {
                stableText(actionTitle, alternatives: actionTitles, alignment: .center)
                    .multilineTextAlignment(.center)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy || installer.isDownloading)
        }
        .padding(.vertical, 8)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.78), value: isBusy)
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.62), value: successPulse)
    }

    private func informationRow(_ title: String, value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                Text(title).foregroundStyle(.secondary).fixedSize()
                Spacer(minLength: 0)
                Text(value).fontWeight(.medium).multilineTextAlignment(.trailing).fixedSize()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title).foregroundStyle(.secondary)
                Text(value).fontWeight(.medium)
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// Measure all possible labels at the current width and Dynamic Type size.
    /// Hidden labels reserve space without adding duplicate accessibility content.
    private func stableText(_ value: String, alternatives: [String], alignment: Alignment = .leading) -> some View {
        ZStack(alignment: alignment) {
            ForEach(alternatives, id: \.self) { text in
                Text(text).fixedSize(horizontal: false, vertical: true)
                    .hidden().accessibilityHidden(true)
            }
            Text(value)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(reduceMotion ? .opacity : .numericText())
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.78), value: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value)
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

    /// Locale.current can retain the launch language after AppleLanguages changes.
    /// Observe the app preference and explicitly apply it to every displayed SDE date.
    private var dateFormatStyle: Date.FormatStyle {
        Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: displayTimeZone)
            .locale(Locale(identifier: selectedLanguage))
    }

    private var lastCheckedText: String {
        NSLocalizedString("SDE_Last_Checked", comment: "") + " "
            + (checker.lastCheckTime ?? Date()).formatted(dateFormatStyle)
    }

    private var footerText: String {
        if checker.checkFailed {
            return NSLocalizedString("SDE_Check_Unavailable", comment: "")
        }
        return checker.lastCheckTime == nil ? "" : lastCheckedText
    }

    private var isBusy: Bool {
        awaitingInitialCheck || checker.isChecking || checker.isButtonDisabled
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
                Circle()
                    .fill(statusColor.opacity(0.12))
                    .scaleEffect(successPulse && !reduceMotion ? 1.08 : 1)
                Image(systemName: statusSymbol)
                    .font(.title3)
                    .foregroundStyle(statusColor)
                    .id(statusSymbol)
                    .transition(.opacity)
                    .opacity(isBusy ? 0 : 1)
                ProgressView().opacity(isBusy ? 1 : 0)
            }
            .frame(width: 44, height: 44)
            .animation(.easeInOut(duration: 0.25), value: isBusy)
            .animation(.easeInOut(duration: 0.25), value: statusSymbol)
            .accessibilityHidden(true)
            stableText(statusTitle, alternatives: statusTitles)
                .font(.body.weight(.semibold))
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var statusSymbol: String {
        if checker.checkFailed {
            return "exclamationmark.circle"
        }
        switch checker.updateStatus {
        case .hasUpdate: return "arrow.down.circle.fill"
        case .noUpdate: return "checkmark.circle.fill"
        case .checking, .notChecked: return "arrow.triangle.2.circlepath"
        }
    }

    private var statusColor: Color {
        if isBusy {
            return .accentColor
        }
        if checker.checkFailed || checker.updateStatus == .hasUpdate {
            return .orange
        }
        return checker.updateStatus == .noUpdate ? .green : .accentColor
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
            return date.formatted(dateFormatStyle)
        }
        formatter.formatOptions.insert(.withFractionalSeconds)
        if let date = formatter.date(from: releaseDate) {
            return date.formatted(dateFormatStyle)
        }
        return releaseDate
    }

    private func reload() {
        version = AppConfiguration.Database.detailedVersionInfo?.fullVersion
        releaseDate = Self.installedMetadata?.releaseDate
        hasChanges = FileManager.default.fileExists(atPath: LocalSDELayout.whatsNewURL.path)
    }
}
