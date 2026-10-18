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
            XCTAssertEqual(remainingShip?.id, ship?.id, "删除装配不能改变飞船 section 的身份")
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
    func testSectionSelectAllPreservesOtherShipsAndDistinctFittingIDs() {
        let first = FittingItemNode(ref: .local(UUID()), name: "Same name", shipTypeId: 1)
        let second = FittingItemNode(ref: .local(UUID()), name: "Same name", shipTypeId: 1)
        let other = FittingItemNode(ref: .online(1), name: "Same name", shipTypeId: 2)
        var selection = FittingCatalogSelection(refs: [first.ref, other.ref])

        selection.toggleAll(in: [first, second])
        XCTAssertEqual(selection.refs, [first.ref, second.ref, other.ref], "部分选中时，全选只补齐当前飞船")
        selection.toggleAll(in: [first, second])
        XCTAssertEqual(selection.refs, [other.ref], "取消全选不能影响其他飞船")
        selection.toggleAll(in: [first, second])
        selection.retainVisible([second.ref, other.ref])
        XCTAssertEqual(selection.refs, [second.ref, other.ref], "删除或刷新后应清除已消失装配的选择")
    }

    func testSectionSelectionDoesNotMixSourcesOrSelectOtherShip() {
        let local = FittingItemNode(ref: .local(UUID()), name: "Fit", shipTypeId: 1)
        let online = FittingItemNode(ref: .online(1), name: "Fit", shipTypeId: 2)
        var selection = FittingCatalogSelection()
        selection.toggleAll(in: [local])
        XCTAssertEqual(selection.refs, [local.ref])
        selection.toggleAll(in: [online])
        XCTAssertEqual(selection.refs, [local.ref, online.ref])
        selection.retainVisible([online.ref])
        XCTAssertEqual(selection.refs, [online.ref])
    }

}
