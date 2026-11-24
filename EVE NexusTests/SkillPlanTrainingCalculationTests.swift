import XCTest
@testable import EVE_Nexus

final class SkillPlanTrainingCalculationTests: XCTestCase {
    private func entry(
        level: Int = 1, rank: Double? = 1, trainedLevel: Int = 0,
        points: Int = 0, rate: Int? = 3360
    ) -> SkillPlanTrainingCalculation.Entry {
        SkillPlanTrainingCalculation.entry(targetLevel: level, multiplier: rank,
                                          trainedLevel: trainedLevel, currentSkillPoints: points,
                                          trainingRate: rate)
    }

    func testScreenshotRowsHavePositiveTimesAndMatchingSummary() throws {
        let rows = [entry(), entry(), entry(level: 2)]
        XCTAssertEqual(try XCTUnwrap(rows[0].trainingTime), 250.0 / 3360 * 3600, accuracy: 0.001)
        XCTAssertEqual(rows.map(\.requiredSP), [250, 250, 1165])
        XCTAssertTrue(rows.allSatisfy { !$0.isCompleted && ($0.trainingTime ?? 0) > 0 })
        let summary = SkillPlanTrainingCalculation.summary(rows)
        XCTAssertEqual(summary.requiredSP, 1665)
        XCTAssertEqual(try XCTUnwrap(summary.trainingTime), 1665.0 / 3360 * 3600, accuracy: 0.001)
    }

    func testUserBlackOpsPlanFromZero() throws {
        let targets: [(skillID: Int, rank: Double, level: Int)] = [
            (3327, 1, 5), (3328, 2, 3), (33093, 2, 3), (3332, 5, 3),
            (33097, 6, 3), (3336, 8, 5), (3402, 1, 5), (3449, 1, 5),
            (3412, 3, 5), (3455, 1, 5), (3456, 5, 5), (24562, 14, 1),
            (3426, 1, 4), (11579, 6, 4), (21611, 9, 4), (28656, 10, 1),
        ]
        let rows = targets.flatMap { target in
            (1 ... target.level).map { entry(level: $0, rank: target.rank, rate: 1800) }
        }
        XCTAssertEqual(rows.count, 61)
        XCTAssertTrue(rows.allSatisfy { ($0.requiredSP ?? 0) > 0 && ($0.trainingTime ?? 0) > 0 })
        let summary = SkillPlanTrainingCalculation.summary(rows)
        XCTAssertEqual(summary.requiredSP, 5_970_080)
        XCTAssertEqual(summary.fullSkillPoints, 5_970_080)
        XCTAssertEqual(try XCTUnwrap(summary.trainingTime), 11_940_160, accuracy: 0.001)
    }

    func testPartialProgressReducesBothPointsAndTime() throws {
        let row = entry(level: 2, trainedLevel: 1, points: 1000, rate: 1800)
        XCTAssertEqual(row.startSP, 1000)
        XCTAssertEqual(row.endSP, 1415)
        XCTAssertEqual(row.requiredSP, 415)
        XCTAssertEqual(row.fullSkillPoints, 1165)
        XCTAssertEqual(try XCTUnwrap(row.trainingTime), 830, accuracy: 0.001)
        let next = entry(level: 3, trainedLevel: 1, points: 1000, rate: 1800)
        XCTAssertEqual(next.startSP, 1415)
        XCTAssertEqual(next.requiredSP, 6585)
    }

    func testCompletedLevelOverridesStalePointSnapshot() {
        let rows = (1 ... 5).map { entry(level: $0, trainedLevel: 5, points: 0, rate: nil) }
        XCTAssertTrue(rows.allSatisfy(\.isCompleted))
        let summary = SkillPlanTrainingCalculation.summary(rows)
        XCTAssertEqual(summary.requiredSP, 0)
        XCTAssertEqual(summary.trainingTime, 0)
        XCTAssertEqual(summary.fullSkillPoints, 256_000)
    }

    func testChangingCharacterInputsDoesNotRequireChangingThePlan() throws {
        let plan = SkillPlan(id: UUID(), name: "科学", skills: [
            PlannedSkill(id: UUID(), skillID: 3402, skillName: "科学原理", targetLevel: 1),
        ], lastUpdated: Date())
        let level = try XCTUnwrap(plan.skills.first).targetLevel
        let initial = entry(level: level, points: 0, rate: nil)
        let loaded = entry(level: level, points: 0, rate: 1800)
        let progressed = entry(level: level, points: 125, rate: 1800)
        XCTAssertNil(initial.trainingTime)
        XCTAssertEqual(loaded.requiredSP, 250)
        XCTAssertEqual(loaded.trainingTime, 500)
        XCTAssertEqual(progressed.requiredSP, 125)
        XCTAssertEqual(progressed.trainingTime, 250)
        XCTAssertEqual(plan.skills.first?.targetLevel, 1)
    }

    func testMissingDataIsNotReportedAsZero() {
        for rate: Int? in [nil, 0, -1] {
            let row = entry(rate: rate)
            XCTAssertEqual(row.requiredSP, 250)
            XCTAssertNil(row.trainingTime)
            XCTAssertFalse(row.isCompleted)
            XCTAssertNil(SkillPlanTrainingCalculation.summary([row, entry()]).trainingTime)
        }
        let missingRank = entry(rank: nil)
        XCTAssertNil(missingRank.requiredSP)
        XCTAssertNil(missingRank.trainingTime)
        XCTAssertNil(SkillPlanTrainingCalculation.summary([missingRank, entry()]).requiredSP)
    }

    func testFractionalMultiplierIsAppliedBeforeIntegerConversion() {
        let row = entry(rank: 0.5, rate: 1800)
        XCTAssertEqual(row.requiredSP, 125)
        XCTAssertEqual(row.trainingTime, 250)
    }

    func testInvalidInputsAndExcessPointsDoNotProduceNegativeTimes() {
        for level in [0, 6, -1] {
            XCTAssertNil(entry(level: level).requiredSP)
        }
        for rank in [0.0, -1, .infinity, .nan] {
            XCTAssertNil(entry(rank: rank).requiredSP)
        }
        let beyondTarget = entry(points: 1000)
        XCTAssertEqual(beyondTarget.requiredSP, 0)
        XCTAssertEqual(beyondTarget.trainingTime, 0)
        XCTAssertTrue(beyondTarget.isCompleted)
    }

    func testEmptyPlanHasZeroTotals() {
        let summary = SkillPlanTrainingCalculation.summary([])
        XCTAssertEqual(summary.requiredSP, 0)
        XCTAssertEqual(summary.trainingTime, 0)
        XCTAssertEqual(summary.fullSkillPoints, 0)
    }
}
