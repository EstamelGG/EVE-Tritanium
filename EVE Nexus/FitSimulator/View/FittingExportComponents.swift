import SwiftUI

// MARK: - 装备模块展示区域

struct ModulesExportSection: View {
    @ObservedObject var viewModel: FittingEditorViewModel

    private struct ExportRow {
        let module: SimModuleOutput?
        var count: Int
    }

    /// 保留首次出现的槽位顺序，只合并状态、弹药和属性一致的装备。
    private func exportRows(
        modules: [SimModuleOutput], slotType: FittingSlotType, slotCount: Int
    ) -> [ExportRow] {
        var rows: [ExportRow] = []
        for slotIndex in 0 ..< slotCount {
            let flag = getSlotFlag(for: slotType, index: slotIndex)
            guard let module = modules.first(where: { $0.flag == flag }) else {
                rows.append(ExportRow(module: nil, count: 1))
                continue
            }
            if let index = rows.firstIndex(where: { row in
                guard let existing = row.module else { return false }
                return existing.typeId == module.typeId
                    && existing.name == module.name
                    && existing.iconFileName == module.iconFileName
                    && existing.mutatedTypeId == module.mutatedTypeId
                    && existing.status == module.status
                    && existing.attributes == module.attributes
                    && existing.charge?.typeId == module.charge?.typeId
                    && existing.charge?.chargeQuantity == module.charge?.chargeQuantity
                    && existing.charge?.attributes == module.charge?.attributes
            }) {
                rows[index].count += 1
            } else {
                rows.append(ExportRow(module: module, count: 1))
            }
        }
        return rows
    }

    /// 获取槽位类型的显示模块
    private func getDisplayModules(for slotType: FittingSlotType) -> [SimModuleOutput] {
        guard let simulationOutput = viewModel.simulationOutput else { return [] }

        let slotFlags = getSlotFlags(for: slotType)
        return simulationOutput.modules.filter { module in
            guard let flag = module.flag else { return false }
            return slotFlags.contains(flag)
        }.sorted { module1, module2 in
            guard let flag1 = module1.flag, let flag2 = module2.flag else { return false }
            return flag1.rawValue < flag2.rawValue
        }
    }

    /// 获取槽位数量
    private func getSlotCount(for slotType: FittingSlotType) -> Int {
        guard let outputShip = viewModel.simulationOutput?.ship else { return 0 }

        switch slotType {
        case .hiSlots:
            return Int(outputShip.attributesByName["hiSlots"] ?? 0)
        case .medSlots:
            return Int(outputShip.attributesByName["medSlots"] ?? 0)
        case .loSlots:
            return Int(outputShip.attributesByName["lowSlots"] ?? 0)
        case .rigSlots:
            return Int(outputShip.attributesByName["rigSlots"] ?? 0)
        case .subSystemSlots:
            let maxSubSystems = Int(outputShip.attributesByName["maxSubSystems"] ?? 0)
            return maxSubSystems > 0 ? 4 : 0 // 子系统槽位数修正为4
        case .t3dModeSlot:
            // 检查是否有安装模式装备，如果没有则返回0（不显示该槽位类型）
            guard let simulationOutput = viewModel.simulationOutput else { return 0 }
            let hasT3DMode = simulationOutput.modules.contains { $0.flag == .t3dModeSlot0 }
            return hasT3DMode ? 1 : 0
        }
    }

    /// 获取空槽位图标
    private func getSlotIcon(for slotType: FittingSlotType) -> String {
        switch slotType {
        case .hiSlots:
            return "highSlot"
        case .medSlots:
            return "midSlot"
        case .loSlots:
            return "lowSlot"
        case .rigSlots:
            return "rigSlot"
        case .subSystemSlots:
            return "subSystem"
        case .t3dModeSlot:
            return "subSystem"
        }
    }

    /// 获取槽位类型对应的flag列表
    private func getSlotFlags(for slotType: FittingSlotType) -> [FittingFlag] {
        slotType.flags
    }

