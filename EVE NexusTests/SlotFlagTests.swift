import XCTest
@testable import EVE_Nexus

final class SlotFlagTests: XCTestCase {
    func testInventoryRangesAndRoundTrips() {
        let expected: [(SlotFlag, Int, Int)] = [
            (.low, 11, 18), (.medium, 19, 26), (.high, 27, 34),
            (.rig, 92, 99), (.subsystem, 125, 132),
            (.fighterTube, 159, 163), (.service, 164, 171),
        ]
        for (slot, first, last) in expected {
            XCTAssertEqual(slot.ids, first ... last)
            for id in first ... last {
                let index = id - first
                XCTAssertEqual(SlotFlag.location(for: id)?.slot, slot)
                XCTAssertEqual(SlotFlag.location(for: id)?.index, index)
                XCTAssertEqual(slot.id(at: index), id)
                let name = slot.name(at: index)!
                XCTAssertEqual(SlotFlag.location(for: name)?.slot, slot)
                XCTAssertEqual(SlotFlag.location(for: name)?.index, index)
            }
        }
    }

    func testFittingsSubsetAndVirtualSlots() {
        XCTAssertEqual(FittingFlag.fromInventorySlot(164), .serviceSlot0)
        XCTAssertEqual(FittingFlag.fromInventorySlot(171), .serviceSlot7)
        XCTAssertNil(FittingFlag.fromInventorySlot(95))
        XCTAssertNil(FittingFlag.fromInventorySlot(129))
        XCTAssertNil(FittingFlag.fromInventorySlot(159))
        XCTAssertEqual(SlotFlag.location(for: 95)?.slot, .rig)
        XCTAssertEqual(SlotFlag.location(for: 129)?.slot, .subsystem)
        XCTAssertNil(FittingFlag.t3dModeSlot0.inventorySlotID)
        XCTAssertNil(FittingFlag.cargo.inventorySlotID)
        for flag in FittingFlag.allCases {
            if let id = flag.inventorySlotID {
                XCTAssertEqual(FittingFlag.fromInventorySlot(id), flag)
            }
        }
    }

    func testInvalidIndicesNeverFallBackToSlotZero() {
        for slot in SlotFlag.allCases {
            XCTAssertNil(slot.id(at: -1))
            XCTAssertNil(slot.id(at: slot.ids.count))
            XCTAssertEqual(FittingFlag.slot(slot, index: -1), .invalid)
            XCTAssertEqual(FittingFlag.slot(slot, index: slot.fittingCount), .invalid)
        }
    }

    func testAssetGroupingAndAliases() {
        for index in 0 ... 7 {
            XCTAssertEqual(SlotFlag.assetGroup(for: "ServiceSlot\(index)"), "ServiceSlots")
            XCTAssertEqual(SlotFlag.assetGroup(for: "StructureServiceSlot\(index)"), "ServiceSlots")
        }
        XCTAssertEqual(SlotFlag.assetGroup(for: "SubSystem0"), "SubSystemSlots")
        for name in ["HiSlot99", "HiSlot-1", "HiSlot00", "ServiceSlots", "Cargo", "FutureFlag"] {
            XCTAssertEqual(SlotFlag.assetGroup(for: name), name)
        }
    }

    func testTataraServiceModulesRetainAllFivePositions() {
        let flags = (164 ... 168).compactMap(FittingFlag.fromInventorySlot)
        XCTAssertEqual(flags, [.serviceSlot0, .serviceSlot1, .serviceSlot2, .serviceSlot3, .serviceSlot4])
        XCTAssertEqual(flags.compactMap(\.inventorySlotID), Array(164 ... 168))
        XCTAssertNil(SlotFlag.location(for: 172))
        XCTAssertNil(SlotFlag.location(for: 180))
    }
}
