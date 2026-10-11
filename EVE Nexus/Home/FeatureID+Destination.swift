import SwiftUI

extension FeatureID {
    /// 详情页唯一装配入口
    @MainActor
    @ViewBuilder
    func destination(
        databaseManager: DatabaseManager,
        viewModel: MainViewModel,
        currentCharacterId: Int
    ) -> some View {
        switch self {
        case .characterSheet:
            if let character = viewModel.selectedCharacter {
                CharacterSheetView(
                    character: character,
                    characterPortrait: viewModel.characterPortrait
                )
            }
        case .characterClones:
            if let character = viewModel.selectedCharacter {
                CharacterClonesView(character: character)
            }
        case .characterSkills:
            if let character = viewModel.selectedCharacter {
                CharacterSkillsView(
                    characterId: character.CharacterID,
                    databaseManager: databaseManager
                )
            }
        case .characterMail:
            if let character = viewModel.selectedCharacter {
                CharacterMailView(characterId: character.CharacterID)
            }
        case .calendar:
            if let character = viewModel.selectedCharacter {
                CharacterCalendarView(
                    characterId: character.CharacterID,
                    databaseManager: databaseManager
                )
            }
        case .characterWealth:
            if let character = viewModel.selectedCharacter {
                CharacterWealthView(characterId: character.CharacterID)
            }
        case .characterLP:
            if let character = viewModel.selectedCharacter {
                CharacterLoyaltyPointsView(characterId: character.CharacterID)
            }
        case .searcher:
            if let character = viewModel.selectedCharacter {
                SearcherView(character: character)
            }
        case .characterMastery:
            ShipMasteryBrowserView(databaseManager: databaseManager)
        case .database:
            DatabaseBrowserView(databaseManager: databaseManager, level: .categories, showFittingButton: true)
        case .market:
            MarketBrowserView(databaseManager: databaseManager)
        case .vipMarketItem:
            MarketQuickbarView(databaseManager: databaseManager)
        case .attributeCompare:
            AttributeCompareView(databaseManager: databaseManager)
        case .npc:
            NPCBrowserView(databaseManager: databaseManager)
        case .npcFaction:
            FactionBrowserView(
                databaseManager: databaseManager,
                characterId: currentCharacterId == 0 ? nil : currentCharacterId
            )
        case .agents:
            AgentSearchView(databaseManager: databaseManager)
        case .wormhole:
            WormholeView(databaseManager: databaseManager)
        case .incursions:
            IncursionsView(databaseManager: databaseManager)
        case .factionWar:
            FactionWarView(databaseManager: databaseManager)
        case .sovereignty:
            SovereigntyView(databaseManager: databaseManager)
        case .languageMap:
            LanguageMapView()
        case .assets:
            if let character = viewModel.selectedCharacter {
                CharacterAssetsView(characterId: character.CharacterID)
            }
        case .marketOrders:
            if let character = viewModel.selectedCharacter {
                CharacterOrdersView(characterId: Int64(character.CharacterID))
            }
        case .contracts:
            if let character = viewModel.selectedCharacter {
                PersonalContractsView(character: character)
            }
        case .marketTransactions:
            if let character = viewModel.selectedCharacter {
                WalletTransactionsView(
                    characterId: character.CharacterID,
                    databaseManager: databaseManager
                )
            }
        case .walletJournal:
            if let character = viewModel.selectedCharacter {
                WalletJournalView(characterId: character.CharacterID)
            }
        case .industryJobs:
            if let character = viewModel.selectedCharacter {
                CharacterIndustryView(characterId: character.CharacterID)
            }
        case .miningLedger:
            if let character = viewModel.selectedCharacter {
                MiningLedgerView(
                    characterId: character.CharacterID,
                    databaseManager: databaseManager
                )
            }
        case .planetary:
            CharacterPlanetaryView(characterId: viewModel.selectedCharacter?.CharacterID)
        case .structureMarket:
            StructureMarketView()
        case .corporationWallet:
            if let character = viewModel.selectedCharacter {
                CorpWalletView(characterId: character.CharacterID)
            }
        case .corporationMoon:
            if let character = viewModel.selectedCharacter {
                CorpMoonMiningView(characterId: character.CharacterID)
            }
        case .corporationStructures:
            if let character = viewModel.selectedCharacter {
                CorpStructureView(characterId: character.CharacterID)
            }
        case .corporationStarbases:
            if let character = viewModel.selectedCharacter {
                CorpStarbaseView(characterId: character.CharacterID)
            }
        case .killboard:
            if let character = viewModel.selectedCharacter {
                BRKillMailView(characterId: character.CharacterID)
            }
        case .corporationMembers:
            if let character = viewModel.selectedCharacter {
                CorpMemberListView(characterId: character.CharacterID)
            }
        case .corporationIndustry:
            if let character = viewModel.selectedCharacter {
                CorpIndustryView(characterId: character.CharacterID)
            }
        case .corporationAssets:
            if let character = viewModel.selectedCharacter {
                CorporationAssetsViewWrapper(characterId: character.CharacterID)
            }
        case .corporationIssuedContracts:
            if let character = viewModel.selectedCharacter {
                CorporationIssuedContractsView(character: character)
            }
        case .jumpNavigation:
            JumpNavigationView(databaseManager: databaseManager)
        case .calculator:
            CalculatorView()
        case .starMap:
            RegionMapView(databaseManager: databaseManager)
        case .fitting:
            FittingMainView(
                characterId: viewModel.selectedCharacter?.CharacterID,
                databaseManager: databaseManager
            )
        case .settings:
            SettingView(databaseManager: databaseManager)
        case .inAppPurchase:
            InAppPurchaseView()
        case .about:
            AboutView()
        case .updateHistory:
            UpdateLogListView()
        }
    }
}
