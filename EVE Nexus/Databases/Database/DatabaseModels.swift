import Foundation
import SwiftUI

/// 通用的数据项模型
struct DatabaseListItem: Identifiable {
    let id: Int
    let name: String
    let enName: String?
    let iconFileName: String
    let published: Bool
    let categoryID: Int?
    let groupID: Int?
    let groupName: String?
    let pgNeed: Double?
    let cpuNeed: Double?
    let rigCost: Int?
    let emDamage: Double?
    let themDamage: Double?
    let kinDamage: Double?
    let expDamage: Double?
    let highSlot: Int?
    let midSlot: Int?
    let lowSlot: Int?
    let rigSlot: Int?
    let gunSlot: Int?
    let missSlot: Int?
    let metaGroupID: Int?
    let marketGroupID: Int?
    /// 是否支持「属性快速比对」（加载时预填充，渲染期无需再查）
    var attributeCompareEligible: Bool = false
    let navigationDestination: AnyView

    init(
        id: Int,
        name: String,
        enName: String?,
        iconFileName: String,
        published: Bool,
        categoryID: Int? = nil,
        groupID: Int? = nil,
        groupName: String? = nil,
        pgNeed: Double? = nil,
        cpuNeed: Double? = nil,
        rigCost: Int? = nil,
        emDamage: Double? = nil,
        themDamage: Double? = nil,
        kinDamage: Double? = nil,
        expDamage: Double? = nil,
        highSlot: Int? = nil,
        midSlot: Int? = nil,
        lowSlot: Int? = nil,
        rigSlot: Int? = nil,
        gunSlot: Int? = nil,
        missSlot: Int? = nil,
        metaGroupID: Int? = nil,
        marketGroupID: Int? = nil,
        attributeCompareEligible: Bool = false,
        navigationDestination: AnyView = AnyView(EmptyView())
    ) {
        self.id = id
        self.name = name
        self.enName = enName
        self.iconFileName = iconFileName
        self.published = published
        self.categoryID = categoryID
        self.groupID = groupID
        self.groupName = groupName
        self.pgNeed = pgNeed
        self.cpuNeed = cpuNeed
        self.rigCost = rigCost
        self.emDamage = emDamage
        self.themDamage = themDamage
        self.kinDamage = kinDamage
        self.expDamage = expDamage
        self.highSlot = highSlot
        self.midSlot = midSlot
        self.lowSlot = lowSlot
        self.rigSlot = rigSlot
        self.gunSlot = gunSlot
        self.missSlot = missSlot
        self.metaGroupID = metaGroupID
        self.marketGroupID = marketGroupID
        self.attributeCompareEligible = attributeCompareEligible
        self.navigationDestination = navigationDestination
    }

    /// 从 SDEMemoryStore 内存索引构建（迁移自 loadMarketItems 的 SQL 行映射）；内存中不存在该物品时返回 nil
    init?(
        typeID: Int,
        databaseManager: DatabaseManager,
        eligibleMarketGroupIDs: Set<Int>? = nil,
        showFittingButton: Bool = false
    ) {
        guard let info = SDEMemoryStore.type(for: typeID) else { return nil }

        let groupName = info.groupID.flatMap { SDEMemoryStore.group(for: $0)?.name }
        let isEligible: Bool
        if let mgID = info.marketGroupID, let eligible = eligibleMarketGroupIDs {
            isEligible = eligible.contains(mgID)
        } else {
            isEligible = false
        }

        self.init(
            id: typeID,
            name: info.name,
            enName: info.enName,
            iconFileName: info.iconFilename,
            published: info.published,
            categoryID: info.categoryID,
            groupID: info.groupID,
            groupName: groupName,
            pgNeed: info.pgNeed,
            cpuNeed: info.cpuNeed,
            rigCost: info.rigCost,
            emDamage: info.emDamage,
            themDamage: info.themDamage,
            kinDamage: info.kinDamage,
            expDamage: info.expDamage,
            highSlot: info.highSlot,
            midSlot: info.midSlot,
            lowSlot: info.lowSlot,
            rigSlot: info.rigSlot,
            gunSlot: info.gunSlot,
            missSlot: info.missSlot,
            metaGroupID: info.metaGroupID,
            marketGroupID: info.marketGroupID,
            attributeCompareEligible: isEligible,
            navigationDestination: ItemInfoMap.getItemInfoView(
                itemID: typeID, databaseManager: databaseManager, showFittingButton: showFittingButton
            )
        )
    }

    /// 按 typeID 批量从内存索引构建（去重后按 id 升序，与旧 `type_id IN (...)` 查询 + 排序等价）
    static func listItems(
        for typeIDs: some Sequence<Int>,
        databaseManager: DatabaseManager,
        eligibleMarketGroupIDs: Set<Int>? = nil
    ) -> [DatabaseListItem] {
        Set(typeIDs)
            .sorted()
            .compactMap { DatabaseListItem(typeID: $0, databaseManager: databaseManager, eligibleMarketGroupIDs: eligibleMarketGroupIDs) }
    }
}

