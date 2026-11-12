import XCTest
@testable import EVE_Nexus

@MainActor
final class StackedModuleSynchronizationTests: XCTestCase {
    private func module(
        flag: FittingFlag, status: Int, chargeType: Int? = nil,
        mutation: [Int: Double] = [:]
    ) -> SimModule {
        SimModule(
            typeId: 100, attributes: [:], attributesByName: [:], effects: [],
            groupID: 1, status: status,
            charge: chargeType.map {
                SimCharge(typeId: $0, attributes: [:], attributesByName: [:], effects: [],
                          groupID: 83, chargeQuantity: 40, requiredSkills: [],
                          name: "charge", iconFileName: nil)
            },
            flag: flag, quantity: 1, name: "module", requiredSkills: [],
            mutatedAttributes: mutation
        )
    }

    func testUsesFirstSlotRatherThanInputOrderAndKeepsChangesAfterExpanding() {
        var modules = [module(flag: .hiSlot1, status: 0, chargeType: 200),
                       module(flag: .hiSlot0, status: 3, chargeType: 201)]
        let identity = modules[0].instanceId
        XCTAssertTrue(FittingEditorViewModel.synchronizeStackedModules(&modules, slotTypes: [.hiSlots]))
        XCTAssertEqual(modules[0].status, 3)
        XCTAssertEqual(modules[0].charge?.typeId, 201)
        XCTAssertEqual(modules[0].charge?.chargeQuantity, 40)
        XCTAssertEqual(modules[0].instanceId, identity)
        XCTAssertNotEqual(modules[0].charge?.instanceId, modules[1].charge?.instanceId)

        XCTAssertFalse(FittingEditorViewModel.synchronizeStackedModules(&modules, slotTypes: []))
        XCTAssertEqual(modules[0].status, 3)
        XCTAssertEqual(modules[0].charge?.typeId, 201)
        XCTAssertFalse(FittingEditorViewModel.synchronizeStackedModules(&modules, slotTypes: [.hiSlots]))
    }

    func testFirstEmptyChargeUnloadsOtherModules() {
        var modules = [module(flag: .hiSlot0, status: 1),
                       module(flag: .hiSlot1, status: 2, chargeType: 200)]
        XCTAssertTrue(FittingEditorViewModel.synchronizeStackedModules(&modules, slotTypes: [.hiSlots]))
        XCTAssertNil(modules[1].charge)
        XCTAssertEqual(modules[1].status, 1)
    }

    func testMutatedModulesAndOtherSlotSectionsStayIndependent() {
        var modules = [module(flag: .hiSlot0, status: 3, chargeType: 201, mutation: [64: 2]),
                       module(flag: .hiSlot1, status: 1),
                       module(flag: .hiSlot2, status: 2, chargeType: 200),
                       module(flag: .medSlot0, status: 2, chargeType: 200)]
        XCTAssertTrue(FittingEditorViewModel.synchronizeStackedModules(&modules, slotTypes: [.hiSlots]))
        XCTAssertEqual(modules[0].status, 3)
        XCTAssertEqual(modules[0].charge?.typeId, 201)
        XCTAssertEqual(modules[2].status, 1)
        XCTAssertNil(modules[2].charge)
        XCTAssertEqual(modules[3].status, 2)
        XCTAssertEqual(modules[3].charge?.typeId, 200)
    }
}
