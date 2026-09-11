import SwiftUI

// MARK: - 深渊突变属性模型

/// 用于展示的突变属性条目
private struct DynamicAttributeEntry: Identifiable {
    let id: Int // attribute_id
    let name: String
    let iconFileName: String?
    let unitID: Int? // 用于按数据库详情规则转换和格式化数值
    let originalValue: Double // 来源物品的原始数值
    let currentValue: Double // ESI 返回的当前实际数值
    let minMutator: Double // 突变质体的最小乘数
    let maxMutator: Double // 突变质体的最大乘数
    let highIsGood: Bool

    /// 当前突变乘数 = currentValue / originalValue
    var mutationMultiplier: Double {
        guard originalValue != 0 else { return 1.0 }
        return currentValue / originalValue
    }

    /// 转换为共享突变属性行使用的模型
    var displayAttribute: MutationDisplayAttribute {
        MutationDisplayAttribute(
            id: id,
            name: name,
            iconFileName: iconFileName,
            unitID: unitID,
            originalValue: originalValue,
            minMutator: minMutator,
            maxMutator: maxMutator,
            highIsGood: highIsGood,
            multiplier: mutationMultiplier
        )
    }
}

// MARK: - 深渊突变物品详情页

/// 通过 ESI dogma/dynamic/items API 获取制作者、来源物品、突变质体及属性突变情况
struct DynamicItemDetailView: View {
    let typeId: Int
    let itemId: Int64
    let itemName: String

    private let databaseManager = DatabaseManager()

    // MARK: - State

    @State private var isLoading = true
    @State private var errorMessage: String?

    /// API 返回的原始结果
    @State private var dynamicResult: DogmaDynamicItemsResult?

    /// 制作者名称
    @State private var creatorName: String?

    /// 来源物品信息
    @State private var sourceItemInfo: (name: String, iconFileName: String)?

    /// 突变质体信息
    @State private var mutaplasmidInfo: (name: String, iconFileName: String)?

    /// 解析后的突变属性列表
    @State private var mutationAttributes: [DynamicAttributeEntry] = []

    /// 来源物品的完整原始属性，以及由 ESI 当前值覆盖后的属性
    @State private var originalAttributeValues: [Int: Double] = [:]
    @State private var currentAttributeValues: [Int: Double] = [:]

    // MARK: - Body

