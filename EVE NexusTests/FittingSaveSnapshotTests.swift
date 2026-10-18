@testable import EVE_Nexus
import XCTest

final class FittingSaveSnapshotTests: XCTestCase {
    private func fitting() -> LocalFitting {
        let mutations = [
            MutationData(mutaplasmid_id: 100, attribute_id: 1, value: 1.15),
            MutationData(mutaplasmid_id: 100, attribute_id: 2, value: 0.8),
        ]
        return LocalFitting(
            description: "Description", fitting_id: UUID(),
            items: [
                LocalFittingItem(flag: .hiSlot0, quantity: 1, type_id: 10, status: 2,
                                 charge_type_id: 20, charge_quantity: 30, muta: mutations, spool_up_full: false),
                LocalFittingItem(flag: .loSlot0, quantity: 1, type_id: 11, status: 1),
            ],
            name: "Snapshot", ship_type_id: 587,
            drones: [Drone(type_id: 40, quantity: 5, active_count: 3, muta: mutations),
                     Drone(type_id: 41, quantity: 2, active_count: 1, muta: nil)],
            fighters: [FighterSquad(type_id: 50, quantity: 9, tubeId: 0), FighterSquad(type_id: 51, quantity: 3, tubeId: 200)],
            cargo: [CargoItem(type_id: 60, quantity: 100), CargoItem(type_id: 61, quantity: 200)],
            implants: [70, 71], environment_type_id: 80
        )
    }

    private func changed(_ fitting: LocalFitting, path: [String], value: Any) throws -> LocalFitting {
        func replace(_ object: Any, path: ArraySlice<String>) -> Any {
            guard let key = path.first else { return value }
            if var array = object as? [Any], let index = Int(key) {
                array[index] = replace(array[index], path: path.dropFirst())
                return array
            }
            var dictionary = object as! [String: Any]
            dictionary[key] = replace(dictionary[key] ?? NSNull(), path: path.dropFirst())
            return dictionary
        }
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(fitting))
        return try JSONDecoder().decode(LocalFitting.self, from: JSONSerialization.data(withJSONObject: replace(object, path: path[...])))
    }

    func testEveryPersistedContentFieldAffectsSnapshot() throws {
        let fitting = fitting()
        let baseline = try FittingSaveSnapshot(fitting)
        let changes: [(String, Any)] = [
            ("name", "Renamed"), ("description", "Changed"), ("ship_type_id", 588),
            ("items.0.flag", "HiSlot1"), ("items.0.quantity", 2), ("items.0.type_id", 12),
            ("items.0.status", 0), ("items.0.charge_type_id", 21), ("items.0.charge_quantity", 31),
            ("items.0.spool_up_full", true), ("items.0.muta.0.value", 1.2),
            ("items.0.muta.0.attribute_id", 3), ("items.0.muta.0.mutaplasmid_id", 101),
            ("drones.0.type_id", 42), ("drones.0.quantity", 6), ("drones.0.active_count", 4),
            ("drones.0.muta.0.value", 1.2), ("fighters.0.type_id", 52),
            ("fighters.0.quantity", 8), ("fighters.0.tubeId", 1),
            ("cargo.0.type_id", 62), ("cargo.0.quantity", 101), ("implants.0", 72),
            ("environment_type_id", 81),
        ]
        for (path, value) in changes {
            let changed = try changed(fitting, path: path.components(separatedBy: "."), value: value)
            XCTAssertNotEqual(try FittingSaveSnapshot(changed), baseline, path)
        }
    }

    func testIdentityAndListOrderingDoNotAffectSnapshot() throws {
        let original = fitting()
        var reordered = original.duplicated(newId: UUID(), name: original.name)
        for field in ["items", "drones", "fighters", "cargo", "implants"] {
            let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(reordered)) as? [String: Any])
            reordered = try changed(reordered, path: [field], value: Array(XCTUnwrap((object[field] as? [Any])?.reversed())))
        }
        reordered = try changed(reordered, path: ["items", "1", "muta"], value: [
            ["mutaplasmid_id": 100, "attribute_id": 2, "value": 0.8],
            ["mutaplasmid_id": 100, "attribute_id": 1, "value": 1.15],
        ])
        XCTAssertEqual(try FittingSaveSnapshot(original), try FittingSaveSnapshot(reordered))
        let duplicate = try changed(original, path: ["implants"], value: [70, 71, 71])
        XCTAssertNotEqual(try FittingSaveSnapshot(original), try FittingSaveSnapshot(duplicate))
    }

    func testEmptyOptionalListsMatchMissingLists() throws {
        let empty = LocalFitting(description: "", fitting_id: UUID(), items: [], name: "Empty", ship_type_id: 587)
        var explicitEmpty = empty
        for key in ["drones", "fighters", "cargo", "implants"] {
            explicitEmpty = try changed(explicitEmpty, path: [key], value: [Any]())
        }
        XCTAssertEqual(try FittingSaveSnapshot(empty), try FittingSaveSnapshot(explicitEmpty))
    }
}
