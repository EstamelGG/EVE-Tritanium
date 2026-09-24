import SwiftUI

/// 无人机设置视图 - 用于显示和修改已安装无人机的详细设置
struct DroneSettingsView: View {
    // 无人机和数据依赖
    let drone: SimDrone
    let databaseManager: DatabaseManager
    let viewModel: FittingEditorViewModel

    // 回调函数
    var onDelete: () -> Void
    var onUpdateQuantity: (Int, Int) -> Void // (新数量, 新激活数)
    var onReplaceDrone: (Int) -> Void // 新无人机类型ID

    /// 环境变量
    @Environment(\.dismiss) var dismiss

    // 状态变量
    @State private var droneDetails: DatabaseListItem? = nil
    @State private var isLoading = true
    @State private var variationsCount: Int = 0
    @State private var quantity: Int
    @State private var activeCount: Int
    @State private var currentDroneID: Int // 当前无人机ID
    @State private var initialActiveCount: Int // 用于跟踪激活数量是否变化
    @State private var hasActiveCountChanged = false // 跟踪激活数量是否发生了变化
    @State private var hasQuantityChanged = false // 跟踪总数量是否发生了变化
    @State private var selectedMutaplasmidID: Int? = nil // 选中的突变质体ID
    @State private var selectedMutaplasmidInfo: (typeID: Int, name: String, iconFileName: String)? = nil // 突变质体信息
    @State private var mutaplasmidAttributes: [MutationAttribute] = [] // 突变质体的属性列表（包含范围和当前值）
    @State private var droneAttributeValues: [Int: Double] = [:] // 无人机原始属性表（用于突变数值换算显示）
    @State private var showingMutationEditor = false // 是否显示突变编辑面板

    /// 初始化方法
    init(
        drone: SimDrone,
        databaseManager: DatabaseManager,
        viewModel: FittingEditorViewModel,
        onDelete: @escaping () -> Void = {},
        onUpdateQuantity: @escaping (Int, Int) -> Void = { _, _ in },
        onReplaceDrone: @escaping (Int) -> Void = { _ in }
    ) {
        self.drone = drone
        self.databaseManager = databaseManager
        self.viewModel = viewModel
        self.onDelete = onDelete
        self.onUpdateQuantity = onUpdateQuantity
        self.onReplaceDrone = onReplaceDrone

        // 初始化状态变量
        _quantity = State(initialValue: drone.quantity)
        _activeCount = State(initialValue: drone.activeCount)
        _initialActiveCount = State(initialValue: drone.activeCount)
        _currentDroneID = State(initialValue: drone.typeId)
    }

