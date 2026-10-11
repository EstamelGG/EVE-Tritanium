import XCTest
@testable import EVE_Nexus

final class FittingNavigationTests: XCTestCase {
    func testShipIdentityRemainsStableAcrossFittingCountChanges() {
        for refs: [FittingRef] in [[.local(UUID()), .local(UUID())], [.online(1), .online(2)]] {
            let first = FittingItemNode(ref: refs[0], name: "A", shipTypeId: 1)
            let second = FittingItemNode(ref: refs[1], name: "B", shipTypeId: 1)
            let other = FittingItemNode(ref: .online(3), name: "Other", shipTypeId: 2)
            let info = FittingShipInfo(names: .filled(with: "Ship"), iconFileName: "")
            func tree(_ items: [FittingItemNode]) -> [FittingGroupNode] {
                FittingTreeBuilder.build(
                    items: items, shipInfo: [1: info, 2: info],
                    groupByType: [1: (1, "Group"), 2: (1, "Group")]
                )
            }

            let multiple = tree([second, first, other])
            let ship = multiple.flatMap(\.children).first { $0.typeId == 1 }
            XCTAssertEqual(ship?.fittings, [first, second])
            let single = tree([second, other])
            let remainingShip = single.flatMap(\.children).first { $0.typeId == 1 }
            XCTAssertEqual(remainingShip?.id, ship?.id, "删除装配不能改变飞船行身份和展开状态")
            XCTAssertEqual(remainingShip?.fittings, [second])
            XCTAssertEqual(single.first?.fittingCount, 2)
            XCTAssertEqual(
                FittingTreeBuilder.searchMatches(tree: single, shipInfo: [1: info, 2: info], query: "B"),
                [second]
            )
            XCTAssertFalse(tree([other]).flatMap(\.children).contains { $0.typeId == 1 })
            XCTAssertTrue(tree([]).isEmpty)
        }
    }
}
