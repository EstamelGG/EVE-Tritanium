import SwiftUI

/// 战斗机状态类，包装 Int 使其符合 Identifiable
class FighterState: ObservableObject, Identifiable {
    var id: Int {
        fighterTypeId ?? 0
    }

    @Published var fighterTypeId: Int?
    @Published var tubeId: Int = 0
    @Published var fighterSquad: SimFighterSquad?

    /// 更新舰载机信息
    func updateFighter(_ fighter: SimFighterSquad) {
        fighterTypeId = fighter.typeId
        tubeId = fighter.tubeId
        fighterSquad = fighter
    }
}

/// 舰载机管视图项
struct FighterTubeItem: Identifiable {
    let id = UUID()
    var fighterTypeId: Int? // 如果为nil，表示未装填舰载机
    var fighterName: String?
    var fighterIconFileName: String?
    var tubeId: Int // 发射管ID

    /// 是否可以点击
    var isClickable: Bool = true
}

struct ShipFittingFightersView: View {
    @ObservedObject var viewModel: FittingEditorViewModel
    @StateObject private var selectedFighter = FighterState()

    // 各类型舰载机选择器状态
    @State private var showingLightFighterSelector = false
    @State private var showingHeavyFighterSelector = false
    @State private var showingSupportFighterSelector = false
    @State private var showingFighterSettings = false

    // 当前选择的舰载机类型
    @State private var currentFighterType: FighterType = .light
    @State private var currentTubeId: Int = 0

    // 储存三种类型舰载机的数据
    @State private var lightFighterTubes: [FighterTubeItem] = []
    @State private var heavyFighterTubes: [FighterTubeItem] = []
    @State private var supportFighterTubes: [FighterTubeItem] = []

    /// 获取舰载机管数量
    private var lightTubesCount: Int {
        return Int(viewModel.simulationInput.ship.baseAttributesByName["fighterLightSlots"] ?? 0)
    }

    private var heavyTubesCount: Int {
        return Int(viewModel.simulationInput.ship.baseAttributesByName["fighterHeavySlots"] ?? 0)
    }

    private var supportTubesCount: Int {
        return Int(viewModel.simulationInput.ship.baseAttributesByName["fighterSupportSlots"] ?? 0)
    }

    /// 判断舰载机是否已满
    private var isFighterBayFull: Bool {
        // 获取飞船的舰载机总管数
        let totalFighterTubes = Int(
            viewModel.simulationInput.ship.baseAttributesByName["fighterTubes"] ?? 0
        )

        // 获取当前已使用的舰载机管数
        let usedFighterTubes =
            viewModel.fighterAttributes.light.used + viewModel.fighterAttributes.heavy.used
                + viewModel.fighterAttributes.support.used

        // 当已使用的舰载机管数大于等于总舰载机管数时，认为舰载机已满
        return usedFighterTubes >= totalFighterTubes && totalFighterTubes > 0
    }

