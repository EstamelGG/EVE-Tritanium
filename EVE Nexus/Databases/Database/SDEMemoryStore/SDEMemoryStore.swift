import Foundation

/// 八语本地化文本；查找时按当前数据库语言解析，语言切换无需重扫表。
struct LocalizedText: Equatable {
    let de: String
    let en: String
    let es: String
    let fr: String
    let ja: String
    let ko: String
    let ru: String
    let zh: String

    /// 用同一字符串填充八语（ESI/联盟名等只有单语种时）
    static func filled(with value: String) -> LocalizedText {
        LocalizedText(
            de: value, en: value, es: value, fr: value,
            ja: value, ko: value, ru: value, zh: value
        )
    }

    /// 从行字典读取 `{prefix}de_name`… 或裸 `de_name`（prefix 为空）
    static func from(row: [String: Any], prefix: String = "") -> LocalizedText {
        func v(_ lang: String) -> String {
            let key = prefix.isEmpty ? "\(lang)_name" : "\(prefix)\(lang)_name"
            return (row[key] as? String) ?? ""
        }
        return LocalizedText(
            de: v("de"), en: v("en"), es: v("es"), fr: v("fr"),
            ja: v("ja"), ko: v("ko"), ru: v("ru"), zh: v("zh")
        )
    }

    /// dogma unit 列：`unit_de_name` …
    static func units(from row: [String: Any]) -> LocalizedText {
        func v(_ lang: String) -> String {
            (row["unit_\(lang)_name"] as? String) ?? ""
        }
        return LocalizedText(
            de: v("de"), en: v("en"), es: v("es"), fr: v("fr"),
            ja: v("ja"), ko: v("ko"), ru: v("ru"), zh: v("zh")
        )
    }

    func resolved(_ languageCode: String? = nil) -> String {
        let lang = SDELanguage.columnPrefix(from: languageCode)
        let primary: String
        switch lang {
        case "de": primary = de
        case "es": primary = es
        case "fr": primary = fr
        case "ja": primary = ja
        case "ko": primary = ko
        case "ru": primary = ru
        case "zh": primary = zh
        default: primary = en
        }
        if !primary.isEmpty { return primary }
        if !en.isEmpty { return en }
        return [zh, de, fr, ja, ko, ru, es].first { !$0.isEmpty } ?? ""
    }

    /// resolved() 结果为空时返回 nil（用于可选展示场景）
    func resolvedNonEmpty(_ languageCode: String? = nil) -> String? {
        let s = resolved(languageCode)
        return s.isEmpty ? nil : s
    }

    /// 任意语种名称包含 query（大小写不敏感）即命中
    func matchesSearch(_ query: String) -> Bool {
        let q = query.lowercased()
        guard !q.isEmpty else { return false }
        return allValues.contains {
            !$0.isEmpty && $0.lowercased().contains(q)
        }
    }

    /// 任意语种名称与 query 全等（大小写不敏感）
    func matchesExact(_ query: String) -> Bool {
        guard !query.isEmpty else { return false }
        return allValues.contains {
            !$0.isEmpty && $0.caseInsensitiveCompare(query) == .orderedSame
        }
    }

    /// 固定检查顺序：en 最常被搜索放首位；de 92% 与 en 同值放末尾，命中短路后通常不再检查
    var allValues: [String] {
        [en, zh, ja, ko, ru, es, fr, de]
    }

    /// `t.name_search LIKE ?`：name_search 为 TEMP VIEW 中以 char(31) 拼接的全语种名称列
    static let typeLangNameLikeSQL = "(t.name_search LIKE ?)"

    static func typeLangNameLikeParams(_ searchText: String) -> [Any] {
        ["%\(searchText)%"]
    }

    static let typeLangNameColumns = [
        "de_name", "en_name", "es_name", "fr_name", "ja_name", "ko_name", "ru_name", "zh_name",
    ]
}