    /// 获取状态图标
    private func getStatusIcon(status: Int) -> some View {
        switch status {
        case 0:
            return IconManager.shared.loadImage(for: "offline")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        case 1:
            return IconManager.shared.loadImage(for: "online")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        case 2:
            return IconManager.shared.loadImage(for: "active")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        case 3:
            return IconManager.shared.loadImage(for: "overheating")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        default:
            return IconManager.shared.loadImage(for: "offline")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 遍历所有槽位类型
            ForEach(FittingSlotType.allCases, id: \.self) { slotType in
                let modules = getDisplayModules(for: slotType)
                let slotCount = getSlotCount(for: slotType)

                // 只显示有槽位的类型
                if slotCount > 0 {
                    let rows = exportRows(modules: modules, slotType: slotType, slotCount: slotCount)
                    VStack(spacing: 0) {
                        // 槽位类型标题
                        HStack {
                            Text(slotType.localizedName)
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)

                            Spacer()

                            // 显示槽位占用情况
                            Text("\(modules.count)/\(slotCount)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                        // 重复装备合并展示，空槽位保持独立显示。
                        ForEach(rows.indices, id: \.self) { rowIndex in
                            let row = rows[rowIndex]

                            HStack(spacing: 8) {
                                if let module = row.module {
                                    // 已安装装备
                                    // 装备图标 - 优先使用突变后的图标
                                    let displayIconFileName = module.mutatedIconFileName ?? module.iconFileName
                                    if let iconFileName = displayIconFileName {
                                        IconManager.shared.loadImage(for: iconFileName)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 28, height: 28)
                                            .cornerRadius(4)
                                    } else {
                                        Image(systemName: "questionmark.square")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 28, height: 28)
                                            .foregroundColor(.gray)
                                    }

                                    // 装备名称和状态 - 优先使用突变后的名称
                                    VStack(alignment: .leading, spacing: 2) {
                                        (Text(module.name)
                                            + Text(row.count > 1 ? " × \(row.count)" : "")
                                            .foregroundColor(.secondary))
                                            .font(.subheadline)
                                            .foregroundColor(.primary)

                                        // 弹药信息
                                        if let charge = module.charge {
                                            HStack(spacing: 4) {
                                                if let chargeIconFileName = charge.iconFileName {
                                                    IconManager.shared.loadImage(
                                                        for: chargeIconFileName
                                                    )
                                                    .resizable()
                                                    .scaledToFit()
                                                    .frame(width: 16, height: 16)
                                                }

                                                Text(
                                                    "\(charge.chargeQuantity ?? 0)× \(charge.name)"
                                                )
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            }
                                        }
                                    }

                                    Spacer()

                                    // 状态图标
                                    getStatusIcon(status: module.status)
                                } else {
                                    // 空槽位
                                    IconManager.shared.loadImage(for: getSlotIcon(for: slotType))
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 28, height: 28)
                                        .opacity(0.4)
                                        .cornerRadius(4)

                                    Text(NSLocalizedString("Fitting_Empty_Slot", comment: "空槽位"))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)

                                    Spacer()
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)

                            // 分割线（除了最后一个）
                            if rowIndex < rows.count - 1 {
                                Divider()
                                    .padding(.leading, 48)
                            }
                        }
                    }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    /// 根据槽位类型和索引获取对应的flag
    private func getSlotFlag(for slotType: FittingSlotType, index: Int) -> FittingFlag {
        slotType.getSlotFlag(index: index)
    }
}

// MARK: - 无人机展示区域

struct DronesExportSection: View {
    @ObservedObject var viewModel: FittingEditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            // 标题
            HStack {
                Text(NSLocalizedString("Fitting_Export_Drones", comment: "无人机"))
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // 无人机列表
            if let drones = viewModel.simulationOutput?.drones {
                ForEach(drones, id: \.typeId) { drone in
                    HStack(spacing: 8) {
                        // 无人机图标
                        if let iconFileName = drone.iconFileName {
                            IconManager.shared.loadImage(for: iconFileName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 28, height: 28)
                                .cornerRadius(4)
                        } else {
                            Image(systemName: "questionmark.square")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 28, height: 28)
                                .foregroundColor(.gray)
                        }

                        // 无人机信息
                        VStack(alignment: .leading, spacing: 2) {
                            // 无人机名称和数量
                            Text("\(drone.quantity)× \(drone.name)")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }

                        Spacer()

                        // 激活状态显示
                        if drone.activeCount > 0 {
                            HStack(spacing: 4) {
                                IconManager.shared.loadImage(for: "active")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 16, height: 16)

                                Text("\(drone.activeCount)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)

                    if drone.typeId != drones.last?.typeId {
                        Divider()
                            .padding(.leading, 48)
                    }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - 货舱展示区域

struct CargoExportSection: View {
    @ObservedObject var viewModel: FittingEditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            // 标题
            HStack {
                Text(NSLocalizedString("Fitting_Export_Cargo", comment: "货舱"))
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // 货舱物品列表
            ForEach(viewModel.simulationInput.cargo.items, id: \.typeId) { item in
                HStack(spacing: 8) {
                    // 物品图标
                    if let iconFileName = item.iconFileName {
                        IconManager.shared.loadImage(for: iconFileName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .cornerRadius(4)
                    } else {
                        Image(systemName: "questionmark.square")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .foregroundColor(.gray)
                    }

                    // 物品名称和数量
                    Text("\(item.quantity)× \(item.name)")
                        .font(.subheadline)
                        .foregroundColor(.primary)

                    Spacer()

                    // 物品体积
                    Text("\(item.volume * Double(item.quantity), specifier: "%.1f") m³")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

                if item.typeId != viewModel.simulationInput.cargo.items.last?.typeId {
                    Divider()
                        .padding(.leading, 48)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - 舰载机展示区域

struct FightersExportSection: View {
    @ObservedObject var viewModel: FittingEditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            // 标题
            HStack {
                Text(NSLocalizedString("Fitting_Export_Fighters", comment: "舰载机"))
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // 舰载机列表
            if let fighters = viewModel.simulationOutput?.fighters {
                ForEach(fighters, id: \.instanceId) { fighter in
                    HStack(spacing: 8) {
                        // 舰载机图标
                        if let iconFileName = fighter.iconFileName {
                            IconManager.shared.loadImage(for: iconFileName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 28, height: 28)
                                .cornerRadius(4)
                        } else {
                            Image(systemName: "questionmark.square")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 28, height: 28)
                                .foregroundColor(.gray)
                        }

                        // 舰载机名称和数量
                        Text("\(fighter.quantity)× \(fighter.name)")
                            .font(.subheadline)
                            .foregroundColor(.primary)

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)

                    if fighter.instanceId != fighters.last?.instanceId {
                        Divider()
                            .padding(.leading, 48)
                    }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - 植入体展示区域

struct ImplantsExportSection: View {
    @ObservedObject var viewModel: FittingEditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            // 标题
            HStack {
                Text(NSLocalizedString("Fitting_Export_Implants", comment: "植入体"))
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // 植入体列表
            ForEach(
                viewModel.simulationInput.implants.sorted(by: { $0.typeId < $1.typeId }),
                id: \.instanceId
            ) { implant in
                HStack(spacing: 8) {
                    // 植入体图标
                    if let iconFileName = implant.iconFileName {
                        IconManager.shared.loadImage(for: iconFileName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .cornerRadius(4)
                    } else {
                        Image(systemName: "questionmark.square")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .foregroundColor(.gray)
                    }

                    // 植入体信息
                    VStack(alignment: .leading, spacing: 2) {
                        // 植入体名称
                        Text(implant.name)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

                if implant.instanceId != viewModel.simulationInput.implants.last?.instanceId {
                    Divider()
                        .padding(.leading, 48)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}
