import Combine
import Foundation
import SwiftUI

/// 突变属性数据结构
struct MutationAttribute: Identifiable {
    let id: Int // attributeID
    let attributeID: Int
    let name: String
    let iconFileName: String?
    let minValue: Double
    let maxValue: Double
    let highIsGood: Bool
    var currentValue: Double? // 当前突变值（可变）
    var originalValue: Double? = nil // 物品的原始属性值（用于判断 originalValueIsNegative）
}

/// 模块状态枚举
enum ModuleStatus: Int, CaseIterable, Identifiable {
    case offline = 0 // 离线
    case online = 1 // 上线
    case active = 2 // 启动
    case overload = 3 // 超载

    var id: Int {
        rawValue
    }

    var name: String {
        switch self {
        case .offline:
            return NSLocalizedString("Module_Status_Offline", comment: "")
        case .online:
            return NSLocalizedString("Module_Status_Online", comment: "")
        case .active:
            return NSLocalizedString("Module_Status_Active", comment: "")
        case .overload:
            return NSLocalizedString("Module_Status_Overload", comment: "")
        }
    }

    var icon: String {
        switch self {
        case .offline:
            return "power.circle"
        case .online:
            return "power.circle.fill"
        case .active:
            return "bolt.circle.fill"
        case .overload:
            return "flame.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .offline:
            return .gray
        case .online:
            return .green
        case .active:
            return .blue
        case .overload:
            return .red
        }
    }
}

/// 模块状态选择视图
struct ModuleStatusView: View {
    /// 可用的状态列表
    let availableStates: [Int]

    /// 当前选中的状态
    @Binding var selectedState: Int

    /// 是否在编辑模式下
    let isEditable: Bool

    /// 状态变化时的回调
    var onStateChanged: ((Int) -> Void)?

    /// 过滤后的状态列表
    private var moduleStates: [ModuleStatus] {
        // 根据可用状态筛选枚举值
        return ModuleStatus.allCases.filter { availableStates.contains($0.rawValue) }
    }

