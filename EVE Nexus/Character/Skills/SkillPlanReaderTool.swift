import Foundation

struct SkillPlanParseResult {
    let skills: [String]
    let parseErrors: [String]
    let notFoundSkills: [String]

    var hasErrors: Bool {
        return !parseErrors.isEmpty || !notFoundSkills.isEmpty
    }
}

class SkillPlanReaderTool {
    static func parseSkillPlan(from text: String, databaseManager: DatabaseManager)
        -> SkillPlanParseResult
    {
        var parseFailedLines: [String] = []
        var notFoundSkills: [String] = []
        var skills: [String] = []

        // 收集所有技能名称和等级
        let lines = text.components(separatedBy: .newlines)
        var skillEntries: [(name: String, level: Int)] = []

        // 第一步：解析每一行，收集技能名称和等级
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.isEmpty {
                continue
            }

            // 使用正则表达式匹配技能名称和等级
            let pattern = "^(.+?)\\s+([1-5])$"
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(
                   in: trimmedLine, range: NSRange(trimmedLine.startIndex..., in: trimmedLine)
               )
            {
                let nameRange = Range(match.range(at: 1), in: trimmedLine)!
                let levelRange = Range(match.range(at: 2), in: trimmedLine)!

                let skillName = String(trimmedLine[nameRange]).trimmingCharacters(in: .whitespaces)
                if let level = Int(trimmedLine[levelRange]),
                   level >= 1 && level <= 5
                {
                    skillEntries.append((name: skillName, level: level))
                } else {
                    parseFailedLines.append(trimmedLine)
                }
            } else {
                parseFailedLines.append(trimmedLine)
            }
        }

        // 如果有技能条目，查询它们的 type_id
        if !skillEntries.isEmpty {
            // 获取唯一的技能名称用于查询
            let uniqueSkillNames = Set(skillEntries.map { $0.name })
            let skillNamesString = uniqueSkillNames.sorted().map { "'\($0)'" }.joined(
                separator: " UNION SELECT "
            )
            let query = """
                SELECT t.type_id, t.name, t.en_name
                FROM types t
                WHERE (t.name IN (SELECT \(skillNamesString)) or t.en_name IN (SELECT \(skillNamesString)))
                AND t.categoryID = 16
            """

            let queryResult = databaseManager.executeQuery(query)
            var typeIdMap: [String: Int] = [:]

            switch queryResult {
            case let .success(rows):
                for row in rows {
                    if let typeId = row["type_id"] as? Int {
                        // 遍历skillEntries找到匹配的技能名称
                        for skillName in uniqueSkillNames {
                            if let name = row["name"] as? String,
                               let enName = row["en_name"] as? String,
                               skillName == name || skillName == enName
                            {
                                typeIdMap[skillName] = typeId
                                break
                            }
                        }
                    }
                }
            case let .error(error):
                Logger.error("查询技能失败: \(error)")
            }

            // 按原始顺序处理每个技能条目
            for entry in skillEntries {
                if let typeId = typeIdMap[entry.name] {
                    skills.append("\(typeId):\(entry.level)")
                } else {
                    notFoundSkills.append(entry.name)
                }
            }
        }

        return SkillPlanParseResult(
            skills: skills,
            parseErrors: parseFailedLines,
            notFoundSkills: notFoundSkills
        )
    }
}
