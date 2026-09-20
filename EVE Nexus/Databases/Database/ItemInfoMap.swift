import SwiftUI

/// 共享的技能数据管理器
@MainActor
class SharedSkillsManager: ObservableObject {
    static let shared = SharedSkillsManager()

    @Published var characterSkills: [Int: Int] = [:]
    @Published var skillQueue: [SkillQueueItem] = []
    @Published var isLoading = false
    /// 认证满足矩阵：certificateID → 最高达标等级（0-5）
    /// 技能加载成功后立即计算，与 characterSkills 同生命周期加载/失效
    @Published var masteryCertLevels: [Int: Int] = [:]

    /// 跟踪当前加载的角色 ID，用于检测角色切换
    private var loadedCharacterId: Int = 0

    private var currentCharacterId: Int {
        UserDefaults.standard.integer(forKey: "currentCharacterId")
    }

    private init() {}

    /// 预加载技能数据
    func preloadSkills() {
        guard currentCharacterId != 0 else {
            characterSkills = [:]
            skillQueue = []
            masteryCertLevels = [:]
            loadedCharacterId = 0
            isLoading = false
            return
        }

        if loadedCharacterId != currentCharacterId {
            Logger.debug("检测到角色切换: \(loadedCharacterId) -> \(currentCharacterId)")
            characterSkills = [:]
            skillQueue = []
            masteryCertLevels = [:]
            loadedCharacterId = 0
            isLoading = false
        }

        if !characterSkills.isEmpty, !isLoading, loadedCharacterId == currentCharacterId {
            return
        }

        if isLoading {
            return
        }

        isLoading = true
        Logger.debug("SharedSkillsManager开始预加载技能数据 - 角色ID: \(currentCharacterId)")

        Task {
            do {
                let (skillsResponse, queue) = try await CharacterSkillsAPI.shared
                    .fetchCharacterSkillsAndQueue(
                        characterId: currentCharacterId,
                        forceRefresh: false
                    )

                let baseSkills = Dictionary(
                    uniqueKeysWithValues: skillsResponse.skillsMap.map {
                        ($0.key, $0.value.trained_skill_level)
                    }
                )
                let skillsDict = CharacterSkillsUtils.mergeCompletedQueueIntoSkills(
                    baseSkills: baseSkills,
                    queue: queue
                )

                await MainActor.run {
                    self.characterSkills = skillsDict
                    self.masteryCertLevels = MasteryEvaluator.certificateLevels(
                        characterSkills: skillsDict
                    )
                    self.skillQueue = queue
                    self.loadedCharacterId = currentCharacterId
                    self.isLoading = false
                    Logger.debug(
                        "SharedSkillsManager技能数据预加载完成 - 角色ID: \(currentCharacterId), 技能数量: \(skillsDict.count), 队列长度: \(queue.count)"
                    )
                }
            } catch {
                Logger.error("SharedSkillsManager预加载技能数据失败: \(error)")
                await MainActor.run {
                    self.characterSkills = [:]
                    self.skillQueue = []
                    self.masteryCertLevels = [:]
                    self.loadedCharacterId = 0
                    self.isLoading = false
                }
            }
        }
    }

    /// - Returns: nil 正在加载，-1 未拥有，-2 无角色登录
    func getSkillLevel(for skillID: Int) -> Int? {
        if currentCharacterId == 0 {
            return -2
        }
        if isLoading {
            return nil
        }
        return characterSkills[skillID] ?? -1
    }

    /// 拉取角色属性（无角色或失败返回 nil），供技能要求/专精等视图共用
    func fetchAttributes(characterId: Int) async -> CharacterAttributes? {
        guard characterId != 0 else { return nil }
        do {
            return try await CharacterSkillsAPI.shared.fetchAttributes(
                characterId: characterId,
                forceRefresh: false
            )
        } catch {
            Logger.error("获取角色属性失败: \(error)")
            return nil
        }
    }

    /// 拉取角色属性并异步回写到视图的 @State（技能要求/专精等视图的 onAppear 共用）
    func loadAttributes(characterId: Int, into attributes: Binding<CharacterAttributes?>) {
        Task { @MainActor in
            attributes.wrappedValue = await fetchAttributes(characterId: characterId)
        }
    }

    /// 获取某技能正在训练到的目标等级（仅当前正在训练的项，不含队列中排队的后续项）
    /// - Returns: nil=未在训练；否则返回正在训练到的等级（1-5）
    func getTrainingTargetLevel(for skillID: Int) -> Int? {
        guard currentCharacterId != 0, !isLoading else { return nil }
        return skillQueue.first(where: { $0.skill_id == skillID && $0.isCurrentlyTraining })?.finished_level
    }

    /// 清除技能数据（角色切换或登出时调用）
    func clearSkillData() {
        Logger.debug("SharedSkillsManager清除技能数据")
        characterSkills = [:]
        skillQueue = []
        masteryCertLevels = [:]
        loadedCharacterId = 0
        isLoading = false
    }
}

enum ItemInfoMap {
    typealias TypeDisplayInfo = SDEMemoryStore.TypeInfo

    /// 在打开数据库 / 切换语言时调用；重建 SDE 内存索引
    static func initializeCache(
        databaseManager: DatabaseManager,
        progress: ((Int, Int) -> Void)? = nil
    ) {
        SDEMemoryStore.loadAll(databaseManager: databaseManager, progress: progress)
    }

    static func typeInfo(for typeID: Int) -> TypeDisplayInfo? {
        SDEMemoryStore.type(for: typeID)
    }

    static func typeName(for typeID: Int) -> String? {
        let name = SDEMemoryStore.type(for: typeID)?.name
        return (name?.isEmpty == false) ? name : nil
    }

    static func iconFilename(for typeID: Int) -> String {
        SDEMemoryStore.type(for: typeID)?.iconFilename ?? IconManager.defaultItemIcon
    }

    static func getItemInfoView(
        itemID: Int,
        databaseManager: DatabaseManager,
        modifiedAttributes: [Int: Double]? = nil
    ) -> AnyView {
        guard let itemCategory = SDEMemoryStore.type(for: itemID) else {
            Logger.error("ItemInfoMap - 无法获取物品分类信息，itemID: \(itemID)")
            return AnyView(Text(NSLocalizedString("Item_load_error", comment: "")))
        }

        let categoryID = itemCategory.categoryID
        let groupID = itemCategory.groupID

        if categoryID == 17 && groupID == 1964 {
            return AnyView(ShowMutationInfo(itemID: itemID, databaseManager: databaseManager))
        }

        switch categoryID {
        case 9, 34:
            return AnyView(ShowBluePrintInfo(blueprintID: itemID, databaseManager: databaseManager))
        case 42, 43:
            return AnyView(ShowPlanetaryInfo(itemID: itemID, databaseManager: databaseManager))
        default:
            return AnyView(
                ShowItemInfo(
                    databaseManager: databaseManager,
                    itemID: itemID,
                    modifiedAttributes: modifiedAttributes
                )
            )
        }
    }
}
