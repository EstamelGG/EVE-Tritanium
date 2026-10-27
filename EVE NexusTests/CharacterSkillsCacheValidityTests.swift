import Foundation
import XCTest
@testable import EVE_Nexus

final class CharacterSkillsCacheValidityTests: XCTestCase {
    private var directory: URL!
    private let modifiedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
        directory = nil
    }

    private func makeCache(contents: Data = Data("{}".utf8)) throws -> URL {
        let path = directory.appendingPathComponent("skills_bundle.json")
        try contents.write(to: path)
        try FileManager.default.setAttributes(
            [.modificationDate: modifiedAt], ofItemAtPath: path.path
        )
        return path
    }

    func testMissingCacheIsInvalid() {
        XCTAssertFalse(CharacterSkillsAPI.shared.isCacheFileValid(
            at: directory.appendingPathComponent("missing.json"), now: modifiedAt
        ))
    }

    func testTwoHourExpiryBoundary() throws {
        let path = try makeCache()
        for (age, expected) in [(0.0, true), (7_199.0, true), (7_200.0, true), (7_201.0, false)] {
            XCTAssertEqual(
                CharacterSkillsAPI.shared.isCacheFileValid(
                    at: path, now: modifiedAt.addingTimeInterval(age)
                ),
                expected,
                "Cache age: \(age) seconds"
            )
        }
    }

    func testFutureModificationDateRemainsValidAfterClockRollback() throws {
        let path = try makeCache()
        XCTAssertTrue(CharacterSkillsAPI.shared.isCacheFileValid(
            at: path, now: modifiedAt.addingTimeInterval(-3_600)
        ))
    }

    func testValidityDoesNotDecodeOrChangeCacheContents() throws {
        // The reported failure precedes JSON decoding; even malformed JSON must
        // be safe to inspect for expiry, leaving decoding to the caller.
        let contents = Data("not JSON".utf8)
        let path = try makeCache(contents: contents)
        XCTAssertTrue(CharacterSkillsAPI.shared.isCacheFileValid(at: path, now: modifiedAt))
        XCTAssertEqual(try Data(contentsOf: path), contents)
    }

    func testDefaultClockAcceptsRecentlyWrittenCache() throws {
        let path = directory.appendingPathComponent("recent.json")
        try Data("{}".utf8).write(to: path)
        XCTAssertTrue(CharacterSkillsAPI.shared.isCacheFileValid(at: path))
    }
}
