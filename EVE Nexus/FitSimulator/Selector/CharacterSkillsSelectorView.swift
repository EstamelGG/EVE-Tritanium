import Foundation
import SwiftUI

/// 角色技能工具类
enum CharacterSkillsType: Equatable {
    case current_char // 当前角色的实际技能等级
    case all5 // 所有技能全部5级
    case all4 // 所有技能全部4级
    case all3 // 所有技能全部3级
    case all2 // 所有技能全部2级
    case all1 // 所有技能全部1级
    case all0 // 所有技能全部0级
    case character(Int) // 指定角色的技能等级

    /// 实现Equatable协议的唯一方法
    static func == (lhs: CharacterSkillsType, rhs: CharacterSkillsType) -> Bool {
        switch (lhs, rhs) {
        case (.current_char, .current_char):
            return true
        case (.all5, .all5):
            return true
        case (.all4, .all4):
            return true
        case (.all3, .all3):
            return true
        case (.all2, .all2):
            return true
        case (.all1, .all1):
            return true
        case (.all0, .all0):
            return true
        case let (.character(id1), .character(id2)):
            return id1 == id2
        default:
            return false
        }
    }
}

enum CharacterSkillsUtils {
    /// 获取指定类型的角色技能等级
    /// - Parameter type: 技能类型（当前角色或全5级）
    /// - Returns: 技能ID与等级的字典 [技能ID: 等级]
    static func getCharacterSkills(type: CharacterSkillsType) -> [Int: Int] {
        switch type {
        case .current_char:
            return getCurrentCharacterSkills()
        case .all5:
            return getAllSkillsWithLevel(5)
        case .all4:
            return getAllSkillsWithLevel(4)
        case .all3:
            return getAllSkillsWithLevel(3)
        case .all2:
            return getAllSkillsWithLevel(2)
        case .all1:
            return getAllSkillsWithLevel(1)
        case .all0:
            return getAllSkillsWithLevel(0)
        case let .character(characterId):
            return getCharacterSkills(characterId: characterId)
        }
    }

    /// 获取当前角色的技能等级
    /// - Returns: 技能ID与等级的字典
    private static func getCurrentCharacterSkills() -> [Int: Int] {
        // 获取当前角色ID
        let currentCharacterId = UserDefaults.standard.integer(forKey: "currentCharacterId")
        if currentCharacterId == 0 {
            Logger.info("未选择人物，默认使用 all5")
            return getAllSkillsWithLevel(5)
        }

        return getCharacterSkills(characterId: currentCharacterId)
    }

    /// 将技能队列合并到技能等级字典
    ///     // - **已完成**（`finish_date <= now`）：视为该 `finished_level` 已达成，可弥补 ESI `/characters/.../skills` 的延迟。
    /// - **未完成**（等待中或正在训练）：仅对该技能在队列中的**第一条**未完成项使用 `max(0, finished_level - 1)`，
    ///   表示「下一档要练到的等级」所隐含的至少已具备等级；**不会**对后续排队项再累加，
    ///   避免出现「已训 1、队列排着 2/3/4」却被算成 3 级的情况。
    static func mergeCompletedQueueIntoSkills(
        baseSkills: [Int: Int],
        queue: [SkillQueueItem]
    ) -> [Int: Int] {
        var result = baseSkills
        let now = Date()
        let sorted = queue.sorted { $0.queue_position < $1.queue_position }
        // 每个技能仅对第一条「未完成」队列项应用 targetLevel-1 启发式
        var appliedFirstIncompleteHeuristic: Set<Int> = []

        for item in sorted {
            let skillId = item.skill_id
            let current = result[skillId] ?? 0
            let targetLevel = item.finished_level

            if let finishDate = item.finish_date, finishDate <= now {
                // 队列项已完成：目标等级已写入（可覆盖 ESI 延迟）
                if targetLevel > current {
                    result[skillId] = targetLevel
                }
                continue
            }

            // 未完成：只处理该技能的第一条未完成项
            if !appliedFirstIncompleteHeuristic.contains(skillId) {
                appliedFirstIncompleteHeuristic.insert(skillId)
                let minLevel = max(0, targetLevel - 1)
                if minLevel > current {
                    result[skillId] = minLevel
                }
            }
        }

        return result
    }

