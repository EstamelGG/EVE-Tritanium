import Foundation

/// 技能注入器计算结果
public struct InjectorCalculation {
    /// 所需大型技能注入器数量
    public let largeInjectorCount: Int
    /// 所需小型技能注入器数量
    public let smallInjectorCount: Int
    /// 总计所需技能点数
    public let totalSkillPoints: Int
}

/// 技能注入器计算工具类
///
/// 注入量由使用前的总技能点（含未分配）决定：
/// - < 5M → 大型 500k / 小型 100k
/// - 5M ~ 50M → 400k / 80k
/// - 50M ~ 80M → 300k / 60k
/// - ≥ 80M → 150k / 30k
///
/// 成本上 5 个小型 ≈ 1 个大型，因此剩余不足 1 个大型时，若小型需求 ≥ 5 则改用 1 个大型。
public enum SkillInjectorCalculator {
    public static let largeInjectorTypeId = 40520
    public static let smallInjectorTypeId = 45635

    /// 计算完成技能队列所需的技能注入器数量
    /// - Parameters:
    ///   - requiredSkillPoints: 所需技能点数
    ///   - characterTotalSP: 角色当前总技能点数（含未分配；全新队列传 0）
    public static func calculate(requiredSkillPoints: Int, characterTotalSP: Int)
        -> InjectorCalculation
    {
        let result = calculateOptimal(
            requiredSkillPoints: requiredSkillPoints, characterTotalSP: characterTotalSP
        )

        Logger.debug(
            "largeCount: \(result.largeInjectorCount), smallCount: \(result.smallInjectorCount), totalSkillPoints: \(requiredSkillPoints), startSP: \(characterTotalSP)"
        )

        return result
    }

    private static func calculateOptimal(requiredSkillPoints: Int, characterTotalSP: Int)
        -> InjectorCalculation
    {
        guard requiredSkillPoints > 0 else {
            return InjectorCalculation(
                largeInjectorCount: 0, smallInjectorCount: 0, totalSkillPoints: 0
            )
        }

        var remainingSP = requiredSkillPoints
        var currentSP = characterTotalSP
        var largeCount = 0

        while remainingSP > 0 {
            let largeValue = getInjectorSkillPoints(isLarge: true, characterTotalSP: currentSP)

            if remainingSP >= largeValue {
                let nextThreshold = nextTierThreshold(characterTotalSP: currentSP)
                let spaceInTier = nextThreshold - currentSP
                let maxBeforeCross = spaceInTier / largeValue
                let needed = remainingSP / largeValue

                if maxBeforeCross > 0 {
                    let use = min(maxBeforeCross, needed)
                    largeCount += use
                    remainingSP -= use * largeValue
                    currentSP += use * largeValue
                } else {
                    // 档内剩余不足 1 个大型，但角色总 SP 仍在当前档：
                    // 本次仍按当前档注入量计算，并允许跨越阈值。
                    largeCount += 1
                    remainingSP -= largeValue
                    currentSP += largeValue
                }
                continue
            }

            // 剩余不足 1 个大型：用小型收尾；≥5 个小型则改用 1 个大型
            let smallCount = calculateSmallInjectors(
                remainingSP: remainingSP, startingSP: currentSP
            )
            if smallCount >= 5 {
                largeCount += 1
                return InjectorCalculation(
                    largeInjectorCount: largeCount,
                    smallInjectorCount: 0,
                    totalSkillPoints: requiredSkillPoints
                )
            }
            return InjectorCalculation(
                largeInjectorCount: largeCount,
                smallInjectorCount: smallCount,
                totalSkillPoints: requiredSkillPoints
            )
        }

        return InjectorCalculation(
            largeInjectorCount: largeCount,
            smallInjectorCount: 0,
            totalSkillPoints: requiredSkillPoints
        )
    }

    /// 下一档阈值；已在最高档时返回 Int.max
    private static func nextTierThreshold(characterTotalSP: Int) -> Int {
        switch characterTotalSP {
        case ..<5_000_000: return 5_000_000
        case ..<50_000_000: return 50_000_000
        case ..<80_000_000: return 80_000_000
        default: return Int.max
        }
    }

    /// 精确计算所需小型注入器数量（逐个模拟，以正确跨档）
    private static func calculateSmallInjectors(remainingSP: Int, startingSP: Int) -> Int {
        var remaining = remainingSP
        var currentSP = startingSP
        var count = 0

        while remaining > 0 {
            let injectorSP = getInjectorSkillPoints(isLarge: false, characterTotalSP: currentSP)
            count += 1
            if injectorSP >= remaining {
                break
            }
            remaining -= injectorSP
            currentSP += injectorSP
        }

        return count
    }

    /// 获取技能注入器在指定技能点数下提供的技能点数
    public static func getInjectorSkillPoints(isLarge: Bool, characterTotalSP: Int) -> Int {
        switch characterTotalSP {
        case ..<5_000_000:
            return isLarge ? 500_000 : 100_000
        case 5_000_000 ..< 50_000_000:
            return isLarge ? 400_000 : 80000
        case 50_000_000 ..< 80_000_000:
            return isLarge ? 300_000 : 60000
        default:
            return isLarge ? 150_000 : 30000
        }
    }
}
