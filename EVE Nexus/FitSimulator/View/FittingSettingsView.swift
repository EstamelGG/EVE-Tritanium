import SwiftUI

struct FittingSettingsView: View {
    @Environment(\.locale) private var displayLocale
    @Environment(\.timeZone) private var displayTimeZone
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var fittingName: String = ""
    @State private var draftFittingName = ""
    @State private var showingRenameAlert = false
    @State private var showingShipInfo = false
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
        if !info.enName.isEmpty {
            return info.enName
        }
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
            Section(header: Text(NSLocalizedString("Fitting_Settings_Header", comment: "装配设置"))) {
                Button {
                    draftFittingName = fittingName
                    showingRenameAlert = true
                } label: {
                    HStack {
                        Text(fittingName.isEmpty ? NSLocalizedString("Fitting_Unnamed_Fitting", comment: "") : fittingName)
                            .foregroundStyle(.primary)
                        Spacer()
                        HStack(spacing: 4) {
                            Text(NSLocalizedString("Fitting_Settings_Edit", comment: "编辑"))
                            Image(systemName: "square.and.pencil")
                        }
                        .foregroundStyle(.blue)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if let shipItem {
                    Button {
                        showingShipInfo = true
                    } label: {
                        HStack {
                            DatabaseListItemView(item: shipItem, showDetails: true)
                            Spacer(minLength: 8)
                            HStack(spacing: 4) {
                                Text(NSLocalizedString("Fitting_Settings_About", comment: "关于"))
                                Image(systemName: "info.circle")
                            }
                            .foregroundStyle(.blue)
                            .fixedSize()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

            Section(header: Text(NSLocalizedString("Fitting_Setting_Skills", comment: "技能设置"))) {
                NavigationLink {
                    CharacterSkillsSelectorView(
                        databaseManager: databaseManager,
                        selectedSkillsMode: skillsMode,
                        selectedCharacterId: selectedCharacterId,
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
                    HStack(spacing: 12) {
                        Image("skill")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString("Fitting_Skills_Mode", comment: "技能模式"))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Text(skillModeText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                }
            }.listRowInsets(EdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18))

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
                    HStack(spacing: 12) {
                        Image("location")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString("Fitting_Environment_Mode", comment: "天文环境"))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Text(environmentModeText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                }
            }.listRowInsets(EdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18))

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

            if onDelete != nil && viewModel.canDeleteConfiguration {
                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirmAlert = true
                    } label: {
                        HStack {
                            Spacer()
                            if isDeletingFitting {
                                ProgressView()
                                    .tint(.red)
                            } else {
                                Label(NSLocalizedString("Misc_Delete", comment: "删除"), systemImage: "trash")
                            }
                            Spacer()
                        }
                        .foregroundStyle(.red)
                        .contentShape(Rectangle())
                    }
                    .listRowBackground(Color.red.opacity(0.12))
                    .disabled(isDeletingFitting)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Main_Setting_Title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showingShipInfo) {
            ShowItemInfo(
                databaseManager: databaseManager,
                itemID: shipTypeID,
                modifiedAttributes: viewModel.simulationOutput?.ship.attributes,
                fittingContext: viewModel.simulationOutput?.attributeContext(for: viewModel.simulationOutput?.originalInput.ship.instanceId)
            )
        }
        .background {
            FittingNameAlert(isPresented: $showingRenameAlert, initialName: draftFittingName) { name in
                guard name != fittingName else { return }
                fittingName = name
                fittingData["name"] = name
                onNameChanged(fittingData)
            }
        }
        .toolbar {
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

                    // 双栏采用独立高度，按顶部对齐，避免左右互相拉伸。
                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: 0) {
                            // 装备模块区域
                            ModulesExportSection(viewModel: viewModel)

                            // 植入体区域
                            if !viewModel.simulationInput.implants.isEmpty {
                                Divider()
                                    .padding(.vertical, 4)
                                ImplantsExportSection(viewModel: viewModel)
                            }

                            // 无人机区域
                            if !(viewModel.simulationOutput?.drones.isEmpty ?? true) {
                                Divider()
                                    .padding(.vertical, 4)
                                DronesExportSection(viewModel: viewModel)
                            }

                            // 货舱区域
                            if !viewModel.simulationInput.cargo.items.isEmpty {
                                Divider()
                                    .padding(.vertical, 4)
                                CargoExportSection(viewModel: viewModel)
                            }

                            // 舰载机区域
                            if let fighters = viewModel.simulationOutput?.fighters, !fighters.isEmpty {
                                Divider()
                                    .padding(.vertical, 4)
                                FightersExportSection(viewModel: viewModel)
                            }
                        }
                        .frame(width: 440)
                        .fixedSize(horizontal: false, vertical: true)
                        .overlay(alignment: .trailing) {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.2))
                                .frame(width: 1)
                        }

                        // 状态信息区域 - 使用原有的状态组件
                        VStack(alignment: .leading, spacing: 12) {
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
                        .frame(width: 412)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 16)

                    // Footer信息
                    FooterView()
                }
                .frame(width: 900)
                .fixedSize(horizontal: false, vertical: true)
                .background(Color(.systemGroupedBackground))
                // 明确设置当前颜色模式
                .environment(\.colorScheme, colorScheme)

                // 使用ImageRenderer渲染
                let renderer = ImageRenderer(content: contentView)
                // 先获取布局尺寸，不绘制位图。长图固定 4 倍渲染可能超过
                // 渲染或相册显示链路的纹理尺寸限制，即使保存成功也可能显示黑图。
                var contentSize = CGSize.zero
                renderer.render { size, _ in
                    contentSize = size
                }
                guard contentSize.width.isFinite, contentSize.height.isFinite,
                      contentSize.width > 0, contentSize.height > 0
                else {
                    throw NSError(
                        domain: "FittingSettingsView", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "图片布局尺寸无效: \(contentSize)"]
                    )
                }
                let preferredScale: CGFloat = 4
                // 保守的兼容性预算，并非所有设备的实际硬件上限。
                let maximumPixelDimension: CGFloat = 8192
                renderer.scale = min(
                    preferredScale,
                    maximumPixelDimension / max(contentSize.width, contentSize.height)
                )

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
    @Environment(\.locale) private var displayLocale
    @Environment(\.timeZone) private var displayTimeZone
    /// 获取应用版本信息
    private var appVersion: String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return version
        }
        return "1.0.0"
    }

    /// 格式化当前时间
    private var currentTime: String {
        return FormatUtil.formatDate(Date(), dateStyle: .medium, timeStyle: .short)
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

/// Native alert text field provides an inline clear button without changing the rename flow.
private struct FittingNameAlert: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let initialName: String
    let onSave: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context _: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        guard isPresented, context.coordinator.alert == nil else { return }
        let coordinator = context.coordinator
        DispatchQueue.main.async {
            guard isPresented, controller.view.window != nil, coordinator.alert == nil else { return }
            let alert = UIAlertController(title: NSLocalizedString("Misc_Rename", comment: ""),
                                          message: nil, preferredStyle: .alert)
            coordinator.alert = alert
            alert.addTextField { field in
                field.text = initialName
                field.placeholder = NSLocalizedString("Fitting_Name", comment: "")
                field.clearButtonMode = .whileEditing
                field.delegate = coordinator
                field.addTarget(coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
            }
            alert.addAction(UIAlertAction(title: NSLocalizedString("Misc_Cancel", comment: ""), style: .cancel) { _ in
                isPresented = false
                coordinator.alert = nil
            })
            let save = UIAlertAction(title: NSLocalizedString("Misc_Save", comment: ""), style: .default) { [weak alert] _ in
                let name = (alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                isPresented = false
                coordinator.alert = nil
                if !name.isEmpty {
                    onSave(name)
                }
            }
            save.isEnabled = !initialName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            coordinator.saveAction = save
            alert.addAction(save)
            controller.present(alert, animated: true)
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        weak var alert: UIAlertController?
        weak var saveAction: UIAlertAction?

        @objc func textChanged(_ field: UITextField) {
            saveAction?.isEnabled = !(field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        func textFieldShouldClear(_: UITextField) -> Bool {
            saveAction?.isEnabled = false
            return true
        }
    }
}