    /// 获取指定角色的技能等级（含队列中已完成的合并）
    /// 优先使用本地缓存（无网络、无阻塞），缓存缺失时回退 all5 并后台异步更新缓存
    /// - Parameter characterId: 角色ID
    /// - Returns: 技能ID与等级的字典
    private static func getCharacterSkills(characterId: Int) -> [Int: Int] {
        // 1. 优先同步读取技能和队列缓存（一次调用获取合并所需数据）
        if let cached = CharacterSkillsAPI.shared.loadSkillsAndQueueFromCacheIfAvailable(characterId: characterId) {
            let baseSkills = Dictionary(uniqueKeysWithValues: cached.skills.skillsMap.map { ($0.key, $0.value.trained_skill_level) })
            return mergeCompletedQueueIntoSkills(baseSkills: baseSkills, queue: cached.queue)
        }

        // 2. 缓存缺失：使用 all5 作为即时回退，避免主线程阻塞
        Logger.info("技能缓存不可用 (角色ID: \(characterId))，使用 all5 作为即时回退，后台异步更新缓存")

        // 3. 后台异步更新缓存，供下次使用
        Task {
            do {
                _ = try await CharacterSkillsAPI.shared.fetchCharacterSkills(
                    characterId: characterId,
                    forceRefresh: true
                )
                Logger.debug("后台技能缓存更新完成 - 角色ID: \(characterId)")
            } catch {
                Logger.error("后台技能缓存更新失败: \(error)")
            }
        }

        return getAllSkillsWithLevel(5)
    }

    /// 获取所有技能并设置为指定等级
    /// - Parameter level: 要设置的技能等级
    /// - Returns: 技能ID与等级的字典
    private static func getAllSkillsWithLevel(_ level: Int) -> [Int: Int] {
        // 内存索引获取所有已发布的技能（categoryID = 16 代表技能分类）
        var skillsDict = [Int: Int]()
        for (typeId, info) in SDEMemoryStore.types where info.categoryID == 16 && info.published {
            skillsDict[typeId] = level // 所有技能都设为指定等级
        }
        return skillsDict
    }

    /// 获取所有登录的角色信息
    /// - Parameter excludeCurrentCharacter: 是否排除当前登录角色，默认为false
    /// - Returns: 角色信息数组
    static func getAllCharacters(excludeCurrentCharacter: Bool = false) -> [(id: Int, name: String)] {
        // 使用EVELogin获取所有已登录角色
        let characterAuths = EVELogin.shared.loadCharacters()
        let currentCharacterId = UserDefaults.standard.integer(forKey: "currentCharacterId")

        var characters: [(id: Int, name: String)] = []
        for auth in characterAuths {
            // 如果需要排除当前角色，并且当前角色ID与该角色匹配，则跳过
            if excludeCurrentCharacter, auth.character.CharacterID == currentCharacterId {
                continue
            }
            characters.append((id: auth.character.CharacterID, name: auth.character.CharacterName))
        }

        return characters
    }
}

/// 角色选择和技能获取视图。
/// 该视图展示所有可用角色，并在选择后返回对应角色的技能列表。
struct CharacterSkillsSelectorView: View {
    /// 数据库管理器
    let databaseManager: DatabaseManager

    var selectedSkillsMode: String? = nil
    var selectedCharacterId: Int? = nil

    /// 回调函数，用于返回所选角色的技能列表
    var onSelectSkills: ([Int: Int], String, Int) -> Void

    /// 环境变量
    @Environment(\.dismiss) private var dismiss

    // 状态变量
    @State private var characters: [(id: Int, name: String)] = []
    @State private var loadingCharacterId: Int? = nil
    @State private var currentCharacterId: Int = UserDefaults.standard.integer(
        forKey: "currentCharacterId"
    )
    @State private var currentCharacterName: String = ""