/// SDE 常用小表 / types 瘦字段内存索引。在 `ItemInfoMap.initializeCache`（loadDatabase）时重建。
/// 本地化字段存全语种，`name` / `displayName` 等为按当前语言动态解析。
///
/// 文件组织（按初始化项目拆分，同目录）：
/// - 本文件：数据结构定义 + 存储属性（extension 不能声明存储属性）+ loadAll 注册表
/// - SDEMemoryStore+Types / +Dogma / +Universe / +CorpStation / +Blueprint /
///   +DynamicItem / +Combat / +PI / +Material：对应域的 loader 与 lookup
/// - SDEMemoryStore+Shared：跨域共享的加载辅助
enum SDEMemoryStore {
    struct TypeInfo {
        let categoryID: Int
        let groupID: Int?
        let metaGroupID: Int?
        let marketGroupID: Int?
        let published: Bool
        let names: LocalizedText
        let iconFilename: String
        let bpcIconFilename: String?
        let volume: Double
        let capacity: Double
        let mass: Double
        let repackagedVolume: Double?
        let descID: String?
        let variationParentTypeID: Int?
        // 装配相关字段（DatabaseListItem 装配列展示用）
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

        var name: String {
            names.resolved()
        }

        var enName: String {
            names.en
        }
    }

    struct CategoryInfo {
        let id: Int
        let names: LocalizedText
        let published: Bool
        let iconFilename: String

        var name: String {
            names.resolved()
        }

        var enName: String {
            names.en
        }
    }

    struct GroupInfo {
        let id: Int
        let names: LocalizedText
        let categoryID: Int
        let published: Bool
        let iconFilename: String

        var name: String {
            names.resolved()
        }

        var enName: String {
            names.en
        }
    }

    struct MarketGroupInfo {
        let id: Int
        let names: LocalizedText
        let iconName: String
        let parentGroupID: Int?
        let show: Bool

        var name: String {
            names.resolved()
        }
    }

    struct DogmaAttributeInfo {
        let id: Int
        let categoryID: Int?
        let name: String // attribute_key，语言无关
        let displayNames: LocalizedText
        let iconID: Int
        let iconFilename: String
        let unitID: Int?
        let unitNames: LocalizedText
        let highIsGood: Bool
        let stackable: Bool
        let defaultValue: Double

        var displayName: String? {
            displayNames.resolvedNonEmpty()
        }
    }

    /// 舰载机能力（已按当前语言解析 name/description）
    struct FighterAbilityInfo {
        let slot: Int
        let abilityID: Int
        let name: String
        let description: String
        let cooldownSeconds: Int?
        let chargeCount: Int?
        let rearmTimeSeconds: Int?
        let iconFilename: String
    }

    struct FactionInfo: Identifiable {
        let id: Int
        let names: LocalizedText
        let iconName: String

        var name: String {
            names.resolved()
        }
    }

    struct NPCCorporationInfo {
        let id: Int
        let names: LocalizedText
        let iconFilename: String
        let factionID: Int?
        let militiaFaction: Int?

        var name: String {
            names.resolved()
        }

        var enName: String {
            names.en
        }

        var zhName: String {
            names.zh
        }
    }

    struct StationInfo {
        let id: Int
        let stationTypeID: Int?
        let regionID: Int?
        let solarSystemID: Int?
        let names: LocalizedText
        let security: Double?
        let lpStore: Int?

        var name: String {
            names.resolved()
        }
    }

    /// 动态物品映射（突变系统）：applicable_type + type_id(突变质体) → resulting_type(突变产物)
    struct DynamicItemMapping {
        let applicableType: Int
        let typeID: Int
        let resultingType: Int
    }

    /// 突变质体可影响的属性范围（dynamic_item_attributes）；
    /// highIsGood 已用表内 high_is_good 覆盖 dogma 默认值（NULL 回退默认值）
    struct DynamicItemAttributeInfo {
        let attributeID: Int
        let name: String
        let iconFileName: String?
        let unitID: Int?
        let minValue: Double
        let maxValue: Double
        let highIsGood: Bool
    }

    /// dynamic_item_attributes 原始行：highIsGoodOverride 为表内覆盖值（NULL 表示未覆盖）
    struct RawDynamicItemAttribute {
        let attributeID: Int
        let minValue: Double
        let maxValue: Double
        let highIsGoodOverride: Bool?
    }

    /// 指挥脉冲波 / 作战链 buff 信息（名称来自新版 dbuffCollection 本地化字段）
    struct WarfareBuffInfo {
        let buffID: Int
        let displayNames: LocalizedText

        /// 按当前语言解析的显示名称
        var displayName: String {
            displayNames.resolved()
        }
    }

    /// dogmaEffects 效果定义（effect_name 为语言无关 key；name/description 八语动态解析）
    struct DogmaEffectInfo {
        let effectID: Int
        let effectName: String
        let effectCategory: Int?
        let isOffensive: Bool
        let isAssistance: Bool
        let resistanceAttributeID: Int?
        /// 修饰器定义 JSON（3212 行有值，语言无关）
        let modifierInfo: String?
        let displayNames: LocalizedText
        let descriptions: LocalizedText

