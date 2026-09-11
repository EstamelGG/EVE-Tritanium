import SwiftUI

struct FittingSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var fittingName: String = ""
    let databaseManager: DatabaseManager
    let shipTypeID: Int
    @State private var shipItem: DatabaseListItem?
    @State private var fittingData: [String: Any]
    let onNameChanged: ([String: Any]) -> Void
    @ObservedObject var viewModel: FittingEditorViewModel
    let onDelete: (() -> Void)?

    @AppStorage("currentCharacterId") private var currentCharacterId: Int = 0
    @AppStorage("selectedDatabaseLanguage") private var selectedDatabaseLanguage: String = "en"
    var onSkillModeChanged: (() -> Void)?

    /// 从 viewModel 中读取和保存技能选择状态
    private var skillsMode: String {
        get { viewModel.currentSkillsMode }
        nonmutating set { viewModel.currentSkillsMode = newValue }
    }

    private var selectedCharacterId: Int? {
        get { viewModel.currentSelectedCharacterId }
        nonmutating set { viewModel.currentSelectedCharacterId = newValue }
    }

    // 添加UI状态管理
    @State private var isExportingToESI = false
    @State private var showingSuccessAlert = false
    @State private var showingErrorAlert = false
    @State private var showingConfirmAlert = false
    @State private var alertMessage = ""

    // 删除配置相关状态
    @State private var showingDeleteConfirmAlert = false
    @State private var isDeletingFitting = false

    // 缺失技能 -> 添加到技能计划（弹窗输入名称）
    @State private var showAddToSkillPlanAlert = false
    @State private var addToSkillPlanName = ""
    @State private var showAddToSkillPlanSuccessAlert = false
    @State private var savedSkillPlanName = ""

    // 环境效果待提交状态（在关闭设置页时统一提交）
    @State private var pendingEnvironmentTypeId: Int?
    @State private var pendingEnvironmentItem: DatabaseListItem?
    @State private var hasInitializedEnvironment = false

    init(
        databaseManager: DatabaseManager, shipTypeID: Int, fittingName: String,
        fittingData: [String: Any], onNameChanged: @escaping ([String: Any]) -> Void,
        onSkillModeChanged: (() -> Void)? = nil, viewModel: FittingEditorViewModel,
        onDelete: (() -> Void)? = nil
    ) {
        self.databaseManager = databaseManager
        self.shipTypeID = shipTypeID
        _fittingName = State(initialValue: fittingName)
        _fittingData = State(initialValue: fittingData)
        self.onNameChanged = onNameChanged
        self.onSkillModeChanged = onSkillModeChanged
        self.viewModel = viewModel
        self.onDelete = onDelete
    }

    /// 是否使用角色技能（当前角色或指定角色），用于决定是否显示缺失技能
    private var isUsingCharacterSkills: Bool {
        switch skillsMode {
        case "current_char": return currentCharacterId != 0
        case "character": return selectedCharacterId != nil
        default: return false
        }
    }

    private var environmentModeText: String {
        if let item = pendingEnvironmentItem {
            return item.name
        }
        if let effect = viewModel.simulationInput.environmentEffects.first {
            return effect.name
        }
        return NSLocalizedString("Environment_None", comment: "无")
    }

    private func loadPendingEnvironmentFromViewModel() {
        guard let effect = viewModel.simulationInput.environmentEffects.first else {
            pendingEnvironmentTypeId = nil
            pendingEnvironmentItem = nil
            return
        }

        let enName = fetchEnvironmentEnglishName(typeId: effect.typeId) ?? effect.name
        let category = EnvironmentEffectNaming.category(for: effect.typeId) ?? .other
        let displayName = EnvironmentEffectNaming.displayName(
            typeId: effect.typeId,
            enName: enName,
            fallbackName: effect.name,
            category: category
        )

        pendingEnvironmentTypeId = effect.typeId
        pendingEnvironmentItem = DatabaseListItem(
            id: effect.typeId,
            name: displayName,
            enName: enName,
            iconFileName: effect.iconFileName ?? "not_found",
            published: true,
            categoryID: 0
        )
    }

    private func fetchEnvironmentEnglishName(typeId: Int) -> String? {
        guard let info = ItemInfoMap.typeInfo(for: typeId) else { return nil }
        if !info.enName.isEmpty { return info.enName }
        return info.name.isEmpty ? nil : info.name
    }

    private func commitPendingEnvironmentSelection() {
        let previousTypeId = viewModel.simulationInput.environmentEffects.first?.typeId
        let newTypeId = pendingEnvironmentTypeId

        guard previousTypeId != newTypeId else {
            return
        }

        if let typeId = newTypeId {
            guard let effect = FitConvert.loadEnvironmentEffect(
                typeId: typeId,
                databaseManager: databaseManager
            ) else {
                Logger.warning("无法加载环境效果: typeId=\(typeId)")
                return
            }

            viewModel.simulationInput.environmentEffects = [effect]
            Logger.info("环境效果已更新: \(effect.name)")
        } else {
            viewModel.simulationInput.environmentEffects = []
            Logger.info("已清空环境效果")
        }

        viewModel.calculateAttributes()
        viewModel.hasUnsavedChanges = true
        viewModel.saveConfiguration()
    }

    private var skillModeText: String {
        switch skillsMode {
        case "current_char":
            if currentCharacterId != 0,
               let character = EVELogin.shared.getCharacterByID(currentCharacterId)?.character
            {
                return character.CharacterName
            }
            return String.localizedStringWithFormat(NSLocalizedString("Fitting_All_Skills", comment: "全5级"), 5)
        case "all5":
            return String.localizedStringWithFormat(NSLocalizedString("Fitting_All_Skills", comment: "全5级"), 5)
        case "all4":
            return String.localizedStringWithFormat(NSLocalizedString("Fitting_All_Skills", comment: ""), 4)
        case "all3":
            return String.localizedStringWithFormat(NSLocalizedString("Fitting_All_Skills", comment: ""), 3)
        case "all2":
            return String.localizedStringWithFormat(NSLocalizedString("Fitting_All_Skills", comment: ""), 2)
        case "all1":
            return String.localizedStringWithFormat(NSLocalizedString("Fitting_All_Skills", comment: ""), 1)
        case "all0":
            return String.localizedStringWithFormat(NSLocalizedString("Fitting_All_Skills", comment: ""), 0)
        case "character":
            if let charId = selectedCharacterId {
                let chars = CharacterSkillsUtils.getAllCharacters(excludeCurrentCharacter: false)
                Logger.debug("skillModeText - 查找角色 \(charId)，可用角色数: \(chars.count)")
                if let character = chars.first(where: { $0.id == charId }) {
                    Logger.debug("skillModeText - 找到角色: \(character.name)")
                    return character.name
                } else {
                    Logger.warning("skillModeText - 未找到角色 \(charId)")
                }
            } else {
                Logger.warning("skillModeText - selectedCharacterId 为 nil")
            }
            return String.localizedStringWithFormat(NSLocalizedString("Fitting_All_Skills", comment: "全5级"), 5)
        default:
            return String.localizedStringWithFormat(NSLocalizedString("Fitting_All_Skills", comment: "全5级"), 5)
        }
    }

    @ViewBuilder
    private var missingSkillsSection: some View {
        let missing = viewModel.getMissingSkillsForFitting()
        let allRequired = viewModel.getAllRequiredSkillsForFitting()
        Section(header: Text(NSLocalizedString("Fitting_Missing_Skills", comment: "缺失技能"))) {
            if missing.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(NSLocalizedString("Fitting_No_Missing_Skills", comment: "无缺失技能"))
                        .foregroundColor(.secondary)
                }
            } else {
                ForEach(missing, id: \.skillID) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.skillName)
                                .font(.body)
                            Text(
                                String.localizedStringWithFormat(
                                    NSLocalizedString("Fitting_Missing_Skill_Level", comment: ""),
                                    item.currentLevel,
                                    item.requiredLevel
                                )
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("Lv.\(item.requiredLevel)")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }

            // 有装配所需技能时始终显示添加按钮（生成完整技能队列，含已满足和未满足）
            if !allRequired.isEmpty {
                Button {
                    addToSkillPlanName = ""
                    showAddToSkillPlanAlert = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text(NSLocalizedString("Fitting_Add_To_Skill_Plan", comment: "添加到技能计划"))
                    }
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        .alert(NSLocalizedString("Fitting_Add_To_Skill_Plan", comment: "添加到技能计划"), isPresented: $showAddToSkillPlanAlert) {
            TextField(NSLocalizedString("Main_Skills_Plan_Name", comment: "计划名称"), text: $addToSkillPlanName)
            Button(NSLocalizedString("Main_EVE_Mail_Cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("Misc_Save", comment: "保存")) {
                saveMissingSkillsToPlan(name: addToSkillPlanName.trimmingCharacters(in: .whitespaces))
            }
        } message: {
            Text(
                String.localizedStringWithFormat(
                    NSLocalizedString("Fitting_All_Skills_Count", comment: "装配所需技能共 %d 项"),
                    viewModel.getAllRequiredSkillsForFitting().count
                )
            )
        }
        .alert(NSLocalizedString("Fitting_Add_To_Skill_Plan_Success", comment: ""), isPresented: $showAddToSkillPlanSuccessAlert) {
            Button(NSLocalizedString("Misc_Done", comment: "")) {}
        } message: {
            Text(
                String.localizedStringWithFormat(
                    NSLocalizedString("Fitting_Add_To_Skill_Plan_Saved_Message", comment: ""),
                    savedSkillPlanName
                )
            )
        }
    }

    private func saveMissingSkillsToPlan(name: String) {
        guard !name.isEmpty else { return }
        let allRequiredSkills = viewModel.getAllRequiredSkillsForFitting()
        let charId = skillsMode == "current_char" ? currentCharacterId : (selectedCharacterId ?? 0)

        Task {
            if let savedName = await AddFittingSkillsToPlanSheet.saveMissingSkillsToPlan(
                missingSkills: allRequiredSkills,
                characterId: charId,
                planName: name,
                databaseManager: databaseManager
            ) {
                await MainActor.run {
                    savedSkillPlanName = savedName
                    showAddToSkillPlanSuccessAlert = true
                }
            }
        }
    }

    var body: some View {
        List {
            Section(header: Text(NSLocalizedString("Fitting_Setting_Ship", comment: ""))) {
                TextField(NSLocalizedString("Fitting_Name", comment: ""), text: $fittingName)
                    .textFieldStyle(.plain)
                    .onChange(of: fittingName) { _, newValue in
                        var updatedData = fittingData
                        updatedData["name"] = newValue
                        fittingData = updatedData
                        onNameChanged(updatedData)
                    }

                if let shipItem = shipItem {
                    NavigationLink {
                        // 获取计算后的飞船属性
                        let shipOutputAttributes = viewModel.simulationOutput?.ship.attributes
                        ShowItemInfo(
                            databaseManager: databaseManager,
                            itemID: shipTypeID,
                            modifiedAttributes: shipOutputAttributes
                        )
                    } label: {
                        DatabaseListItemView(
                            item: shipItem,
                            showDetails: true
                        )
                    }
                }
            }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

            Section(header: Text(NSLocalizedString("Fitting_Setting_Skills", comment: "技能设置"))) {
                NavigationLink {
                    CharacterSkillsSelectorView(
                        databaseManager: databaseManager,
                        onSelectSkills: { skills, skillModeName, characterId in
                            // 更新技能模式
                            if characterId == 0 {
                                // 虚拟角色情况 (All 5/4/3/2/1/0)
                                if skillModeName.contains("5") {
                                    skillsMode = "all5"
                                } else if skillModeName.contains("4") {
                                    skillsMode = "all4"
                                } else if skillModeName.contains("3") {
                                    skillsMode = "all3"
                                } else if skillModeName.contains("2") {
                                    skillsMode = "all2"
                                } else if skillModeName.contains("1") {
                                    skillsMode = "all1"
                                } else if skillModeName.contains("0") {
                                    skillsMode = "all0"
                                }
                                selectedCharacterId = nil
                            } else if characterId == currentCharacterId {
                                // 当前角色情况
                                skillsMode = "current_char"
                                selectedCharacterId = nil
                            } else {
                                // 其他角色情况
                                skillsMode = "character"
                                selectedCharacterId = characterId
                            }

                            // 确定技能类型
                            var skillType: CharacterSkillsType
                            if characterId == 0 {
                                if skillModeName.contains("5") {
                                    skillType = .all5
                                } else if skillModeName.contains("4") {
                                    skillType = .all4
                                } else if skillModeName.contains("3") {
                                    skillType = .all3
                                } else if skillModeName.contains("2") {
                                    skillType = .all2
                                } else if skillModeName.contains("1") {
                                    skillType = .all1
                                } else {
                                    skillType = .all0
                                }
                            } else if characterId == currentCharacterId {
                                skillType = .current_char
                            } else {
                                skillType = .character(characterId)
                            }

                            // 更新视图模型中的技能数据
                            viewModel.updateCharacterSkills(skills: skills, sourceType: skillType)

                            // 执行技能模式更改回调
                            onSkillModeChanged?()
                        }
                    )
                } label: {
                    HStack {
                        Image("skill")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                        Text(NSLocalizedString("Fitting_Skills_Mode", comment: "技能模式"))
                        Spacer()
                        Text(skillModeText)
                            .foregroundColor(.secondary)
                    }
                }
            }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

            Section(header: Text(NSLocalizedString("Fitting_Setting_Environment", comment: "环境设置"))) {
                NavigationLink {
                    EnvironmentSettingsView(
                        databaseManager: databaseManager,
                        viewModel: viewModel,
                        selectedTypeId: $pendingEnvironmentTypeId,
                        pendingSelectionItem: $pendingEnvironmentItem,
                        onCommit: commitPendingEnvironmentSelection
                    )
                } label: {
                    HStack {
                        Image("location")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                        Text(NSLocalizedString("Fitting_Environment_Mode", comment: "天文环境"))
                        Spacer()
                        Text(environmentModeText)
                            .foregroundColor(.secondary)
                    }
                }
            }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

            // 缺失技能（仅在使用角色技能时显示）
            if isUsingCharacterSkills {
                missingSkillsSection
            }

            Section(header: Text(NSLocalizedString("Fitting_Setting_Implants", comment: "植入体设置"))) {
                NavigationLink {
                    ImplantSettingsView(
                        databaseManager: databaseManager,
                        viewModel: viewModel
                    )
                } label: {
                    HStack {
                        Image("implants")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                        Text(NSLocalizedString("Fitting_Implants_Mode", comment: "查看/编辑植入体"))
                    }
                }
            }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

            Section {
                Button {
                    showingConfirmAlert = true
                } label: {
                    HStack {
                        if isExportingToESI {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text(
                                NSLocalizedString(
                                    "Fitting_Exporting_To_ESI", comment: "正在上传到ESI..."
                                )
                            )
                            .foregroundColor(.secondary)
                            .font(.system(size: 17))
                        } else {
                            Text(NSLocalizedString("Fitting_Export_To_ESI", comment: "导出到ESI"))
                                .foregroundColor(.blue)
                                .font(.system(size: 17))
                        }
                        Spacer()
                    }
                }
                .disabled(isExportingToESI || currentCharacterId == 0)
                .contentShape(Rectangle())
                .listRowSeparator(.visible, edges: .bottom)
                .listRowSeparatorTint(Color(UIColor.separator))

                Button {
                    exportToClipboard(useEnglishNames: false)
                } label: {
                    HStack {
                        Text(NSLocalizedString("Fitting_Export_To_Clipboard", comment: "导出到剪贴板"))
                            .foregroundColor(.blue)
                            .font(.system(size: 17))
                        Spacer()
                    }
                }
                .contentShape(Rectangle())
                .listRowSeparator(.visible, edges: .bottom)
                .listRowSeparatorTint(Color(UIColor.separator))

                if selectedDatabaseLanguage != "en" {
                    Button {
                        exportToClipboard(useEnglishNames: true)
                    } label: {
                        HStack {
                            Text("Fitting_Export_To_Clipboard_en")
                                .foregroundColor(.blue)
                                .font(.system(size: 17))
                            Spacer()
                        }
                    }
                    .contentShape(Rectangle())
                    .listRowSeparator(.visible, edges: .bottom)
                    .listRowSeparatorTint(Color(UIColor.separator))
                }

                Button {
                    exportToImage()
                } label: {
                    HStack {
                        Text(NSLocalizedString("Fitting_Export_To_Image", comment: "导出到图片"))
                            .foregroundColor(.blue)
                            .font(.system(size: 17))
                        Spacer()
                    }
                }
                .contentShape(Rectangle())
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Main_Setting_Title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if onDelete != nil {
                    Button {
                        showingDeleteConfirmAlert = true
                    } label: {
                        if isDeletingFitting {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                    }
                    .disabled(isDeletingFitting)
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.primary)
                }
            }
        }
        .alert(
            NSLocalizedString("Fitting_Upload_Success_Title", comment: "导出成功"),
            isPresented: $showingSuccessAlert
        ) {
            Button(NSLocalizedString("Common_OK", comment: "确定")) {}
        } message: {
            Text(alertMessage)
        }
        .alert(
            NSLocalizedString("Fitting_Upload_Failed_Title", comment: "导出失败"),
            isPresented: $showingErrorAlert
        ) {
            Button(NSLocalizedString("Common_OK", comment: "确定")) {}
        } message: {
            Text(alertMessage)
        }
        .alert(
            NSLocalizedString("Fitting_Upload_Confirm_Title", comment: "确认上传"),
            isPresented: $showingConfirmAlert
        ) {
            Button(NSLocalizedString("Fitting_Upload_Cancel", comment: "取消"), role: .cancel) {}
            Button(NSLocalizedString("Fitting_Upload_Confirm", comment: "确认上传"), role: .destructive) {
                exportToESI()
            }
        } message: {
            Text(
                String(
                    format: NSLocalizedString(
                        "Fitting_Upload_Confirm_Message", comment: "将配置上传到EVE游戏内？"
                    ),
                    viewModel.simulationInput.name.isEmpty
                        ? NSLocalizedString("Fitting_Unnamed_Fitting", comment: "未命名配置")
                        : viewModel.simulationInput.name
                )
            )
        }
        .fittingDeleteConfirmation(
            message: String(
                format: NSLocalizedString(
                    "Fitting_Delete_Confirm_Message", comment: "确定要删除配置吗？"
                ),
                viewModel.simulationInput.name.isEmpty
                    ? NSLocalizedString("Fitting_Unnamed_Fitting", comment: "未命名配置")
                    : viewModel.simulationInput.name
            ),
            isPresented: $showingDeleteConfirmAlert,
            onConfirm: {
                deleteFitting()
            }
        )
        .onAppear {
            shipItem = DatabaseListItem(
                typeID: shipTypeID,
                databaseManager: databaseManager
            )

            if !hasInitializedEnvironment {
                hasInitializedEnvironment = true
                loadPendingEnvironmentFromViewModel()
            }
        }
        .onDisappear {
            commitPendingEnvironmentSelection()
        }
    }

    // MARK: - 导出方法

    /// 导出配置到ESI
    private func exportToESI() {
        // 检查是否有当前角色
        guard currentCharacterId != 0 else {
            Logger.error("导出到ESI失败: 没有当前角色")
            alertMessage = NSLocalizedString(
                "Fitting_Upload_No_Character", comment: "请先登录角色后再尝试上传配置"
            )
            showingErrorAlert = true
            return
        }

        // 设置加载状态
        isExportingToESI = true

        Task {
            do {
                Logger.info("开始导出配置到ESI - 配置名称: \(viewModel.simulationInput.name)")

                // 将SimulationInput转换为CharacterFitting格式
                let characterFitting = FitConvert.simulationInputToCharacterFitting(
                    input: viewModel.simulationInput
                )

                // 上传到EVE服务器
                let newFittingId = try await CharacterFittingAPI.uploadCharacterFitting(
                    characterID: currentCharacterId,
                    fitting: characterFitting
                )

                Logger.info("配置上传成功 - 新装配ID: \(newFittingId)")

                // 在主线程显示成功消息
                await MainActor.run {
                    isExportingToESI = false
                    alertMessage = String(
                        format: NSLocalizedString(
                            "Fitting_Upload_Success_Message", comment: "配置已成功上传到EVE"
                        ), newFittingId
                    )
                    showingSuccessAlert = true
                }

            } catch {
                Logger.error("导出配置到ESI失败: \(error)")

                // 在主线程显示错误消息
                await MainActor.run {
                    isExportingToESI = false
                    alertMessage = String(
                        format: NSLocalizedString("Fitting_Upload_Failed_Message", comment: "上传失败"),
                        error.localizedDescription
                    )
                    showingErrorAlert = true
                }
            }
        }
    }

    /// 导出配置到剪贴板
    /// - Parameter useEnglishNames: 是否使用英文名称导出（用于非英文SDE时导出兼容EFT/Pyfa的格式）
    private func exportToClipboard(useEnglishNames: Bool = false) {
        // 将 SimulationInput 转换为 LocalFitting
        let localFitting = FitConvert.simulationInputToLocalFitting(
            input: viewModel.simulationInput
        )

        // 使用 FitConvert 的 localFittingToEFT 方法生成 EFT 格式文本
        let clipboardText = FitConvert.localFittingToEFT(
            localFitting: localFitting, databaseManager: databaseManager,
            useEnglishNames: useEnglishNames
        )

        // 将文本复制到剪贴板
        UIPasteboard.general.string = clipboardText

        // 显示成功提示
        alertMessage = NSLocalizedString("Fitting_Export_Clipboard_Success", comment: "配置已复制到剪贴板")
        showingSuccessAlert = true

        Logger.info("配置已导出到剪贴板")
        Logger.info("clipboardText: \(clipboardText)")
    }

    /// 导出配置到图片
    private func exportToImage() {
        Logger.info("开始直接导出装配到相册")

        Task {
            do {
                // 创建用于渲染的完整内容视图
                let contentView = VStack(spacing: 0) {
                    // 飞船信息区域
                    VStack(spacing: 12) {
                        HStack(spacing: 16) {
                            Image(
                                uiImage: IconManager.shared.loadUIImage(
                                    for: viewModel.shipInfo.iconFileName
                                )
                            )
                            .resizable()
                            .frame(width: 64, height: 64)
                            .cornerRadius(8)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(viewModel.shipInfo.name)
                                    .font(.title2)
                                    .fontWeight(.semibold)

                                Text(
                                    viewModel.simulationInput.name.isEmpty
                                        ? NSLocalizedString("Unnamed", comment: "")
                                        : viewModel.simulationInput.name
                                )
                                .font(.headline)
                                .foregroundColor(.secondary)
                            }

                            Spacer()
                        }
                    }
                    .padding()
                    .background(Color(.systemGroupedBackground))

                    // 装备模块区域
                    ModulesExportSection(viewModel: viewModel)

                    // 植入体区域
                    if !viewModel.simulationInput.implants.isEmpty {
                        Divider()
                            .padding(.vertical, 8)
                        ImplantsExportSection(viewModel: viewModel)
                    }

                    // 无人机区域
                    if !(viewModel.simulationOutput?.drones.isEmpty ?? true) {
                        Divider()
                            .padding(.vertical, 8)
                        DronesExportSection(viewModel: viewModel)
                    }

                    // 货舱区域
                    if !viewModel.simulationInput.cargo.items.isEmpty {
                        Divider()
                            .padding(.vertical, 8)
                        CargoExportSection(viewModel: viewModel)
                    }

                    // 舰载机区域
                    if let fighters = viewModel.simulationOutput?.fighters, !fighters.isEmpty {
                        Divider()
                            .padding(.vertical, 8)
                        FightersExportSection(viewModel: viewModel)
                    }

                    // 状态信息区域前的分割线
                    Divider()
                        .padding(.vertical, 8)

                    // 状态信息区域 - 使用原有的状态组件
                    VStack(spacing: 16) {
                        // 资源统计
                        ShipResourcesStatsView(viewModel: viewModel)

                        // 抗性统计
                        ShipResistancesStatsView(viewModel: viewModel)

                        // 电容统计
                        ShipCapacitorStatsView(viewModel: viewModel)

                        // 火力统计
                        ShipFirepowerStatsView(viewModel: viewModel)

                        // 维修统计
                        ShipRepairStatsView(viewModel: viewModel)

                        // 其他属性
                        ShipMiscStatsView(viewModel: viewModel)

                        // 货仓属性
                        ShipAllCargoView(viewModel: viewModel)
                    }
                    .padding(.horizontal)

                    // Footer信息
                    FooterView()
                }
                .frame(width: 425)
                .fixedSize(horizontal: false, vertical: true)
                .background(Color(.systemGroupedBackground))
                // 明确设置当前颜色模式
                .environment(\.colorScheme, colorScheme)

                // 使用ImageRenderer渲染
                let renderer = ImageRenderer(content: contentView)
                renderer.scale = 4.0 // 分辨率

                if let uiImage = renderer.uiImage {
                    // 保存到相册
                    try await saveImageToPhotoLibrary(uiImage)

                    await MainActor.run {
                        alertMessage = NSLocalizedString(
                            "Fitting_Export_Photo_Success", comment: "装配图片已保存到相册"
                        )
                        showingSuccessAlert = true
                        Logger.info("装配图片已成功保存到相册")
                    }
                } else {
                    throw NSError(
                        domain: "FittingSettingsView", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "无法生成图片"]
                    )
                }
            } catch {
                Logger.error("导出装配图片失败: \(error)")
                await MainActor.run {
                    alertMessage = String(
                        format: NSLocalizedString("Fitting_Export_Failed_Message", comment: ""),
                        error.localizedDescription
                    )
                    showingErrorAlert = true
                }
            }
        }
    }

    /// 保存图片到相册
    private func saveImageToPhotoLibrary(_ image: UIImage) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            // 创建一个临时类来处理保存回调
            class SaveImageTarget: NSObject {
                let continuation: CheckedContinuation<Void, Error>

                init(continuation: CheckedContinuation<Void, Error>) {
                    self.continuation = continuation
                }

                @objc func image(
                    _: UIImage, didFinishSavingWithError error: Error?,
                    contextInfo _: UnsafeRawPointer
                ) {
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }

            let target = SaveImageTarget(continuation: continuation)
            UIImageWriteToSavedPhotosAlbum(
                image, target,
                #selector(SaveImageTarget.image(_:didFinishSavingWithError:contextInfo:)), nil
            )
        }
    }

    /// 删除配置
    private func deleteFitting() {
        guard let deleteHandler = onDelete else {
            Logger.error("删除配置失败: 没有删除处理器")
            return
        }

        isDeletingFitting = true

        Logger.info("开始删除配置: \(viewModel.simulationInput.name)")

        // 调用删除处理器（会处理本地或在线配置的删除，并自动关闭页面）
        deleteHandler()

        // 关闭设置页面
        dismiss()

        Logger.info("配置删除处理完成")
    }
}

// MARK: - Footer视图

struct FooterView: View {
    /// 获取应用版本信息
    private var appVersion: String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return version
        }
        return "1.0.0"
    }

    /// 格式化当前时间
    private var currentTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale.current
        return formatter.string(from: Date())
    }

    var body: some View {
        VStack(spacing: 8) {
            Divider()
                .padding(.horizontal)

            VStack(spacing: 4) {
                // 第一行：应用信息
                Text(
                    String(
                        format: NSLocalizedString("Fitting_Export_Generated_By", comment: ""),
                        "Tritanium", appVersion
                    )
                )
                .font(.caption)
                .foregroundColor(.secondary)

                // 第二行：时间信息
                Text(
                    String(
                        format: NSLocalizedString("Fitting_Export_Generated_Time", comment: ""),
                        currentTime
                    )
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
    }
}