    var body: some View {
        List {
            // 显示角色列表（当前角色 + 其他角色）
            Section(header: Text(NSLocalizedString("Fitting_All_Characters", comment: "所有角色"))) {
                // 当前登录角色（如果有）
                if currentCharacterId != 0 {
                    Button {
                        // 开始加载当前角色的技能
                        loadCharacterSkills(
                            characterId: currentCharacterId,
                            characterName: currentCharacterName.isEmpty
                                ? NSLocalizedString("Fitting_Current_Character", comment: "当前角色")
                                : currentCharacterName
                        )
                    } label: {
                        CharacterSelectionRow(
                            characterId: currentCharacterId,
                            characterName: currentCharacterName.isEmpty
                                ? NSLocalizedString("Fitting_Current_Character", comment: "当前角色")
                                : currentCharacterName,
                            isSelected: selectedSkillsMode == "current_char"
                                || (selectedSkillsMode == "character" && selectedCharacterId == currentCharacterId),
                            isLoading: loadingCharacterId == currentCharacterId
                        )
                    }
                    .foregroundColor(.primary)
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    .disabled(loadingCharacterId != nil)
                }

                // 其他角色列表
                if !characters.isEmpty {
                    ForEach(characters, id: \.id) { character in
                        Button {
                            // 加载所选角色的技能
                            loadCharacterSkills(
                                characterId: character.id, characterName: character.name
                            )
                        } label: {
                            CharacterSelectionRow(
                                characterId: character.id,
                                characterName: character.name,
                                isSelected: selectedSkillsMode == "character" && selectedCharacterId == character.id,
                                isLoading: loadingCharacterId == character.id
                            )
                        }
                        .foregroundColor(.primary)
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                        .disabled(loadingCharacterId != nil)
                    }
                }

                // 无角色情况显示提示
                if currentCharacterId == 0 && characters.isEmpty {
                    Text(NSLocalizedString("Fitting_No_Characters", comment: "没有可选角色"))
                        .foregroundColor(.secondary)
                        .font(.caption)
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }

            // 虚拟技能角色（All 5/4/3/2/1/0）
            Section(header: Text(NSLocalizedString("Fitting_Virtual_Characters", comment: "虚拟角色"))) {
                // 使用循环创建所有技能等级选项
                ForEach((0 ... 5).reversed(), id: \.self) { level in
                    Button {
                        // 获取对应技能等级的虚拟数据
                        let skillType: CharacterSkillsType = {
                            switch level {
                            case 5: return .all5
                            case 4: return .all4
                            case 3: return .all3
                            case 2: return .all2
                            case 1: return .all1
                            case 0: return .all0
                            default: return .all0
                            }
                        }()

                        let skills = CharacterSkillsUtils.getCharacterSkills(type: skillType)

                        // 新手角色特殊处理
                        let localizedText = String(
                            format: NSLocalizedString("Fitting_All_Skills", comment: "全n级"), level
                        )

                        onSelectSkills(skills, localizedText, 0)
                        dismiss()
                    } label: {
                        HStack {
                            Image("skill_lv_\(level)")
                                .resizable()
                                .frame(width: 32, height: 32)
                                .cornerRadius(6)

                            // 新手角色特殊处理
                            Text(
                                String(
                                    format: NSLocalizedString("Fitting_All_Skills", comment: "全n级"),
                                    level
                                )
                            )
                            .font(.body)

                            Spacer()

                            if selectedSkillsMode == "all\(level)"
                                || (selectedSkillsMode == "current_char" && currentCharacterId == 0 && level == 5)
                            {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .foregroundColor(.primary)
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    .disabled(loadingCharacterId != nil)
                }
            }
        }
        .navigationTitle(NSLocalizedString("Fitting_Select_Character", comment: "选择角色"))
        .onAppear {
            // 加载所有可用角色
            characters = CharacterSkillsUtils.getAllCharacters(excludeCurrentCharacter: true)

            // 获取当前角色名称
            if currentCharacterId != 0 {
                // 使用EVELogin获取当前角色信息
                if let character = EVELogin.shared.getCharacterByID(currentCharacterId)?.character {
                    currentCharacterName = character.CharacterName
                }
            }
        }
    }

    /// 加载角色技能
    private func loadCharacterSkills(characterId: Int, characterName: String) {
        // 设置加载状态
        loadingCharacterId = characterId

        // 预加载技能数据
        Task {
            do {
                let skills = try await FittingCharacterSkillsLoader.fetchMergedSkills(characterId: characterId)

                // 更新UI并关闭页面
                await MainActor.run {
                    // 通过回调返回技能数据
                    onSelectSkills(skills, characterName, characterId)

                    // 重置加载状态
                    loadingCharacterId = nil

                    // 关闭视图
                    dismiss()
                }
            } catch {
                Logger.error("加载角色技能数据失败: \(error)")

                // 错误处理：重置加载状态
                await MainActor.run {
                    loadingCharacterId = nil
                }
            }
        }
    }
}

/// 角色头像视图组件
struct CharacterPortraitView: View {
    let characterId: Int
    @State private var portrait: UIImage?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            if let portrait = portrait {
                Image(uiImage: portrait)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 32, height: 32)

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                        .foregroundColor(.gray)
                }
            }
        }
        .overlay(
            Circle()
                .stroke(Color.primary.opacity(0.2), lineWidth: 2)
        )
        .background(
            Circle()
                .fill(Color.primary.opacity(0.05))
        )
        .shadow(color: Color.primary.opacity(0.2), radius: 3, x: 0, y: 2)
        .task {
            do {
                portrait = try await CharacterAPI.shared.fetchCharacterPortrait(
                    characterId: characterId,
                    forceRefresh: false
                )
            } catch {
                Logger.error("获取角色头像失败: \(error)")
            }
            isLoading = false
        }
    }
}

/// 角色选择行组件
struct CharacterSelectionRow: View {
    let characterId: Int
    let characterName: String
    let isSelected: Bool
    let isLoading: Bool

    var body: some View {
        HStack {
            CharacterPortraitView(characterId: characterId)
                .padding(.trailing, 12)

            Text(characterName)
                .font(.body)

            Spacer()

            if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
                    .padding(.trailing, 8)
            } else if isSelected {
                Image(systemName: "checkmark")
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.vertical, 4)
    }
}