        var description: String? {
            descriptions.resolvedNonEmpty()
        }
    }

    /// 专精认证的单条技能要求（certificateSkills 表）
    struct CertificateSkillRequirement {
        let skillID: Int
        /// 5 档要求等级，下标 0-4 对应认证 1-5 级（basic/standard/improved/advanced/elite）
        /// 某档值为 0 表示该档不要求此技能
        let tierLevels: [Int]
    }

    /// universe 表星系摘要：安等 + 行星类型计数 + 坐标/跳跃门等扩展字段
    struct UniverseSystemInfo {
        let regionID: Int
        let constellationID: Int
        let security: Double
        /// 行星类型列名（temperate/barren/oceanic/ice/gas/lava/storm/plasma）→ 数量
        let planetCounts: [String: Int]
        /// 星系类型 typeID（如 POCO/未知星系），NULL 表示普通星系
        let systemType: Int?
        let x: Double
        let y: Double
        let z: Double
        let hasStation: Bool
        let hasJumpGate: Bool
        let isJSpace: Bool
    }

    /// PI 配方（planetSchematics 表）；输入物以原始逗号分隔字符串保存，按需解析
    struct PlanetSchematic {
        let id: Int
        let outputTypeID: Int
        let names: LocalizedText
        let cycleTime: Int
        let outputValue: Int
        let rawInputTypeIDs: String
        let rawInputValues: String

        /// 解析输入物品 (typeID, 数量) 对
        var inputs: [(typeID: Int, value: Int)] {
            let ids = rawInputTypeIDs.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            let values = rawInputValues.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            return zip(ids, values).map { (typeID: $0.0, value: $0.1) }
        }
    }

    /// LP 商店单条 offer 的产出（loyalty_offer_outputs 表）
    struct LPOfferOutput {
        let offerID: Int
        let typeID: Int
        let quantity: Int
        let iskCost: Int
        let lpCost: Int
        let akCost: Int
    }

    /// LP 商店单条兑换需求（loyalty_offer_requirements 表）
    struct LPOfferRequirement {
        let typeID: Int
        let quantity: Int
    }

    /// 物品技能要求（typeSkillRequirement 表核心列）
    struct SkillRequirement {
        let skillID: Int
        let level: Int
    }

    /// 再利用材料（typeMaterials 表核心列，名称/icon 运行时查 types）
    struct TypeMaterialEntry {
        let processSize: Int
        let outputMaterial: Int
        let outputQuantity: Int
    }

    // MARK: - 存储属性（extension 不能声明存储属性，统一集中在此）

