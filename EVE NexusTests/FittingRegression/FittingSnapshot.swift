import CryptoKit
import Foundation
import XCTest
import Zip
@testable import EVE_Nexus

/// Deliberately excludes instance UUIDs, localized display names, icons and timestamps.
struct FittingSnapshot: Codable {
    var schema = 1
    var sdeSHA256: String
    var fixturesSHA256: String
    var numbers: [String: Double] = [:]
    var labels: [String: String] = [:]

    static let absoluteTolerance = 1e-8
    static let relativeTolerance = 1e-9

    func differences(from expected: Self) -> [String] {
        var changes: [String] = []
        if schema != expected.schema { changes.append("snapshot schema changed") }
        if sdeSHA256 != expected.sdeSHA256 { changes.append("bundled SDE changed; review data changes before updating baseline") }
        if fixturesSHA256 != expected.fixturesSHA256 { changes.append("fixture inputs changed; review before updating baseline") }
        for key in Set(labels.keys).union(expected.labels.keys).sorted() where labels[key] != expected.labels[key] {
            changes.append("\(key): \(expected.labels[key] ?? "<missing>") -> \(labels[key] ?? "<missing>")")
        }
        for key in Set(numbers.keys).union(expected.numbers.keys).sorted() {
            guard let old = expected.numbers[key], let new = numbers[key] else {
                changes.append("\(key): \(expected.numbers[key].map(String.init(describing:)) ?? "<missing>") -> \(numbers[key].map(String.init(describing:)) ?? "<missing>")")
                continue
            }
            let tolerance = Self.absoluteTolerance + Self.relativeTolerance * max(abs(old), abs(new))
            if !old.isFinite || !new.isFinite || abs(new - old) > tolerance {
                changes.append("\(key): \(old) -> \(new) (delta \(new - old))")
            }
        }
        return changes
    }

    mutating func add(_ output: SimulationOutput, caseID: String) throws {
        func number(_ path: String, _ value: Double) throws {
            guard value.isFinite else { throw SnapshotError.invalid("\(caseID)/\(path) is not finite: \(value)") }
            numbers["\(caseID)/\(path)"] = value
        }
        func label(_ path: String, _ value: String) { labels["\(caseID)/\(path)"] = value }
        func attributes(_ path: String, _ ids: [Int: Double], _ names: [String: Double]) throws {
            for (id, value) in ids { try number("\(path)/attributes/\(id)", value) }
            // The UI reads the name index. Snapshot it too, to catch divergence from IDs.
            for (name, value) in names { try number("\(path)/byName/\(name)", value) }
        }
        func entity(_ path: String, _ type: Int, _ ids: [Int: Double], _ names: [String: Double]) throws {
            label("\(path)/typeID", String(type))
            try attributes(path, ids, names)
        }
        try entity("ship", output.ship.typeId, output.ship.attributes, output.ship.attributesByName)
        try attributes("character", output.ship.characterAttributes, output.ship.characterAttributesByName)
        for (skill, attrs) in output.characterSkillCalculatedAttributes {
            try attributes("skills/\(skill)", attrs, [:])
        }
        for (skill, level) in output.characterSkills { label("skills/\(skill)/level", String(level)) }
        var slots = Set<String>()
        for module in output.modules {
            let slot = try XCTUnwrap(module.flag?.rawValue, "Missing module slot in \(caseID)")
            guard slots.insert(slot).inserted else { throw SnapshotError.invalid("Duplicate slot: \(caseID)/\(slot)") }
            let path = "modules/\(slot)"
            try entity(path, module.typeId, module.attributes, module.attributesByName)
            label("\(path)/status", String(module.status))
            label("\(path)/quantity", String(module.quantity))
            label("\(path)/mutatedTypeID", module.mutatedTypeId.map(String.init) ?? "none")
            if let charge = module.charge {
                try entity("\(path)/charge", charge.typeId, charge.attributes, charge.attributesByName)
                label("\(path)/charge/quantity", charge.chargeQuantity.map(String.init) ?? "unspecified")
            }
            // Unit volley isolates magazine/cycle/reload behavior without duplicating UI weapon formulas.
            let cycle = (module.attributesByName["speed"] ?? 0) / 1000
            if cycle > 0 {
                try number("\(path)/unitVolleyDPSWithReload", FittingWeaponStatistics.dpsIncludingReload(volley: 1, cycle: cycle, module: module))
            }
        }
        // Array position is a stable persisted group identity (same type can have different mutations).
        for (index, drone) in output.drones.enumerated() {
            let path = "drones/\(index)"
            try entity(path, drone.typeId, drone.attributes, drone.attributesByName)
            label("\(path)/quantity", String(drone.quantity))
            label("\(path)/activeCount", String(drone.activeCount))
            label("\(path)/mutatedTypeID", drone.mutatedTypeId.map(String.init) ?? "none")
        }
        for (index, fighter) in (output.fighters ?? []).enumerated() {
            let path = "fighters/\(fighter.tubeId)/\(index)"
            try entity(path, fighter.typeId, fighter.attributes, fighter.attributesByName)
            label("\(path)/quantity", String(fighter.quantity))
        }
        for (index, implant) in output.implants.enumerated() {
            try entity("implants/\(index)", implant.typeId, implant.attributes, implant.attributesByName)
        }
        for (index, effect) in output.environmentEffects.enumerated() {
            try entity("environment/\(index)", effect.typeId, effect.attributes, effect.attributesByName)
        }
        for (index, item) in output.cargo.items.enumerated() {
            label("cargo/\(index)/typeID", String(item.typeId))
            label("cargo/\(index)/quantity", String(item.quantity))
            try number("cargo/\(index)/volume", item.volume)
        }
        let capacitor = FittingCapacitorCalculator().calculate(ship: output.ship, modules: output.modules)
        label("capacitor/isStable", String(capacitor.isStable))
        label("capacitor/reachedLimit", String(capacitor.reachedLimit))
        try number("capacitor/stableLevel", capacitor.stableLevel)
        try number("capacitor/delta", capacitor.delta)
        if capacitor.lastsTime == .infinity && capacitor.isStable {
            label("capacitor/lastsTime", "infinity")
        } else {
            try number("capacitor/lastsTime", capacitor.lastsTime)
        }
    }
}

