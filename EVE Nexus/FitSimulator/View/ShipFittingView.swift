import SwiftUI

/// 定义配置视图类型枚举
enum FittingViewType: String, CaseIterable, Identifiable {
    case modules
    case drones
    case fighters
    case cargo
    case stats

    var id: String {
        rawValue
    }

    var localizedName: String {
        switch self {
        case .modules:
            return NSLocalizedString("Fitting_modules", comment: "Modules")
        case .drones:
            return NSLocalizedString("Fitting_drones", comment: "Drones")
        case .fighters:
            return NSLocalizedString("Fitting_fighters", comment: "Fighters")
        case .cargo:
            return NSLocalizedString("Fitting_cargo", comment: "Cargo")
        case .stats:
            return NSLocalizedString("Fitting_stats", comment: "Stats")
        }
    }
}

struct ShipFittingView: View {
    private enum Entry {
        case new(shipTypeId: Int, shipInfo: (name: String, iconFileName: String))
        case local(fittingId: UUID)
        case online(CharacterFitting)
        case temporary(LocalFitting)
    }

    @State private var viewModel: FittingEditorViewModel?

    private let entry: Entry
    private let databaseManager: DatabaseManager

    init(
        shipTypeId: Int, shipInfo: (name: String, iconFileName: String),
        databaseManager: DatabaseManager
    ) {
        entry = .new(shipTypeId: shipTypeId, shipInfo: shipInfo)
        self.databaseManager = databaseManager
    }

    init(fittingId: UUID, databaseManager: DatabaseManager) {
        entry = .local(fittingId: fittingId)
        self.databaseManager = databaseManager
    }

    init(onlineFitting: CharacterFitting, databaseManager: DatabaseManager) {
        entry = .online(onlineFitting)
        self.databaseManager = databaseManager
    }

    init(temporaryFitting: LocalFitting, databaseManager: DatabaseManager) {
        entry = .temporary(temporaryFitting)
        self.databaseManager = databaseManager
    }

    var body: some View {
        ZStack {
            if let viewModel {
                FittingEditorPage(viewModel: viewModel, databaseManager: databaseManager)
                    .transition(Self.detailContentTransition)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(Self.loadingTransition)
            }
        }
        .task { await loadViewModel() }
    }

    private static let switchAnimation: Animation = .easeInOut(duration: 0.38)
    private static let loadingTransition: AnyTransition = .opacity
    private static let detailContentTransition: AnyTransition = .opacity

    private func loadViewModel() async {
        guard viewModel == nil else { return }
        let skills = await FittingCharacterSkillsLoader.loadSkillsBeforeFittingCalculation()
        await MainActor.run {
            let vm: FittingEditorViewModel
            switch entry {
            case let .new(shipTypeId, shipInfo):
                vm = FittingEditorViewModel(
                    shipTypeId: shipTypeId,
                    shipInfo: shipInfo,
                    databaseManager: databaseManager,
                    characterSkills: skills
                )
            case let .local(fittingId):
                vm = FittingEditorViewModel(
                    fittingId: fittingId,
                    databaseManager: databaseManager,
                    characterSkills: skills
                )
            case let .online(onlineFitting):
                vm = FittingEditorViewModel(
                    onlineFitting: onlineFitting,
                    databaseManager: databaseManager,
                    characterSkills: skills
                )
            case let .temporary(localFitting):
                vm = FittingEditorViewModel(
                    temporaryFitting: localFitting,
                    databaseManager: databaseManager,
                    characterSkills: skills
                )
            }
            withAnimation(Self.switchAnimation) {
                viewModel = vm
            }
        }
    }
}

private struct FittingEditorPage: View {
    @ObservedObject var viewModel: FittingEditorViewModel
    let databaseManager: DatabaseManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var successfulSaveCount = 0
    @State private var showingSettings = false
    @State private var selectedViewType: FittingViewType = .modules
    @State private var showingExitConfirmation = false
    @State private var showingSaveError = false

    private var showsSavedCheckmark: Bool {
        successfulSaveCount > 0 && !viewModel.hasUnsavedChanges
    }

    private var fittingName: String {
        viewModel.simulationInput.name.isEmpty ? viewModel.shipInfo.name : viewModel.simulationInput.name
    }

