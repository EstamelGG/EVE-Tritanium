import Foundation

/// 工业项目数据更新后台任务
/// 负责定期更新所有所选角色的工业项目数据
/// 使用 BGProcessingTask 以获得更长的执行时间
@MainActor
class IndustryRefreshTask: BaseProcessingTask {
    static let identifier = "com.evenexus.industryrefresh"
    static let interval: TimeInterval = 60 * 60 // 1小时

    init() {
        super.init(identifier: Self.identifier, interval: Self.interval)
    }

    override func perform() async {
        Logger.notice("开始执行后台工业项目数据更新")

        // 获取工业设置中的多人物模式状态
        let multiCharacterMode = UserDefaults.standard.bool(forKey: "multiCharacterMode_industry")

        // 获取选中的角色ID列表
        let savedCharacterIds = UserDefaults.standard.array(forKey: "selectedCharacterIds_industry") as? [Int] ?? []
        let selectedCharacterIds = Set(savedCharacterIds)

        // 确定要更新的角色ID列表
        let characterIdsToUpdate: Set<Int>
        if multiCharacterMode, !selectedCharacterIds.isEmpty {
            // 多人物模式：使用选中的角色
            characterIdsToUpdate = selectedCharacterIds
        } else {
            // 单人物模式：使用当前角色
            let currentCharacterId = UserDefaults.standard.integer(forKey: "currentCharacterId")
            if currentCharacterId != 0 {
                characterIdsToUpdate = Set([currentCharacterId])
            } else {
                Logger.info("没有需要更新的角色，跳过工业项目数据更新")
                return
            }
        }

        guard !characterIdsToUpdate.isEmpty else {
            Logger.info("没有需要更新的角色，跳过工业项目数据更新")
            return
        }

        // 获取隐藏已完成和已取消项目的设置
        let hideCompletedAndCancelled = UserDefaults.standard.bool(forKey: "hideCompletedAndCancelled_global")

        // 遍历所有需要更新的角色
        for characterId in characterIdsToUpdate {
            // 检查任务是否被取消
            if Task.isCancelled {
                Logger.warning("工业项目数据更新任务被取消")
                return
            }

            // 检查角色是否存在且token未过期
            guard let characterAuth = EVELogin.shared.getCharacterByID(characterId) else {
                Logger.warning("找不到角色: \(characterId)，跳过工业项目数据更新")
                continue
            }

            if characterAuth.character.refreshTokenExpired {
                Logger.warning("角色token已过期，跳过工业项目数据更新: \(characterId)")
                continue
            }

            do {
                _ = try await CharacterIndustryAPI.shared.fetchIndustryJobs(
                    characterId: characterId,
                    includeCompleted: !hideCompletedAndCancelled
                )
                Logger.success("成功更新工业项目数据: \(characterId)")
            } catch {
                Logger.error("更新工业项目数据失败: \(characterId), 错误: \(error)")
                // 继续处理其他角色，不因为一个角色失败而停止
            }
        }

        Logger.success("后台工业项目数据更新完成")
    }
}
