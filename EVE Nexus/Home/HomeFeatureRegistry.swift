import Foundation
import SwiftUI

/// 首页侧栏功能 ID（rawValue 与历史 selection / 置顶隐藏存储兼容）
enum FeatureID: String, CaseIterable, Hashable, Identifiable {
    case characterSheet = "character_sheet"
    case characterClones = "character_clones"
    case characterSkills = "character_skills"
    case characterMail = "character_mail"
    case calendar
    case characterWealth = "character_wealth"
    case characterLP = "character_lp"
    case searcher
    case characterMastery = "character_mastery"

    case corporationWallet = "corporation_wallet"
    case corporationMembers = "corporation_members"
    case corporationMoon = "corporation_moon"
    case corporationStructures = "corporation_structures"
    case corporationStarbases = "corporation_starbases"
    case corporationIndustry = "corporation_industry"
    case corporationAssets = "corporation_assets"
    case corporationIssuedContracts = "corporation_issued_contracts"

    case database
    case market
    case vipMarketItem = "vip_market_item"
    case attributeCompare = "attribute_compare"
    case npc
    case npcFaction = "npc_faction"
    case agents
    case starMap = "star_map"
    case wormhole
    case incursions
    case factionWar = "faction_war"
    case sovereignty
    case languageMap = "language_map"
    case jumpNavigation = "jump_navigation"
    case calculator

    case assets
    case marketOrders = "market_orders"
    case contracts
    case marketTransactions = "market_transactions"
    case walletJournal = "wallet_journal"
    case industryJobs = "industry_jobs"
    case miningLedger = "mining_ledger"
    case planetary
    case structureMarket = "structure_market"

    case killboard
    case fitting

    case settings
    case updateHistory = "update_history"
    case inAppPurchase = "in_app_purchase"
    case about

    var id: String {
        rawValue
    }
}

enum FeatureSection: String, CaseIterable {
    case character
    case corporation
    case database
    case business
    case battle
    case fitting
    case other

    var title: String {
        switch self {
        case .character: return NSLocalizedString("Main_Character", comment: "")
        case .corporation: return NSLocalizedString("Main_Corporation", comment: "")
        case .database: return NSLocalizedString("Main_Databases", comment: "")
        case .business: return NSLocalizedString("Main_Business", comment: "")
        case .battle: return NSLocalizedString("Main_Battle", comment: "")
        case .fitting: return NSLocalizedString("Main_Fitting", comment: "")
        case .other: return NSLocalizedString("Main_Other", comment: "")
        }
    }
}

enum FeatureNoteKind {
    case none
    case skillPoints
    case walletBalance
    case cloneCooldown
    case skillQueue
    case killMailDataSource
    case sdeUpdateHint
}

enum FeaturePlatform {
    case all
    case iOSDeviceOnly // 隐藏 macOS / Catalyst
}

struct FeatureDescriptor: Identifiable {
    let id: FeatureID
    let section: FeatureSection
    let requiresLogin: Bool
    let icon: String
    var noteKind: FeatureNoteKind = .none
    var platform: FeaturePlatform = .all