enum SnapshotError: Error { case invalid(String) }

struct FittingRegressionFixture: Decodable {
    let id: String
    let scenario: String
    let kind: String
    let fitting: LocalFitting
}

/// Real bundled database and real editor pipeline, never a hand-written SDE adapter.
@MainActor
final class FittingRegressionData {
    struct Package: Decodable { let fixtures: [FittingRegressionFixture] }
    static let shared: Result<FittingRegressionData, Error> = Result { try FittingRegressionData() }
    let fixtures: [FittingRegressionFixture]
    let skills: [Int: Int]
    let sdeHash: String
    let fixtureHash: String
    private var outputs: [String: SimulationOutput] = [:]
    private(set) var inputs: [String: SimulationInput] = [:]
    private(set) var rejected: [String: [Int]] = [:]
    let db = DatabaseManager.shared

    static func resource(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle(for: FittingRegressionTests.self).url(forResource: name, withExtension: "json"), "Missing test resource \(name).json")
    }

    private init() throws {
        let fixtureData = try Data(contentsOf: Self.resource("FittingRegressionFixtures"))
        fixtures = try JSONDecoder().decode(Package.self, from: fixtureData).fixtures
        fixtureHash = Self.hash(fixtureData)
        let zipURL = try XCTUnwrap(Bundle.main.url(forResource: "sde", withExtension: "zip"))
        sdeHash = Self.hash(try Data(contentsOf: zipURL, options: .mappedIfSafe))
        // Unit-test host suppresses normal app startup. Re-seed every process: no OTA/user data dependency.
        let destination = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("sde")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Zip.unzipFile(zipURL, destination: destination, overwrite: true, password: nil)
        db.loadDatabase()
        guard SDEMemoryStore.types.count > 1000, !SDEMemoryStore.dogmaEffects.isEmpty else {
            throw SnapshotError.invalid("Bundled SDE failed to load")
        }
        skills = SDEMemoryStore.types.filter { $0.value.categoryID == 16 && $0.value.published }.mapValues { _ in 5 }
        guard skills.count > 400 else { throw SnapshotError.invalid("Missing all-5 skills") }
        guard fixtures.count == 48, Set(fixtures.map(\.id)).count == 48 else { throw SnapshotError.invalid("Fixture inventory changed") }
    }

    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    func emptySnapshot() -> FittingSnapshot { FittingSnapshot(sdeSHA256: sdeHash, fixturesSHA256: fixtureHash) }

    func fixture(_ id: String) throws -> FittingRegressionFixture {
        try XCTUnwrap(fixtures.first { $0.id == id }, "Unknown case \(id)")
    }

    func output(_ id: String) throws -> SimulationOutput {
        if let cached = outputs[id] { return cached }
        let fixture = try fixture(id)
        let model = FittingEditorViewModel(temporaryFitting: fixture.fitting, databaseManager: db, characterSkills: skills)
        rejected[id] = model.invalidModules.map { $0.module.typeId }.sorted()
        // output.originalInput is Step3's prepared graph, not the editor's raw input.
        inputs[id] = model.simulationInput
        let output = try XCTUnwrap(model.simulationOutput, "No result for \(id)")
        guard !output.ship.attributes.isEmpty else { throw SnapshotError.invalid("Empty result: \(id)") }
        outputs[id] = output
        return output
    }
}
