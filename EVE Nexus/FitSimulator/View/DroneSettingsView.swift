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
    @State private var editingAttributeID: Int? = nil // 正在编辑的属性ID
    @State private var editingAttributeValue: String = "" // 正在编辑的属性值文本
    @State private var showingValueInputAlert = false // 显示输入弹窗
    @State private var validationError: String? = nil // 验证错误信息
    @State private var isValidInput: Bool = false // 输入是否合法
    @State private var debounceTask: Task<Void, Never>? = nil // 防抖任务

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
                        ForEach(mutaplasmidAttributes.sorted { $0.attributeID < $1.attributeID }) { attribute in
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
                            // 清除SimDrone的突变数据
                            viewModel.updateDroneMutation(typeId: currentDroneID, mutaplasmidID: nil, mutatedAttributes: [:])
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

        let attributeIDs = mutatorAttributes.map(\.attributeID)
        // 查询物品的原始属性值（用于 originalValueIsNegative 判断，内存索引）
        var originalValues: [Int: Double] = [:]
        if !attributeIDs.isEmpty {
            let droneAttributes = SDEMemoryStore.typeAttributes(for: currentDroneID)
            for attrID in attributeIDs {
                if let value = droneAttributes[attrID] {
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

        // 更新SimDrone的突变数据
        let mutatedAttributes = mutaplasmidAttributes.reduce(into: [Int: Double]()) { result, attribute in
            if let currentValue = attribute.currentValue {
                result[attribute.attributeID] = currentValue
            }
        }
        viewModel.updateDroneMutation(
            typeId: currentDroneID,
            mutaplasmidID: selectedMutaplasmidID,
            mutatedAttributes: mutatedAttributes
        )

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