    var body: some View {
        VStack(spacing: 0) {
            // 战斗机属性条
            FighterAttributesView(viewModel: viewModel)

            // 使用List代替ScrollView来获得更好的布局
            List {
                // 轻型舰载机部分
                if lightTubesCount > 0 {
                    Section(
                        header: sectionHeader(
                            title: NSLocalizedString("Fitting_Fighter_Light", comment: "")
                        )
                    ) {
                        ForEach(lightFighterTubes) { tube in
                            FighterTubeRowView(
                                fighterTube: tube, isFighterBayFull: isFighterBayFull,
                                viewModel: viewModel,
                                onSelected: {
                                    if tube.fighterTypeId != nil {
                                        // 如果已有舰载机，显示设置页面
                                        if let fighters = viewModel.simulationInput.fighters,
                                           let fighter = fighters.first(where: {
                                               $0.tubeId == tube.tubeId
                                           })
                                        {
                                            selectedFighter.updateFighter(fighter)
                                            showingFighterSettings = true
                                        }
                                    } else {
                                        // 否则，显示选择器
                                        selectedFighter.fighterTypeId = tube.fighterTypeId
                                        selectedFighter.tubeId = tube.tubeId
                                        selectedFighter.fighterSquad = nil
                                        currentFighterType = .light
                                        currentTubeId = tube.tubeId
                                        showingLightFighterSelector = true
                                    }
                                }
                            )
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }
                }

                // 重型舰载机部分
                if heavyTubesCount > 0 {
                    Section(
                        header: sectionHeader(
                            title: NSLocalizedString("Fitting_Fighter_Heavy", comment: "")
                        )
                    ) {
                        ForEach(heavyFighterTubes) { tube in
                            FighterTubeRowView(
                                fighterTube: tube, isFighterBayFull: isFighterBayFull,
                                viewModel: viewModel,
                                onSelected: {
                                    if tube.fighterTypeId != nil {
                                        // 如果已有舰载机，显示设置页面
                                        if let fighters = viewModel.simulationInput.fighters,
                                           let fighter = fighters.first(where: {
                                               $0.tubeId == tube.tubeId
                                           })
                                        {
                                            selectedFighter.updateFighter(fighter)
                                            showingFighterSettings = true
                                        }
                                    } else {
                                        // 否则，显示选择器
                                        selectedFighter.fighterTypeId = tube.fighterTypeId
                                        selectedFighter.tubeId = tube.tubeId
                                        selectedFighter.fighterSquad = nil
                                        currentFighterType = .heavy
                                        currentTubeId = tube.tubeId
                                        showingHeavyFighterSelector = true
                                    }
                                }
                            )
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }
                }

                // 辅助舰载机部分
                if supportTubesCount > 0 {
                    Section(
                        header: sectionHeader(
                            title: NSLocalizedString("Fitting_Fighter_Support", comment: "")
                        )
                    ) {
                        ForEach(supportFighterTubes) { tube in
                            FighterTubeRowView(
                                fighterTube: tube, isFighterBayFull: isFighterBayFull,
                                viewModel: viewModel,
                                onSelected: {
                                    if tube.fighterTypeId != nil {
                                        // 如果已有舰载机，显示设置页面
                                        if let fighters = viewModel.simulationInput.fighters,
                                           let fighter = fighters.first(where: {
                                               $0.tubeId == tube.tubeId
                                           })
                                        {
                                            selectedFighter.updateFighter(fighter)
                                            showingFighterSettings = true
                                        }
                                    } else {
                                        // 否则，显示选择器
                                        selectedFighter.fighterTypeId = tube.fighterTypeId
                                        selectedFighter.tubeId = tube.tubeId
                                        selectedFighter.fighterSquad = nil
                                        currentFighterType = .support
                                        currentTubeId = tube.tubeId
                                        showingSupportFighterSelector = true
                                    }
                                }
                            )
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            // 添加这行使List的分隔线延伸到边缘
            .environment(\.defaultMinListRowHeight, 0)
        }
        // 轻型舰载机选择器
        .sheet(isPresented: $showingLightFighterSelector) {
            FighterSelectorView(
                databaseManager: viewModel.databaseManager,
                fighterType: .light,
                shipTypeID: viewModel.simulationInput.ship.typeId,
                onSelect: { fighterItem in
                    // 处理选择轻型舰载机
                    addFighter(fighterItem, type: .light, tubeId: currentTubeId)
                }
            )
        }
        // 重型舰载机选择器
        .sheet(isPresented: $showingHeavyFighterSelector) {
            FighterSelectorView(
                databaseManager: viewModel.databaseManager,
                fighterType: .heavy,
                shipTypeID: viewModel.simulationInput.ship.typeId,
                onSelect: { fighterItem in
                    // 处理选择重型舰载机
                    addFighter(fighterItem, type: .heavy, tubeId: currentTubeId)
                }
            )
        }
        // 辅助舰载机选择器
        .sheet(isPresented: $showingSupportFighterSelector) {
            FighterSelectorView(
                databaseManager: viewModel.databaseManager,
                fighterType: .support,
                shipTypeID: viewModel.simulationInput.ship.typeId,
                onSelect: { fighterItem in
                    // 处理选择辅助舰载机
                    addFighter(fighterItem, type: .support, tubeId: currentTubeId)
                }
            )
        }
        // 舰载机设置弹窗
        .sheet(isPresented: $showingFighterSettings) {
            if selectedFighter.fighterSquad != nil {
                FighterSettingsView(
                    selectedFighter: selectedFighter,
                    databaseManager: viewModel.databaseManager,
                    viewModel: viewModel,
                    onDelete: {
                        // 移除舰载机
                        viewModel.removeFighter(tubeId: selectedFighter.tubeId)

                        // 在UI上也移除舰载机显示
                        updateTubeDisplayAfterDelete(tubeId: selectedFighter.tubeId)
                    },
                    onUpdateQuantity: { newQuantity in
                        // 更新舰载机数量
                        viewModel.updateFighterQuantity(
                            tubeId: selectedFighter.tubeId, quantity: newQuantity
                        )
                    },
                    onReplaceFighter: { newFighterTypeId in
                        // 替换舰载机变体
                        let tubeId = selectedFighter.tubeId

                        // 获取新舰载机的信息
                        if let newFighterItem = viewModel.getDatabaseItemInfo(
                            typeId: newFighterTypeId
                        ) {
                            // 获取原舰载机的数量，保持不变
                            let currentQuantity = selectedFighter.fighterSquad?.quantity ?? 1

                            // 获取新舰载机的最大中队大小（内存索引）
                            var maxQuantity = currentQuantity
                            if
                                let attrID = SDEMemoryStore.attributeID(named: "fighterSquadronMaxSize"),
                                let value = SDEMemoryStore.typeAttributeValue(
                                    for: newFighterTypeId, attributeID: attrID
                                )
                            {
                                maxQuantity = min(currentQuantity, Int(value))
                            }

                            // 创建新的舰载机中队，保持原有的数量（在允许范围内）
                            let newSquad = SimFighterSquad(
                                typeId: newFighterTypeId,
                                attributes: [:], // 这些属性将由viewModel填充
                                attributesByName: [:],
                                effects: [],
                                quantity: maxQuantity,
                                tubeId: tubeId,
                                groupID: 0, // 这个属性将由viewModel填充
                                requiredSkills: [],
                                name: newFighterItem.name,
                                iconFileName: newFighterItem.iconFileName
                            )

                            // 更新 ViewModel 中的舰载机数据
                            viewModel.addOrUpdateFighter(
                                newSquad, name: newFighterItem.name,
                                iconFileName: newFighterItem.iconFileName
                            )

                            // 更新 selectedFighter 的状态
                            selectedFighter.updateFighter(newSquad)

                            // 确定舰载机类型
                            var fighterType: FighterType = .light
                            if tubeId >= 0, tubeId < 100 {
                                fighterType = .light
                            } else if tubeId >= 100, tubeId < 200 {
                                fighterType = .heavy
                            } else if tubeId >= 200 {
                                fighterType = .support
                            }

                            // 更新UI显示
                            updateTubeDisplay(
                                typeId: newFighterTypeId,
                                name: newFighterItem.name,
                                iconFileName: newFighterItem.iconFileName,
                                tubeId: tubeId,
                                type: fighterType
                            )
                        }
                    }
                )
            }
        }
        .onAppear {
            // 初始化舰载机管数据
            initializeFighterTubes()
            // 从现有配置加载舰载机数据
            loadFightersFromConfig()
        }
    }

    /// 添加舰载机
    private func addFighter(_ fighterItem: DatabaseListItem, type: FighterType, tubeId: Int) {
        Logger.info("选择舰载机：\(fighterItem.name)，类型：\(type.rawValue)，管ID：\(tubeId)")

        // 检查舰载机舱是否已满
        if isFighterBayFull {
            // 如果是修改现有舰载机，则允许操作
            let isReplacingExisting: Bool
            switch type {
            case .light:
                isReplacingExisting =
                    lightFighterTubes.first(where: { $0.tubeId == tubeId })?.fighterTypeId != nil
            case .heavy:
                isReplacingExisting =
                    heavyFighterTubes.first(where: { $0.tubeId == tubeId })?.fighterTypeId != nil
            case .support:
                isReplacingExisting =
                    supportFighterTubes.first(where: { $0.tubeId == tubeId })?.fighterTypeId != nil
            }

            // 如果不是替换现有舰载机，而是添加新的，则阻止操作
            if !isReplacingExisting {
                Logger.info("舰载机舱已满，无法添加更多舰载机")
                return
            }
        }

        // 获取舰载机的最大中队大小
        var defaultQuantity = 1

        // 查询舰载机的fighterSquadronMaxSize属性
        let query = """
            SELECT ta.value
            FROM typeAttributes ta
            JOIN dogmaAttributes da ON ta.attribute_id = da.attribute_id
            WHERE ta.type_id = ? AND da.name = 'fighterSquadronMaxSize'
        """

        if case let .success(rows) = viewModel.databaseManager.executeQuery(
            query, parameters: [fighterItem.id]
        ),
            let row = rows.first,
            let value = row["value"] as? Double
        {
            defaultQuantity = Int(value)
            Logger.info("舰载机最大中队大小: \(defaultQuantity)")
        }

        // 创建舰载机中队
        let squad = SimFighterSquad(
            typeId: fighterItem.id,
            attributes: [:], // 这些属性将由viewModel填充
            attributesByName: [:],
            effects: [],
            quantity: defaultQuantity,
            tubeId: tubeId,
            groupID: 0, // 这个属性将由viewModel填充
            requiredSkills: [],
            name: fighterItem.name,
            iconFileName: fighterItem.iconFileName
        )

        // 添加或更新舰载机到视图模型
        viewModel.addOrUpdateFighter(
            squad, name: fighterItem.name, iconFileName: fighterItem.iconFileName
        )

        // 更新UI
        updateTubeDisplay(
            typeId: fighterItem.id, name: fighterItem.name, iconFileName: fighterItem.iconFileName,
            tubeId: tubeId, type: type
        )
    }

    /// 更新管道显示
    private func updateTubeDisplay(
        typeId: Int, name: String, iconFileName: String?, tubeId: Int, type: FighterType
    ) {
        switch type {
        case .light:
            if let index = lightFighterTubes.firstIndex(where: { $0.tubeId == tubeId }) {
                lightFighterTubes[index].fighterTypeId = typeId
                lightFighterTubes[index].fighterName = name
                lightFighterTubes[index].fighterIconFileName = iconFileName
            }
        case .heavy:
            if let index = heavyFighterTubes.firstIndex(where: { $0.tubeId == tubeId }) {
                heavyFighterTubes[index].fighterTypeId = typeId
                heavyFighterTubes[index].fighterName = name
                heavyFighterTubes[index].fighterIconFileName = iconFileName
            }
        case .support:
            if let index = supportFighterTubes.firstIndex(where: { $0.tubeId == tubeId }) {
                supportFighterTubes[index].fighterTypeId = typeId
                supportFighterTubes[index].fighterName = name
                supportFighterTubes[index].fighterIconFileName = iconFileName
            }
        }
    }

    /// 从现有配置加载舰载机数据
    private func loadFightersFromConfig() {
        guard let fighters = viewModel.simulationInput.fighters else { return }

        // 获取飞船的舰载机总管数
        let totalFighterTubes = Int(
            viewModel.simulationInput.ship.baseAttributesByName["fighterTubes"] ?? 0
        )
        if totalFighterTubes <= 0 {
            // 如果飞船不支持舰载机，不加载任何舰载机
            return
        }

        // 创建一个新的舰载机列表，只包含有效的舰载机
        var validFighters: [SimFighterSquad] = []
        var currentCount = 0

        for fighter in fighters {
            let tubeId = fighter.tubeId

            // 如果已达到舰载机总槽位数限制，跳过剩余的舰载机
            if currentCount >= totalFighterTubes {
                Logger.info("跳过超额舰载机，ID: \(fighter.typeId), tubeId: \(tubeId)")
                continue
            }

            // 添加到有效舰载机列表
            validFighters.append(fighter)
            currentCount += 1

            // 获取舰载机信息
            if let item = viewModel.getDatabaseItemInfo(typeId: fighter.typeId) {
                // 确定舰载机类型并更新对应的管道
                if let fighterInfo = viewModel.getFighterInfo(typeId: fighter.typeId) {
                    if let groupId = fighterInfo.groupID {
                        // 根据groupID确定舰载机类型
                        if groupId == FighterType.light.rawValue || (tubeId >= 0 && tubeId < 100) {
                            updateTubeDisplay(
                                typeId: fighter.typeId, name: item.name,
                                iconFileName: item.iconFileName, tubeId: tubeId, type: .light
                            )
                        } else if groupId == FighterType.heavy.rawValue
                            || (tubeId >= 100 && tubeId < 200)
                        {
                            updateTubeDisplay(
                                typeId: fighter.typeId, name: item.name,
                                iconFileName: item.iconFileName, tubeId: tubeId, type: .heavy
                            )
                        } else if groupId == FighterType.support.rawValue || tubeId >= 200 {
                            updateTubeDisplay(
                                typeId: fighter.typeId, name: item.name,
                                iconFileName: item.iconFileName, tubeId: tubeId, type: .support
                            )
                        }
                    }
                }
            }
        }

        // 如果有舰载机被移除，更新simulationInput中的fighters列表
        if fighters.count != validFighters.count {
            Logger.info("移除了 \(fighters.count - validFighters.count) 个超额舰载机")
            viewModel.simulationInput.fighters = validFighters

            // 保存更新后的配置
            viewModel.saveConfiguration()
        }
    }

    /// 初始化舰载机管数据
    private func initializeFighterTubes() {
        // 清空现有数据
        lightFighterTubes = []
        heavyFighterTubes = []
        supportFighterTubes = []

        // 轻型舰载机管的tubeId从0开始
        for i in 0 ..< lightTubesCount {
            lightFighterTubes.append(
                FighterTubeItem(
                    fighterTypeId: nil, fighterName: nil, fighterIconFileName: nil, tubeId: i,
                    isClickable: true
                )
            )
        }

        // 重型舰载机管的tubeId从100开始
        for i in 0 ..< heavyTubesCount {
            heavyFighterTubes.append(
                FighterTubeItem(
                    fighterTypeId: nil, fighterName: nil, fighterIconFileName: nil, tubeId: 100 + i,
                    isClickable: true
                )
            )
        }

        // 辅助舰载机管的tubeId从200开始
        for i in 0 ..< supportTubesCount {
            supportFighterTubes.append(
                FighterTubeItem(
                    fighterTypeId: nil, fighterName: nil, fighterIconFileName: nil, tubeId: 200 + i,
                    isClickable: true
                )
            )
        }
    }

    /// 区域头部视图
    private func sectionHeader(title: String) -> some View {
        Text(title)
            .padding(.leading, 4)
    }

    /// 添加新方法：删除舰载机后更新UI
    private func updateTubeDisplayAfterDelete(tubeId: Int) {
        // 根据tubeId范围确定舰载机类型并更新相应管道
        if tubeId >= 0, tubeId < 100 {
            if let index = lightFighterTubes.firstIndex(where: { $0.tubeId == tubeId }) {
                lightFighterTubes[index].fighterTypeId = nil
                lightFighterTubes[index].fighterName = nil
                lightFighterTubes[index].fighterIconFileName = nil
            }
        } else if tubeId >= 100, tubeId < 200 {
            if let index = heavyFighterTubes.firstIndex(where: { $0.tubeId == tubeId }) {
                heavyFighterTubes[index].fighterTypeId = nil
                heavyFighterTubes[index].fighterName = nil
                heavyFighterTubes[index].fighterIconFileName = nil
            }
        } else if tubeId >= 200 {
            if let index = supportFighterTubes.firstIndex(where: { $0.tubeId == tubeId }) {
                supportFighterTubes[index].fighterTypeId = nil
                supportFighterTubes[index].fighterName = nil
                supportFighterTubes[index].fighterIconFileName = nil
            }
        }
    }
}

/// 舰载机管行视图
struct FighterTubeRowView: View {
    var fighterTube: FighterTubeItem
    var isFighterBayFull: Bool = false
    var viewModel: FittingEditorViewModel?
    var onSelected: () -> Void

    /// 获取舰载机的计算后属性
    private func getFighterOutput() -> SimFighterSquad? {
        guard let viewModel = viewModel,
              let outputFighters = viewModel.simulationOutput?.fighters
        else {
            return nil
        }

        // 通过tubeId查找匹配的舰载机输出数据
        guard
            let outputFighter = outputFighters.first(where: { fighter in
                fighter.tubeId == fighterTube.tubeId
            })
        else {
            return nil
        }

        // 将FighterSquadOutput转换为SimFighterSquad
        return SimFighterSquad(
            typeId: outputFighter.typeId,
            attributes: outputFighter.attributes,
            attributesByName: outputFighter.attributesByName,
            effects: outputFighter.effects,
            quantity: outputFighter.quantity,
            tubeId: outputFighter.tubeId,
            groupID: outputFighter.groupID,
            requiredSkills: FitConvert.extractRequiredSkills(attributes: outputFighter.attributes),
            name: outputFighter.name,
            iconFileName: outputFighter.iconFileName
        )
    }

    /// 格式化距离显示（与装备模块页面保持一致）
    /// 大于1000km时显示完整数字，不使用k km缩写
    private func formatDistance(_ distance: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.numberStyle = .decimal

        if distance >= 1000 {
            // 大于等于1km时，使用km单位，保留2位小数
            let value = distance / 1000.0
            formatter.maximumFractionDigits = 2
            let formattedValue = formatter.string(from: NSNumber(value: value)) ?? "0"
            return "\(formattedValue) km"
        } else {
            // 小于1km时，使用m单位
            formatter.maximumFractionDigits = 0
            let formattedValue = formatter.string(from: NSNumber(value: distance)) ?? "0"
            return "\(formattedValue) m"
        }
    }

    /// 格式化速度显示
    private func formatSpeed(_ speed: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: speed)) ?? "0"
    }

    var body: some View {
        Button(action: {
            if (fighterTube.isClickable && !isFighterBayFull) || fighterTube.fighterTypeId != nil {
                onSelected()
            }
        }) {
            HStack {
                // 图标
                if let iconFileName = fighterTube.fighterIconFileName {
                    IconManager.shared.loadImage(for: iconFileName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .cornerRadius(4)
                } else {
                    IconManager.shared.loadImage(for: "add_item")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .foregroundColor(
                            fighterTube.isClickable && !isFighterBayFull ? .blue : .gray
                        )
                }

                // 右侧垂直布局：舰载机名称和属性信息
                VStack(alignment: .leading, spacing: 2) {
                    // 第一行：名称和数量
                    if let name = fighterTube.fighterName,
                       let fighterTypeId = fighterTube.fighterTypeId, let viewModel = viewModel
                    {
                        // 获取舰载机数量
                        if let fighters = viewModel.simulationInput.fighters,
                           let fighter = fighters.first(where: {
                               $0.typeId == fighterTypeId && $0.tubeId == fighterTube.tubeId
                           })
                        {
                            Text("\(fighter.quantity)× \(name)")
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        } else {
                            Text(name)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }

                        // 舰载机属性展示（只有在有舰载机时才显示）
                        if let fighterOutput = getFighterOutput() {
                            // 射程与失准
                            let maxRange =
                                fighterOutput.attributesByName[
                                    "fighterAbilityAttackMissileRangeOptimal"
                                ] ?? 0
                            let falloff =
                                fighterOutput.attributesByName[
                                    "fighterAbilityAttackMissileRangeFalloff"
                                ] ?? 0

                            if maxRange > 0 || falloff > 0 {
                                HStack(spacing: 4) {
                                    if maxRange > 0 {
                                        // 有maxRange时使用maxRange图标
                                        IconManager.shared.loadImage(for: "target_range")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 20, height: 20)
                                    } else {
                                        // 只有falloff时使用falloff图标
                                        IconManager.shared.loadImage(for: "falloff_mod")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 20, height: 20)
                                    }

                                    HStack(spacing: 0) {
                                        if maxRange > 0 && falloff > 0 {
                                            Text(
                                                "\(NSLocalizedString("Module_Attribute_Range", comment: ""))+\(NSLocalizedString("Module_Attribute_Falloff", comment: "")): "
                                            )
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            Text(
                                                "\(formatDistance(maxRange)) + \(formatDistance(falloff))"
                                            )
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.secondary)
                                        } else if maxRange > 0 {
                                            Text(
                                                "\(NSLocalizedString("Module_Attribute_Range", comment: "")): "
                                            )
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            Text("\(formatDistance(maxRange))")
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.secondary)
                                        } else {
                                            Text(
                                                "\(NSLocalizedString("Module_Attribute_Falloff", comment: "")): "
                                            )
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            Text("\(formatDistance(falloff))")
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }

                            // 速度
                            let maxVelocity = fighterOutput.attributesByName["maxVelocity"] ?? 0

                            if maxVelocity > 0 {
                                HStack(spacing: 4) {
                                    IconManager.shared.loadImage(for: "turret_volley")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 20, height: 20)

                                    HStack(spacing: 0) {
                                        Text(
                                            "\(NSLocalizedString("Module_Attribute_Speed", comment: "")): "
                                        )
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        Text("\(formatSpeed(maxVelocity)) m/s")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    } else {
                        // 如果舰载机已满，显示不同的文本
                        Text(
                            NSLocalizedString(
                                isFighterBayFull
                                    ? "Fitting_can_not_add_Fighters" : "Fitting_Add_Fighters",
                                comment: ""
                            )
                        )
                        .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .disabled(
            fighterTube.fighterTypeId == nil && (!fighterTube.isClickable || isFighterBayFull)
        )
        .padding(.vertical, 2)
    }
}

/// 战斗机属性条视图
struct FighterAttributesView: View {
    @ObservedObject var viewModel: FittingEditorViewModel

    var body: some View {
        VStack(spacing: 12) {
            // 战斗机状态行
            HStack(spacing: 8) {
                // 轻型战斗机发射筒
                FighterSlotView(
                    icon: "drone_band",
                    slotType: NSLocalizedString("Fitting_Fighter_Light", comment: ""),
                    used: viewModel.fighterAttributes.light.used,
                    total: viewModel.fighterAttributes.light.total
                )
                .frame(maxWidth: .infinity)
                .layoutPriority(1)

                // 重型战斗机发射筒
                FighterSlotView(
                    icon: "drone_band",
                    slotType: NSLocalizedString("Fitting_Fighter_Heavy", comment: ""),
                    used: viewModel.fighterAttributes.heavy.used,
                    total: viewModel.fighterAttributes.heavy.total
                )
                .frame(maxWidth: .infinity)
                .layoutPriority(1)

                // 后勤战斗机发射筒
                FighterSlotView(
                    icon: "drone_band",
                    slotType: NSLocalizedString("Fitting_Fighter_Support", comment: ""),
                    used: viewModel.fighterAttributes.support.used,
                    total: viewModel.fighterAttributes.support.total
                )
                .frame(maxWidth: .infinity)
                .layoutPriority(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .overlay(Divider(), alignment: .bottom)
    }
}

/// 战斗机发射筒视图组件
struct FighterSlotView: View {
    let icon: String
    let slotType: String
    let used: Int
    let total: Int

    var body: some View {
        HStack(spacing: 4) {
            // 图标
            IconManager.shared.loadImage(for: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 0) {
                // 类型名称
                Text(slotType)
                    .font(.caption)
                    .foregroundColor(.secondary)

                // 使用数量
                Text("\(used)/\(total)")
                    .font(.callout)
                    .fontWeight(.medium)
            }
        }
    }
}