    var body: some View {
        NavigationStack {
            List {
                Section(
                    header:
                    HStack {
                        Text(NSLocalizedString("Fitting_Setting_Drones", comment: ""))
                        Spacer()
                        // 获取计算后的无人机属性
                        let currentOutputDrone = viewModel.simulationOutput?.drones.first(
                            where: { $0.typeId == currentDroneID }
                        )
                        NavigationLink(
                            destination: ShowItemInfo(
                                databaseManager: databaseManager, itemID: currentDroneID,
                                modifiedAttributes: currentOutputDrone?.attributes
                            )
                        ) {
                            Text(NSLocalizedString("View_Details", comment: ""))
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                ) {
                    if isLoading {
                        HStack {
                            ProgressView()
                            Text(NSLocalizedString("Misc_Loading", comment: ""))
                        }
                    } else if let details = droneDetails {
                        // 如果有变体，点击显示变体列表
                        if variationsCount > 1 {
                            NavigationLink(
                                destination: DroneVariationSelectionView(
                                    databaseManager: databaseManager,
                                    currentDroneID: currentDroneID,
                                    onSelectVariation: { variationID in
                                        // 保存当前状态
                                        let previousQuantity = quantity
                                        let previousActiveCount = min(activeCount, previousQuantity)

                                        // 替换无人机
                                        onReplaceDrone(variationID)

                                        // 更新当前无人机ID
                                        currentDroneID = variationID

                                        // 重新加载无人机信息
                                        loadDroneDetails()
                                        checkVariations()

                                        // 保持之前的数量和激活状态
                                        quantity = previousQuantity
                                        activeCount = previousActiveCount

                                        // 更新无人机数量和激活状态
                                        onUpdateQuantity(quantity, activeCount)

                                        // 如果激活数量与初始值不同，标记为已更改
                                        if activeCount != initialActiveCount {
                                            hasActiveCountChanged = true
                                        }
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

                    // 数量设置
                    Stepper(value: $quantity, in: 1 ... 500, step: 1) {
                        Text(
                            String(
                                format: NSLocalizedString("Fitting_Drones_Qty", comment: ""),
                                quantity
                            )
                        )
                    }
                    .onChange(of: quantity) { _, newValue in
                        // 如果数量小于激活数，更新激活数
                        if activeCount > newValue {
                            activeCount = newValue
                            // 如果激活数量与初始值不同，标记为已更改
                            if activeCount != initialActiveCount {
                                hasActiveCountChanged = true
                            }
                        }

                        // 标记数量已更改
                        hasQuantityChanged = true

                        // 更新无人机数量
                        onUpdateQuantity(newValue, activeCount)
                    }

                    // 激活数量设置
                    Stepper(value: $activeCount, in: 0 ... min(quantity, viewModel.maxActiveDrones)) {
                        Text(
                            String(
                                format: NSLocalizedString("Fitting_Act_Drones_Qty", comment: ""),
                                activeCount
                            )
                        )
                    }
                    .onChange(of: activeCount) { _, newValue in
                        // 更新激活数量
                        onUpdateQuantity(quantity, newValue)

                        // 如果激活数量与初始值不同，标记为已更改
                        if newValue != initialActiveCount {
                            hasActiveCountChanged = true
                        } else {
                            hasActiveCountChanged = false
                        }
                    }
                }

                // 已选中的突变质体
                if let mutaplasmidInfo = selectedMutaplasmidInfo {
                    Section {
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
                        ForEach(sortedMutationAttributes) { attribute in
                            mutationAttributeRow(for: attribute)
                        }

                        // 最后一行：移除按钮
                        Button(action: {
                            // 清除SimDrone的突变数据
                            viewModel.updateDroneMutation(typeId: currentDroneID, mutaplasmidID: nil, mutatedAttributes: [:])
                            selectedMutaplasmidID = nil
                            selectedMutaplasmidInfo = nil
                            mutaplasmidAttributes = []
                        }) {
                            Text(NSLocalizedString("Fitting_Remove_Mutation", comment: ""))
                                .foregroundColor(.red)
                        }
                    } header: {
                        droneMutationSectionHeader
                    }
                }

                // 可用突变质体
                let availableMutaplasmids = databaseManager.getRequiredMutaplasmids(for: currentDroneID)
                if !availableMutaplasmids.isEmpty {
                    Section(header: Text(NSLocalizedString("Fitting_Available_Mutations", comment: ""))) {
                        NavigationLink(
                            destination: MutaplasmidSelectionView(
                                databaseManager: databaseManager,
                                itemTypeID: currentDroneID,
                                onSelectMutaplasmid: { mutaplasmidID in
                                    // 选择突变质体后的处理
                                    selectedMutaplasmidID = mutaplasmidID
                                    loadMutaplasmidInfo(mutaplasmidID: mutaplasmidID)
                                    // 保存突变质体选择（此时还没有突变数值，所以mutatedAttributes为空）
                                    viewModel.updateDroneMutation(typeId: currentDroneID, mutaplasmidID: mutaplasmidID, mutatedAttributes: [:])
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
            .navigationTitle(NSLocalizedString("Fitting_Setting_Drones", comment: ""))
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
                loadDroneDetails()
                checkVariations()

                // 加载突变数据（从SimDrone读取）
                if let currentDrone = viewModel.simulationInput.drones.first(where: { $0.typeId == currentDroneID }) {
                    if let mutaplasmidID = currentDrone.selectedMutaplasmidID {
                        selectedMutaplasmidID = mutaplasmidID
                        loadMutaplasmidInfo(mutaplasmidID: mutaplasmidID)
                        // 从SimDrone的mutatedAttributes恢复currentValue
                        for (index, attribute) in mutaplasmidAttributes.enumerated() {
                            if let multiplier = currentDrone.mutatedAttributes[attribute.attributeID] {
                                mutaplasmidAttributes[index].currentValue = multiplier
                            }
                        }
                    }
                }
            }
            .onDisappear {
                // 无人机设置视图消失时，如果激活数量或总数量有变化，重新计算整个配置
                if hasActiveCountChanged || hasQuantityChanged {
                    Logger.info("无人机数量或激活数量发生变化，重新计算属性")
                    viewModel.calculateAttributes()
                }
            }
        }
        .sheet(isPresented: $showingMutationEditor) {
            mutationEditorSheet
        }
        .presentationDetents([.fraction(0.81)]) // 设置为屏幕高度的81%
        .presentationDragIndicator(.visible) // 显示拖动指示器
    }

    /// 加载无人机详细信息
    private func loadDroneDetails() {
        isLoading = true

        // 内存索引单点构建
        droneDetails = DatabaseListItem(
            typeID: currentDroneID,
            databaseManager: databaseManager
        )

        isLoading = false
    }

    /// 检查是否有变体
    private func checkVariations() {
        variationsCount = databaseManager.getVariationsCount(for: currentDroneID)
    }

    /// 加载突变质体信息
    private func loadMutaplasmidInfo(mutaplasmidID: Int) {
        // 获取突变质体的基本信息
        let mutaplasmids = databaseManager.getRequiredMutaplasmids(for: currentDroneID)
        if let mutaplasmid = mutaplasmids.first(where: { $0.typeID == mutaplasmidID }) {
            selectedMutaplasmidInfo = (
                typeID: mutaplasmid.typeID,
                name: mutaplasmid.name,
                iconFileName: mutaplasmid.iconFileName
            )
        }

        // 加载突变质体的属性信息（范围与 highIsGood 从 SDEMemoryStore 内存缓存取）
        let mutatorAttributes = SDEMemoryStore.dynamicItemAttributes(forTypeID: mutaplasmidID)

        // 无人机的原始属性表（用于数值换算显示与突变方向判断）
        let droneAttributes = SDEMemoryStore.typeAttributes(for: currentDroneID)
        droneAttributeValues = droneAttributes

        mutaplasmidAttributes = mutatorAttributes.map { attribute in
            MutationAttribute(
                id: attribute.attributeID,
                attributeID: attribute.attributeID,
                name: attribute.name,
                iconFileName: attribute.iconFileName,
                unitID: attribute.unitID,
                minValue: attribute.minValue,
                maxValue: attribute.maxValue,
                highIsGood: attribute.highIsGood,
                currentValue: nil, // 初始值为nil
                originalValue: droneAttributes[attribute.attributeID]
            )
        }
    }

    // MARK: - 突变区块

    /// 排序后的可突变属性
    private var sortedMutationAttributes: [MutationAttribute] {
        mutaplasmidAttributes.sorted { $0.attributeID < $1.attributeID }
    }

    /// 突变区块标题（右侧带编辑按钮）
    private var droneMutationSectionHeader: some View {
        HStack {
            Text(NSLocalizedString("Fitting_Selected_Mutation", comment: ""))
            Spacer()
            Button {
                showingMutationEditor = true
            } label: {
                Text(NSLocalizedString("Fitting_Mutation_Edit", comment: ""))
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
            .textCase(nil)
            .disabled(mutaplasmidAttributes.isEmpty)
        }
    }

    /// 突变编辑面板（拖动实时计算，保存后才重算装配模拟）
    private var mutationEditorSheet: some View {
        MutationEditSheetView(
            mutaplasmidName: selectedMutaplasmidInfo?.name ?? "",
            mutaplasmidIconFileName: selectedMutaplasmidInfo?.iconFileName,
            attributes: sortedMutationAttributes,
            referenceAttributes: droneAttributeValues,
            onSave: { mutatedAttributes in
                applyMutation(mutatedAttributes)
            }
        )
    }

    /// 单行突变属性（只读展示，编辑在面板中进行）
    private func mutationAttributeRow(for attribute: MutationAttribute) -> some View {
        MutationAttributeControlRow(
            name: attribute.name,
            iconFileName: attribute.iconFileName,
            attributeID: attribute.attributeID,
            unitID: attribute.unitID,
            originalValue: attribute.originalValue ?? 1,
            minValue: attribute.minValue,
            maxValue: attribute.maxValue,
            highIsGood: attribute.highIsGood,
            multiplier: .constant(attribute.currentValue ?? 1.0),
            referenceAttributes: droneAttributeValues,
            isInteractive: false
        )
    }

    /// 应用突变（只有点击保存后才重算装配模拟）
    private func applyMutation(_ mutatedAttributes: [Int: Double]) {
        // 同步本地状态，使列表立即反映最新数值
        for index in mutaplasmidAttributes.indices {
            mutaplasmidAttributes[index].currentValue =
                mutatedAttributes[mutaplasmidAttributes[index].attributeID]
        }

        guard !mutatedAttributes.isEmpty else {
            Logger.info("突变属性值为空，不应用突变（仅临时显示）")
            return
        }

        viewModel.updateDroneMutation(
            typeId: currentDroneID,
            mutaplasmidID: selectedMutaplasmidID,
            mutatedAttributes: mutatedAttributes
        )
        Logger.info("应用无人机突变: 无人机ID \(currentDroneID)，突变属性数量: \(mutatedAttributes.count)")
    }
}

/// 无人机变体选择视图 - 独立的Sheet视图
struct DroneVariationSelectionView: View {
    let databaseManager: DatabaseManager
    let currentDroneID: Int
    let onSelectVariation: (Int) -> Void

    @Environment(\.dismiss) var dismiss
    @State private var items: [DatabaseListItem] = []
    @State private var metaGroupNames: [Int: String] = [:]
    @State private var isLoading = true

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
        .navigationTitle(NSLocalizedString("Main_Database_Variations", comment: ""))
        .onAppear {
            loadData()
        }
    }

    private var groupedItems: [Int: [DatabaseListItem]] {
        Dictionary(grouping: items) { $0.metaGroupID ?? 0 }
    }

    private func loadData() {
        isLoading = true
        let result = databaseManager.loadVariations(for: currentDroneID)
        items = result.0
        metaGroupNames = result.1
        isLoading = false
    }
}
