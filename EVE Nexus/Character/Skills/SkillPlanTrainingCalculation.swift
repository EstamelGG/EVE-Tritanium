import Foundation

enum SkillPlanTrainingCalculation {
    struct Entry {
        let startSP: Int?
        let endSP: Int?
        let fullSkillPoints: Int?
        let requiredSP: Int?
        let trainingTime: TimeInterval?
        let isCompleted: Bool
    }

    struct Summary {
        let requiredSP: Int?
        let trainingTime: TimeInterval?
        let fullSkillPoints: Int?
    }

    static func entry(
        targetLevel: Int, multiplier: Double?, trainedLevel: Int,
        currentSkillPoints: Int, trainingRate: Int?
    ) -> Entry {
        let basePoints = [0, 250, 1415, 8000, 45255, 256_000]
        guard (1 ... 5).contains(targetLevel) else {
            return Entry(startSP: nil, endSP: nil, fullSkillPoints: nil,
                         requiredSP: nil, trainingTime: nil, isCompleted: false)
        }
        let completedByLevel = trainedLevel >= targetLevel
        guard let multiplier, multiplier.isFinite, multiplier > 0,
              Double(basePoints[targetLevel]) * multiplier < Double(Int.max)
        else {
            return Entry(startSP: nil, endSP: nil, fullSkillPoints: nil,
                         requiredSP: completedByLevel ? 0 : nil,
                         trainingTime: completedByLevel ? 0 : nil, isCompleted: completedByLevel)
        }

        let baseStart = Int(Double(basePoints[targetLevel - 1]) * multiplier)
        let end = Int(Double(basePoints[targetLevel]) * multiplier)
        let start = completedByLevel ? end : min(end, max(baseStart, currentSkillPoints))
        let remaining = end - start
        let time: TimeInterval?
        if remaining == 0 {
            time = 0
        } else if let trainingRate, trainingRate > 0 {
            time = Double(remaining) / Double(trainingRate) * 3600
        } else {
            // 未取得训练速度不等于不需要训练。
            time = nil
        }
        return Entry(startSP: start, endSP: end, fullSkillPoints: end - baseStart,
                     requiredSP: remaining, trainingTime: time, isCompleted: remaining == 0)
    }

    static func summary(_ entries: [Entry]) -> Summary {
        func total<T: AdditiveArithmetic>(_ values: [T?]) -> T? {
            var sum: T = .zero
            for value in values {
                guard let value else { return nil }
                sum += value
            }
            return sum
        }
        return Summary(requiredSP: total(entries.map(\.requiredSP)),
                       trainingTime: total(entries.map(\.trainingTime)),
                       fullSkillPoints: total(entries.map(\.fullSkillPoints)))
    }
}
