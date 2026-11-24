import Foundation

/// 数据刷新后台任务
/// 负责刷新所有角色的钱包余额、位置信息以及公共数据（主权数据）
@MainActor
class DataRefreshTask: BaseBackgroundTask {
    static let identifier = WidgetBackgroundRefresh.identifier
    static let interval: TimeInterval = 30 * 60 // 30分钟

    init() {
        super.init(identifier: Self.identifier, interval: Self.interval)
    }

    override func perform() async {
        Logger.notice("开始执行后台数据刷新")

        await refreshWidgets()
        guard !Task.isCancelled else { return }

        let characters = EVELogin.shared.loadCharacters()
        guard !characters.isEmpty else {
            Logger.warning("没有需要刷新的角色")
            return
        }

        // 刷新所有角色的基本信息
        for characterAuth in characters {
            // 检查任务是否被取消
            if Task.isCancelled {
                Logger.warning("数据刷新任务被取消")
                return
            }

            let characterId = characterAuth.character.CharacterID

            // 跳过token已过期的角色
            if characterAuth.character.refreshTokenExpired {
                Logger.warning("跳过token已过期的角色: \(characterId)")
                continue
            }

            do {
                // 刷新角色详细信息
                try await refreshCharacterData(characterId: characterId)
                Logger.success("成功刷新角色数据: \(characterId)")
            } catch {
                Logger.error("刷新角色数据失败: \(characterId), 错误: \(error)")
                // 继续处理其他角色，不中断整个任务
            }
        }

        // 刷新公共数据
        await refreshPublicData()

        Logger.success("后台数据刷新完成")
    }

    private func refreshWidgets() async {
        await WidgetRefreshService.shared.refresh()
    }

    /// 刷新单个角色的数据（仅钱包和位置信息）
    private func refreshCharacterData(characterId: Int) async throws {
        // 获取角色信息
        guard var character = EVELogin.shared.getCharacterByID(characterId)?.character else {
            throw NetworkError.invalidData
        }

        // 并发获取钱包余额和位置信息
        async let balance = CharacterWalletAPI.shared.getWalletBalance(characterId: characterId)
        async let location = CharacterLocationAPI.shared.fetchCharacterLocation(characterId: characterId)

        let (balanceResult, locationResult) = try await (balance, location)

        // 获取位置详细信息
        let databaseManager = DatabaseManager()
        let locationInfo = await getSolarSystemInfo(
            solarSystemId: locationResult.solar_system_id,
            databaseManager: databaseManager
        )

        // 只更新钱包和位置信息
        character.walletBalance = balanceResult
        character.location = locationInfo
        character.locationStatus = locationResult.locationStatus

        // 保存更新后的信息
        try await EVELogin.shared.saveCharacterInfo(character)
    }

    /// 刷新公共数据（仅主权数据）
    private func refreshPublicData() async {
        // 刷新主权数据
        do {
            _ = try await SovereigntyDataAPI.shared.fetchSovereigntyData(forceRefresh: false)
            Logger.success("主权数据刷新完成")
        } catch {
            Logger.error("主权数据刷新失败: \(error)")
        }
    }
}