    /// 字面量 key，供 String Catalog 静态提取
    var title: String {
        switch id {
        case .characterSheet: return NSLocalizedString("Main_Character_Sheet", comment: "")
        case .characterClones: return NSLocalizedString("Main_Jump_Clones", comment: "")
        case .characterSkills: return NSLocalizedString("Main_Skills", comment: "")
        case .characterMail: return NSLocalizedString("Main_EVE_Mail", comment: "")
        case .calendar: return NSLocalizedString("Main_Calendar", comment: "")
        case .characterWealth: return NSLocalizedString("Main_Wealth", comment: "")
        case .characterLP: return NSLocalizedString("Main_Loyalty_Points", comment: "")
        case .searcher: return NSLocalizedString("Main_Contact_Search", comment: "")
        case .characterMastery: return NSLocalizedString("Main_Mastery", comment: "专精")
        case .corporationWallet: return NSLocalizedString("Main_Corporation_wallet", comment: "")
        case .corporationMembers: return NSLocalizedString("Main_Corporation_Members", comment: "")
        case .corporationMoon: return NSLocalizedString("Main_Corporation_Moon_Mining", comment: "")
        case .corporationStructures: return NSLocalizedString("Main_Corporation_Structures", comment: "")
        case .corporationStarbases: return NSLocalizedString("Main_Corporation_Starbases", comment: "")
        case .corporationIndustry: return NSLocalizedString("Main_Corporation_Industry", comment: "")
        case .corporationAssets: return NSLocalizedString("Main_Corporation_Assets", comment: "")
        case .corporationIssuedContracts: return NSLocalizedString("Main_Corporation_Issued_Contracts", comment: "")
        case .database: return NSLocalizedString("Main_Database", comment: "")
        case .market: return NSLocalizedString("Main_Market", comment: "")
        case .vipMarketItem: return NSLocalizedString("Main_Market_Watch_List", comment: "")
        case .attributeCompare: return NSLocalizedString("Main_Attribute_Compare", comment: "")
        case .npc: return NSLocalizedString("Main_NPC_entity", comment: "")
        case .npcFaction: return NSLocalizedString("Main_NPC_Faction", comment: "")
        case .agents: return NSLocalizedString("Main_Agents", comment: "")
        case .starMap: return NSLocalizedString("Main_Star_Map", comment: "")
        case .wormhole: return NSLocalizedString("Main_WH", comment: "")
        case .incursions: return NSLocalizedString("Main_Incursions", comment: "")
        case .factionWar: return NSLocalizedString("Main_Section_Frontlines", comment: "")
        case .sovereignty: return NSLocalizedString("Main_Sovereignty", comment: "")
        case .languageMap: return NSLocalizedString("Main_Language_Map", comment: "")
        case .jumpNavigation: return NSLocalizedString("Main_Jump_Navigation", comment: "")
        case .calculator: return NSLocalizedString("Calculator_Title", comment: "")
        case .assets: return NSLocalizedString("Main_Assets", comment: "")
        case .marketOrders: return NSLocalizedString("Main_Market_Orders", comment: "")
        case .contracts: return NSLocalizedString("Main_Contracts", comment: "")
        case .marketTransactions: return NSLocalizedString("Main_Market_Transactions", comment: "")
        case .walletJournal: return NSLocalizedString("Main_Wallet_Journal", comment: "")
        case .industryJobs: return NSLocalizedString("Main_Industry_Jobs", comment: "")
        case .miningLedger: return NSLocalizedString("Main_Mining_Ledger", comment: "")
        case .planetary: return NSLocalizedString("Main_Planetary", comment: "")
        case .structureMarket: return NSLocalizedString("Main_Structure_Market", comment: "")
        case .killboard: return NSLocalizedString("Main_Killboard", comment: "")
        case .fitting: return NSLocalizedString("Main_Fitting_Simulation", comment: "")
        case .settings: return NSLocalizedString("Main_Setting", comment: "")
        case .updateHistory: return NSLocalizedString("Main_Update_History", comment: "")
        case .inAppPurchase: return NSLocalizedString("Main_In_App_Purchase", comment: "")
        case .about: return NSLocalizedString("Main_About", comment: "")
        }
    }

    var participatesInHiding: Bool {
        section != .other
    }

    var showSelectionCircle: Bool {
        section != .other
    }

    var isAvailableOnCurrentPlatform: Bool {
        switch platform {
        case .all: return true
        case .iOSDeviceOnly: return !ProcessInfo.processInfo.isiOSAppOnMac
        }
    }
}