    static var types: [Int: TypeInfo] = [:]
    static var categories: [Int: CategoryInfo] = [:]
    static var groups: [Int: GroupInfo] = [:]
    static var groupsByCategory: [Int: [GroupInfo]] = [:]
    static var metaGroupNames: [Int: LocalizedText] = [:]
    static var marketGroups: [Int: MarketGroupInfo] = [:]
    static var dogmaAttributes: [Int: DogmaAttributeInfo] = [:]
    /// attribute_key（name，语言无关）→ attributeID 索引
    static var dogmaAttributeIDsByName: [String: Int] = [:]
    static var regionNames: [Int: LocalizedText] = [:]
    static var solarSystemNames: [Int: LocalizedText] = [:]
    /// 星系 ID → 星域 ID 映射（从 universe 表加载）
    static var systemRegionIDs: [Int: Int] = [:]
    static var constellationNames: [Int: LocalizedText] = [:]
    static var factions: [Int: FactionInfo] = [:]
    static var divisionNames: [Int: LocalizedText] = [:]
    static var oreColors: [Int: String] = [:]
    static var originToCompressed: [Int: Int] = [:]
    static var compressedToOrigin: [Int: Int] = [:]
    static var npcCorporations: [Int: NPCCorporationInfo] = [:]
    static var stations: [Int: StationInfo] = [:]
    static var typeEffectIDs: [Int: [Int]] = [:]
    /// typeEffects 带默认标志：typeID → [(effectID, isDefault)]
    static var typeEffectEntries: [Int: [(effectID: Int, isDefault: Bool)]] = [:]
    /// dogmaEffects 效果定义：effectID → DogmaEffectInfo
    static var dogmaEffects: [Int: DogmaEffectInfo] = [:]
    /// 反向索引：parentTypeID → 子变体 typeID 列表（不含 parent 本身）
    static var variationsByParent: [Int: [Int]] = [:]
    /// 动态物品映射三个维度的索引 + resulting_type 去重集合
    static var dynamicMappingsByApplicable: [Int: [DynamicItemMapping]] = [:]
    static var dynamicMappingsByResulting: [Int: [DynamicItemMapping]] = [:]
    static var dynamicMappingsByTypeID: [Int: [DynamicItemMapping]] = [:]
    static var dynamicResultingTypeIDs: Set<Int> = []
    /// 突变质体属性范围：typeID(突变质体) → 原始属性行
    static var dynamicItemAttributesByType: [Int: [RawDynamicItemAttribute]] = [:]
    /// 舰载机能力：typeID → 按 slot 升序的能力列表
    static var fighterAbilities: [Int: [FighterAbilityInfo]] = [:]
    /// 指挥脉冲波 buff：buffID → WarfareBuffInfo（含中英显示名和正负判断）
    static var warfareBuffs: [Int: [Int: WarfareBuffInfo]] = [:]
    /// 专精认证技能要求（certificateSkills 表）：certificateID → 技能要求列表
    static var certificateSkills: [Int: [CertificateSkillRequirement]] = [:]
    /// 飞船专精认证（masteries 表）：typeid → [masteryLevel: 该等级要求全部达到的认证集合]
    static var shipMasteryCerts: [Int: [Int: Set<Int>]] = [:]
    /// 认证名称（certificates 表）
    static var certificateNames: [Int: LocalizedText] = [:]
    /// universe 星系摘要：systemID → 安等/星域/行星计数
    static var universeSystems: [Int: UniverseSystemInfo] = [:]
    /// PI 配方：schematicID → 配方
    static var planetSchematicsByID: [Int: PlanetSchematic] = [:]
    /// PI 配方索引：outputTypeID → 配方
    static var planetSchematicByOutput: [Int: PlanetSchematic] = [:]
    /// 行星资源采集（planetResourceHarvest）：资源 typeID → 采集器 typeID 列表
    static var planetResourceHarvests: [Int: [Int]] = [:]
    /// 蓝图制造产出：blueprintTypeID → (产品 typeID, 每流程数量)
    static var blueprintOutputs: [Int: (typeID: Int, quantity: Int)] = [:]
    /// 产品 → 蓝图反索引（制造+发明来源合并去重）
    static var blueprintIDsByProduct: [Int: [Int]] = [:]
    /// 蓝图制造所需技能：blueprintTypeID → 技能 typeID 列表（去重）
    static var blueprintSkills: [Int: [Int]] = [:]
    /// 蓝图制造材料：blueprintTypeID → [(材料 typeID, 数量)]
    static var blueprintMaterials: [Int: [(typeID: Int, quantity: Int)]] = [:]
    /// 蓝图制造基础时间：blueprintTypeID → manufacturing_time（秒）
    static var blueprintManufacturingTimes: [Int: Int] = [:]
    /// 建筑插件效果范围（facility_rig_effects）：插件 typeID → [(category, groupID)]（0 表示通配）
    static var facilityRigEffects: [Int: [(category: Int, groupID: Int)]] = [:]
    /// LP 商店 offer 索引：军团ID → offerID 列表
    static var loyaltyOffersByCorporation: [Int: [Int]] = [:]
    /// LP 商店产出：offerID → 输出
    static var loyaltyOfferOutputs: [Int: LPOfferOutput] = [:]
    /// LP 商店产出反索引：产出 typeID → offerID 列表
    static var loyaltyOfferOutputsByType: [Int: [Int]] = [:]
    /// LP 商店需求：offerID → 需求列表
    static var loyaltyOfferRequirements: [Int: [LPOfferRequirement]] = [:]
    /// typeAttributes 扁平存储：按 (type_id, attribute_id) 排序的平行数组（attribute_id 用 Int32 省内存）
    static var typeAttrIDs: [Int32] = []
    static var typeAttrValues: [Double] = []
    /// typeID → 平行数组中的行区间
    static var typeAttrRanges: [Int: Range<Int>] = [:]
    /// 物品技能要求（typeSkillRequirement 表）：typeID → 技能要求列表
    static var skillRequirements: [Int: [SkillRequirement]] = [:]
    /// 再利用材料（typeMaterials 表核心列）：typeID → 材料列表（名称/icon 运行时查 types）
    static var typeMaterialEntries: [Int: [TypeMaterialEntry]] = [:]
    /// 虫洞列表（load 时按当前语言解析）
    static var wormholeList: [WormholeInfo] = []
    /// 可模拟装配的飞船 typeID 集合（market group 4「Ships」子树，仅 show=true 分组）
    static var simulatableShipTypeIDs: Set<Int> = []

