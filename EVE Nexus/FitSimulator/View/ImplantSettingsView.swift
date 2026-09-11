import SwiftUI

struct ImplantSettingsView: View {
    let databaseManager: DatabaseManager
    @ObservedObject var viewModel: FittingEditorViewModel
    @State private var implantSlots: [Int] = []
    @State private var boosterSlots: [Int] = []
    @State private var isLoading = true
    @State private var showingPresetSelector = false
    @State private var showingImplantSelector = false
    @State private var showingBoosterSelector = false
    @State private var showingSavePresetDialog = false
    @State private var showingNoItemsAlert = false
    @State private var showingDuplicateAlert = false
    @State private var showingClearConfirmation = false
    @State private var clearedImplantCount = 0
    @State private var clearedBoosterCount = 0
    @State private var duplicatePresetName = ""
    @State private var presetName = ""

    // 用于存储所有槽位的植入体和增效剂引用
    @State private var implantRows: [Int: ImplantSlotRowProxy] = [:]
    @State private var boosterRows: [Int: BoosterSlotRowProxy] = [:]

    var body: some View {
        List {
            // 第一个section：使用预设
            Section(header: Text(NSLocalizedString("Implant_Use_Preset", comment: "使用预设"))) {
                Button {
                    showingPresetSelector = true
                } label: {
                    HStack {
                        Image(systemName: "bookmark.fill")
                            .foregroundColor(.blue)
                            .frame(width: 32, height: 32)
                        Text(NSLocalizedString("Implant_Select_Preset", comment: "选择预设"))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
                .foregroundColor(.primary)

                Button {
                    // 统计当前有多少植入体和增效剂
                    let implantCount = implantRows.values.filter { $0.selectedImplant != nil }.count
                    let boosterCount = boosterRows.values.filter { $0.selectedBooster != nil }.count

                    if implantCount > 0 || boosterCount > 0 {
                        clearedImplantCount = implantCount
                        clearedBoosterCount = boosterCount
                        clearAllImplantsAndBoosters()
                        showingClearConfirmation = true
                    }
                } label: {
                    HStack {
                        Image(systemName: "trash.fill")
                            .foregroundColor(.red)
                            .frame(width: 32, height: 32)
                        Text(NSLocalizedString("Implant_Clear_All", comment: "清空当前选项"))
                        Spacer()
                    }
                }
                .foregroundColor(.primary)

                Button {
                    if hasAnyImplantsOrBoosters() {
                        // 收集当前的 typeIds
                        let currentTypeIds = collectCurrentTypeIds()

                        // 检查是否有完全相同的配置
                        if let duplicatePreset = findDuplicatePreset(typeIds: currentTypeIds) {
                            duplicatePresetName = duplicatePreset.name
                            showingDuplicateAlert = true
                            Logger.info("发现重复配置: \(duplicatePreset.name)")
                        } else {
                            presetName = ""
                            showingSavePresetDialog = true
                        }
                    } else {
                        showingNoItemsAlert = true
                    }
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.down.fill")
                            .foregroundColor(.green)
                            .frame(width: 32, height: 32)
                        Text(NSLocalizedString("Implant_Save_As_Preset", comment: "保存为自定义预设"))
                        Spacer()
                    }
                }
                .foregroundColor(.primary)
            }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

            // 第二个section：手动选择
            Section(header: Text(NSLocalizedString("Implant_Manual_Select", comment: "手动选择"))) {
                Button {
                    showingImplantSelector = true
                } label: {
                    HStack {
                        Image("implants")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                        Text(NSLocalizedString("Implant_Select_Implants", comment: "选择植入体"))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
                .foregroundColor(.primary)

                Button {
                    showingBoosterSelector = true
                } label: {
                    HStack {
                        Image("booster")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                        Text(NSLocalizedString("Implant_Select_Boosters", comment: "选择增效剂"))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
                .foregroundColor(.primary)
            }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

            // 第三个section：植入体
            Section(header: Text(NSLocalizedString("Implant_Implants", comment: "植入体"))) {
                if isLoading {
                    ProgressView()
                } else if implantSlots.isEmpty {
                    Text(NSLocalizedString("Implant_No_Slots", comment: "没有可用的植入体槽位"))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(implantSlots, id: \.self) { slot in
                        if let proxy = implantRows[slot] {
                            ImplantSlotRow(
                                proxy: proxy,
                                slotNumber: slot,
                                slotName: getImplantSlotName(slot),
                                databaseManager: databaseManager
                            )
                        }
                    }
                }
            }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

            // 第四个section：增效剂
            Section(header: Text(NSLocalizedString("Implant_Boosters", comment: "增效剂"))) {
                if isLoading {
                    ProgressView()
                } else if boosterSlots.isEmpty {
                    Text(NSLocalizedString("Booster_No_Boosters", comment: "没有可用的增效剂槽位"))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(boosterSlots, id: \.self) { slot in
                        if let proxy = boosterRows[slot] {
                            BoosterSlotRow(
                                proxy: proxy,
                                slotNumber: slot,
                                slotName: getBoosterSlotName(slot),
                                databaseManager: databaseManager
                            )
                        }
                    }
                }
            }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        }
        .navigationTitle(NSLocalizedString("Implant_Settings_Title", comment: "植入体设置"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadSlotData()
        }
        .onDisappear {
            saveImplantsToConfiguration()
        }
        .sheet(isPresented: $showingPresetSelector) {
            ImplantPresetView(
                databaseManager: databaseManager,
                onSelectPreset: { typeIds in
                    applyImplantPreset(typeIds)
                    showingPresetSelector = false
                }
            )
        }
        .sheet(isPresented: $showingImplantSelector) {
            AllImplantsSelector(
                databaseManager: databaseManager,
                onSelect: { item, slotNumber in
                    handleImplantSelection(item: item, slotNumber: slotNumber)
                }
            )
        }
        .sheet(isPresented: $showingBoosterSelector) {
            AllBoosterSelector(
                databaseManager: databaseManager,
                onSelect: { item, slotNumber in
                    handleBoosterSelection(item: item, slotNumber: slotNumber)
                }
            )
        }
        .alert(NSLocalizedString("Implant_Save_As_Preset", comment: "保存为自定义预设"), isPresented: $showingSavePresetDialog) {
            TextField(NSLocalizedString("Implant_Preset_Name", comment: "预设名称"), text: $presetName)
            Button(NSLocalizedString("Misc_Cancel", comment: "取消"), role: .cancel) {
                presetName = ""
            }
            Button(NSLocalizedString("Misc_Save", comment: "保存")) {
                saveCurrentConfigurationAsPreset()
            }
            .disabled(presetName.trimmingCharacters(in: .whitespaces).isEmpty)
        } message: {
            Text(NSLocalizedString("Implant_Enter_Preset_Name", comment: "请输入预设名称"))
        }
        .alert(NSLocalizedString("Implant_No_Items_To_Save", comment: "无需保存"), isPresented: $showingNoItemsAlert) {
            Button(NSLocalizedString("Calendar_OK", comment: "确定"), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("Implant_No_Items_To_Save_Message", comment: "没有设置任何植入体/增效剂，无需保存"))
        }
        .alert(NSLocalizedString("Implant_Duplicate_Preset", comment: "重复配置"), isPresented: $showingDuplicateAlert) {
            Button(NSLocalizedString("Calendar_OK", comment: "确定"), role: .cancel) {}
        } message: {
            Text(String(format: NSLocalizedString("Implant_Duplicate_Preset_Message", comment: "已有重复配置：%@"), duplicatePresetName))
        }
        .alert(NSLocalizedString("Implant_Cleared", comment: "已清空"), isPresented: $showingClearConfirmation) {
            Button(NSLocalizedString("Calendar_OK", comment: "确定"), role: .cancel) {}
        } message: {
            Text(getClearedMessage())
        }
    }

    /// 加载槽位数据
    private func loadSlotData() {
        isLoading = true

        // 使用一个SQL查询同时获取植入体和增效剂槽位
        let query = """
            SELECT ta.attribute_id, ta.value 
            FROM typeAttributes AS ta
            LEFT JOIN types t ON t.published = 1 AND t.marketGroupID IS NOT NULL
            WHERE ta.attribute_id IN (331, 1087) AND ta.value NOT IN (65, 79) AND t.type_id = ta.type_id
            ORDER BY ta.attribute_id, ta.value
        """

        if case let .success(rows) = databaseManager.executeQuery(query) {
            // 分别处理植入体和增效剂槽位
            var implantSlots: [Int] = []
            var boosterSlots: [Int] = []

            for row in rows {
                if let attributeID = row["attribute_id"] as? Int,
                   let value = row["value"] as? Double
                {
                    let slotNumber = Int(value)

                    if attributeID == 331 {
                        // 植入体槽位
                        if !implantSlots.contains(slotNumber) {
                            implantSlots.append(slotNumber)
                        }
                    } else if attributeID == 1087 {
                        // 增效剂槽位
                        if !boosterSlots.contains(slotNumber) {
                            boosterSlots.append(slotNumber)
                        }
                    }
                }
            }

            // 对槽位进行排序
            self.implantSlots = implantSlots.sorted()
            self.boosterSlots = boosterSlots.sorted()

            // 为每个槽位创建代理对象
            for slot in self.implantSlots {
                implantRows[slot] = ImplantSlotRowProxy()
            }

            for slot in self.boosterSlots {
                boosterRows[slot] = BoosterSlotRowProxy()
            }

            // 加载现有植入体和增效剂
            loadExistingImplants()

            isLoading = false
        } else {
            isLoading = false
        }
    }

    /// 加载现有的植入体和增效剂
    private func loadExistingImplants() {
        // 遍历当前配置中的植入体和增效剂
        for implant in viewModel.simulationInput.implants {
            // 创建通用的数据库项
            let item = DatabaseListItem(
                id: implant.typeId,
                name: implant.name,
                enName: nil,
                iconFileName: implant.iconFileName ?? "",
                published: true,
                categoryID: 0
            )

            // 检查是植入体还是增效剂
            if let implantness = implant.attributesByName["implantness"],
               let slotNumber = Int(exactly: implantness),
               implantSlots.contains(slotNumber)
            {
                implantRows[slotNumber]?.selectedImplant = item
            } else if let boosterness = implant.attributesByName["boosterness"],
                      let slotNumber = Int(exactly: boosterness),
                      boosterSlots.contains(slotNumber)
            {
                boosterRows[slotNumber]?.selectedBooster = item
                // 恢复会话内的副作用开关状态（不落盘，仅在内存中保留）
                boosterRows[slotNumber]?.enabledSideEffectAttributeIDs =
                    implant.enabledSideEffectAttributeIDs
            }
        }
    }

    /// 保存植入体和增效剂到配置
    private func saveImplantsToConfiguration() {
        // 收集所有需要查询的植入体和增效剂ID
        var implantIds: [Int] = []
        var boosterIds: [Int] = []
        var implantSlotMap: [Int: (id: Int, name: String, iconFileName: String)] = [:]
        var boosterSlotMap: [Int: (id: Int, name: String, iconFileName: String)] = [:]

        // 收集植入体ID
        for (slot, proxy) in implantRows {
            if let implant = proxy.selectedImplant {
                implantIds.append(implant.id)
                implantSlotMap[slot] = (
                    id: implant.id, name: implant.name, iconFileName: implant.iconFileName
                )
            }
        }

        // 收集增效剂ID
        for (slot, proxy) in boosterRows {
            if let booster = proxy.selectedBooster {
                boosterIds.append(booster.id)
                boosterSlotMap[slot] = (
                    id: booster.id, name: booster.name, iconFileName: booster.iconFileName
                )
            }
        }

        // 检查配置是否发生变化（包含增效剂副作用开关状态）
        let currentSignature = viewModel.simulationInput.implants
            .map {
                implantSignature(
                    typeId: $0.typeId, enabledSideEffects: $0.enabledSideEffectAttributeIDs
                )
            }
            .sorted()
            .joined(separator: "|")

        var newSignatures: [String] = implantSlotMap.values.map {
            implantSignature(typeId: $0.id, enabledSideEffects: [])
        }
        for (slot, item) in boosterSlotMap {
            newSignatures.append(
                implantSignature(
                    typeId: item.id,
                    enabledSideEffects: boosterRows[slot]?.enabledSideEffectAttributeIDs ?? []
                )
            )
        }
        let newSignature = newSignatures.sorted().joined(separator: "|")
        let hasChanges = currentSignature != newSignature

        // 如果没有植入体和增效剂，则清空现有的并返回
        if implantIds.isEmpty, boosterIds.isEmpty {
            if !viewModel.simulationInput.implants.isEmpty {
                viewModel.simulationInput.implants = []
                viewModel.hasUnsavedChanges = true

                // 只有在配置发生变化时才重新计算属性
                if hasChanges {
                    Logger.info("清空所有植入体和增效剂，重新计算属性")
                    viewModel.calculateAttributes()
                }

                // 保存配置
                viewModel.saveConfiguration()
            }
            return
        }

        // 一次性查询所有植入体和增效剂的属性和效果（内存索引）
        let allIds = implantIds + boosterIds
        if allIds.isEmpty {
            return
        }

        // 批量取属性（byID + byName，name 从 dogmaAttributes 内存解析）
        let attrResult = SDEMemoryStore.typeAttributes(for: allIds)

        var typeAttributes: [Int: [Int: Double]] = [:]
        var typeAttributesByName: [Int: [String: Double]] = [:]
        var typeGroupIDs: [Int: Int] = [:]

        for (typeId, attrs) in attrResult {
            typeAttributes[typeId] = attrs.attributes
            typeAttributesByName[typeId] = attrs.attributesByName
            // groupID 从 types 内存索引获取
            if let groupID = SDEMemoryStore.type(for: typeId)?.groupID {
                typeGroupIDs[typeId] = groupID
            }
        }

        // 创建新的植入体列表
        var newImplants: [SimImplant] = []

        // 添加植入体
        for (slot, item) in implantSlotMap {
            if let attributes = typeAttributes[item.id],
               let attributesByName = typeAttributesByName[item.id]
            {
                let effects = SDEMemoryStore.effectIDs(forType: item.id)

                // 创建植入体对象
                let groupID = typeGroupIDs[item.id] ?? 0
                let implant = SimImplant(
                    typeId: item.id,
                    attributes: attributes,
                    attributesByName: attributesByName,
                    effects: effects,
                    requiredSkills: FitConvert.extractRequiredSkills(attributes: attributes),
                    groupID: groupID,
                    name: item.name,
                    iconFileName: item.iconFileName
                )

                newImplants.append(implant)
                Logger.info("添加植入体: \(item.name), 槽位: \(slot)")
            }
        }

        // 添加增效剂
        for (slot, item) in boosterSlotMap {
            if let attributes = typeAttributes[item.id],
               let attributesByName = typeAttributesByName[item.id]
            {
                let effects = SDEMemoryStore.effectIDs(forType: item.id)

                // 创建增效剂对象
                let groupID = typeGroupIDs[item.id] ?? 0
                let booster = SimImplant(
                    typeId: item.id,
                    attributes: attributes,
                    attributesByName: attributesByName,
                    effects: effects,
                    requiredSkills: FitConvert.extractRequiredSkills(attributes: attributes),
                    groupID: groupID,
                    name: item.name,
                    iconFileName: item.iconFileName,
                    enabledSideEffectAttributeIDs:
                    boosterRows[slot]?.enabledSideEffectAttributeIDs ?? []
                )

                newImplants.append(booster)
                Logger.info("添加增效剂: \(item.name), 槽位: \(slot)")
            }
        }

        // 更新配置中的植入体列表
        viewModel.simulationInput.implants = newImplants

        // 只有在配置发生变化时才重新计算属性
        if hasChanges {
            Logger.info("植入体和增效剂配置发生变化，重新计算属性")
            viewModel.calculateAttributes()
        } else {
            Logger.info("植入体和增效剂配置未变化，跳过属性计算")
        }

        // 标记有未保存的更改
        viewModel.hasUnsavedChanges = true

        // 自动保存配置
        viewModel.saveConfiguration()
    }

    /// 生成植入体/增效剂的变更签名（typeId + 副作用开关），用于判断是否需要重算属性
    private func implantSignature(typeId: Int, enabledSideEffects: Set<Int>) -> String {
        let effects = enabledSideEffects.sorted().map(String.init).joined(separator: ",")
        return "\(typeId):\(effects)"
    }

    private func getImplantSlotName(_ slot: Int) -> String {
        return String.localizedStringWithFormat(NSLocalizedString("Implant_Slot_Num", comment: "植入体槽位 %d"), slot)
    }

    private func getBoosterSlotName(_ slot: Int) -> String {
        return String.localizedStringWithFormat(NSLocalizedString("Booster_Slot_Num", comment: "增效剂槽位 %d"), slot)
    }

    /// 获取清空提示消息
    private func getClearedMessage() -> String {
        var parts: [String] = []

        if clearedImplantCount > 0 {
            parts.append(String(format: NSLocalizedString("Implant_Cleared_Implants", comment: "%d 个植入体"), clearedImplantCount))
        }

        if clearedBoosterCount > 0 {
            parts.append(String(format: NSLocalizedString("Implant_Cleared_Boosters", comment: "%d 个增效剂"), clearedBoosterCount))
        }

        if parts.isEmpty {
            return NSLocalizedString("Implant_Cleared_Nothing", comment: "没有可清空的内容")
        }

        return String(format: NSLocalizedString("Implant_Cleared_Message", comment: "已移除：%@"), parts.joined(separator: "、"))
    }

    private func clearAllImplantsAndBoosters() {
        // 清空所有槽位的植入体和增效剂
        for (slot, _) in implantRows {
            implantRows[slot]?.selectedImplant = nil
        }
        for (slot, _) in boosterRows {
            boosterRows[slot]?.selectedBooster = nil
            boosterRows[slot]?.enabledSideEffectAttributeIDs = []
        }
    }

    /// 应用植入体预设
    private func applyImplantPreset(_ typeIds: [Int]) {
        // 首先清空现有植入体
        clearAllImplantsAndBoosters()

        // 如果没有选择预设，直接返回
        if typeIds.isEmpty {
            return
        }

        // 查询预设植入体的详细信息（内存索引：types + 槽位属性 331/1087）
        var implantInfo:
            [Int: (name: String, iconFile: String, slotNumber: Int, isImplant: Bool)] = [:]

        for typeId in typeIds {
            guard let typeInfo = SDEMemoryStore.type(for: typeId) else { continue }
            // 331 = 植入体槽位属性，1087 = 增效剂槽位属性
            let implantSlot = SDEMemoryStore.typeAttributeValue(for: typeId, attributeID: 331)
            let boosterSlot = SDEMemoryStore.typeAttributeValue(for: typeId, attributeID: 1087)
            guard let slotValue = implantSlot ?? boosterSlot else { continue }

            implantInfo[typeId] = (
                name: typeInfo.name,
                iconFile: typeInfo.iconFilename.isEmpty
                    ? IconManager.defaultItemIcon : typeInfo.iconFilename,
                slotNumber: Int(slotValue),
                isImplant: implantSlot != nil
            )
        }

        // 应用植入体到相应槽位
        for (typeId, info) in implantInfo {
            let item = DatabaseListItem(
                id: typeId,
                name: info.name,
                enName: nil,
                iconFileName: info.iconFile,
                published: true,
                categoryID: 0
            )

            if info.isImplant {
                // 应用植入体
                if let proxy = implantRows[info.slotNumber] {
                    proxy.selectedImplant = item
                }
            } else {
                // 应用增效剂
                if let proxy = boosterRows[info.slotNumber] {
                    proxy.selectedBooster = item
                    proxy.enabledSideEffectAttributeIDs = []
                }
            }
        }
    }

    /// 处理植入体选择
    private func handleImplantSelection(item: DatabaseListItem, slotNumber: Int) {
        if let proxy = implantRows[slotNumber] {
            proxy.selectedImplant = item
            Logger.info("选择植入体: \(item.name), 槽位: \(slotNumber)")
        }
    }

    /// 处理增效剂选择
    private func handleBoosterSelection(item: DatabaseListItem, slotNumber: Int) {
        if let proxy = boosterRows[slotNumber] {
            proxy.selectedBooster = item
            proxy.enabledSideEffectAttributeIDs = []
            Logger.info("选择增效剂: \(item.name), 槽位: \(slotNumber)")
        }
    }

    /// 检查是否有任何植入体或增效剂
    private func hasAnyImplantsOrBoosters() -> Bool {
        // 检查是否有植入体
        for (_, proxy) in implantRows {
            if proxy.selectedImplant != nil {
                return true
            }
        }

        // 检查是否有增效剂
        for (_, proxy) in boosterRows {
            if proxy.selectedBooster != nil {
                return true
            }
        }

        return false
    }

    /// 收集当前配置的所有 typeId
    private func collectCurrentTypeIds() -> [Int] {
        var typeIds: [Int] = []

        // 收集植入体
        for (_, proxy) in implantRows {
            if let implant = proxy.selectedImplant {
                typeIds.append(implant.id)
            }
        }

        // 收集增效剂
        for (_, proxy) in boosterRows {
            if let booster = proxy.selectedBooster {
                typeIds.append(booster.id)
            }
        }

        return typeIds
    }

    /// 检查是否有完全相同的配置
    private func findDuplicatePreset(typeIds: [Int]) -> CustomImplantPreset? {
        let existingPresets = CustomImplantPresetManager.shared.loadPresets()
        let sortedTypeIds = typeIds.sorted()

        for preset in existingPresets {
            let presetSortedTypeIds = preset.implantTypeIds.sorted()
            Logger.info("比较预设: \(preset.name), 类型ID: \(presetSortedTypeIds)")
            Logger.info("比较当前: \(sortedTypeIds)")
            // 比较两个数组是否完全相同
            if sortedTypeIds == presetSortedTypeIds {
                return preset
            }
        }

        return nil
    }

    /// 保存当前配置为自定义预设
    private func saveCurrentConfigurationAsPreset() {
        let trimmedName = presetName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            Logger.warning("预设名称不能为空")
            return
        }

        // 收集所有植入体和增效剂的 typeId
        let typeIds = collectCurrentTypeIds()

        // 如果没有选择任何植入体或增效剂，提示用户
        if typeIds.isEmpty {
            Logger.warning("当前没有选择任何植入体或增效剂，无法保存预设")
            return
        }

        // 注意：重复配置检查已在点击保存按钮时完成，这里不再检查

        // 创建预设并保存
        let preset = CustomImplantPreset(
            name: trimmedName,
            implantTypeIds: typeIds
        )

        CustomImplantPresetManager.shared.addPreset(preset)
        Logger.info("成功保存自定义预设: \(trimmedName), 包含 \(typeIds.count) 个物品")

        // 清空预设名称
        presetName = ""
    }
}

/// 植入体行代理类
class ImplantSlotRowProxy: ObservableObject {
    @Published var selectedImplant: DatabaseListItem?
}

/// 增效剂行代理类
class BoosterSlotRowProxy: ObservableObject {
    @Published var selectedBooster: DatabaseListItem?
    /// 已启用的副作用惩罚属性 ID（默认空 = 全部关闭，仅当前会话有效）
    @Published var enabledSideEffectAttributeIDs: Set<Int> = []
}

/// 植入体插槽行组件
struct ImplantSlotRow: View {
    @ObservedObject var proxy: ImplantSlotRowProxy
    let slotNumber: Int
    let slotName: String
    let databaseManager: DatabaseManager
    @State private var showingSelector = false
    @State private var showingItemInfo = false

    var body: some View {
        HStack {
            // 插槽图标
            if let implant = proxy.selectedImplant {
                IconManager.shared.loadImage(for: implant.iconFileName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)

                Text(implant.name)
                    .font(.body)

                Spacer()

                // 添加物品信息按钮
                Button {
                    showingItemInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                }
                .buttonStyle(BorderlessButtonStyle())
                .sheet(isPresented: $showingItemInfo) {
                    NavigationStack {
                        ShowItemInfo(databaseManager: databaseManager, itemID: implant.id)
                    }
                    .presentationDragIndicator(.visible)
                }
            } else {
                IconManager.shared.loadImage(for: "add_item")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)

                Text(slotName)
                    .font(.body)

                Spacer()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            showingSelector = true
        }
        .sheet(isPresented: $showingSelector) {
            ImplantSelectorView(
                databaseManager: databaseManager,
                slotNumber: slotNumber,
                hasExistingItem: proxy.selectedImplant != nil,
                onSelect: { item in
                    proxy.selectedImplant = item
                },
                onRemove: {
                    proxy.selectedImplant = nil
                }
            )
        }
    }
}

/// 增效剂插槽行组件
struct BoosterSlotRow: View {
    @ObservedObject var proxy: BoosterSlotRowProxy
    let slotNumber: Int
    let slotName: String
    let databaseManager: DatabaseManager
    @State private var showingDetail = false

    var body: some View {
        HStack {
            // 插槽图标
            if let booster = proxy.selectedBooster {
                IconManager.shared.loadImage(for: booster.iconFileName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)

                Text(booster.name)
                    .font(.body)
            } else {
                IconManager.shared.loadImage(for: "add_item")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)

                Text(slotName)
                    .font(.body)
            }

            Spacer()

            // 副作用启用数量摘要
            if proxy.selectedBooster != nil, !sideEffects.isEmpty {
                Text(sideEffectSummary)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            showingDetail = true
        }
        .sheet(isPresented: $showingDetail) {
            BoosterDetailView(
                proxy: proxy,
                slotNumber: slotNumber,
                slotName: slotName,
                databaseManager: databaseManager
            )
        }
    }

    /// 当前增效剂的副作用列表
    private var sideEffects: [SDEMemoryStore.BoosterSideEffect] {
        guard let booster = proxy.selectedBooster else { return [] }
        return SDEMemoryStore.boosterSideEffects(forType: booster.id)
    }

    /// 副作用启用数量 / 总数 摘要
    private var sideEffectSummary: String {
        let enabledCount = sideEffects.filter {
            proxy.enabledSideEffectAttributeIDs.contains($0.attributeID)
        }.count
        let label = NSLocalizedString("Booster_Side_Effects", comment: "副作用")
        return "\(label) \(enabledCount)/\(sideEffects.count)"
    }
}

/// 增效剂详情页：统一管理更换增效剂与副作用开关
struct BoosterDetailView: View {
    @ObservedObject var proxy: BoosterSlotRowProxy
    let slotNumber: Int
    let slotName: String
    let databaseManager: DatabaseManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingSelector = false

    var body: some View {
        NavigationStack {
            List {
                // 当前增效剂
                Section {
                    Button {
                        showingSelector = true
                    } label: {
                        HStack {
                            if let booster = proxy.selectedBooster {
                                IconManager.shared.loadImage(for: booster.iconFileName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 32, height: 32)

                                Text(booster.name)
                                    .font(.body)
                            } else {
                                IconManager.shared.loadImage(for: "add_item")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 32, height: 32)

                                Text(slotName)
                                    .font(.body)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)
                }

                // 副作用
                if proxy.selectedBooster != nil {
                    Section(
                        header: Text(NSLocalizedString("Booster_Side_Effects", comment: "副作用"))
                    ) {
                        if sideEffects.isEmpty {
                            Text(NSLocalizedString("Booster_No_Side_Effects", comment: "无副作用"))
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(sideEffects, id: \.attributeID) { sideEffect in
                                HStack {
                                    Text(sideEffect.name)
                                    Spacer()
                                    Text(penaltyText(sideEffect.value))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Toggle("", isOn: sideEffectBinding(sideEffect.attributeID))
                                        .labelsHidden()
                                        .tint(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(proxy.selectedBooster?.name ?? slotName)
            .navigationBarTitleDisplayMode(.inline)
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
        }
        .sheet(isPresented: $showingSelector) {
            BoosterSelectorView(
                databaseManager: databaseManager,
                slotNumber: slotNumber,
                hasExistingItem: proxy.selectedBooster != nil,
                onSelect: { item in
                    proxy.selectedBooster = item
                    proxy.enabledSideEffectAttributeIDs = []
                },
                onRemove: {
                    proxy.selectedBooster = nil
                    proxy.enabledSideEffectAttributeIDs = []
                }
            )
        }
    }

    /// 当前增效剂的副作用列表
    private var sideEffects: [SDEMemoryStore.BoosterSideEffect] {
        guard let booster = proxy.selectedBooster else { return [] }
        return SDEMemoryStore.boosterSideEffects(forType: booster.id)
    }

    /// 某个副作用属性的开关绑定
    private func sideEffectBinding(_ attributeID: Int) -> Binding<Bool> {
        Binding(
            get: { proxy.enabledSideEffectAttributeIDs.contains(attributeID) },
            set: { enabled in
                if enabled {
                    proxy.enabledSideEffectAttributeIDs.insert(attributeID)
                } else {
                    proxy.enabledSideEffectAttributeIDs.remove(attributeID)
                }
            }
        )
    }

    /// 惩罚值显示（如 -20%、+20%）
    private func penaltyText(_ value: Double) -> String {
        String(format: "%+g%%", value)
    }
}