enum FeatureRegistry {
    static let all: [FeatureDescriptor] = [
        .init(id: .characterSheet, section: .character, requiresLogin: true, icon: "charactersheet", noteKind: .skillPoints),
        .init(id: .characterClones, section: .character, requiresLogin: true, icon: "jumpclones", noteKind: .cloneCooldown),
        .init(id: .characterSkills, section: .character, requiresLogin: true, icon: "skills", noteKind: .skillQueue),
        .init(id: .characterMail, section: .character, requiresLogin: true, icon: "evemail"),
        .init(id: .calendar, section: .character, requiresLogin: true, icon: "calendar"),
        .init(id: .characterWealth, section: .character, requiresLogin: true, icon: "Folder", noteKind: .walletBalance),
        .init(id: .characterLP, section: .character, requiresLogin: true, icon: "lpstore"),
        .init(id: .searcher, section: .character, requiresLogin: true, icon: "peopleandplaces"),
        .init(id: .characterMastery, section: .character, requiresLogin: true, icon: "certificates"),

        .init(id: .corporationWallet, section: .corporation, requiresLogin: true, icon: "wallet"),
        .init(id: .corporationMembers, section: .corporation, requiresLogin: true, icon: "corporation"),
        .init(id: .corporationMoon, section: .corporation, requiresLogin: true, icon: "satellite"),
        .init(id: .corporationStructures, section: .corporation, requiresLogin: true, icon: "Structurebrowser"),
        .init(id: .corporationStarbases, section: .corporation, requiresLogin: true, icon: "Structurebrowser"),
        .init(id: .corporationIndustry, section: .corporation, requiresLogin: true, icon: "industry"),
        .init(id: .corporationAssets, section: .corporation, requiresLogin: true, icon: "assets"),
        .init(id: .corporationIssuedContracts, section: .corporation, requiresLogin: true, icon: "contracts"),

        .init(id: .database, section: .database, requiresLogin: false, icon: "items"),
        .init(id: .market, section: .database, requiresLogin: false, icon: "market"),
        .init(id: .vipMarketItem, section: .database, requiresLogin: false, icon: "searchmarket"),
        .init(id: .attributeCompare, section: .database, requiresLogin: false, icon: "comparetool"),
        .init(id: .npc, section: .database, requiresLogin: false, icon: "criminal"),
        .init(id: .npcFaction, section: .database, requiresLogin: false, icon: "concord"),
        .init(id: .agents, section: .database, requiresLogin: false, icon: "agentfinder"),
        .init(id: .starMap, section: .database, requiresLogin: false, icon: "map"),
        .init(id: .wormhole, section: .database, requiresLogin: false, icon: "terminate"),
        .init(id: .incursions, section: .database, requiresLogin: false, icon: "incursions"),
        .init(id: .factionWar, section: .database, requiresLogin: false, icon: "factionalwarfare"),
        .init(id: .sovereignty, section: .database, requiresLogin: false, icon: "sovereignty"),
        .init(id: .languageMap, section: .database, requiresLogin: false, icon: "browser"),
        .init(id: .jumpNavigation, section: .database, requiresLogin: false, icon: "capitalnavigation"),
        .init(id: .calculator, section: .database, requiresLogin: false, icon: "calculator"),

        .init(id: .assets, section: .business, requiresLogin: true, icon: "assets"),
        .init(id: .marketOrders, section: .business, requiresLogin: true, icon: "marketdeliveries"),
        .init(id: .contracts, section: .business, requiresLogin: true, icon: "contracts"),
        .init(id: .marketTransactions, section: .business, requiresLogin: true, icon: "journal"),
        .init(id: .walletJournal, section: .business, requiresLogin: true, icon: "wallet"),
        .init(id: .industryJobs, section: .business, requiresLogin: true, icon: "industry"),
        .init(id: .miningLedger, section: .business, requiresLogin: true, icon: "miningledger"),
        .init(id: .planetary, section: .business, requiresLogin: true, icon: "planets"),
        .init(id: .structureMarket, section: .business, requiresLogin: true, icon: "Structurebrowser"),

        .init(id: .killboard, section: .battle, requiresLogin: true, icon: "killreport", noteKind: .killMailDataSource),
        .init(id: .fitting, section: .fitting, requiresLogin: false, icon: "fitting"),

        .init(id: .settings, section: .other, requiresLogin: false, icon: "Settings"),
        .init(id: .updateHistory, section: .other, requiresLogin: false, icon: "log"),
        .init(id: .inAppPurchase, section: .other, requiresLogin: false, icon: "tipoftheday", platform: .iOSDeviceOnly),
        .init(id: .about, section: .other, requiresLogin: false, icon: "info", noteKind: .sdeUpdateHint),
    ]

    private static let byID: [FeatureID: FeatureDescriptor] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func descriptor(forRaw raw: String) -> FeatureDescriptor? {
        FeatureID(rawValue: raw).flatMap { byID[$0] }
    }

    static func features(in section: FeatureSection) -> [FeatureDescriptor] {
        all.filter { $0.section == section }
    }

    static func index(ofRaw raw: String) -> Int {
        all.firstIndex(where: { $0.id.rawValue == raw }) ?? Int.max
    }
}