/// 搜索/浏览列表的分组模型
struct SearchResultSection<Item: Identifiable>: Identifiable {
    enum Identity: Hashable {
        /// 真实分组（市场组/元组等的 ID）
        case group(Int)
    }

    let identity: Identity
    let name: String
    let items: [Item]

    var id: Identity {
        identity
    }
}

/// 分类模型
public struct Category: Identifiable {
    public let id: Int
    public let name: String
    public let enName: String
    public let published: Bool
    public let iconID: Int
    public let iconFileNew: String

    public init(
        id: Int,
        name: String,
        enName: String,
        published: Bool,
        iconID: Int,
        iconFileNew: String
    ) {
        self.id = id
        self.name = name
        self.enName = enName
        self.published = published
        self.iconID = iconID
        self.iconFileNew = iconFileNew
    }
}

/// 组模型
public struct TypeGroup: Identifiable {
    public let id: Int
    public let name: String
    public let enName: String
    public let iconID: Int
    public let categoryID: Int
    public let published: Bool
    public let icon_filename: String

    public init(
        id: Int,
        name: String,
        enName: String,
        iconID: Int,
        categoryID: Int,
        published: Bool,
        icon_filename: String
    ) {
        self.id = id
        self.name = name
        self.enName = enName
        self.iconID = iconID
        self.categoryID = categoryID
        self.published = published
        self.icon_filename = icon_filename
    }
}

/// Trait 相关模型
public struct Trait {
    public let content: String
    public let importance: Int
    public let skill: Int?
    public let bonusType: String

    public init(content: String, importance: Int, skill: Int? = nil, bonusType: String = "") {
        self.content = content
        self.importance = importance
        self.skill = skill
        self.bonusType = bonusType
    }
}

public struct TraitGroup {
    public let roleBonuses: [Trait]
    public let typeBonuses: [Trait]
    public let miscBonuses: [Trait]

    public init(roleBonuses: [Trait], typeBonuses: [Trait], miscBonuses: [Trait] = []) {
        self.roleBonuses = roleBonuses
        self.typeBonuses = typeBonuses
        self.miscBonuses = miscBonuses
    }
}

/// 物品详情模型
public struct ItemDetails {
    public let name: String
    public let en_name: String?
    public let description: String
    public let iconFileName: String
    public let groupName: String
    public let categoryName: String
    public let categoryID: Int?
    public let roleBonuses: [Trait]?
    public let typeBonuses: [Trait]?
    public let miscBonuses: [Trait]?
    public let typeId: Int
    public let groupID: Int?
    public let volume: Double?
    public let repackagedVolume: Double?
    public let capacity: Double?
    public let mass: Double?
    public let marketGroupID: Int?

    public init(
        name: String,
        en_name: String,
        description: String,
        iconFileName: String,
        groupName: String,
        categoryID: Int? = nil,
        categoryName: String,
        roleBonuses: [Trait]? = [],
        typeBonuses: [Trait]? = [],
        miscBonuses: [Trait]? = [],
        typeId: Int,
        groupID: Int? = nil,
        volume: Double? = nil,
        repackagedVolume: Double? = nil,
        capacity: Double? = nil,
        mass: Double? = nil,
        marketGroupID: Int? = nil
    ) {
        self.name = name
        self.en_name = en_name
        self.description = description
        self.iconFileName = iconFileName
        self.groupName = groupName
        self.categoryName = categoryName
        self.categoryID = categoryID
        self.roleBonuses = roleBonuses
        self.typeBonuses = typeBonuses
        self.miscBonuses = miscBonuses
        self.typeId = typeId
        self.groupID = groupID
        self.volume = volume
        self.repackagedVolume = repackagedVolume
        self.capacity = capacity
        self.mass = mass
        self.marketGroupID = marketGroupID
    }
}

/// 属性分类模型
struct DogmaAttributeCategory: Identifiable {
    let id: Int
    let name: String
    let description: String
}

/// 属性模型
struct DogmaAttribute: Identifiable {
    let id: Int
    let categoryID: Int
    let name: String
    let displayName: String?
    let iconID: Int
    let iconFileName: String
    let value: Double
    let unitID: Int?
    let highIsGood: Bool
    let modifiedValue: Double?

    /// 有效的本地化显示名（空字符串视为无）
    var localizedDisplayName: String? {
        guard let displayName, !displayName.isEmpty else { return nil }
        return displayName
    }

    /// 优先用本地化名，否则回退到 attribute_key
    var displayTitle: String {
        localizedDisplayName ?? name
    }

    var shouldDisplay: Bool {
        !name.isEmpty
    }
}

/// 属性分组模型
struct AttributeGroup: Identifiable {
    let id: Int
    let name: String
    let attributes: [DogmaAttribute]
}
