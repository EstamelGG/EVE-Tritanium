import XCTest
@testable import EVE_Nexus

final class FittingPersistenceTests: XCTestCase {
    private func directory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func fitting(_ name: String, ship: Int = 587) -> LocalFitting {
        LocalFitting(description: "preserve me", fitting_id: UUID(),
                     items: [LocalFittingItem(flag: .hiSlot0, quantity: 1, type_id: 123, status: 0)],
                     name: name, ship_type_id: ship)
    }

    /// Compare identities, names, content and actual on-disk bytes on every subsequent load.
    private func assertStableCatalog(_ original: [LocalFitting], directory: URL,
                                     file: StaticString = #filePath, line: UInt = #line) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let expectedContents = try Dictionary(uniqueKeysWithValues: original.map {
            ($0.fitting_id, try encoder.encode($0.renamed("")))
        })
        func files() throws -> [String: Data] {
            let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("local_fitting_") && $0.pathExtension == "json" }
            return try Dictionary(uniqueKeysWithValues: urls.map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
        }
        func backups() throws -> [String] {
            let folder = directory.appendingPathComponent("MigrationBackups")
            guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
            return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .map(\.lastPathComponent).sorted()
        }
        let initial = try FitConvert.loadAllLocalFittings(directory: directory).fittings
        let names = Dictionary(uniqueKeysWithValues: initial.map { ($0.fitting_id, $0.name) })
        let initialFiles = try files()
        let initialBackups = try backups()
        XCTAssertEqual(initialFiles.count, original.count, file: file, line: line)
        for _ in 0..<20 {
            let loaded = try FitConvert.loadAllLocalFittings(directory: directory).fittings
            XCTAssertEqual(loaded.count, original.count, file: file, line: line)
            XCTAssertEqual(Set(loaded.map(\.fitting_id)), Set(original.map(\.fitting_id)), file: file, line: line)
            for shipFittings in Dictionary(grouping: loaded, by: \.ship_type_id).values {
                XCTAssertEqual(Set(shipFittings.map { FittingNamePolicy.key($0.name) }).count,
                               shipFittings.count, file: file, line: line)
            }
            XCTAssertEqual(Dictionary(uniqueKeysWithValues: loaded.map { ($0.fitting_id, $0.name) }), names, file: file, line: line)
            for fitting in loaded {
                XCTAssertEqual(try encoder.encode(fitting.renamed("")), expectedContents[fitting.fitting_id], file: file, line: line)
                XCTAssertEqual(try FitConvert.loadLocalFitting(fittingId: fitting.fitting_id, directory: directory).name,
                               fitting.name, file: file, line: line)
            }
            XCTAssertEqual(try files(), initialFiles, file: file, line: line)
            XCTAssertEqual(try backups(), initialBackups, file: file, line: line)
        }
    }

    func testCollisionIncrementsFinalSuffixAndSkipsOccupiedNames() {
        let names = Set(["Fit", "Fit(1)", "Fit(3)"].map(FittingNamePolicy.key))
        XCTAssertEqual(FittingNamePolicy.uniqueName("Fit", occupied: names), "Fit(2)")
        XCTAssertEqual(FittingNamePolicy.uniqueName("Fit(1)", occupied: names), "Fit(2)")
        XCTAssertEqual(FittingNamePolicy.uniqueName("Fit(3)", occupied: names), "Fit(4)")
        XCTAssertEqual(FittingNamePolicy.uniqueName("Fit(9)", occupied: names), "Fit(9)")
        XCTAssertEqual(FittingNamePolicy.uniqueName(" fit ", occupied: names), "fit(2)")
        XCTAssertEqual(FittingNamePolicy.uniqueName("PvP (active)", occupied: ["pvp (active)"]), "PvP (active)(1)")
    }

    func testSavingScopesNamesToShipTypeAndOverwritingExcludesSelf() throws {
        let directory = try directory()
        let first = try FitConvert.saveLocalFitting(fitting("Fit"), directory: directory)
        let second = try FitConvert.saveLocalFitting(fitting("Fit", ship: 588), directory: directory)
        XCTAssertEqual(first.name, "Fit")
        XCTAssertEqual(second.name, "Fit", "不同飞船允许同名")
        let duplicate = try FitConvert.saveLocalFitting(fitting("Fit", ship: 588), directory: directory)
        XCTAssertEqual(duplicate.name, "Fit(1)", "同一飞船的重名才追加尾号")
        let again = try FitConvert.saveLocalFitting(duplicate, directory: directory)
        XCTAssertEqual(again.name, "Fit(1)")
        let renamed = try FitConvert.saveLocalFitting(duplicate.renamed("Fit"), directory: directory)
        XCTAssertEqual(renamed.name, "Fit(1)")
        XCTAssertEqual(renamed.fitting_id, duplicate.fitting_id)
        XCTAssertEqual(try FitConvert.loadAllLocalFittings(directory: directory).fittings.count, 3)
        XCTAssertEqual(try FitConvert.loadLocalFitting(fittingId: first.fitting_id, directory: directory).name, "Fit")
        try assertStableCatalog([first, second, duplicate], directory: directory)
    }

    func testMigrationPreservesIDsContentsAndExistingNumberedNames() throws {
        let directory = try directory()
        let original = [fitting("Fit"), fitting("Fit"), fitting("Fit(1)"), fitting("Fit(1)")]
        let encoder = JSONEncoder()
        for fitting in original {
            try encoder.encode(fitting).write(to: directory.appendingPathComponent("local_fitting_\(fitting.fitting_id.uuidString).json"))
        }
        let migrated = try FitConvert.loadAllLocalFittings(directory: directory).fittings
        XCTAssertEqual(Set(migrated.map(\.fitting_id)), Set(original.map(\.fitting_id)))
        XCTAssertEqual(Set(migrated.map(\.name)), ["Fit", "Fit(1)", "Fit(2)", "Fit(3)"])
        for fitting in migrated {
            XCTAssertEqual(fitting.description, "preserve me")
            XCTAssertEqual(fitting.items.first?.status, 0)
            XCTAssertEqual(fitting.items.first?.type_id, 123)
            XCTAssertEqual(try FitConvert.loadLocalFitting(fittingId: fitting.fitting_id, directory: directory).name, fitting.name)
        }
        try assertStableCatalog(original, directory: directory)
        let repeated = try FitConvert.loadAllLocalFittings(directory: directory).fittings
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: migrated.map { ($0.fitting_id, $0.name) }),
                       Dictionary(uniqueKeysWithValues: repeated.map { ($0.fitting_id, $0.name) }))
    }
    func testMigrationPreservesLowercaseUUIDFileNames() throws {
        let directory = try directory()
        let first = fitting("Fit").duplicated(
            newId: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!, name: "Fit"
        )
        let second = fitting("Fit", ship: 588).duplicated(
            newId: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!, name: "Fit"
        )
        for fitting in [first, second] {
            try JSONEncoder().encode(fitting).write(to: directory.appendingPathComponent(
                "local_fitting_\(fitting.fitting_id.uuidString.lowercased()).json"
            ))
        }
        try assertStableCatalog([first, second], directory: directory)
        let reloaded = try FitConvert.loadAllLocalFittings(directory: directory).fittings
        XCTAssertEqual(Set(reloaded.map(\.fitting_id)), [first.fitting_id, second.fitting_id])
        XCTAssertEqual(Set(reloaded.map(\.name)), ["Fit"])
        for fitting in [first, second] {
            XCTAssertNoThrow(try FitConvert.loadLocalFitting(fittingId: fitting.fitting_id, directory: directory))
        }
    }

    func testMigrationReadsAllFilesBeforeRewritingMismatchedNames() throws {
        try assertMismatchedNamesPreserved(lowercase: false)
    }

    func testMigrationPreservesCrossedIDsWithLowercaseFileNames() throws {
        try assertMismatchedNamesPreserved(lowercase: true)
    }

    private func assertMismatchedNamesPreserved(lowercase: Bool) throws {
        let directory = try directory()
        let first = fitting("Fit", ship: 587)
        let second = fitting("Fit", ship: 588)
        func sourceURL(_ id: UUID) -> URL {
            let value = lowercase ? id.uuidString.lowercased() : id.uuidString
            return directory.appendingPathComponent("local_fitting_\(value).json")
        }
        // Both UUIDs are distinct, but each hand-written filename points to the other JSON ID.
        try JSONEncoder().encode(first).write(to: sourceURL(second.fitting_id))
        try JSONEncoder().encode(second).write(to: sourceURL(first.fitting_id))
        try assertStableCatalog([first, second], directory: directory)
        let reloaded = try FitConvert.loadAllLocalFittings(directory: directory).fittings
        XCTAssertEqual(Set(reloaded.map(\.fitting_id)), [first.fitting_id, second.fitting_id])
        XCTAssertEqual(Set(reloaded.map(\.name)), ["Fit"])
        XCTAssertEqual(try FitConvert.loadLocalFitting(fittingId: first.fitting_id, directory: directory).ship_type_id, 587)
        XCTAssertEqual(try FitConvert.loadLocalFitting(fittingId: second.fitting_id, directory: directory).ship_type_id, 588)
    }

    func testDuplicateJSONIDsKeepBothContentsAndBackupOriginalFiles() throws {
        let directory = try directory()
        let first = fitting("Fit", ship: 587)
        let second = fitting("Fit", ship: 588).duplicated(newId: first.fitting_id, name: "Fit")
        let canonical = directory.appendingPathComponent("local_fitting_\(first.fitting_id.uuidString).json")
        let copied = directory.appendingPathComponent("local_fitting_copy.json")
        let firstData = try JSONEncoder().encode(first)
        let secondData = try JSONEncoder().encode(second)
        try firstData.write(to: canonical)
        try secondData.write(to: copied)
        let migrated = try FitConvert.loadAllLocalFittings(directory: directory).fittings
        XCTAssertEqual(migrated.count, 2)
        XCTAssertEqual(Set(migrated.map(\.fitting_id)).count, 2)
        XCTAssertEqual(Set(migrated.map(\.ship_type_id)), [587, 588])
        XCTAssertEqual(try FitConvert.loadLocalFitting(fittingId: first.fitting_id, directory: directory).ship_type_id, 587)
        let backupFolders = try FileManager.default.contentsOfDirectory(
            at: directory.appendingPathComponent("MigrationBackups"), includingPropertiesForKeys: nil
        )
        let backup = try XCTUnwrap(backupFolders.first)
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent(canonical.lastPathComponent)), firstData)
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent(copied.lastPathComponent)), secondData)
        try assertStableCatalog(migrated, directory: directory)
    }

    func testUnreadableFilesAreNeverDeletedDuringLoadingOrOverwrittenDuringMigration() throws {
        let directory = try directory()
        let valid = fitting("Fit")
        let unreadable = directory.appendingPathComponent("local_fitting_\(valid.fitting_id.uuidString).json")
        let invalidData = Data("broken hand-written JSON".utf8)
        try invalidData.write(to: unreadable)
        try JSONEncoder().encode(valid).write(to: directory.appendingPathComponent("local_fitting_copy.json"))
        let result = try FitConvert.loadAllLocalFittings(directory: directory)
        XCTAssertEqual(result.unreadable.count, 1)
        XCTAssertEqual(result.fittings.count, 1)
        XCTAssertNotEqual(result.fittings.first?.fitting_id, valid.fitting_id)
        XCTAssertEqual(try Data(contentsOf: unreadable), invalidData)
        XCTAssertEqual(try FitConvert.loadAllLocalFittings(directory: directory).unreadable.count, 1)
    }

    func testRenamingPreservesUnrecognizedJSONFields() throws {
        let directory = try directory()
        for fitting in [fitting("Fit"), fitting("Fit")] {
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(fitting)) as? [String: Any])
            json["custom_note"] = "preserve hand-written data"
            try JSONSerialization.data(withJSONObject: json).write(
                to: directory.appendingPathComponent("local_fitting_\(fitting.fitting_id.uuidString).json")
            )
        }
        for fitting in try FitConvert.loadAllLocalFittings(directory: directory).fittings {
            let data = try Data(contentsOf: directory.appendingPathComponent("local_fitting_\(fitting.fitting_id.uuidString).json"))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(json["custom_note"] as? String, "preserve hand-written data")
        }
    }

    func testSavingLowercaseFilePreservesBothSameNameFittings() throws {
        let directory = try directory()
        let first = fitting("Fit")
        let second = fitting("Fit", ship: 588)
        for fitting in [first, second] {
            try JSONEncoder().encode(fitting).write(to: directory.appendingPathComponent(
                "local_fitting_\(fitting.fitting_id.uuidString.lowercased()).json"
            ))
        }
        let migrated = try FitConvert.loadAllLocalFittings(directory: directory).fittings
        let firstToSave = try XCTUnwrap(migrated.first { $0.fitting_id == first.fitting_id })
        let saved = try FitConvert.saveLocalFitting(firstToSave.renamed("Updated"), directory: directory)
        XCTAssertEqual(saved.name, "Updated")
        XCTAssertEqual(saved.fitting_id, first.fitting_id)
        try assertStableCatalog([saved, second], directory: directory)
    }

    func testLegacyNumericIDsMigrateAndStayStable() throws {
        let directory = try directory()
        for number in [1, 2] {
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(fitting("Fit"))) as? [String: Any])
            json["fitting_id"] = number
            try JSONSerialization.data(withJSONObject: json).write(
                to: directory.appendingPathComponent("local_fitting_\(number).json")
            )
        }
        let migrated = try FitConvert.loadAllLocalFittings(directory: directory).fittings
        XCTAssertEqual(migrated.count, 2)
        XCTAssertEqual(Set(migrated.map(\.name)), ["Fit", "Fit(1)"])
        try assertStableCatalog(migrated, directory: directory)
    }

    func testSuffixNumbersUsedByOtherShipDoNotReserveNames() throws {
        let directory = try directory()
        let first = try FitConvert.saveLocalFitting(fitting("Fit"), directory: directory)
        let otherShip = try FitConvert.saveLocalFitting(fitting("Fit(1)", ship: 588), directory: directory)
        let duplicate = try FitConvert.saveLocalFitting(fitting("Fit"), directory: directory)
        XCTAssertEqual(duplicate.name, "Fit(1)")
        try assertStableCatalog([first, otherShip, duplicate], directory: directory)
    }

    func testMigrationRenamesDuplicatesIndependentlyForEachShip() throws {
        let directory = try directory()
        let original = [fitting("Fit"), fitting("Fit"), fitting("Fit", ship: 588),
                        fitting("Fit", ship: 588), fitting("Fit(1)", ship: 588)]
        for fitting in original {
            try JSONEncoder().encode(fitting).write(
                to: directory.appendingPathComponent("local_fitting_\(fitting.fitting_id.uuidString).json")
            )
        }
        let migrated = try FitConvert.loadAllLocalFittings(directory: directory).fittings
        let grouped = Dictionary(grouping: migrated, by: \.ship_type_id)
        XCTAssertEqual(Set(grouped[587, default: []].map(\.name)), ["Fit", "Fit(1)"])
        XCTAssertEqual(Set(grouped[588, default: []].map(\.name)), ["Fit", "Fit(1)", "Fit(2)"])
        try assertStableCatalog(original, directory: directory)
    }

    func testUnreadableNameIsReservedOnlyForItsKnownShipType() throws {
        let directory = try directory()
        let unreadable = directory.appendingPathComponent("local_fitting_unreadable.json")
        let originalData = try JSONSerialization.data(withJSONObject: ["name": "Fit", "ship_type_id": 587])
        try originalData.write(to: unreadable)
        let sameShip = try FitConvert.saveLocalFitting(fitting("Fit"), directory: directory)
        let otherShip = try FitConvert.saveLocalFitting(fitting("Fit", ship: 588), directory: directory)
        XCTAssertEqual(sameShip.name, "Fit(1)")
        XCTAssertEqual(otherShip.name, "Fit")
        for _ in 0..<20 {
            let result = try FitConvert.loadAllLocalFittings(directory: directory)
            XCTAssertEqual(result.unreadable.count, 1)
            XCTAssertEqual(result.fittings.count, 2)
            XCTAssertEqual(result.fittings.first { $0.fitting_id == sameShip.fitting_id }?.name, "Fit(1)")
            XCTAssertEqual(result.fittings.first { $0.fitting_id == otherShip.fitting_id }?.name, "Fit")
            XCTAssertEqual(try Data(contentsOf: unreadable), originalData)
        }
    }

}
