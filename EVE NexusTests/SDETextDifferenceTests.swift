import XCTest
@testable import EVE_Nexus

final class SDETextDifferenceTests: XCTestCase {
    func testTextAndUnchangedContextArePreserved() {
        let cases = [
            ("hello world", "hello EVE world"),
            ("需要50个材料", "需要30个材料"),
            ("👨‍👩‍👧你好", "👨‍👩‍👧您好"),
            ("a\nb\nc", "a\nB\nc"),
            ("", "new"), ("old", ""), ("same", "same"),
            ("<b>old</b>", "<b>new</b>"),
        ]
        for (before, after) in cases {
            let diff = SDETextDifference(old: before, new: after)
            XCTAssertEqual(diff.old.map(\.text).joined(), before)
            XCTAssertEqual(diff.new.map(\.text).joined(), after)
            XCTAssertEqual(diff.old.filter { !$0.changed }.map(\.text).joined(),
                           diff.new.filter { !$0.changed }.map(\.text).joined())
        }
    }

    func testSmallChangeInLongDescriptionStaysVisible() {
        let context = String(repeating: "相同内容", count: 300)
        let diff = SDETextDifference(old: context + "50" + context, new: context + "30" + context)
        XCTAssertEqual(diff.old.filter(\.changed).map(\.text).joined(), "5")
        XCTAssertEqual(diff.new.filter(\.changed).map(\.text).joined(), "3")
        let compact = SDETextDifference.compact(diff.new)
        XCTAssertLessThan(compact.map(\.text).joined().count, 200)
        XCTAssertEqual(compact.filter(\.changed), diff.new.filter(\.changed))
    }
}
