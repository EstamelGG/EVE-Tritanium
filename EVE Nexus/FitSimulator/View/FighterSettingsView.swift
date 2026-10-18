import SwiftUI

/// 舰载机设置视图 - 用于显示和修改已安装舰载机的详细设置
struct FighterSettingsView: View {
    // 舰载机和数据依赖
    @ObservedObject var selectedFighter: FighterState
    let databaseManager: DatabaseManager
    let viewModel: FittingEditorViewModel

    /// 获取当前选中的舰载机
    private var fighter: SimFighterSquad {
        selectedFighter.fighterSquad!
    }

    // 回调函数
    var onDelete: () -> Void
    var onUpdateQuantity: (Int) -> Void // 新数量
    var onReplaceFighter: (Int) -> Void // 新舰载机类型ID

    /// 环境变量
    @Environment(\.dismiss) var dismiss

    // 状态变量
    @State private var fighterDetails: DatabaseListItem? = nil
    @State private var isLoading = true
    @State private var variationsCount: Int = 0
    @State private var quantity: Int
    @State private var maxQuantity: Int = 5 // 默认最大值，将从fighterSquadronMaxSize属性获取
    @State private var currentQuantity: Int // 用于显示当前实际数量
    @State private var initialQuantity: Int // 用于跟踪数量是否变化
    @State private var hasQuantityChanged = false // 跟踪数量是否发生了变化
    @State private var currentFighterID: Int // 当前舰载机ID

    /// 初始化方法
    init(
        selectedFighter: FighterState,
        databaseManager: DatabaseManager,
        viewModel: FittingEditorViewModel,
        onDelete: @escaping () -> Void = {},
        onUpdateQuantity: @escaping (Int) -> Void = { _ in },
        onReplaceFighter: @escaping (Int) -> Void = { _ in }
    ) {
        self.selectedFighter = selectedFighter
        self.databaseManager = databaseManager
        self.viewModel = viewModel
        self.onDelete = onDelete
        self.onUpdateQuantity = onUpdateQuantity
        self.onReplaceFighter = onReplaceFighter

        // 初始化状态变量
        guard let fighter = selectedFighter.fighterSquad else {
            fatalError("FighterSettingsView initialized with nil fighterSquad")
        }

        _quantity = State(initialValue: fighter.quantity)
        _currentQuantity = State(initialValue: fighter.quantity)
        _initialQuantity = State(initialValue: fighter.quantity)
        _currentFighterID = State(initialValue: fighter.typeId)
    }

    var body: some View {
        NavigationStack {
            List {
                Section(
                    header:
                    HStack {
                        Text(NSLocalizedString("Fitting_Setting_Fighters", comment: "舰载机设置"))
                        Spacer()
                        // 获取计算后的舰载机属性
                        let currentOutputFighter = viewModel.simulationOutput?.fighters?.first(
                            where: {
                                $0.typeId == currentFighterID
                                    && $0.tubeId == selectedFighter.tubeId
                            }
                        )
                        NavigationLink(
                            destination: ShowItemInfo(
                                databaseManager: databaseManager, itemID: currentFighterID,
                                modifiedAttributes: currentOutputFighter?.attributes,
                                fittingContext: viewModel.simulationOutput?.attributeContext(for: currentOutputFighter?.instanceId)
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
                    } else if let details = fighterDetails {
                        // 如果有变体，点击显示变体列表
                        if variationsCount > 1 {
                            NavigationLink(
                                destination: FighterVariationSelectionView(
                                    databaseManager: databaseManager,
                                    currentFighterID: currentFighterID,
                                    onSelectVariation: { variationID in
                                        // 保存当前状态
                                        let previousQuantity = quantity

                                        // 替换舰载机
                                        onReplaceFighter(variationID)

                                        // 更新当前舰载机ID
                                        currentFighterID = variationID

                                        // 重新加载舰载机信息
                                        loadFighterDetails()
                                        checkVariations()
                                        loadMaxQuantity()

                                        // 保持之前的数量，但确保不超过新舰载机的最大数量
                                        quantity = min(previousQuantity, maxQuantity)

                                        // 更新舰载机数量
                                        onUpdateQuantity(quantity)
                                        currentQuantity = quantity

                                        // 如果数量与初始值不同，标记为已更改
                                        if quantity != initialQuantity {
                                            hasQuantityChanged = true
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
                    Stepper(value: $quantity, in: 1 ... maxQuantity, step: 1) {
                        Text(
                            String(
                                format: NSLocalizedString(
                                    "Fitting_Fighters_Qty", comment: "舰载机数量: %d/%d"
                                ), quantity,
                                maxQuantity
                            )
                        )
                    }
                    .onChange(of: quantity) { _, newValue in
                        // 仅更新舰载机数量，不重新计算属性
                        onUpdateQuantity(newValue)
                        // 立即更新显示的当前数量
                        currentQuantity = newValue

                        // 如果数量与初始值不同，标记为已更改
                        if newValue != initialQuantity {
                            hasQuantityChanged = true
                        } else {
                            hasQuantityChanged = false
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Fitting_Setting_Fighters", comment: "舰载机设置"))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        // 执行删除操作
                        onDelete()
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
                loadFighterDetails()
                loadMaxQuantity()
                checkVariations()
            }
            .onDisappear {
                // 舰载机设置视图消失时，如果数量有变化且不是因为删除操作，重新计算整个配置
                if hasQuantityChanged {
                    Logger.info("舰载机数量发生变化，重新计算属性")
                    viewModel.calculateAttributes()
                }
            }
        }
        .presentationDetents([.fraction(0.81)]) // 设置为屏幕高度的81%，与无人机设置页面一致
        .presentationDragIndicator(.visible) // 显示拖动指示器
    }

    /// 加载舰载机详细信息
    private func loadFighterDetails() {
        isLoading = true

        // 内存索引单点构建
        fighterDetails = DatabaseListItem(
            typeID: currentFighterID,
            databaseManager: databaseManager
        )

        isLoading = false
    }

    /// 加载舰载机最大数量
    private func loadMaxQuantity() {
        // 获取舰载机的fighterSquadronMaxSize属性
        if let maxSize = fighter.attributesByName["fighterSquadronMaxSize"] {
            maxQuantity = Int(maxSize)
        } else if
            let attrID = SDEMemoryStore.attributeID(named: "fighterSquadronMaxSize"),
            let value = SDEMemoryStore.typeAttributeValue(for: currentFighterID, attributeID: attrID)
        {
            maxQuantity = Int(value)
        } else {
            // 默认值
            maxQuantity = 5
        }
    }

    /// 检查是否有变体
    private func checkVariations() {
        variationsCount = databaseManager.getVariationsCount(for: currentFighterID)
    }
}

/// 舰载机变体选择视图 - 独立的Sheet视图
struct FighterVariationSelectionView: View {
    let databaseManager: DatabaseManager
    let currentFighterID: Int
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
        let result = databaseManager.loadVariations(for: currentFighterID)
        items = result.0
        metaGroupNames = result.1
        isLoading = false
    }
}