    /// 全量加载（各域 loader 见同目录 extension 文件）
    /// - Parameter progress: 内存索引逐表构建进度回调 (已完成数, 总数)，在后台线程触发
    static func loadAll(
        databaseManager: DatabaseManager,
        progress: ((Int, Int) -> Void)? = nil
    ) {
        // (项目名, 加载函数)；日志逐项输出名称、耗时与内存增量（phys_footprint 差值）
        let loaders: [(name: String, loader: (DatabaseManager) -> Void)] = [
            ("types", loadTypes),
            ("categories", loadCategories),
            ("groups", loadGroups),
            ("metaGroups", loadMetaGroups),
            ("dogmaAttributes", loadDogmaAttributes),
            ("marketGroups", loadMarketGroups),
            ("simulatableShips", loadSimulatableShips),
            ("regions", loadRegions),
            ("solarsystems", loadSolarSystems),
            ("universe", loadUniverseSystems),
            ("constellations", loadConstellations),
            ("factions", loadFactions),
            ("divisions", loadDivisions),
            ("oreColors", loadOreColors),
            ("compressibleTypes", loadCompressibleTypes),
            ("npcCorporations", loadNPCCorporations),
            ("stations", loadStations),
            ("typeEffects", loadTypeEffects),
            ("dogmaEffects", loadDogmaEffects),
            ("dynamicItemMappings", loadDynamicItemMappings),
            ("dynamicItemAttributes", loadDynamicItemAttributes),
            ("fighterAbilities", loadFighterAbilities),
            ("dbuffCollection", loadWarfareBuffs),
            ("masteries", loadMasteryData),
            ("planetSchematics", loadPlanetSchematics),
            ("planetResourceHarvest", loadPlanetResourceHarvest),
            ("blueprints", loadBlueprintData),
            ("loyaltyOffers", loadLoyaltyOffers),
            ("typeAttributes", loadTypeAttributes),
            ("typeSkillRequirement", loadSkillRequirements),
            ("typeMaterials", loadTypeMaterials),
            ("wormholes", loadWormholes),
            ("mapRegions", { _ in StarMapRegionAvailability.preload() }),
        ]

        let clock = ContinuousClock()
        for (index, entry) in loaders.enumerated() {
            let duration = clock.measure {
                entry.loader(databaseManager)
            }
            let ms = Self.durationMilliseconds(duration)
            Logger.info(
                "SDE 加载 [\(index + 1)/\(loaders.count)] \(entry.name) 完成，耗时 \(ms)ms"
            )
            progress?(index + 1, loaders.count)
        }

        Logger.info(
            "SDEMemoryStore 已加载 types=\(types.count) categories=\(categories.count) groups=\(groups.count) meta=\(metaGroupNames.count) market=\(marketGroups.count) dogma=\(dogmaAttributes.count) regions=\(regionNames.count) systems=\(solarSystemNames.count) constellations=\(constellationNames.count) factions=\(factions.count) divisions=\(divisionNames.count) ores=\(oreColors.count) compress=\(originToCompressed.count) npcCorps=\(npcCorporations.count) stations=\(stations.count) typeEffects=\(typeEffectIDs.count) dynMappings=\(dynamicResultingTypeIDs.count) dynItemAttrs=\(dynamicItemAttributesByType.count) fighterAbilities=\(fighterAbilities.count) warfareBuffs=\(warfareBuffs.count) certSkills=\(certificateSkills.count) shipMastery=\(shipMasteryCerts.count) typeAttrRows=\(typeAttrValues.count) skillReqs=\(skillRequirements.count) typeMaterials=\(typeMaterialEntries.count) wormholes=\(wormholeList.count) dogmaEffects=\(dogmaEffects.count)"
        )
    }

    /// Duration → 毫秒（保留 1 位小数）
    private static func durationMilliseconds(_ duration: Duration) -> String {
        let (seconds, attoseconds) = duration.components
        let ms = Double(seconds) * 1000 + Double(attoseconds) / 1_000_000_000_000_000
        return String(format: "%.1f", ms)
    }
}
