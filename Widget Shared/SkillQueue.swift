import Foundation

/// 技能队列项目
public struct SkillQueueItem: Codable, Identifiable, Equatable, Sendable {
    public let queue_position: Int
    public let skill_id: Int
    public let finished_level: Int
    public let training_start_sp: Int?
    public let level_end_sp: Int?
    public let level_start_sp: Int?
    public let start_date: Date?
    public let finish_date: Date?

    public var id: Int {
        queue_position
    }

    public var isCurrentlyTraining: Bool {
        guard let startDate = start_date,
              let finishDate = finish_date
        else {
            return false
        }
        let now = Date()
        return now >= startDate && now <= finishDate
    }

    public var remainingTime: TimeInterval? {
        guard let finishDate = finish_date else {
            return nil
        }
        return finishDate.timeIntervalSinceNow
    }

    /// 获取技能等级的罗马数字表示
    public var skillLevel: String {
        let romanNumerals = ["I", "II", "III", "IV", "V"]
        return romanNumerals[finished_level - 1]
    }

    /// 计算训练进度
    public var progress: Double {
        progress(at: Date())
    }

    public func progress(at now: Date) -> Double {
        guard let startDate = start_date,
              let finishDate = finish_date,
              let trainingStartSp = training_start_sp,
              let levelEndSp = level_end_sp,
              let levelStartSp = level_start_sp
        else {
            return 0
        }

        // 如果还没开始训练，进度为0
        if now < startDate {
            return 0
        }

        // 如果已经完成训练，进度为1
        if now > finishDate {
            return 1
        }

        // 正在训练中：使用基于时间的进度计算
        let totalTrainingTime = finishDate.timeIntervalSince(startDate)
        guard totalTrainingTime > 0, levelEndSp > levelStartSp else { return 0 }
        let trainedTime = now.timeIntervalSince(startDate)
        let timeProgress = trainedTime / totalTrainingTime

        // 计算剩余需要训练的技能点
        let remainingSP = levelEndSp - trainingStartSp

        // 计算当前已训练的技能点
        let trainedSP = Double(remainingSP) * timeProgress
        let currentSP = Double(trainingStartSp) + trainedSP

        // 计算当前等级的进度
        let levelCurrentSP = currentSP - Double(levelStartSp) // 在该等级已获得的技能点
        let levelTotalSP = Double(levelEndSp - levelStartSp) // 该等级需要的总技能点

        return min(max(levelCurrentSP / levelTotalSP, 0), 1)
    }
}

struct CharacterSkillQueueSample: Codable, Equatable, Sendable {
    let queue: [SkillQueueItem]
    let fetchedAt: Date
    let names: [Int: String]

    func needsRefresh(at date: Date, maxAge: TimeInterval, afterSkillFinishes: Bool = false) -> Bool {
        let age = date.timeIntervalSince(fetchedAt)
        if age >= maxAge { return true }
        return afterSkillFinishes && queue.contains { skill in
            guard let finish = skill.finish_date else { return false }
            return fetchedAt < finish && finish <= date
        }
    }

    func relocalized(lookup: (Int) -> String?) -> Self {
        let localized = Set(queue.map(\.skill_id)).reduce(into: [Int: String]()) { result, id in
            result[id] = lookup(id) ?? names[id]
        }
        return Self(queue: queue, fetchedAt: fetchedAt, names: localized)
    }

    func widgetSkills(previous: [WidgetSkill]? = nil) -> [WidgetSkill] {
        let previousNames = Dictionary(
            (previous ?? []).compactMap { skill in skill.name.map { (skill.typeID, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        return queue.sorted { $0.queue_position < $1.queue_position }.map { skill in
            WidgetSkill(
                typeID: skill.skill_id,
                name: names[skill.skill_id] ?? previousNames[skill.skill_id],
                level: skill.finished_level,
                start: skill.start_date,
                finish: skill.finish_date,
                trainingStartSP: skill.training_start_sp,
                levelStartSP: skill.level_start_sp,
                levelEndSP: skill.level_end_sp
            )
        }
    }
}

