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
    @State private var showingSettings = false
    @State private var selectedViewType: FittingViewType = .modules
    @Environment(\.dismiss) private var dismiss

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
                fittingBody(viewModel: viewModel)
                    .transition(Self.detailContentTransition)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(Self.loadingTransition)
            }
        }
        .navigationTitle(viewModel?.shipInfo.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadViewModel()
        }
        .onDisappear {
            if let viewModel {
                clearSelectorPreferences(viewModel: viewModel)
            }
            // 返回配置列表时刷新本地配置（详情内改名/删除后立即反映）
            NotificationCenter.default.post(
                name: NSNotification.Name("RefreshLocalFittings"),
                object: nil
            )
        }
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
                            viewModel.saveConfiguration()
                            Logger.info("配置名称更新并保存: \(name)")
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

    /// 仅用于「加载中 → 配置详情」切换，不影响导航栈其它动画。
    private static let switchAnimation: Animation = .easeInOut(duration: 0.38)

    private static let loadingTransition: AnyTransition = .opacity

    private static let detailContentTransition: AnyTransition = .opacity

    private func loadViewModel() async {
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

        guard
            let documentsDirectory = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first
        else {
            Logger.error("删除本地配置失败: 无法访问文档目录")
            return
        }

        let fittingsDirectory = documentsDirectory.appendingPathComponent("Fitting")
        let filePath = fittingsDirectory.appendingPathComponent(
            "local_fitting_\(fittingId.uuidString).json"
        )

        do {
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