    var body: some View {
        // 如果只有一个状态选项，不显示此视图
        if availableStates.count <= 1 {
            EmptyView()
        } else {
            if isEditable {
                // 可编辑模式 - 使用Picker
                Picker("", selection: $selectedState) {
                    ForEach(moduleStates) { state in
                        Label(
                            title: { Text(state.name) },
                            icon: { Image(systemName: state.icon).foregroundColor(state.color) }
                        )
                        .tag(state.rawValue)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .onChange(of: selectedState) { _, newValue in
                    onStateChanged?(newValue)
                }
            } else {
                // 只读模式 - 显示当前状态
                if let state = ModuleStatus(rawValue: selectedState) {
                    HStack {
                        Image(systemName: state.icon)
                            .foregroundColor(state.color)
                        Text(state.name)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(8)
                }
            }
        }
    }
}

/// 装备设置视图 - 用于显示和修改已安装装备的详细设置
struct ModuleSettingsView: View {
    // 模块和数据依赖
    let module: SimModule
    let databaseManager: DatabaseManager
    let viewModel: FittingEditorViewModel
    let slotFlag: FittingFlag
    let relatedModules: [SimModule]

    // 回调函数
    var onDelete: () -> Void
    var onReplaceModule: (Int) -> Void

    /// 环境变量
    @Environment(\.dismiss) var dismiss

    // 状态变量
    @State private var moduleDetails: DatabaseListItem? = nil
    @State private var isLoading = true
    @State private var variationsCount: Int = 0
    @State private var selectedModuleState: Int
    @State private var availableModuleStates: [Int] = []
    @State private var chargeGroupIDs: [Int] = [] // 可装载的弹药组ID
    @State private var currentModuleID: Int // 添加当前模块ID状态变量
    @State private var selectedMutaplasmidID: Int? = nil // 选中的突变质体ID
    @State private var selectedMutaplasmidInfo: (typeID: Int, name: String, iconFileName: String)? = nil // 突变质体信息
    @State private var mutaplasmidAttributes: [MutationAttribute] = [] // 突变质体的属性列表（包含范围和当前值）
    @State private var editingAttributeID: Int? = nil // 正在编辑的属性ID
    @State private var editingAttributeValue: String = "" // 正在编辑的属性值文本
    @State private var showingValueInputAlert = false // 显示输入弹窗
    @State private var validationError: String? = nil // 验证错误信息
    @State private var isValidInput: Bool = false // 输入是否合法
    @State private var debounceTask: Task<Void, Never>? = nil // 防抖任务

    /// 计算属性：是否为批量操作模式
    private var isBatchMode: Bool {
        // 如果装备有突变（已设置了突变属性值），不应该进入批量模式（因为每个有突变的装备都是独立的）
        // 注意：只有 mutatedAttributes 不为空才认为真正应用了突变
        let hasAppliedMutation = !module.mutatedAttributes.isEmpty
        if hasAppliedMutation {
            return false
        }
        // 只有在没有应用突变且相关模块数量大于1时才进入批量模式
        return relatedModules.count > 1
    }

    /// 计算属性：是否已应用突变（即是否有突变属性值）
    private var hasAppliedMutation: Bool {
        return !module.mutatedAttributes.isEmpty
    }

    /// 计算属性：是否有临时选择的突变质体（但未设置属性值）
    private var hasTemporaryMutationSelection: Bool {
        return selectedMutaplasmidID != nil && mutaplasmidAttributes.allSatisfy { $0.currentValue == nil }
    }

    /// 计算属性：获取当前模块的弹药信息（从viewModel中直接获取，避免SQL查询）
    private var currentModuleCharge: SimCharge? {
        if let currentModule = viewModel.simulationInput.modules.first(where: {
            $0.flag == slotFlag
        }) {
            return currentModule.charge
        }
        return nil
    }

    /// 初始化方法
    init(
        module: SimModule,
        slotFlag: FittingFlag,
        databaseManager: DatabaseManager,
        viewModel: FittingEditorViewModel,
        relatedModules: [SimModule] = [],
        onDelete: @escaping () -> Void = {},
        onReplaceModule: @escaping (Int) -> Void = { _ in }
    ) {
        self.module = module
        self.slotFlag = slotFlag
        self.databaseManager = databaseManager
        self.viewModel = viewModel
        self.relatedModules = relatedModules.isEmpty ? [module] : relatedModules // 如果为空，使用当前模块
        self.onDelete = onDelete
        self.onReplaceModule = onReplaceModule

        // 使用模块当前状态初始化
        _selectedModuleState = State(initialValue: module.status)
        _currentModuleID = State(initialValue: module.typeId)
    }

    var body: some View {
        NavigationView {
            List {
                // 如果是批量模式，显示批量操作信息
                if isBatchMode {
                    Section(header: Text(NSLocalizedString("Fitting_Batch_Operation", comment: ""))) {
                        HStack {
                            Image(systemName: "square.stack.3d.up")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading) {
                                Text(NSLocalizedString("Fitting_Batch_Mode", comment: ""))
                                    .font(.headline)
                                Text(
                                    String(
                                        format: NSLocalizedString(
                                            "Fitting_Batch_Mode_Description", comment: ""
                                        ),
                                        relatedModules.count
                                    )
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section(
                    header:
                    HStack {
                        Text(NSLocalizedString("Fitting_Setting_Module", comment: ""))
                        Spacer()
                        if !isLoading, moduleDetails != nil {
                            let currentModule = viewModel.simulationOutput?.modules.first(
                                where: { $0.flag == slotFlag }
                            )
                            NavigationLink(
                                destination: ShowItemInfo(
                                    databaseManager: databaseManager, itemID: currentModuleID,
                                    modifiedAttributes: currentModule?.attributes
                                )
                            ) {
                                Text(NSLocalizedString("View_Details", comment: ""))
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                ) {
                    if isLoading {
                        HStack {
                            ProgressView()
                            Text(NSLocalizedString("Misc_Loading", comment: ""))
                        }
                    } else if let details = moduleDetails {
                        // 如果是T3D模式槽位，使用T3D模式选择器
                        if slotFlag == .t3dModeSlot0 {
                            NavigationLink(
                                destination: T3DModeSelectorView(
                                    databaseManager: databaseManager,
                                    slotFlag: slotFlag,
                                    onModuleSelected: { modeID in
                                        // 保存当前状态
                                        let previousState = selectedModuleState

                                        // 直接替换T3D模式
                                        let success = viewModel.replaceModule(
                                            typeId: modeID, flag: slotFlag
                                        )

                                        if success {
                                            // 更新当前模块ID
                                            currentModuleID = modeID

                                            // 重新加载模块信息
                                            loadModuleDetails()
                                            checkVariations()
                                            updateAvailableStates()
                                            loadChargeGroups()

                                            // 检查之前的状态是否可用
                                            if availableModuleStates.contains(previousState) {
                                                // 保持之前的状态（如果状态没有改变，不需要重新计算）
                                                selectedModuleState = previousState
                                                if let currentModule = viewModel.simulationInput
                                                    .modules.first(where: { $0.flag == slotFlag }),
                                                    currentModule.status != previousState
                                                {
                                                    viewModel.updateModuleStatus(
                                                        flag: slotFlag, newStatus: previousState
                                                    )
                                                }
                                            } else if !availableModuleStates.isEmpty {
                                                // 如果之前的状态不可用，设置为新模式支持的最高状态
                                                let newState = availableModuleStates.max() ?? 0
                                                selectedModuleState = newState
                                                if let currentModule = viewModel.simulationInput
                                                    .modules.first(where: { $0.flag == slotFlag }),
                                                    currentModule.status != newState
                                                {
                                                    viewModel.updateModuleStatus(
                                                        flag: slotFlag, newStatus: newState
                                                    )
                                                }
                                            }
                                        }

                                        // 不需要关闭整个设置页
                                    },
                                    shipTypeID: viewModel.simulationInput.ship.typeId
                                )
                            ) {
                                DatabaseListItemView(
                                    item: details,
                                    showDetails: true
                                )
                            }
                        }
                        // 如果有变体且不是T3D模式槽位，点击跳转到变体列表
                        else if variationsCount > 1 {
                            NavigationLink(
                                destination: ModuleVariationsView(
                                    databaseManager: databaseManager,
                                    typeID: currentModuleID,
                                    onSelectVariation: { variationID in
                                        // 保存当前状态
                                        let previousState = selectedModuleState

                                        // 替换模块 - 如果是批量模式，会在外部处理
                                        if isBatchMode {
                                            // 批量模式下，调用外部回调
                                            onReplaceModule(variationID)

                                            // 批量替换完成后，从viewModel同步获取最新的模块ID
                                            if let updatedModule = viewModel.simulationInput.modules
                                                .first(where: { $0.flag == slotFlag })
                                            {
                                                // 更新内部状态以反映新装备
                                                currentModuleID = updatedModule.typeId

                                                // 重新加载模块信息
                                                loadModuleDetails()
                                                checkVariations()
                                                updateAvailableStates()
                                                loadChargeGroups()

                                                // 检查之前的状态是否可用
                                                if availableModuleStates.contains(previousState) {
                                                    selectedModuleState = previousState
                                                } else if !availableModuleStates.isEmpty {
                                                    let newState = availableModuleStates.max() ?? 0
                                                    selectedModuleState = newState
                                                }
                                            } else {
                                                Logger.warning("批量替换后未找到更新的模块")
                                            }
                                        } else {
                                            // 单个模式下，直接替换
                                            let success = viewModel.replaceModule(
                                                typeId: variationID, flag: slotFlag
                                            )

                                            if success {
                                                // 更新当前模块ID
                                                currentModuleID = variationID

                                                // 重新加载模块信息
                                                loadModuleDetails()
                                                checkVariations()
                                                updateAvailableStates()
                                                loadChargeGroups()

                                                // 检查之前的状态是否可用
                                                if availableModuleStates.contains(previousState) {
                                                    // 保持之前的状态（如果状态没有改变，不需要重新计算）
                                                    selectedModuleState = previousState
                                                    if let currentModule = viewModel.simulationInput
                                                        .modules.first(where: {
                                                            $0.flag == slotFlag
                                                        }),
                                                        currentModule.status != previousState
                                                    {
                                                        viewModel.updateModuleStatus(
                                                            flag: slotFlag, newStatus: previousState
                                                        )
                                                    }
                                                } else if !availableModuleStates.isEmpty {
                                                    // 如果之前的状态不可用，设置为新装备支持的最高状态
                                                    let newState = availableModuleStates.max() ?? 0
                                                    selectedModuleState = newState
                                                    if let currentModule = viewModel.simulationInput
                                                        .modules.first(where: {
                                                            $0.flag == slotFlag
                                                        }),
                                                        currentModule.status != newState
                                                    {
                                                        viewModel.updateModuleStatus(
                                                            flag: slotFlag, newStatus: newState
                                                        )
                                                    }
                                                }
                                            }
                                        }

                                        // 不需要关闭整个设置页
                                    }
                                )
                            ) {
                                DatabaseListItemView(
                                    item: details,
                                    showDetails: true
                                )
                            }
                        } else {
                            // 没有变体时只显示信息
                            DatabaseListItemView(
                                item: details,
                                showDetails: true
                            )
                        }
                    }

                    // 模块状态选择器
                    ModuleStatusSelector(
                        selectedState: $selectedModuleState,
                        availableStates: availableModuleStates,
                        onStateChanged: { newState in
                            // 更新模块状态 - 如果是批量模式，更新所有相关模块
                            if isBatchMode {
                                // 批量更新所有相关模块的状态
                                let flags = relatedModules.compactMap { $0.flag }
                                viewModel.batchUpdateModuleStatus(flags: flags, newStatus: newState)
                                Logger.info(
                                    "批量更新模块状态: \(relatedModules.count) 个模块状态设置为 \(newState)"
                                )
                            } else {
                                // 单个模块更新
                                viewModel.updateModuleStatus(flag: slotFlag, newStatus: newState)
                            }
                        }
                    )

                    if !isLoading, moduleDetails?.categoryID == 7,
                       let actualForSpool = viewModel.simulationInput.modules.first(where: {
                           $0.flag == slotFlag
                       }),
                       actualForSpool.attributes[2734] != nil
                       || actualForSpool.attributesByName["damageMultiplierBonusMax"] != nil
                    {
                        Section {
                            Toggle(
                                NSLocalizedString("Fitting_Spool_Up_Full", comment: ""),
                                isOn: Binding(
                                    get: {
                                        viewModel.simulationInput.modules.first(where: {
                                            $0.flag == slotFlag
                                        })?.isSpoolUpFull ?? true
                                    },
                                    set: { newValue in
                                        if isBatchMode {
                                            let flags = relatedModules.compactMap { $0.flag }
                                            viewModel.batchUpdateModuleSpoolUpFull(
                                                flags: flags, isFull: newValue
                                            )
                                        } else {
                                            viewModel.updateModuleSpoolUpFull(
                                                flag: slotFlag, isFull: newValue
                                            )
                                        }
                                    }
                                )
                            )
                        }
                    }
                }

                // 如果模块可以装载弹药，显示弹药设置
                if canLoadCharge() {
                    Section(
                        header:
                        HStack {
                            Text(NSLocalizedString("Fitting_Setting_Ammo", comment: ""))
                            Spacer()
                            if let charge = currentModuleCharge {
                                // 获取计算后的弹药属性
                                let currentOutputModule = viewModel.simulationOutput?.modules
                                    .first(where: { $0.flag == slotFlag })
                                NavigationLink(
                                    destination: ShowItemInfo(
                                        databaseManager: databaseManager, itemID: charge.typeId,
                                        modifiedAttributes: currentOutputModule?.charge?
                                            .attributes
                                    )
                                ) {
                                    Text(NSLocalizedString("View_Details", comment: ""))
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    ) {
                        NavigationLink(
                            destination: ChargeSelectionView(
                                databaseManager: databaseManager,
                                chargeGroupIDs: chargeGroupIDs,
                                typeID: currentModuleID,
                                slotFlag: slotFlag,
                                viewModel: viewModel,
                                module: module,
                                relatedModules: relatedModules // 传递相关模块列表
                            )
                        ) {
                            HStack {
                                Text(NSLocalizedString("Fitting_Ammo", comment: ""))
                                Spacer()
                                if let charge = currentModuleCharge {
                                    Text(charge.name)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text(NSLocalizedString("Misc_Null", comment: ""))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        // 如果当前有弹药，显示清除弹药按钮
                        if currentModuleCharge != nil {
                            Button(action: {
                                // 如果是批量模式，清除所有相关模块的弹药
                                if isBatchMode {
                                    let flags = relatedModules.compactMap { $0.flag }
                                    viewModel.batchRemoveCharge(flags: flags)
                                    Logger.info("批量清除弹药: \(relatedModules.count) 个模块")
                                } else {
                                    viewModel.removeCharge(flag: slotFlag)
                                }
                            }) {
                                Text(NSLocalizedString("Fitting_Setting_Clear_Ammo", comment: ""))
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }

                // 已选中的突变质体（显示临时选择或已应用的突变）
                // 显示条件：有临时选择的突变质体，或者已应用了突变
                if let mutaplasmidInfo = selectedMutaplasmidInfo, hasTemporaryMutationSelection || hasAppliedMutation {
                    Section(header: Text(NSLocalizedString("Fitting_Selected_Mutation", comment: ""))) {
                        // 第一行：突变质体图标、名称和跳转链接
                        NavigationLink(
                            destination: ShowItemInfo(
                                databaseManager: databaseManager,
                                itemID: mutaplasmidInfo.typeID
                            )
                        ) {
                            HStack {
                                IconManager.shared.loadImage(for: mutaplasmidInfo.iconFileName)
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(6)

                                Text(mutaplasmidInfo.name)
                                    .font(.body)

                                Spacer()
                            }
                        }

                        // 所有可突变属性的列表行（按属性ID排序）
                        ForEach(mutaplasmidAttributes.sorted { $0.attributeID < $1.attributeID }, id: \.attributeID) { attribute in
                            MutationAttributeRowView(
                                attribute: attribute,
                                onTap: {
                                    editingAttributeID = attribute.attributeID
                                    if let currentValue = attribute.currentValue {
                                        let percentage = (currentValue - 1) * 100
                                        editingAttributeValue = formatMutationValueForInput(percentage)
                                    } else {
                                        editingAttributeValue = ""
                                    }
                                    validationError = nil
                                    isValidInput = false
                                    showingValueInputAlert = true
                                    // 如果已有值，立即验证
                                    if !editingAttributeValue.isEmpty {
                                        validateInputDebounced(editingAttributeValue)
                                    }
                                }
                            )
                        }

                        // 最后一行：移除按钮
                        Button(action: {
                            // 如果已应用了突变，需要清除SimModule的突变数据
                            // 堆叠模式下，只清除当前选中的装备的突变，不对所有堆叠的装备进行清除
                            if hasAppliedMutation {
                                viewModel.updateModuleMutation(flag: slotFlag, mutaplasmidID: nil, mutatedAttributes: [:])
                                Logger.info("清除突变: 槽位 \(slotFlag.rawValue)")
                            }
                            // 清除临时选择（无论是否已应用）
                            selectedMutaplasmidID = nil
                            selectedMutaplasmidInfo = nil
                            mutaplasmidAttributes = []
                        }) {
                            Text(NSLocalizedString("Fitting_Remove_Mutation", comment: ""))
                                .foregroundColor(.red)
                        }
                    }
                }

                // 可用突变质体
                let availableMutaplasmids = databaseManager.getRequiredMutaplasmids(for: currentModuleID)
                if !availableMutaplasmids.isEmpty {
                    Section(header: Text(NSLocalizedString("Fitting_Available_Mutations", comment: ""))) {
                        NavigationLink(
                            destination: MutaplasmidSelectionView(
                                databaseManager: databaseManager,
                                itemTypeID: currentModuleID,
                                onSelectMutaplasmid: { mutaplasmidID in
                                    // 选择突变质体后的处理
                                    // 注意：此时只是临时选择，不立即应用突变（不保存、不重算属性）
                                    // 只有当用户设置了突变属性值后，才会真正应用突变
                                    selectedMutaplasmidID = mutaplasmidID
                                    loadMutaplasmidInfo(mutaplasmidID: mutaplasmidID)
                                    Logger.info("临时选择突变质体: \(mutaplasmidID)，等待设置属性值后才会应用")
                                }
                            )
                        ) {
                            HStack {
                                Text(NSLocalizedString("Fitting_Available_Mutations", comment: ""))
                                Spacer()
                                Text("\(availableMutaplasmids.count)")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(Text(NSLocalizedString("Fitting_Setting_Module", comment: "")))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        onDelete() // 调用删除回调
                        dismiss()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
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
            .onAppear {
                Logger.info("selectedSlotFlag: \(slotFlag)")
                Logger.info(
                    "模块名称: \(module.name), 模块ID: \(module.typeId), 槽位: \(slotFlag.rawValue)"
                )
                if isBatchMode {
                    Logger.info("批量模式: \(relatedModules.count) 个相关模块")
                }
                // 从 viewModel 读取实时模块，避免快照值在 onAppear 再次触发时覆盖变体替换后的新装备
                let liveModule = viewModel.simulationInput.modules.first(where: { $0.flag == slotFlag }) ?? module
                currentModuleID = liveModule.typeId
                selectedModuleState = liveModule.status
                loadModuleDetails()
                checkVariations()
                updateAvailableStates()
                loadChargeGroups()

                // 加载突变数据（从SimModule读取）
                // 注意：只加载已应用的突变（mutatedAttributes 不为空）
                // 如果是批量模式，使用第一个相关模块的突变数据（假设它们是一致的）
                let moduleToLoad = isBatchMode ? relatedModules.first : viewModel.simulationInput.modules.first(where: { $0.flag == slotFlag })
                if let currentModule = moduleToLoad {
                    // 只有当 mutatedAttributes 不为空时，才认为已应用了突变
                    if !currentModule.mutatedAttributes.isEmpty, let mutaplasmidID = currentModule.selectedMutaplasmidID {
                        selectedMutaplasmidID = mutaplasmidID
                        loadMutaplasmidInfo(mutaplasmidID: mutaplasmidID)
                        // 从SimModule的mutatedAttributes恢复currentValue
                        for (index, attribute) in mutaplasmidAttributes.enumerated() {
                            if let multiplier = currentModule.mutatedAttributes[attribute.attributeID] {
                                mutaplasmidAttributes[index].currentValue = multiplier
                            }
                        }
                        Logger.info("加载已应用的突变: 突变质体ID: \(mutaplasmidID)，突变属性数量: \(currentModule.mutatedAttributes.count)")
                    }
                }

                // 检查当前状态是否在可用状态列表中
                if !availableModuleStates.contains(selectedModuleState)
                    && !availableModuleStates.isEmpty
                {
                    // 如果不在，设置为可用的最高状态
                    let newState = availableModuleStates.max() ?? 0
                    selectedModuleState = newState
                    viewModel.updateModuleStatus(flag: slotFlag, newStatus: newState)
                }
            }
            .alert(
                NSLocalizedString("Fitting_Mutation_Value_Input", comment: ""),
                isPresented: $showingValueInputAlert
            ) {
                TextField(
                    NSLocalizedString("Fitting_Mutation_Value_Placeholder", comment: ""),
                    text: Binding(
                        get: { editingAttributeValue },
                        set: { newValue in
                            editingAttributeValue = newValue
                            validateInputDebounced(newValue)
                        }
                    )
                )

                Button(NSLocalizedString("Misc_Done", comment: "")) {
                    confirmMutationValue()
                }
                .disabled(!isValidInput)

                Button(NSLocalizedString("Main_EVE_Mail_Cancel", comment: ""), role: .cancel) {
                    cancelEditing()
                }
            } message: {
                if let attributeID = editingAttributeID,
                   let attribute = mutaplasmidAttributes.first(where: { $0.attributeID == attributeID })
                {
                    let minPercent = formatPercentage((attribute.minValue - 1) * 100)
                    let maxPercent = formatPercentage((attribute.maxValue - 1) * 100)
                    Text(String(format: NSLocalizedString("Fitting_Mutation_Value_Range", comment: ""), minPercent, maxPercent))
                }
            }
        }
        .presentationDetents([.fraction(0.81)]) // 设置为屏幕高度的81%
        .presentationDragIndicator(.visible) // 显示拖动指示器
    }

    /// 判断模块是否可以装载弹药
    private func canLoadCharge() -> Bool {
        // 检查是否有已加载的弹药组
        return !chargeGroupIDs.isEmpty
    }

    /// 加载模块详细信息
    private func loadModuleDetails() {
        Logger.info("加载物品:\(currentModuleID)的详细信息")
        isLoading = true

        // 内存索引单点构建
        moduleDetails = DatabaseListItem(
            typeID: currentModuleID,
            databaseManager: databaseManager
        )

        isLoading = false
    }

    /// 检查是否有变体
    private func checkVariations() {
        variationsCount = databaseManager.getVariationsCount(for: currentModuleID)
    }

    /// 更新可用的模块状态
    private func updateAvailableStates() {
        // 获取当前槽位的实际模块数据
        if let actualModule = viewModel.simulationInput.modules.first(where: { $0.flag == slotFlag }) {
            // 使用实际模块的效果和属性
            availableModuleStates = getAvailableStatuses(
                itemEffects: actualModule.effects,
                itemAttributes: actualModule.attributes,
                databaseManager: databaseManager
            )
        } else {
            // 如果找不到实际模块，使用传入的模块数据作为后备
            availableModuleStates = getAvailableStatuses(
                itemEffects: module.effects,
                itemAttributes: module.attributes,
                databaseManager: databaseManager
            )
        }

        // 不自动重置状态，让调用者决定如何处理
    }

    /// 加载模块可装载的弹药组
    private func loadChargeGroups() {
        chargeGroupIDs = []

        // 优先从当前槽位的实际模块获取弹药组信息
        if let actualModule = viewModel.simulationInput.modules.first(where: { $0.flag == slotFlag }) {
            // 直接从模块的attributesByName中获取弹药组
            for (name, value) in actualModule.attributesByName {
                if name.hasPrefix("chargeGroup"), value > 0 {
                    chargeGroupIDs.append(Int(value))
                }
            }
            Logger.info("从实际模块获取弹药组 ID \(actualModule.typeId): \(chargeGroupIDs)")
        } else {
            // 如果找不到实际模块，使用数据库查询作为后备
            let attrQuery = """
                SELECT ta.attribute_id, ta.value, da.name 
                FROM typeAttributes ta 
                JOIN dogmaAttributes da ON ta.attribute_id = da.attribute_id 
                WHERE ta.type_id = ?
            """

            // 执行查询
            if case let .success(rows) = databaseManager.executeQuery(
                attrQuery, parameters: [currentModuleID]
            ) {
                for row in rows {
                    if let name = row["name"] as? String,
                       let value = row["value"] as? Double,
                       name.hasPrefix("chargeGroup"), value > 0
                    {
                        chargeGroupIDs.append(Int(value))
                    }
                }
            }
            Logger.info("从数据库查询获取弹药组 ID \(currentModuleID): \(chargeGroupIDs)")
        }
    }

    /// 加载突变质体信息
    private func loadMutaplasmidInfo(mutaplasmidID: Int) {
        // 获取突变质体的基本信息
        let mutaplasmids = databaseManager.getRequiredMutaplasmids(for: currentModuleID)
        if let mutaplasmid = mutaplasmids.first(where: { $0.typeID == mutaplasmidID }) {
            selectedMutaplasmidInfo = (
                typeID: mutaplasmid.typeID,
                name: mutaplasmid.name,
                iconFileName: mutaplasmid.iconFileName
            )
        }

        // 加载突变质体的属性信息（范围与 highIsGood 从 SDEMemoryStore 内存缓存取）
        let mutatorAttributes = SDEMemoryStore.dynamicItemAttributes(forTypeID: mutaplasmidID)

        let attributeIDs = mutatorAttributes.map(\.attributeID)
        // 查询物品的原始属性值（用于 originalValueIsNegative 判断，内存索引）
        var originalValues: [Int: Double] = [:]
        if !attributeIDs.isEmpty {
            let moduleAttributes = SDEMemoryStore.typeAttributes(for: currentModuleID)
            for attrID in attributeIDs {
                if let value = moduleAttributes[attrID] {
                    originalValues[attrID] = value
                }
            }
        }

        mutaplasmidAttributes = mutatorAttributes.map { attribute in
            MutationAttribute(
                id: attribute.attributeID,
                attributeID: attribute.attributeID,
                name: attribute.name,
                iconFileName: attribute.iconFileName,
                minValue: attribute.minValue,
                maxValue: attribute.maxValue,
                highIsGood: attribute.highIsGood,
                currentValue: nil, // 初始值为nil
                originalValue: originalValues[attribute.attributeID]
            )
        }
    }

    /// 取消编辑
    private func cancelEditing() {
        debounceTask?.cancel()
        editingAttributeID = nil
        editingAttributeValue = ""
        validationError = nil
        isValidInput = false
    }

    /// 防抖验证输入
    private func validateInputDebounced(_ value: String) {
        // 取消之前的防抖任务
        debounceTask?.cancel()

        // 创建新的防抖任务
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒

            if Task.isCancelled {
                return
            }

            await MainActor.run {
                validateInput(value)
            }
        }
    }

    /// 验证输入
    private func validateInput(_ value: String) {
        guard let attributeID = editingAttributeID,
              let attribute = mutaplasmidAttributes.first(where: { $0.attributeID == attributeID })
        else {
            Logger.warning("突变数值验证失败: 未找到属性ID \(editingAttributeID ?? -1)")
            validationError = nil
            isValidInput = false
            return
        }

        // 如果输入为空，不显示错误，但也不允许确认
        if value.trimmingCharacters(in: .whitespaces).isEmpty {
            Logger.info("突变数值验证: 输入为空")
            validationError = nil
            isValidInput = false
            return
        }

        Logger.info("突变数值验证: 开始验证输入 '\(value)'")

        // 使用正则表达式验证：只允许负号、正号、数字、小数点
        // 允许的格式：可选的正负号，后跟数字，可选的小数点和更多数字
        let pattern = #"^[+-]?(\d+\.?\d*|\.\d+)$"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: value.utf16.count)

        guard let regex = regex,
              regex.firstMatch(in: value, options: [], range: range) != nil
        else {
            Logger.warning("突变数值验证失败: 格式不合法 '\(value)'，只允许数字、小数点、正负号")
            validationError = NSLocalizedString("Fitting_Mutation_Value_Invalid_Format", comment: "")
            isValidInput = false
            return
        }

        Logger.info("突变数值验证: 格式校验通过")

        // 转换为Double
        guard let doubleValue = Double(value) else {
            Logger.warning("突变数值验证失败: 无法转换为数字 '\(value)'")
            validationError = NSLocalizedString("Fitting_Mutation_Value_Invalid_Number", comment: "")
            isValidInput = false
            return
        }

        Logger.info("突变数值验证: 数值转换成功 \(doubleValue)")

        // 将用户输入的百分比转换为倍数（避免浮点数精度问题）
        // 用户输入的是百分比（如 15 表示 15%），需要转换为倍数（1.15）
        let inputMultiplier = (doubleValue / 100) + 1

        // 直接使用数据库的原始倍数进行比较，避免百分比转换的精度误差
        Logger.info("突变数值验证: 范围检查 - 输入倍数: \(inputMultiplier), 允许范围: \(attribute.minValue) 至 \(attribute.maxValue)")

        // 直接比较倍数，避免浮点数精度问题
        if inputMultiplier < attribute.minValue || inputMultiplier > attribute.maxValue {
            // 转换为百分比用于显示（仅在错误时转换）
            let minPercent = (attribute.minValue - 1) * 100
            let maxPercent = (attribute.maxValue - 1) * 100
            let minPercentStr = formatPercentage(minPercent)
            let maxPercentStr = formatPercentage(maxPercent)
            Logger.warning("突变数值验证失败: 超出范围 '\(value)' (输入倍数: \(inputMultiplier), 范围倍数: \(attribute.minValue) 至 \(attribute.maxValue), 范围百分比: \(minPercentStr) 至 \(maxPercentStr))")
            validationError = String(format: NSLocalizedString("Fitting_Mutation_Value_Out_Of_Range", comment: ""), minPercentStr, maxPercentStr)
            isValidInput = false
            return
        }

        // 验证通过
        Logger.info("突变数值验证: 验证通过 - 输入: '\(value)' (百分比: \(doubleValue)%, 倍数: \(inputMultiplier))")
        validationError = nil
        isValidInput = true
    }

    /// 确认突变数值
    private func confirmMutationValue() {
        guard isValidInput,
              let attributeID = editingAttributeID,
              let attributeIndex = mutaplasmidAttributes.firstIndex(where: { $0.attributeID == attributeID })
        else { return }

        // 再次验证（确保数据一致性）
        guard let doubleValue = Double(editingAttributeValue) else {
            return
        }

        // 更新属性值（将百分比转换回倍数）
        let mutationValue = (doubleValue / 100) + 1
        mutaplasmidAttributes[attributeIndex].currentValue = mutationValue

        // 收集所有已设置的突变属性值
        let mutatedAttributes = mutaplasmidAttributes.reduce(into: [Int: Double]()) { result, attribute in
            if let currentValue = attribute.currentValue {
                result[attribute.attributeID] = currentValue
            }
        }

        // 只有当至少设置了一个突变属性值时，才真正应用突变（保存、重算属性）
        if !mutatedAttributes.isEmpty {
            // 堆叠模式下，只对当前选中的装备进行突变修改，不对所有堆叠的装备进行修改
            // 这样可以让用户单独为某个装备设置突变，而不会影响其他相同类型的装备
            viewModel.updateModuleMutation(
                flag: slotFlag,
                mutaplasmidID: selectedMutaplasmidID,
                mutatedAttributes: mutatedAttributes
            )
            Logger.info("应用突变: 槽位 \(slotFlag.rawValue)，突变属性数量: \(mutatedAttributes.count)")
        } else {
            Logger.info("突变属性值为空，不应用突变（仅临时显示）")
        }

        cancelEditing()
    }

    /// 格式化突变数值（用于输入框）
    private func formatMutationValueForInput(_ percentage: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.numberStyle = .decimal

        if let formatted = formatter.string(from: NSNumber(value: percentage)) {
            return formatted
        }
        return String(format: "%.2f", percentage)
    }

    /// 格式化百分比（用于提示信息）
    private func formatPercentage(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.numberStyle = .decimal

        if let formatted = formatter.string(from: NSNumber(value: value)) {
            if value >= 0 {
                return "+\(formatted)%"
            } else {
                return "\(formatted)%"
            }
        }
        return String(format: "%.2f%%", value)
    }
}

/// 突变属性行视图
struct MutationAttributeRowView: View {
    let attribute: MutationAttribute
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // 第一行：属性图标、文本和编辑按钮
                HStack(spacing: 8) {
                    if let iconFileName = attribute.iconFileName, !iconFileName.isEmpty {
                        IconManager.shared.loadImage(for: iconFileName)
                            .resizable()
                            .frame(width: 24, height: 24)
                    }

                    Text(attribute.name)
                        .font(.body)
                        .foregroundColor(.primary)

                    Spacer()

                    // 右侧显示实际突变数值或编辑按钮
                    if let currentValue = attribute.currentValue {
                        Text(formatMutationValue(currentValue))
                            .font(.body)
                            .foregroundColor(getValueColor(currentValue))
                    } else {
                        Text(NSLocalizedString("Fitting_Mutation_Edit", comment: ""))
                            .font(.body)
                            .foregroundColor(.blue)
                    }
                }

                // 第二行：进度条（只有编辑过的属性才显示）
                if let currentValue = attribute.currentValue {
                    MutationProgressBarView(
                        currentValue: currentValue,
                        minValue: attribute.minValue,
                        maxValue: attribute.maxValue,
                        highIsGood: attribute.highIsGood,
                        originalValueIsNegative: (attribute.originalValue ?? 0) < 0
                    )
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }

    /// 格式化突变数值（用于显示）
    private func formatMutationValue(_ value: Double) -> String {
        let percentage = (value - 1) * 100
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.numberStyle = .decimal

        if let formatted = formatter.string(from: NSNumber(value: percentage)) {
            return "\(formatted)%"
        }
        return String(format: "%.2f%%", percentage)
    }

    /// 获取数值颜色（与 MutationProgressBarView 逻辑一致，需考虑 originalValueIsNegative）
    private func getValueColor(_ value: Double) -> Color {
        if abs(value - 1) < 0.0001 {
            return .secondary
        }
        let originalValueIsNegative = (attribute.originalValue ?? 0) < 0
        let multiplierIndicatesIncrease = originalValueIsNegative ? (value < 1) : (value > 1)
        let improved = attribute.highIsGood ? multiplierIndicatesIncrease : !multiplierIndicatesIncrease
        return improved ? .green : .red
    }
}

/// 突变进度条视图
struct MutationProgressBarView: View {
    let currentValue: Double?
    let minValue: Double
    let maxValue: Double
    let highIsGood: Bool
    /// 当原始值为负时（如 -27），乘数 > 1 表示数值变得更负（diff < 0），需反转判断逻辑
    var originalValueIsNegative: Bool = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let centerX = width / 2

            // 基点（0%）在中间，对应 value = 1.0
            let baseValue = 1.0

            // 计算进度
            let (progress, progressColor, fillDirection) = calculateProgress(
                currentValue: currentValue,
                minValue: minValue,
                maxValue: maxValue,
                baseValue: baseValue,
                highIsGood: highIsGood,
                originalValueIsNegative: originalValueIsNegative
            )

            ZStack(alignment: .leading) {
                // 背景（浅灰色）
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 4)

                // 进度条填充（从中心点开始）
                if progress > 0 {
                    HStack(spacing: 0) {
                        // 左侧空白（占据中心点左侧的空间）
                        Spacer()
                            .frame(width: centerX)

                        // 进度条填充区域
                        if fillDirection == .right {
                            // 向右填充：从中心点向右
                            RoundedRectangle(cornerRadius: height / 2)
                                .fill(progressColor)
                                .frame(width: centerX * progress, height: height)
                        } else {
                            // 向左填充：从中心点向左
                            // 使用负的 frame 宽度和 offset 来实现向左填充
                            RoundedRectangle(cornerRadius: height / 2)
                                .fill(progressColor)
                                .frame(width: centerX * progress, height: height)
                                .offset(x: -centerX * progress)
                        }
                    }
                }

                // 中间白点（基点）
                Circle()
                    .fill(Color.white)
                    .frame(width: height * 1.2, height: height * 1.2)
                    .overlay(
                        Circle()
                            .stroke(Color(.systemGray3), lineWidth: 1)
                    )
                    .position(x: centerX, y: height / 2)
            }
        }
        .frame(height: 6)
    }

    /// 计算进度、颜色和方向
    private func calculateProgress(
        currentValue: Double?,
        minValue: Double,
        maxValue: Double,
        baseValue: Double,
        highIsGood: Bool,
        originalValueIsNegative: Bool = false
    ) -> (progress: Double, color: Color, direction: FillDirection) {
        guard let value = currentValue else {
            return (0, .clear, .right)
        }

        let progress: Double
        let progressColor: Color
        let fillDirection: FillDirection

        // 判断是变好还是变差
        // 当 originalValue > 0：乘数 > 1 表示数值增加，< 1 表示减少
        // 当 originalValue < 0：乘数 > 1 表示数值更负（减少），< 1 表示更接近 0（增加），需反转
        let multiplierIndicatesIncrease = originalValueIsNegative ? (value < baseValue) : (value > baseValue)
        let isGood = highIsGood ? multiplierIndicatesIncrease : !multiplierIndicatesIncrease

        if isGood {
            // 变好：绿色，向右填充
            progressColor = .green
            fillDirection = .right

            if value >= baseValue {
                // 向右填充（value >= 1.0）
                let range = maxValue - baseValue
                if range > 0 {
                    progress = (value - baseValue) / range
                } else {
                    progress = 0
                }
            } else {
                // 向右填充（value < 1.0，但这是变好的情况，比如 highIsGood=false）
                // 需要计算从 minValue 到 baseValue 的进度
                let range = baseValue - minValue
                if range > 0 {
                    // 计算从 value 到 baseValue 的进度，然后反向（因为向右填充）
                    progress = (baseValue - value) / range
                } else {
                    progress = 0
                }
            }
        } else {
            // 变差：红色，向左填充
            progressColor = .red
            fillDirection = .left

            if value < baseValue {
                // 向左填充（value < 1.0）
                let range = baseValue - minValue
                if range > 0 {
                    progress = (baseValue - value) / range
                } else {
                    progress = 0
                }
            } else {
                // 向左填充（value >= 1.0，但这是变差的情况，比如 highIsGood=false）
                // 需要计算从 baseValue 到 maxValue 的进度
                let range = maxValue - baseValue
                if range > 0 {
                    // 计算从 baseValue 到 value 的进度，然后反向（因为向左填充）
                    progress = (value - baseValue) / range
                } else {
                    progress = 0
                }
            }
        }

        return (progress, progressColor, fillDirection)
    }

    enum FillDirection {
        case left
        case right
    }
}

/// 模块状态选择器
struct ModuleStatusSelector: View {
    @Binding var selectedState: Int
    let availableStates: [Int]
    let onStateChanged: (Int) -> Void

    var body: some View {
        ModuleStatusView(
            availableStates: availableStates,
            selectedState: $selectedState,
            isEditable: true,
            onStateChanged: onStateChanged
        )
    }
}

/// 弹药选择视图
struct ChargeSelectionView: View {
    let databaseManager: DatabaseManager
    let chargeGroupIDs: [Int]
    let typeID: Int
    let slotFlag: FittingFlag
    let viewModel: FittingEditorViewModel
    let module: SimModule
    let relatedModules: [SimModule]

    // 自定义回调函数
    var onChargeSelected: (Int, String, String?) -> Void
    var onClearCharge: () -> Void

    @State private var items: [DatabaseListItem] = []
    @State private var cargoAmmoDbItems: [DatabaseListItem] = []
    @State private var metaGroupNames: [Int: String] = [:]
    @State private var isLoading = true
    @Environment(\.dismiss) var dismiss

    /// 使用原始viewModel初始化，但提供符合参考代码的回调方式
    init(
        databaseManager: DatabaseManager,
        chargeGroupIDs: [Int],
        typeID: Int,
        slotFlag: FittingFlag,
        viewModel: FittingEditorViewModel,
        module: SimModule,
        relatedModules: [SimModule]
    ) {
        self.databaseManager = databaseManager
        self.chargeGroupIDs = chargeGroupIDs
        self.typeID = typeID
        self.slotFlag = slotFlag
        self.viewModel = viewModel
        self.module = module
        self.relatedModules = relatedModules

        // 初始化回调函数 - 支持批量操作
        onChargeSelected = { chargeID, chargeName, iconFileName in
            if relatedModules.count > 1 {
                // 批量模式：为所有相关模块安装弹药
                let flags = relatedModules.compactMap { $0.flag }
                viewModel.batchInstallCharge(
                    typeId: chargeID,
                    name: chargeName,
                    iconFileName: iconFileName,
                    flags: flags
                )
                Logger.info("批量安装弹药: \(chargeName) 到 \(relatedModules.count) 个模块")
            } else {
                // 单个模式：只为当前模块安装弹药
                viewModel.installCharge(
                    typeId: chargeID,
                    name: chargeName,
                    iconFileName: iconFileName,
                    flag: slotFlag
                )
            }
        }

        onClearCharge = {
            if relatedModules.count > 1 {
                // 批量模式：清除所有相关模块的弹药
                let flags = relatedModules.compactMap { $0.flag }
                viewModel.batchRemoveCharge(flags: flags)
                Logger.info("批量清除弹药: \(relatedModules.count) 个模块")
            } else {
                // 单个模式：只清除当前模块的弹药
                viewModel.removeCharge(flag: slotFlag)
            }
        }
    }

    var body: some View {
        List {
            // 如果是批量模式，显示批量操作信息
            if relatedModules.count > 1 {
                Section(header: Text(NSLocalizedString("Fitting_Batch_Operation", comment: ""))) {
                    HStack {
                        Image(systemName: "square.stack.3d.up")
                            .foregroundColor(.blue)
                        VStack(alignment: .leading) {
                            Text(NSLocalizedString("Fitting_Batch_Ammo_Setting", comment: ""))
                                .font(.headline)
                            Text(
                                String(
                                    format: NSLocalizedString(
                                        "Fitting_Batch_Ammo_Description", comment: ""
                                    ),
                                    relatedModules.count
                                )
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }

            // 清除弹药选项
            Button(action: {
                onClearCharge()
                dismiss() // 选择后关闭当前视图
            }) {
                HStack {
                    Text(NSLocalizedString("Fitting_Setting_No_Ammo", comment: ""))
                        .foregroundColor(.red)
                    Spacer()
                }
            }

            // 货舱中的弹药
            if !cargoAmmoDbItems.isEmpty {
                Section(header: Text(NSLocalizedString("Fitting_Cargo_Ammo", comment: "货舱中的弹药"))) {
                    ForEach(cargoAmmoDbItems, id: \.id) { item in
                        HStack {
                            DatabaseListItemView(item: item, showDetails: true)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onChargeSelected(item.id, item.name, item.iconFileName)
                            dismiss()
                        }
                    }
                }
            }

            if isLoading {
                HStack {
                    ProgressView()
                    Text(NSLocalizedString("Misc_Loading", comment: ""))
                }
            } else {
                ForEach(groupedItems.keys.sorted(), id: \.self) { metaGroupID in
                    Section(
                        header: Text(
                            metaGroupNames[metaGroupID] ?? NSLocalizedString("Unknown", comment: "")
                        )
                    ) {
                        ForEach(groupedItems[metaGroupID] ?? [], id: \.id) { item in
                            HStack {
                                DatabaseListItemView(
                                    item: item,
                                    showDetails: true,
                                    showCargoIndicator: cargoTypeIds.contains(item.id)
                                )
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onChargeSelected(item.id, item.name, item.iconFileName)
                                dismiss() // 选择后关闭当前视图
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(Text(NSLocalizedString("Fitting_Setting_Ammo", comment: "")))
        .onAppear {
            loadCharges()
        }
    }

    /// 货舱中的物品 typeId 集合，用于在非货舱弹药列表中显示货舱图标
    private var cargoTypeIds: Set<Int> {
        Set(viewModel.simulationInput.cargo.items.map { $0.typeId })
    }

    private var groupedItems: [Int: [DatabaseListItem]] {
        let grouped = Dictionary(grouping: items) { $0.metaGroupID ?? 0 }

        // 对每个分组内的项目进行排序
        return grouped.mapValues { items in
            items.sorted { item1, item2 in
                // 首先按名称的本地化标准比较排序
                let nameComparison = item1.name.localizedStandardCompare(item2.name)
                if nameComparison != .orderedSame {
                    return nameComparison == .orderedAscending
                }
                // 如果名称相同，则按typeID排序
                return item1.id < item2.id
            }
        }
    }

    private func loadCharges() {
        isLoading = true

        // 如果没有弹药组，直接返回
        if chargeGroupIDs.isEmpty {
            isLoading = false
            return
        }

        // 弹药组 ID 集合（内存过滤用）
        let groupIDSet = Set(chargeGroupIDs)

        // 获取模块的chargeSize属性
        var chargeSize: Double? = nil

        // 直接从module的attributesByName中获取chargeSize
        if let size = module.attributesByName["chargeSize"] {
            Logger.info("模块的chargeSize属性值: \(size)")
            chargeSize = size
        }

        // 获取模块的容量
        var moduleCapacity: Double? = nil
        if let capacity = module.attributesByName["capacity"] {
            Logger.info("模块的capacity属性值: \(capacity)")
            moduleCapacity = capacity
        }

        // 基础候选：groupID 匹配且已发布（内存索引）
        var candidateTypeIDs = Set<Int>()
        for (typeID, info) in SDEMemoryStore.types {
            if let gid = info.groupID, groupIDSet.contains(gid), info.published {
                candidateTypeIDs.insert(typeID)
            }
        }

        // 容量限制（内存索引）
        if let capacity = moduleCapacity, capacity > 0 {
            candidateTypeIDs = candidateTypeIDs.filter { typeID in
                let volume = SDEMemoryStore.type(for: typeID)?.volume ?? .infinity
                return volume <= capacity
            }
            Logger.info("添加容量筛选条件: \(capacity)")
        }

        // chargeSize 限制（typeAttributes 未预加载，保留 SQL 查询）
        if let size = chargeSize, size > 0 {
            let chargeQuery = """
                SELECT ta.type_id
                FROM typeAttributes ta
                JOIN dogmaAttributes dat ON ta.attribute_id = dat.attribute_id
                WHERE dat.name = 'chargeSize' AND ta.value = ?
            """
            var chargeTypeIDs = Set<Int>()
            if case let .success(rows) = databaseManager.executeQuery(
                chargeQuery, parameters: [size]
            ) {
                for row in rows {
                    if let typeID = row["type_id"] as? Int {
                        chargeTypeIDs.insert(typeID)
                    }
                }
            }
            candidateTypeIDs.formIntersection(chargeTypeIDs)
            Logger.info("添加chargeSize筛选条件: \(size)")
        }

        // 内存索引批量构建弹药
        items = DatabaseListItem.listItems(
            for: candidateTypeIDs.sorted(),
            databaseManager: databaseManager
        )
        Logger.info("找到 \(items.count) 种可用弹药")

        // 获取Meta组名称（内存索引）
        metaGroupNames = SDEMemoryStore.localizedMetaGroupNames

        // 加载货舱中可作为弹药的物品（含伤害属性）
        let cargoTypeIds = viewModel.simulationInput.cargo.items
            .filter { viewModel.canLoadCharge(moduleTypeId: typeID, chargeTypeId: $0.typeId) }
            .map { $0.typeId }
        if !cargoTypeIds.isEmpty {
            cargoAmmoDbItems = DatabaseListItem.listItems(
                for: cargoTypeIds,
                databaseManager: databaseManager
            )
        } else {
            cargoAmmoDbItems = []
        }

        isLoading = false
    }
}

/// 模块变体选择视图
struct ModuleVariationsView: View {
    let databaseManager: DatabaseManager
    let typeID: Int
    let onSelectVariation: (Int) -> Void

    @State private var items: [DatabaseListItem] = []
    @State private var metaGroupNames: [Int: String] = [:]
    @State private var isLoading = true
    @Environment(\.dismiss) var dismiss

    var body: some View {
        List {
            if isLoading {
                HStack {
                    ProgressView()
                    Text(NSLocalizedString("Misc_Loading", comment: ""))
                }
            } else {
                ForEach(groupedItems.keys.sorted(), id: \.self) { metaGroupID in
                    Section(
                        header: Text(
                            metaGroupNames[metaGroupID] ?? NSLocalizedString("Unknown", comment: "")
                        )
                    ) {
                        ForEach(groupedItems[metaGroupID] ?? [], id: \.id) { item in
                            HStack {
                                DatabaseListItemView(item: item, showDetails: true)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelectVariation(item.id)
                                dismiss() // 只关闭变体选择器，返回到设置页
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Fitting_select_Variations", comment: ""))
        .onAppear {
            loadData()
        }
    }

    private var groupedItems: [Int: [DatabaseListItem]] {
        Dictionary(grouping: items) { $0.metaGroupID ?? 0 }
    }

    private func loadData() {
        isLoading = true
        let result = databaseManager.loadVariations(for: typeID)
        items = result.0
        metaGroupNames = result.1
        isLoading = false
    }
}
