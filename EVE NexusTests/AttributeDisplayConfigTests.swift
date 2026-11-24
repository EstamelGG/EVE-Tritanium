import XCTest
@testable import EVE_Nexus

final class AttributeDisplayConfigTests: XCTestCase {
    override func tearDown() {
        AttributeDisplayConfig.initializeUnits(with: [:])
        super.tearDown()
    }

    func testHardpointAndLevelUnitsAreHidden() {
        AttributeDisplayConfig.initializeUnits(with: [
            101: "hardpoints",
            102: "hardpoints",
            280: "Level",
            422: "Level",
        ])

        assertNumberWithoutUnit(
            AttributeDisplayConfig.transformValue(
                101,
                allAttributes: [101: 4],
                unitID: 141
            ),
            expectedValue: 4
        )
        assertNumberWithoutUnit(
            AttributeDisplayConfig.transformValue(
                102,
                allAttributes: [102: 6],
                unitID: 141
            ),
            expectedValue: 6
        )
        assertNumberWithoutUnit(
            AttributeDisplayConfig.transformValue(
                422,
                allAttributes: [422: 2],
                unitID: 140
            ),
            expectedValue: 2
        )
        assertNumberWithoutUnit(
            AttributeDisplayConfig.transformValue(
                280,
                allAttributes: [280: 5],
                unitID: nil
            ),
            expectedValue: 5
        )
    }

    func testOtherAttributeUnitsRemainVisible() {
        AttributeDisplayConfig.initializeUnits(with: [37: "m"])

        guard case let .number(value, unit) = AttributeDisplayConfig.transformValue(
            37,
            allAttributes: [37: 1_250],
            unitID: 1
        ) else {
            return XCTFail("Expected numeric transformed value")
        }

        XCTAssertEqual(value, 1_250)
        XCTAssertEqual(unit, " m")
    }

    private func assertNumberWithoutUnit(
        _ result: AttributeDisplayConfig.TransformResult,
        expectedValue: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .number(value, unit) = result else {
            return XCTFail("Expected numeric transformed value", file: file, line: line)
        }

        XCTAssertEqual(value, expectedValue, file: file, line: line)
        XCTAssertNil(unit, file: file, line: line)
    }
}
