import SwiftUI
import UIKit

/// 蓝图活动数据模型
struct BlueprintActivity {
    let materials: [(typeID: Int, typeName: String, typeIcon: String, quantity: Int)]
    let skills:
        [(typeID: Int, typeName: String, typeIcon: String, level: Int, timeMultiplier: Double?)]
    let products:
        [(typeID: Int, typeName: String, typeIcon: String, quantity: Int, probability: Double?)]
    let time: Int
    let maxRunsPerCopy: Int
}

/// 产出物项视图
struct ProductItemView: View {
    let item: (typeID: Int, typeName: String, typeIcon: String, quantity: Int, probability: Double?)
    let databaseManager: DatabaseManager

    var body: some View {
        NavigationLink(
            destination: {
                ItemInfoMap.getItemInfoView(
                    itemID: item.typeID,
                    databaseManager: databaseManager
                )
            }
        ) {
            HStack {
                IconManager.shared.loadImage(
                    for: item.typeIcon.isEmpty ? "not_found" : item.typeIcon
                )
                .resizable()
                .frame(width: 32, height: 32)
                .cornerRadius(6)

                Text(NSLocalizedString("Blueprint_Product", comment: ""))

                Spacer()

                Text("\(item.quantity) × \(item.typeName)")
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

/// 发明产出项视图
struct InventionProductItemView: View {
    let product:
        (typeID: Int, typeName: String, typeIcon: String, quantity: Int, probability: Double?)
    let databaseManager: DatabaseManager

    var body: some View {
        NavigationLink(
            destination: {
                ItemInfoMap.getItemInfoView(
                    itemID: product.typeID,
                    databaseManager: databaseManager
                )
            }
        ) {
            HStack {
                IconManager.shared.loadImage(
                    for: product.typeIcon.isEmpty ? "not_found" : product.typeIcon
                )
                .resizable()
                .frame(width: 32, height: 32)
                .cornerRadius(6)

                VStack(alignment: .leading) {
                    Text(product.typeName)
                        .foregroundColor(.primary)
                    if let probability = product.probability {
                        Text(
                            "\(NSLocalizedString("Blueprint_Success_Rate", comment: "")) \(FormatUtil.formatPercent(probability, fractionDigits: 0))"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

/// 蓝图技能需求行
struct BlueprintSkillRow: View {
    let skill:
        (typeID: Int, typeName: String, typeIcon: String, level: Int, timeMultiplier: Double?)
    let databaseManager: DatabaseManager
    let currentSkillLevel: Int?

    /// 获取当前技能点数（直接查表，不累加）
    private func getCurrentSkillPointsSimple() -> Int {
        guard let currentLevel = currentSkillLevel else { return 0 }
        return SkillTreeManager.skillPoints(level: currentLevel, multiplier: skill.timeMultiplier) ?? 0
    }

    /// 获取所需总点数（直接查表）
    private func getRequiredSkillPointsSimple() -> Int {
        SkillTreeManager.skillPoints(level: skill.level, multiplier: skill.timeMultiplier) ?? 0
    }

    /// 获取技能点数文本
    private var skillPointsText: String {
        guard let points = SkillTreeManager.skillPoints(
            level: skill.level,
            multiplier: skill.timeMultiplier
        ) else {
            return ""
        }
        return "\(FormatUtil.format(Double(points))) SP"
    }

    var body: some View {
        NavigationLink {
            ItemInfoMap.getItemInfoView(
                itemID: skill.typeID,
                databaseManager: databaseManager
            )
        } label: {
            HStack {
                // 技能图标
                if currentSkillLevel == nil {
                    // 正在加载技能数据
                    ProgressView()
                        .frame(width: 32, height: 32)
                        .scaleEffect(0.8)
                } else if let currentLevel = currentSkillLevel, currentLevel == -2 {
                    // 无角色登录，显示通用技能图标
                    Image("skill")
                        .resizable()
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                } else if let currentLevel = currentSkillLevel, currentLevel == -1 {
                    Image(systemName: "xmark.circle.fill")
                        .frame(width: 32, height: 32)
                        .foregroundColor(.red)
                } else if let currentLevel = currentSkillLevel, currentLevel >= skill.level {
                    Image(systemName: "checkmark.circle.fill")
                        .frame(width: 32, height: 32)
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "circle")
                        .frame(width: 32, height: 32)
                        .foregroundColor(.primary)
                }

                VStack(alignment: .leading) {
                    // 技能名称
                    Text(skill.typeName)
                        .font(.body)

                    // 技能点数显示
                    if currentSkillLevel == nil {
                        // 正在加载中
                        Text(NSLocalizedString("Misc_Loading", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if let currentLevel = currentSkillLevel, currentLevel == -2 {
                        // 无角色登录，显示需要的总技能点数
                        if !skillPointsText.isEmpty {
                            Text(skillPointsText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else if let currentLevel = currentSkillLevel, currentLevel >= -1,
                              currentLevel < skill.level
                    {
                        // 当有技能但等级不足时，显示当前/需要的技能点数
                        let currentSP = getCurrentSkillPointsSimple()
                        let requiredSP = getRequiredSkillPointsSimple()
                        Text(
                            "\(FormatUtil.format(Double(currentSP)))/\(FormatUtil.format(Double(requiredSP))) SP"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    } else {
                        // 其他情况显示需要的总技能点数
                        if !skillPointsText.isEmpty {
                            Text(skillPointsText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                // 等级要求
                Text(
                    String(
                        format: NSLocalizedString(
                            "Misc_Level", comment: ""
                        ), skill.level
                    )
                )
                .foregroundColor(.secondary)
                .frame(alignment: .trailing)
            }
        }
    }
}

/// 活动区头：标题 + 复制材料按钮；存在不同英文名称时附加复制材料(EN)按钮
struct BlueprintActivityHeader: View {
    let title: String
    let materials: [(typeID: Int, typeName: String, typeIcon: String, quantity: Int)]
    let onCopied: () -> Void

    /// 是否存在与当前显示名不同的英文名称
    private var hasDifferentEnglishNames: Bool {
        materials.contains { material in
            guard let enName = ItemInfoMap.typeInfo(for: material.typeID)?.enName,
                  !enName.isEmpty
            else { return false }
            return enName != material.typeName
        }
    }

    /// 复制材料列表到剪贴板（英文名缺失时回退当前显示名）
    private func copyMaterials(useEnglishNames: Bool) {
        let materialsText = materials.map { material in
            var name = material.typeName
            if useEnglishNames,
               let enName = ItemInfoMap.typeInfo(for: material.typeID)?.enName, !enName.isEmpty
            {
                name = enName
            }
            return "\(name)      \(material.quantity)"
        }.joined(separator: "\n")
        UIPasteboard.general.string = materialsText
        onCopied()
    }

    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()

            if !materials.isEmpty {
                Button(action: {
                    copyMaterials(useEnglishNames: false)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 14))
                        Text(NSLocalizedString("Blueprint_Copy_Materials", comment: ""))
                            .font(.system(size: 14))
                    }
                }
                .buttonStyle(.borderless)

                // 如果有不同的英文名称，显示复制英文版按钮
                if hasDifferentEnglishNames {
                    Button(action: {
                        copyMaterials(useEnglishNames: true)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 14))
                            Text(NSLocalizedString("Blueprint_Copy_Materials_EN", comment: ""))
                                .font(.system(size: 14))
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }
}

/// 主视图
struct ShowBluePrintInfo: View {
    @Environment(\.locale) private var displayLocale
    let blueprintID: Int
    let databaseManager: DatabaseManager
    @State private var manufacturing: BlueprintActivity?
    @State private var researchMaterial: BlueprintActivity?
    @State private var researchTime: BlueprintActivity?
    @State private var copying: BlueprintActivity?
    @State private var invention: BlueprintActivity?
    @State private var itemDetails: ItemDetails?
    @State private var blueprintSource: [(typeID: Int, typeName: String, typeIcon: String)] = []
    @StateObject private var skillsManager = SharedSkillsManager.shared
    @State private var showingCopyAlert = false
    @State private var isManufacturingMaterialsExpanded = false
    @State private var isManufacturingSkillsExpanded = false
    @State private var isResearchMaterialMaterialsExpanded = false
    @State private var isResearchMaterialSkillsExpanded = false
    @State private var isResearchMaterialLevelsExpanded = false
    @State private var isResearchTimeMaterialsExpanded = false
    @State private var isResearchTimeSkillsExpanded = false
    @State private var isResearchTimeLevelsExpanded = false
    @State private var isCopyingMaterialsExpanded = false
    @State private var isCopyingSkillsExpanded = false
    @State private var isInventionMaterialsExpanded = false
    @State private var isInventionSkillsExpanded = false
    @State private var showBlueprintCalculator = false

    /// 加载蓝图来源
    private func loadBlueprintSource() {
        blueprintSource = databaseManager.getBlueprintSource(for: blueprintID)
    }

    private func skillsWithTimeMultipliers(
        _ skills: [(typeID: Int, typeName: String, typeIcon: String, level: Int)]
    ) -> [(
        typeID: Int, typeName: String, typeIcon: String, level: Int, timeMultiplier: Double?
    )] {
        let multipliers = SkillTreeManager.shared.getTrainingTimeMultipliers(
            for: skills.map(\.typeID),
            databaseManager: databaseManager
        )
        return skills.map {
            (
                typeID: $0.typeID,
                typeName: $0.typeName,
                typeIcon: $0.typeIcon,
                level: $0.level,
                timeMultiplier: multipliers[$0.typeID]
            )
        }
    }

    /// 加载蓝图数据
    private func loadBlueprintData() {
        guard let processTime = databaseManager.getBlueprintProcessTime(for: blueprintID) else {
            return
        }

        let maxRunsPerCopy = processTime.maxRunsPerCopy

        if processTime.manufacturing_time > 0 {
            let materials = databaseManager.getBlueprintManufacturingMaterials(for: blueprintID)
            let products = databaseManager.getBlueprintManufacturingOutput(for: blueprintID)
            let skills = databaseManager.getBlueprintManufacturingSkills(for: blueprintID)

            manufacturing = BlueprintActivity(
                materials: materials,
                skills: skillsWithTimeMultipliers(skills),
                products: products.map {
                    ($0.typeID, $0.typeName, $0.typeIcon, $0.quantity, nil)
                },
                time: processTime.manufacturing_time,
                maxRunsPerCopy: 0
            )
        }

        if processTime.research_material_time > 0 {
            researchMaterial = BlueprintActivity(
                materials: databaseManager.getBlueprintResearchMaterialMaterials(for: blueprintID),
                skills: skillsWithTimeMultipliers(
                    databaseManager.getBlueprintResearchMaterialSkills(for: blueprintID)
                ),
                products: [],
                time: processTime.research_material_time,
                maxRunsPerCopy: 0
            )
        }

        if processTime.research_time_time > 0 {
            researchTime = BlueprintActivity(
                materials: databaseManager.getBlueprintResearchTimeMaterials(for: blueprintID),
                skills: skillsWithTimeMultipliers(
                    databaseManager.getBlueprintResearchTimeSkills(for: blueprintID)
                ),
                products: [],
                time: processTime.research_time_time,
                maxRunsPerCopy: 0
            )
        }

        if processTime.copying_time > 0 {
            copying = BlueprintActivity(
                materials: databaseManager.getBlueprintCopyingMaterials(for: blueprintID),
                skills: skillsWithTimeMultipliers(
                    databaseManager.getBlueprintCopyingSkills(for: blueprintID)
                ),
                products: [],
                time: processTime.copying_time,
                maxRunsPerCopy: maxRunsPerCopy
            )
        }

        if processTime.invention_time > 0 {
            let products = databaseManager.getBlueprintInventionProducts(for: blueprintID)
            invention = BlueprintActivity(
                materials: databaseManager.getBlueprintInventionMaterials(for: blueprintID),
                skills: skillsWithTimeMultipliers(
                    databaseManager.getBlueprintInventionSkills(for: blueprintID)
                ),
                products: products.map {
                    ($0.typeID, $0.typeName, $0.typeIcon, $0.quantity, $0.probability)
                },
                time: processTime.invention_time,
                maxRunsPerCopy: 0
            )
        }
    }

    /// 计算特定等级的时间
    private func calculateLevelTime(baseTime: Int, level: Int) -> Int {
        let levelMultipliers = [105, 250, 595, 1414, 3360, 8000, 19000, 45255, 107_700, 256_000]
        let rank = baseTime / 105
        return levelMultipliers[level - 1] * rank

        // 此处采用blueprints.yaml中提供的基准时间，除以rank1的基准时间获取rank值，再乘各个rank的标准时间来计算。
        // rank值也可以通过查询typeAttributes表中对应物品的attribute_id = 1955的值来获取
    }

    /// 获取当前技能等级
    private func getCurrentSkillLevel(for skillID: Int) -> Int? {
        return skillsManager.getSkillLevel(for: skillID)
    }

    var body: some View {
        List {
            // 基础信息部分
            if let itemDetails = itemDetails {
                ItemBasicInfoView(
                    itemDetails: itemDetails, databaseManager: databaseManager,
                    modifiedAttributes: nil
                )
            }

            // 制造活动
            if let manufacturing = manufacturing {
                Section(
                    header: BlueprintActivityHeader(
                        title: NSLocalizedString("Blueprint_Manufacturing", comment: ""),
                        materials: manufacturing.materials,
                        onCopied: { showingCopyAlert = true }
                    ),
                    footer: Button(action: {
                        showBlueprintCalculator = true
                    }) {
                        HStack(spacing: 4) {
                            Spacer()
                            Image(systemName: "compass.drawing")
                                .font(.system(size: 14))
                            Text(
                                NSLocalizedString(
                                    "Blueprint_Calculator_Open_Calculator", comment: "打开计算器"
                                )
                            )
                            .font(.system(size: 14))
                        }
                    }
                    .buttonStyle(.borderless)
                ) {
                    // 产出物
                    if !manufacturing.products.isEmpty {
                        ForEach(manufacturing.products, id: \.typeID) { product in
                            ProductItemView(item: product, databaseManager: databaseManager)
                        }
                    }

                    // 材料折叠组
                    if !manufacturing.materials.isEmpty {
                        DisclosureGroup(
                            isExpanded: $isManufacturingMaterialsExpanded,
                            content: {
                                ForEach(manufacturing.materials, id: \.typeID) { material in
                                    NavigationLink {
                                        ShowItemInfo(
                                            databaseManager: databaseManager,
                                            itemID: material.typeID
                                        )
                                    } label: {
                                        HStack {
                                            IconManager.shared.loadImage(
                                                for: material.typeIcon.isEmpty
                                                    ? "not_found" : material.typeIcon
                                            )
                                            .resizable()
                                            .frame(width: 32, height: 32)
                                            .cornerRadius(6)

                                            Text(material.typeName)

                                            Spacer()

                                            Text(
                                                "\(material.quantity)"
                                            )
                                            .foregroundColor(.secondary)
                                            .frame(alignment: .trailing)
                                        }
                                    }
                                }
                                .listRowInsets(
                                    EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)
                                )
                            },
                            label: {
                                HStack {
                                    Text(
                                        NSLocalizedString(
                                            "Blueprint_Required_Materials", comment: ""
                                        )
                                    )
                                    Spacer()
                                    Text(
                                        "\(manufacturing.materials.count)\(NSLocalizedString("Misc_number_items", comment: ""))"
                                    )
                                    .foregroundColor(.secondary)
                                    .frame(alignment: .trailing)
                                }
                            }
                        )
                    }

                    // 技能折叠组
                    if !manufacturing.skills.isEmpty {
                        DisclosureGroup(
                            isExpanded: $isManufacturingSkillsExpanded,
                            content: {
                                ForEach(manufacturing.skills, id: \.typeID) { skill in
                                    BlueprintSkillRow(
                                        skill: skill,
                                        databaseManager: databaseManager,
                                        currentSkillLevel: getCurrentSkillLevel(for: skill.typeID)
                                    )
                                }.listRowInsets(
                                    EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)
                                )
                            },
                            label: {
                                HStack {
                                    Text(
                                        NSLocalizedString("Blueprint_Required_Skills", comment: "")
                                    )
                                    Spacer()
                                    Text(
                                        "\(manufacturing.skills.count) \(NSLocalizedString("Misc_number_items", comment: ""))"
                                    )
                                    .foregroundColor(.secondary)
                                    .frame(alignment: .trailing)
                                }
                            }
                        )
                    }

                    // 制造时间
                    HStack {
                        Text(NSLocalizedString("Blueprint_Manufacturing_Time", comment: ""))
                        Spacer()
                        Text(FormatUtil.formatBlueprintDuration(manufacturing.time))
                            .foregroundColor(.secondary)
                            .frame(alignment: .trailing)
                    }
                }
            }

            // 材料研究活动
            if let researchMaterial = researchMaterial {
                Section(
                    header: BlueprintActivityHeader(
                        title: NSLocalizedString("Blueprint_Research_Material", comment: ""),
                        materials: researchMaterial.materials,
                        onCopied: { showingCopyAlert = true }
                    )
                ) {
                    // 材料折叠组
                    if !researchMaterial.materials.isEmpty {
                        DisclosureGroup(
                            isExpanded: $isResearchMaterialMaterialsExpanded,
                            content: {
                                ForEach(researchMaterial.materials, id: \.typeID) { material in
                                    NavigationLink {
                                        ItemInfoMap.getItemInfoView(
                                            itemID: material.typeID,
                                            databaseManager: databaseManager
                                        )
                                    } label: {
                                        HStack {
                                            IconManager.shared.loadImage(
                                                for: material.typeIcon.isEmpty
                                                    ? "not_found" : material.typeIcon
                                            )
                                            .resizable()
                                            .frame(width: 32, height: 32)
                                            .cornerRadius(6)

                                            Text(material.typeName)

                                            Spacer()

                                            Text("\(material.quantity)")
                                                .foregroundColor(.secondary)
                                                .frame(alignment: .trailing)
                                        }
                                    }
                                }
                                .listRowInsets(
                                    EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)
                                )
                            },
                            label: {
                                HStack {
                                    Text(
                                        NSLocalizedString(
                                            "Blueprint_Required_Materials", comment: ""
                                        )
                                    )
                                    Spacer()
                                    Text(
                                        "\(researchMaterial.materials.count) \(NSLocalizedString("Misc_number_items", comment: ""))"
                                    )
                                    .foregroundColor(.secondary)
                                    .frame(alignment: .trailing)
                                }
                            }
                        )
                    }

                    // 技能折叠组
                    if !researchMaterial.skills.isEmpty {
                        DisclosureGroup(
                            isExpanded: $isResearchMaterialSkillsExpanded,
                            content: {
                                ForEach(researchMaterial.skills, id: \.typeID) { skill in
                                    BlueprintSkillRow(
                                        skill: skill,
                                        databaseManager: databaseManager,
                                        currentSkillLevel: getCurrentSkillLevel(for: skill.typeID)
                                    )
                                }.listRowInsets(
                                    EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)
                                )
                            },
                            label: {
                                HStack {
                                    Text(
                                        NSLocalizedString("Blueprint_Required_Skills", comment: "")
                                    )
                                    Spacer()
                                    Text(
                                        "\(researchMaterial.skills.count) \(NSLocalizedString("Misc_number_items", comment: ""))"
                                    )
                                    .foregroundColor(.secondary)
                                    .frame(alignment: .trailing)
                                }
                            }
                        )
                    }

                    // 时间等级折叠组
                    DisclosureGroup(
                        isExpanded: $isResearchMaterialLevelsExpanded,
                        content: {
                            ForEach(1 ... 10, id: \.self) { level in
                                HStack {
                                    Text(
                                        String(
                                            format: NSLocalizedString(
                                                "Misc_Level", comment: "lv%d"
                                            ), level
                                        )
                                    )
                                    Spacer()
                                    Text(
                                        FormatUtil.formatBlueprintDuration(
                                            calculateLevelTime(
                                                baseTime: researchMaterial.time, level: level
                                            )
                                        )
                                    )
                                    .foregroundColor(.secondary)
                                    .frame(alignment: .trailing)
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                        },
                        label: {
                            HStack {
                                Text(
                                    NSLocalizedString("Blueprint_Research_Time_Label", comment: "")
                                )
                                Spacer()
                            }
                        }
                    )
                }
            }

            // 时间研究活动
            if let researchTime = researchTime {
                Section(
                    header: BlueprintActivityHeader(
                        title: NSLocalizedString("Blueprint_Research_Time", comment: ""),
                        materials: researchTime.materials,
                        onCopied: { showingCopyAlert = true }
                    )
                ) {
                    // 材料折叠组
                    if !researchTime.materials.isEmpty {
                        DisclosureGroup(
                            isExpanded: $isResearchTimeMaterialsExpanded,
                            content: {
                                ForEach(researchTime.materials, id: \.typeID) { material in
                                    NavigationLink {
                                        ItemInfoMap.getItemInfoView(
                                            itemID: material.typeID,
                                            databaseManager: databaseManager
                                        )
                                    } label: {
                                        HStack {
                                            IconManager.shared.loadImage(
                                                for: material.typeIcon.isEmpty
                                                    ? "not_found" : material.typeIcon
                                            )
                                            .resizable()
                                            .frame(width: 32, height: 32)
                                            .cornerRadius(6)

                                            Text(material.typeName)

                                            Spacer()

                                            Text(
                                                "\(material.quantity)"
                                            )
                                            .foregroundColor(.secondary)
                                            .frame(alignment: .trailing)
                                        }
                                    }
                                }
                                .listRowInsets(
                                    EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)
                                )
                            },
                            label: {
                                HStack {
                                    Text(
                                        NSLocalizedString(
                                            "Blueprint_Required_Materials", comment: ""
                                        )
                                    )
                                    Spacer()
                                    Text(
                                        "\(researchTime.materials.count) \(NSLocalizedString("Misc_number_items", comment: ""))"
                                    )
                                    .foregroundColor(.secondary)
                                    .frame(alignment: .trailing)
                                }
                            }
                        )
                    }

                    // 技能折叠组
                    if !researchTime.skills.isEmpty {
                        DisclosureGroup(
                            isExpanded: $isResearchTimeSkillsExpanded,
                            content: {
                                ForEach(researchTime.skills, id: \.typeID) { skill in
                                    BlueprintSkillRow(
                                        skill: skill,
                                        databaseManager: databaseManager,
                                        currentSkillLevel: getCurrentSkillLevel(for: skill.typeID)
                                    )
                                }.listRowInsets(
                                    EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)
                                )
                            },
                            label: {
                                HStack {
                                    Text(
                                        NSLocalizedString("Blueprint_Required_Skills", comment: "")
                                    )
                                    Spacer()
                                    Text(
                                        "\(researchTime.skills.count) \(NSLocalizedString("Misc_number_items", comment: ""))"
                                    )
                                    .foregroundColor(.secondary)
                                    .frame(alignment: .trailing)
                                }
                            }
                        )
                    }

                    // 时间等级折叠组
                    DisclosureGroup(
                        isExpanded: $isResearchTimeLevelsExpanded,
                        content: {
                            ForEach(1 ... 10, id: \.self) { level in
                                HStack {
                                    Text(
                                        String(
                                            format: NSLocalizedString(
                                                "Misc_Level", comment: "lv%d"
                                            ), 2 * level
                                        )
                                    )
                                    Spacer()
                                    Text(
                                        FormatUtil.formatBlueprintDuration(
                                            calculateLevelTime(
                                                baseTime: researchTime.time, level: level
                                            )
                                        )
                                    )
                                    .foregroundColor(.secondary)
                                    .frame(alignment: .trailing)
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                        },
                        label: {
                            HStack {
                                Text(
                                    NSLocalizedString("Blueprint_Research_Time_Label", comment: "")
                                )
                                Spacer()
                            }
                        }
                    )
                }
            }

            // 复制活动
            if let copying = copying {
                Section(
                    header: BlueprintActivityHeader(
                        title: NSLocalizedString("Blueprint_Copying", comment: ""),
                        materials: copying.materials,
                        onCopied: { showingCopyAlert = true }
                    )
                ) {
                    // 材料折叠组
                    if !copying.materials.isEmpty {
                        DisclosureGroup(
                            isExpanded: $isCopyingMaterialsExpanded,
                            content: {
                                ForEach(copying.materials, id: \.typeID) { material in
                                    NavigationLink {
                                        ItemInfoMap.getItemInfoView(
                                            itemID: material.typeID,
                                            databaseManager: databaseManager
                                        )
                                    } label: {
                                        HStack {
                                            IconManager.shared.loadImage(
                                                for: material.typeIcon.isEmpty
                                                    ? "not_found" : material.typeIcon
                                            )
                                            .resizable()
                                            .frame(width: 32, height: 32)
                                            .cornerRadius(6)

                                            Text(material.typeName)

                                            Spacer()

                                            Text(
                                                "\(material.quantity)"
                                            )
                                            .foregroundColor(.secondary)
                                            .frame(alignment: .trailing)
                                        }
                                    }
                                }
                                .listRowInsets(
                                    EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)
                                )
                            },
                            label: {
                                HStack {
                                    Text(
                                        NSLocalizedString(
                                            "Blueprint_Required_Materials", comment: ""
                                        )
                                    )
                                    Spacer()
                                    Text(
                                        "\(copying.materials.count) \(NSLocalizedString("Misc_number_items", comment: ""))"
                                    )
                                    .foregroundColor(.secondary)
                                    .frame(alignment: .trailing)
                                }
                            }
                        )
                    }

                    // 技能折叠组
                    if !copying.skills.isEmpty {
                        DisclosureGroup(
                            isExpanded: $isCopyingSkillsExpanded,
                            content: {
                                ForEach(copying.skills, id: \.typeID) { skill in
                                    BlueprintSkillRow(
                                        skill: skill,
                                        databaseManager: databaseManager,
                                        currentSkillLevel: getCurrentSkillLevel(for: skill.typeID)
                                    )
                                }.listRowInsets(
                                    EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)
                                )
                            },
                            label: {
                                HStack {
                                    Text(
                                        NSLocalizedString("Blueprint_Required_Skills", comment: "")
                                    )
                                    Spacer()
                                    Text(
                                        "\(copying.skills.count) \(NSLocalizedString("Misc_number_items", comment: ""))"
                                    )
                                    .foregroundColor(.secondary)
                                    .frame(alignment: .trailing)
                                }
                            }
                        )
                    }

                    // 复制时间
                    HStack {
                        Text(NSLocalizedString("Blueprint_Copying_Time", comment: ""))
                        Spacer()
                        Text(FormatUtil.formatBlueprintDuration(copying.time))
                            .foregroundColor(.secondary)
                            .frame(alignment: .trailing)
                    }

                    // 每次复制的最大流程数（仅在大于0时显示）
                    if copying.maxRunsPerCopy > 0 {
                        HStack {
                            Text(NSLocalizedString("Blueprint_Max_Runs_Per_Copy", comment: ""))
                            Spacer()
                            Text("\(copying.maxRunsPerCopy)")
                                .foregroundColor(.secondary)
                                .frame(alignment: .trailing)
                        }
                    }
                }
            }

            // 发明活动
            if let invention = invention {
                Section(
                    header: BlueprintActivityHeader(
                        title: NSLocalizedString("Blueprint_Invention", comment: ""),
                        materials: invention.materials,
                        onCopied: { showingCopyAlert = true }
                    )
                ) {
                    // 产出物
                    if !invention.products.isEmpty {
                        ForEach(invention.products, id: \.typeID) { product in
                            InventionProductItemView(
                                product: product, databaseManager: databaseManager
                            )
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }

                    // 材料折叠组
                    if !invention.materials.isEmpty {
                        DisclosureGroup(
                            isExpanded: $isInventionMaterialsExpanded,
                            content: {
                                ForEach(invention.materials, id: \.typeID) { material in
                                    NavigationLink {
                                        ItemInfoMap.getItemInfoView(
                                            itemID: material.typeID,
                                            databaseManager: databaseManager
                                        )
                                    } label: {
                                        HStack {
                                            IconManager.shared.loadImage(
                                                for: material.typeIcon.isEmpty
                                                    ? "not_found" : material.typeIcon
                                            )
                                            .resizable()
                                            .frame(width: 32, height: 32)
                                            .cornerRadius(6)

                                            Text(material.typeName)

                                            Spacer()

                                            Text(
                                                "\(material.quantity)"
                                            )
                                            .foregroundColor(.secondary)
                                            .frame(alignment: .trailing)
                                        }
                                    }
                                }
                                .listRowInsets(
                                    EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)
                                )
                            },
                            label: {
                                HStack {
                                    Text(
                                        NSLocalizedString(
                                            "Blueprint_Required_Materials", comment: ""
                                        )
                                    )
                                    Spacer()
                                    Text(
                                        "\(invention.materials.count) \(NSLocalizedString("Misc_number_items", comment: ""))"
                                    )
                                    .foregroundColor(.secondary)
                                    .frame(alignment: .trailing)
                                }
                            }
                        )
                    }

                    // 技能折叠组
                    if !invention.skills.isEmpty {
                        DisclosureGroup(
                            isExpanded: $isInventionSkillsExpanded,
                            content: {
                                ForEach(invention.skills, id: \.typeID) { skill in
                                    BlueprintSkillRow(
                                        skill: skill,
                                        databaseManager: databaseManager,
                                        currentSkillLevel: getCurrentSkillLevel(for: skill.typeID)
                                    )
                                }.listRowInsets(
                                    EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)
                                )
                            },
                            label: {
                                HStack {
                                    Text(
                                        NSLocalizedString("Blueprint_Required_Skills", comment: "")
                                    )
                                    Spacer()
                                    Text(
                                        "\(invention.skills.count) \(NSLocalizedString("Misc_number_items", comment: ""))"
                                    )
                                    .foregroundColor(.secondary)
                                    .frame(alignment: .trailing)
                                }
                            }
                        )
                    }

                    // 发明时间
                    HStack {
                        Text(NSLocalizedString("Blueprint_Invention_Time", comment: ""))
                        Spacer()
                        Text(FormatUtil.formatBlueprintDuration(invention.time))
                            .foregroundColor(.secondary)
                            .frame(alignment: .trailing)
                    }
                }
            }

            // 来源部分
            if !blueprintSource.isEmpty { // 检查是否有来源
                Section(
                    header: Text(NSLocalizedString("Blueprint_Source", comment: "")).font(.headline)
                ) {
                    ForEach(blueprintSource, id: \.typeID) { source in
                        NavigationLink(
                            destination: ItemInfoMap.getItemInfoView(
                                itemID: source.typeID,
                                databaseManager: databaseManager
                            )
                        ) {
                            HStack {
                                IconManager.shared.loadImage(
                                    for: source.typeIcon.isEmpty
                                        ? IconManager.defaultItemIcon : source.typeIcon
                                )
                                .resizable()
                                .frame(width: 32, height: 32)
                                .cornerRadius(6)

                                Text(source.typeName)
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Blueprint_Info", comment: ""))
        .alert(
            NSLocalizedString("Blueprint_Copy_Success", comment: "材料已复制"),
            isPresented: $showingCopyAlert
        ) {
            Button("OK", role: .cancel) {}
        }
        .navigationDestination(isPresented: $showBlueprintCalculator) {
            BlueprintCalculatorView(
                initParams: BlueprintCalculatorInitParams(
                    blueprintId: blueprintID
                )
            )
        }
        .onAppear {
            itemDetails = databaseManager.getItemDetails(for: blueprintID)
            loadBlueprintData()
            loadBlueprintSource()
        }
    }
}