    var body: some View {
        List {
            // 物品基本信息
            if let details = databaseManager.getItemDetails(for: typeId) {
                ItemBasicInfoView(
                    itemDetails: details,
                    databaseManager: databaseManager,
                    modifiedAttributes: nil
                )
            }

            // 加载中
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(.trailing, 8)
                        Text(NSLocalizedString("Abyssal_Loading", comment: ""))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }

            // 错误提示
            if let errorMessage = errorMessage {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text(errorMessage)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // 突变属性
            if !mutationAttributes.isEmpty {
                Section(
                    header: sectionHeader(NSLocalizedString("Main_Database_Mutation_Attribute", comment: ""))
                ) {
                    ForEach(mutationAttributes.sorted { $0.id < $1.id }) { attr in
                        MutationAttributeDisplayRowView(
                            attribute: .constant(attr.displayAttribute),
                            originalAttributes: originalAttributeValues,
                            currentAttributes: currentAttributeValues,
                            onEdit: nil
                        )
                    }
                }
                .listRowInsets(itemSectionRowInsets)
            }

            // 制作者（可跳转到角色详情）
            if let creatorName = creatorName, let result = dynamicResult {
                Section(header: sectionHeader(NSLocalizedString("Abyssal_Created_By", comment: ""))) {
                    if let character = currentCharacter {
                        NavigationLink {
                            CharacterDetailView(
                                characterId: result.created_by,
                                character: character
                            )
                        } label: {
                            creatorRow(createdBy: result.created_by, name: creatorName)
                        }
                    } else {
                        creatorRow(createdBy: result.created_by, name: creatorName)
                    }
                }
            }

            // 来源物品
            if let sourceInfo = sourceItemInfo, let result = dynamicResult {
                Section(header: sectionHeader(NSLocalizedString("Abyssal_Source_Item", comment: ""))) {
                    NavigationLink {
                        ShowItemInfo(databaseManager: databaseManager, itemID: result.source_type_id)
                    } label: {
                        HStack(spacing: 12) {
                            IconManager.shared.loadImage(for: sourceInfo.iconFileName)
                                .resizable()
                                .frame(width: 32, height: 32)
                                .cornerRadius(6)
                            Text(sourceInfo.name)
                        }
                    }
                }
            }

            // 使用的突变质体
            if let mutaInfo = mutaplasmidInfo, let result = dynamicResult {
                Section(header: sectionHeader(NSLocalizedString("Abyssal_Mutaplasmid_Used", comment: ""))) {
                    NavigationLink {
                        ShowItemInfo(databaseManager: databaseManager, itemID: result.mutator_type_id)
                    } label: {
                        HStack(spacing: 12) {
                            IconManager.shared.loadImage(for: mutaInfo.iconFileName)
                                .resizable()
                                .frame(width: 32, height: 32)
                                .cornerRadius(6)
                            Text(mutaInfo.name)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Abyssal_Item_Detail", comment: ""))
        .task {
            await loadDynamicItemInfo()
        }
    }

    // MARK: - 当前登录角色

    /// 通过 UserDefaults 获取当前角色信息，用于跳转 CharacterDetailView
    private var currentCharacter: EVECharacterInfo? {
        let charId = UserDefaults.standard.integer(forKey: "currentCharacterId")
        guard charId > 0 else { return nil }
        return EVELogin.shared.getCharacterByID(charId)?.character
    }

    /// 制作者行视图（提取复用，避免 NavigationLink 和非跳转两种情况重复代码）
    private func creatorRow(createdBy: Int, name: String) -> some View {
        HStack(spacing: 12) {
            AsyncImage(
                url: URL(
                    string: "https://images.evetech.net/characters/\(createdBy)/portrait?size=64"
                )
            ) { phase in
                switch phase {
                case let .success(image):
                    image.resizable()
                        .frame(width: 40, height: 40)
                        .cornerRadius(20)
                case .failure:
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .frame(width: 40, height: 40)
                        .foregroundColor(.secondary)
                default:
                    ProgressView()
                        .frame(width: 40, height: 40)
                }
            }
            Text(name)
        }
    }

    // MARK: - 通用 Section Header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
    }

    // MARK: - 数据加载

    private func loadDynamicItemInfo() async {
        isLoading = true
        errorMessage = nil

        do {
            // 1. 调用 ESI API 获取突变物品信息
            let result = try await DogmaDynamicItemsAPI.shared.fetch(
                typeId: typeId, itemId: Int(itemId)
            )
            dynamicResult = result

            // 2. 获取制作者名称
            let namesMap = try await UniverseAPI.shared.getNamesWithFallback(
                ids: [result.created_by]
            )
            creatorName = namesMap[result.created_by]?.name ?? "ID: \(result.created_by)"

            // 3. 从数据库获取来源物品信息
            sourceItemInfo = queryTypeInfo(typeId: result.source_type_id)

            // 4. 从数据库获取突变质体信息
            mutaplasmidInfo = queryTypeInfo(typeId: result.mutator_type_id)

            // 5. 构建突变属性列表及数据库详情格式化所需的属性上下文
            let attributeData = buildMutationAttributes(
                apiAttributes: result.dogma_attributes,
                sourceTypeId: result.source_type_id,
                mutatorTypeId: result.mutator_type_id
            )
            mutationAttributes = attributeData.entries
            originalAttributeValues = attributeData.originalValues
            currentAttributeValues = attributeData.currentValues

            isLoading = false
        } catch {
            Logger.error("加载深渊物品详情失败: \(error)")
            errorMessage = NSLocalizedString("Abyssal_Load_Error", comment: "")
            isLoading = false
        }
    }

    // MARK: - 构建突变属性

    /// 组合三方数据：突变质体属性范围 + 来源物品原始值 + ESI 返回的当前值
    private func buildMutationAttributes(
        apiAttributes: [DogmaAttributeItem],
        sourceTypeId: Int,
        mutatorTypeId: Int
    ) -> (
        entries: [DynamicAttributeEntry],
        originalValues: [Int: Double],
        currentValues: [Int: Double]
    ) {
        AttributeDisplayConfig.initializeUnits(with: databaseManager.loadAttributeUnits())

        // 1. 从 dynamic_item_attributes 获取突变质体能影响的属性（含范围和 highIsGood）
        let mutatorAttrs = loadMutatorAttributeRanges(mutatorTypeId: mutatorTypeId)
        guard !mutatorAttrs.isEmpty else { return ([], [:], [:]) }

        // 2. 从 typeAttributes 获取来源物品的完整原始属性，保留数据库详情格式化所需的上下文
        let originalValues = loadOriginalAttributeValues(sourceTypeId: sourceTypeId)

        // 3. 以来源物品属性为基础，用 ESI 返回的当前值覆盖
        var currentValues = originalValues
        for attr in apiAttributes {
            currentValues[attr.attribute_id] = attr.value
        }

        // 4. 组装
        var entries: [DynamicAttributeEntry] = []
        for mAttr in mutatorAttrs {
            guard let original = originalValues[mAttr.attributeID],
                  let current = currentValues[mAttr.attributeID]
            else { continue }

            entries.append(DynamicAttributeEntry(
                id: mAttr.attributeID,
                name: mAttr.name,
                iconFileName: mAttr.iconFileName,
                unitID: mAttr.unitID,
                originalValue: original,
                currentValue: current,
                minMutator: mAttr.minValue,
                maxMutator: mAttr.maxValue,
                highIsGood: mAttr.highIsGood
            ))
        }

        return (entries, originalValues, currentValues)
    }

    /// 从 SDEMemoryStore 加载突变质体的属性范围（highIsGood 已按表内覆盖值修正）
    private func loadMutatorAttributeRanges(mutatorTypeId: Int) -> [(
        attributeID: Int, name: String, iconFileName: String?, unitID: Int?,
        minValue: Double, maxValue: Double, highIsGood: Bool
    )] {
        SDEMemoryStore.dynamicItemAttributes(forTypeID: mutatorTypeId).map { info in
            (
                attributeID: info.attributeID,
                name: info.name,
                iconFileName: info.iconFileName,
                unitID: info.unitID,
                minValue: info.minValue,
                maxValue: info.maxValue,
                highIsGood: info.highIsGood
            )
        }
    }

    /// 从内存索引获取来源物品的完整原始属性
    private func loadOriginalAttributeValues(sourceTypeId: Int) -> [Int: Double] {
        SDEMemoryStore.typeAttributes(for: sourceTypeId)
    }

    /// 从内存索引查询 type_id 对应的名称和图标
    private func queryTypeInfo(typeId: Int) -> (name: String, iconFileName: String)? {
        guard let info = ItemInfoMap.typeInfo(for: typeId), !info.name.isEmpty else { return nil }
        return (name: info.name, iconFileName: info.iconFilename)
    }
}