    var body: some View {
        fittingBody(viewModel: viewModel)
            .navigationTitle(fittingName)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Text(fittingName)
                            .lineLimit(1)
                        if viewModel.hasUnsavedChanges {
                            Text(NSLocalizedString("Fitting_Unsaved", comment: ""))
                                .foregroundStyle(.orange)
                                .fixedSize()
                        }
                    }
                    .font(.headline)
                    .accessibilityElement(children: .combine)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: requestExit) {
                        Label(NSLocalizedString("Fitting_Back", comment: ""), systemImage: "chevron.left")
                    }
                }
            }
            .safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
                Button {
                    save()
                } label: {
                    Label {
                        Text(NSLocalizedString("Misc_Save", comment: ""))
                    } icon: {
                        Image(systemName: showsSavedCheckmark ? "checkmark" : "square.and.arrow.down")
                            .foregroundStyle(showsSavedCheckmark ? Color.green : Color.white)
                            .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                    }
                    .font(.headline)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(Capsule().fill(Color.accentColor))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                .disabled(!viewModel.canSaveConfiguration)
                .opacity(viewModel.canSaveConfiguration || showsSavedCheckmark ? 1 : 0.5)
                .animation(reduceMotion ? nil : .easeInOut(duration: 1), value: showsSavedCheckmark)
                .padding(.trailing, 20)
                .padding(.vertical, 12)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: successfulSaveCount)
            .background(FittingExitGuard(isDirty: viewModel.hasUnsavedChanges, onExitAttempt: requestExit))
            .alert(NSLocalizedString("Fitting_Unsaved_Exit_Title", comment: ""), isPresented: $showingExitConfirmation) {
                Button(NSLocalizedString("Fitting_Save_And_Exit", comment: "")) {
                    if save() {
                        dismiss()
                    }
                }
                Button(NSLocalizedString("Fitting_Discard_And_Exit", comment: ""), role: .destructive) { dismiss() }
                Button(NSLocalizedString("Fitting_Continue_Editing", comment: ""), role: .cancel) {}
            } message: {
                Text(NSLocalizedString("Fitting_Unsaved_Exit_Message", comment: ""))
            }
            .alert(NSLocalizedString("Fitting_Local_Save_Failed", comment: ""), isPresented: $showingSaveError) {
                Button(NSLocalizedString("Common_OK", comment: "")) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .onDisappear {
                clearSelectorPreferences(viewModel: viewModel)
                NotificationCenter.default.post(name: NSNotification.Name("RefreshLocalFittings"), object: nil)
            }
    }

    private func requestExit() {
        if viewModel.hasUnsavedChanges {
            showingExitConfirmation = true
        } else {
            dismiss()
        }
    }

    @discardableResult
    private func save() -> Bool {
        let saved = viewModel.saveConfiguration()
        if saved {
            successfulSaveCount += 1
        } else {
            showingSaveError = true
        }
        return saved
    }

    private func fittingBody(viewModel: FittingEditorViewModel) -> some View {
        VStack(spacing: 0) {
            Picker("ViewType", selection: $selectedViewType) {
                ForEach(getFittingViewTypes(viewModel: viewModel)) { viewType in
                    Text(viewType.localizedName).tag(viewType)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            .padding(.vertical, 8)

            switch selectedViewType {
            case .modules:
                ShipFittingModulesView(viewModel: viewModel)
            case .drones:
                ShipFittingDronesView(viewModel: viewModel)
            case .fighters:
                ShipFittingFightersView(viewModel: viewModel)
            case .cargo:
                ShipFittingCargoView(viewModel: viewModel)
            case .stats:
                ShipFittingStatsView(viewModel: viewModel)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                FittingSettingsView(
                    databaseManager: viewModel.databaseManager,
                    shipTypeID: viewModel.simulationInput.ship.typeId,
                    fittingName: viewModel.simulationInput.name,
                    fittingData: [
                        "name": viewModel.simulationInput.name,
                    ],
                    onNameChanged: { updatedData in
                        if let name = updatedData["name"] as? String {
                            viewModel.updateName(name)
                            Logger.info("配置名称已更新，等待保存: \(name)")
                        }
                    },
                    onSkillModeChanged: {
                        Logger.info("技能模式已更改")
                    },
                    viewModel: viewModel,
                    onDelete: {
                        deleteFitting(viewModel: viewModel)
                    }
                )
            }
        }
    }

    private func getFittingViewTypes(viewModel: FittingEditorViewModel) -> [FittingViewType] {
        var viewTypes = [FittingViewType]()
        viewTypes.append(.modules)
        viewTypes.append(.drones)

        if let fighterTubes = viewModel.simulationInput.ship.baseAttributesByName["fighterTubes"],
           fighterTubes > 0
        {
            viewTypes.append(.fighters)
        }

        viewTypes.append(.cargo)
        viewTypes.append(.stats)

        return viewTypes
    }

    private func deleteFitting(viewModel: FittingEditorViewModel) {
        Logger.info(
            "开始删除配置: \(viewModel.simulationInput.name) (ID: \(viewModel.simulationInput.fittingId.debugDescription))"
        )

        if viewModel.isLocalFitting {
            deleteLocalFitting(viewModel: viewModel)
        } else {
            deleteOnlineFitting(viewModel: viewModel)
        }
    }

    private func deleteLocalFitting(viewModel: FittingEditorViewModel) {
        guard case let .local(fittingId) = viewModel.simulationInput.fittingId
        else {
            Logger.error("删除本地配置失败: 装配引用不是本地 UUID")
            return
        }

        do {
            let filePath = try FitConvert.localFittingFileURL(fittingId: fittingId)
            try FileManager.default.removeItem(at: filePath)
            Logger.info("本地配置文件删除成功: \(filePath.path)")
            dismiss()
        } catch {
            Logger.error("删除本地配置文件失败: \(error.localizedDescription)")
        }
    }

    private func deleteOnlineFitting(viewModel: FittingEditorViewModel) {
        let currentCharacterId = UserDefaults.standard.integer(forKey: "currentCharacterId")
        guard currentCharacterId != 0 else {
            Logger.error("删除在线配置失败: 没有当前角色")
            return
        }

        guard case let .online(fittingId) = viewModel.simulationInput.fittingId
        else {
            Logger.error("删除在线配置失败: 装配引用不是在线 ESI ID")
            return
        }

        FittingDeletionCacheManager.shared.addDeletedFitting(
            fittingId: fittingId,
            characterId: currentCharacterId
        )

        Logger.info("在线装配配置已标记为删除 - ID: \(fittingId)，已添加到5分钟删除缓存")

        NotificationCenter.default.post(
            name: NSNotification.Name("RefreshOnlineFittings"),
            object: nil,
            userInfo: ["characterId": currentCharacterId]
        )

        dismiss()

        Task {
            do {
                try await CharacterFittingAPI.deleteCharacterFitting(
                    characterID: currentCharacterId,
                    fittingID: fittingId
                )
                Logger.info("后台API删除成功 - ID: \(fittingId)")
            } catch {
                Logger.error("后台API删除失败: \(error)")
            }
        }
    }

    private func clearSelectorPreferences(viewModel: FittingEditorViewModel) {
        UserDefaults.standard.removeObject(forKey: "LastVisitedHighSlotGroupID")
        UserDefaults.standard.removeObject(forKey: "LastHighSlotSearchKeyword")

        UserDefaults.standard.removeObject(forKey: "LastVisitedMidSlotGroupID")
        UserDefaults.standard.removeObject(forKey: "LastMidSlotSearchKeyword")

        UserDefaults.standard.removeObject(forKey: "LastVisitedLowSlotGroupID")
        UserDefaults.standard.removeObject(forKey: "LastLowSlotSearchKeyword")

        let shipTypeId = viewModel.simulationInput.ship.typeId

        UserDefaults.standard.removeObject(forKey: "LastVisitedHighSlotGroupID_\(shipTypeId)")
        UserDefaults.standard.removeObject(forKey: "LastHighSlotSearchKeyword_\(shipTypeId)")

        UserDefaults.standard.removeObject(forKey: "LastVisitedMidSlotGroupID_\(shipTypeId)")
        UserDefaults.standard.removeObject(forKey: "LastMidSlotSearchKeyword_\(shipTypeId)")

        UserDefaults.standard.removeObject(forKey: "LastVisitedLowSlotGroupID_\(shipTypeId)")
        UserDefaults.standard.removeObject(forKey: "LastLowSlotSearchKeyword_\(shipTypeId)")

        UserDefaults.standard.removeObject(forKey: "LastVisitedRigSlotGroupID_\(shipTypeId)")
        UserDefaults.standard.removeObject(forKey: "LastRigSlotSearchKeyword_\(shipTypeId)")

        UserDefaults.standard.removeObject(forKey: "LastVisitedSubSysSlotGroupID_\(shipTypeId)")
        UserDefaults.standard.removeObject(forKey: "LastSubSysSlotSearchKeyword_\(shipTypeId)")

        UserDefaults.standard.synchronize()
        Logger.info("已清理所有装备选择器状态，飞船ID：\(shipTypeId)")
    }
}
