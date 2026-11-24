import XCTest
@testable import EVE_Nexus

final class SkillPlanNamingTests: XCTestCase {
    func testNewPlanCannotReuseAnotherPlansName() {
        XCTAssertThrowsError(try SkillPlanNaming.validate(
            "黑隐", planID: UUID(), existingPlans: [(UUID(), "黑隐")]
        )) { error in
            guard case SkillPlanNaming.ValidationError.duplicateName = error else {
                return XCTFail("Expected a duplicate name error, got \(error)")
            }
        }
    }

    func testWhitespaceDoesNotBypassNameValidation() {
        XCTAssertThrowsError(try SkillPlanNaming.validate(
            " 黑隐\n", planID: UUID(), existingPlans: [(UUID(), "黑隐")]
        ))
        XCTAssertThrowsError(try SkillPlanNaming.validate(
            " \n\t", planID: UUID(), existingPlans: []
        ))
    }

    func testDifferentNameIsAllowed() throws {
        try SkillPlanNaming.validate(
            "黑隐备用", planID: UUID(), existingPlans: [(UUID(), "黑隐")]
        )
    }

    func testRenameExcludesThePlanItselfButChecksOtherPlans() throws {
        let id = UUID()
        let plans: [(id: UUID?, name: String)] = [(id, "黑隐"), (UUID(), "炸鱼")]
        try SkillPlanNaming.validate("黑隐", planID: id, existingPlans: plans)
        try SkillPlanNaming.validate("新名称", planID: id, existingPlans: plans)
        XCTAssertThrowsError(try SkillPlanNaming.validate("炸鱼", planID: id, existingPlans: plans))
    }

    func testInputValidationExcludesOnlyTheEditedPlan() {
        let id = UUID()
        let plans: [(id: UUID?, name: String)] = [(id, "黑隐")]
        XCTAssertEqual(SkillPlanNaming.validationError(for: "黑隐", existingPlans: plans), .duplicateName)
        XCTAssertNil(SkillPlanNaming.validationError(for: "黑隐", excludingPlanID: id, existingPlans: plans))
        XCTAssertNil(SkillPlanNaming.validationError(for: "黑隐备用", existingPlans: plans))
    }

    func testDuplicateNamesGetNumberedSuffixes() {
        XCTAssertEqual(
            SkillPlanNaming.uniqueNames(for: ["黑隐", "黑隐", "黑隐"]),
            ["黑隐", "黑隐（1）", "黑隐（2）"]
        )
    }

    func testRenamingReservesExistingSuffixesAndIsIdempotent() {
        let names = ["黑隐", " 黑隐 ", "黑隐（1）", "黑隐"]
        let unique = SkillPlanNaming.uniqueNames(for: names)
        XCTAssertEqual(unique, ["黑隐", "黑隐（2）", "黑隐（1）", "黑隐（3）"])
        XCTAssertEqual(SkillPlanNaming.uniqueNames(for: unique), unique)
    }

    func testLegacyPlanWithoutIDStillReservesItsName() {
        XCTAssertThrowsError(try SkillPlanNaming.validate(
            "黑隐", planID: UUID(), existingPlans: [(nil, "黑隐")]
        ))
    }

    func testLoadingRenamesDuplicatesOnDiskWithoutChangingTheirSkillsOrIDs() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let manager = SkillPlanFileManager(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let originals = ["黑隐", "黑隐", "黑隐（1）", "黑隐"].enumerated().map { index, name in
            SkillPlanData(id: UUID(), name: name, lastUpdated: Date(timeIntervalSince1970: 1_000),
                          skills: ["3402:\(index + 1)"])
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .formatted(DateFormatter.iso8601Full)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(DateFormatter.iso8601Full)
        for (index, plan) in originals.enumerated() {
            try encoder.encode(plan).write(to: directory.appendingPathComponent("\(index).json"))
        }

        let loaded = manager.loadSkillPlans(characterId: 0)
        XCTAssertEqual(Set(loaded.map(\.name)), Set(["黑隐", "黑隐（1）", "黑隐（2）", "黑隐（3）"]))
        XCTAssertEqual(loaded.count, originals.count)
        var persisted: [Data] = []
        for (index, original) in originals.enumerated() {
            let data = try Data(contentsOf: directory.appendingPathComponent("\(index).json"))
            persisted.append(data)
            let saved = try decoder.decode(SkillPlanData.self, from: data)
            XCTAssertEqual(saved.id, original.id)
            XCTAssertEqual(saved.skills, original.skills)
            XCTAssertEqual(saved.lastUpdated, original.lastUpdated)
        }

        _ = manager.loadSkillPlans(characterId: 0)
        for (index, previous) in persisted.enumerated() {
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("\(index).json")), previous)
        }
    }

    func testIdenticalContentsWithDifferentNamesCanBeSaved() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let manager = SkillPlanFileManager(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = SkillPlan(id: UUID(), name: "黑隐", skills: [], lastUpdated: Date())
        let second = SkillPlan(id: UUID(), name: "黑隐备用", skills: [], lastUpdated: Date())
        _ = try manager.saveSkillPlan(characterId: 0, plan: first, databaseManager: .shared)
        _ = try manager.saveSkillPlan(characterId: 0, plan: second, databaseManager: .shared)
        XCTAssertEqual(Set(manager.loadPlanNames().map(\.name)), Set(["黑隐", "黑隐备用"]))
        var duplicate = second
        duplicate.name = first.name
        XCTAssertThrowsError(try manager.saveSkillPlan(characterId: 0, plan: duplicate, databaseManager: .shared))
        XCTAssertEqual(Set(manager.loadPlanNames().map(\.name)), Set(["黑隐", "黑隐备用"]))
    }
}
