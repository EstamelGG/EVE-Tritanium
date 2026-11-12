import Foundation
import XCTest

@testable import EVE_Nexus

final class AvailableModelsAPITests: XCTestCase {
    func testDecodesAvailableTypeIDsArray() throws {
        let data = Data("[24566,24567,24568]".utf8)

        XCTAssertEqual(
            try AvailableModelsAPI.decodeAvailableModels(from: data),
            [24566, 24567, 24568]
        )
    }

    func testRejectsOldWrappedResponseFormat() {
        let data = Data(#"{"available":[24566]}"#.utf8)

        XCTAssertThrowsError(try AvailableModelsAPI.decodeAvailableModels(from: data))
    }
}
