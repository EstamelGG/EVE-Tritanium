@testable import EVE_Nexus
import XCTest

@MainActor
final class FittingRegressionTests: XCTestCase {
    private func data() throws -> FittingRegressionData {
        try FittingRegressionData.shared.get()
    }

    private func check(_ scenario: String) throws {
        let data = try data()
        let fixtures = data.fixtures.filter { $0.scenario == scenario }
        XCTAssertFalse(fixtures.isEmpty)
        var snapshot = data.emptySnapshot()
        for fixture in fixtures {
            let output = try data.output(fixture.id)
            try snapshot.add(output, caseID: fixture.id)
            snapshot.labels["\(fixture.id)/rejectedTypes"] = (data.rejected[fixture.id] ?? []).map(String.init).joined(separator: ",")
            if fixture.kind == "positive" {
                XCTAssertEqual(data.rejected[fixture.id], [], "Positive fixture rejected modules: \(fixture.id)")
                XCTAssertEqual(output.modules.count, fixture.fitting.items.count, "Module loss: \(fixture.id)")
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let encoded = try encoder.encode(snapshot)
        let name = "FittingSnapshot-\(scenario)"
        let attachment = XCTAttachment(data: encoded, uniformTypeIdentifier: "public.json")
        attachment.name = name + "-actual.json"
        attachment.lifetime = .keepAlways
        add(attachment)
        if let candidate = ProcessInfo.processInfo.environment["EVE_FITTING_CANDIDATE_DIR"] {
            // Explicit candidate capture only. This never overwrites the checked-in expected result.
            let directory = URL(fileURLWithPath: candidate, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try encoded.write(to: directory.appendingPathComponent(name + ".json"), options: .atomic)
            return
        }
        let expected = try JSONDecoder().decode(FittingSnapshot.self, from: Data(contentsOf: FittingRegressionData.resource(name)))
        let changes = snapshot.differences(from: expected)
        if !changes.isEmpty {
            let report = XCTAttachment(string: changes.joined(separator: "\n"))
            report.name = name + "-diff.txt"
            report.lifetime = .keepAlways
            add(report)
            XCTFail("\(scenario): \(changes.count) differences. Full actual/diff attached.\n" + changes.prefix(30).joined(separator: "\n"))
        }
    }

    func testAttributeTracesMatchEveryDisplayedInstance() throws {
        let data = try data()
        var checked = 0
        for fixture in data.fixtures {
            let output = try data.output(fixture.id)
            var values: [UUID: [Int: Double]] = [output.originalInput.ship.instanceId: output.ship.attributes]
            for module in output.modules {
                values[module.instanceId] = module.attributes
                if let charge = module.charge { values[charge.instanceId] = charge.attributes }
            }
            for drone in output.drones { values[drone.instanceId] = drone.attributes }
            for fighter in output.fighters ?? [] { values[fighter.instanceId] = fighter.attributes }
            for (id, attributes) in output.attributeTraces {
                for (attributeID, trace) in attributes {
                    var previous = trace.baseValue
                    for step in trace.steps {
                        XCTAssertEqual(step.before, previous, accuracy: 1e-9, "Broken trace: \(fixture.id)/\(attributeID)")
                        previous = step.after
                    }
                    XCTAssertEqual(previous, trace.finalValue, accuracy: 1e-9)
                    if let final = values[id]?[attributeID] {
                        XCTAssertEqual(trace.finalValue, final, accuracy: 1e-9, "Wrong final: \(fixture.id)/\(attributeID)")
                        checked += 1
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 0)
    }

    func testS01WeaponsAndStates() throws {
        try check("S01")
    }

    func testS02CapacitorCycles() throws {
        try check("S02")
    }

    func testS03RepairAndMutation() throws {
        try check("S03")
    }

    func testS04PropulsionAndElectronicWarfare() throws {
        try check("S04")
    }

    func testS05Drones() throws {
        try check("S05")
    }

    func testS06ImplantsAndEnvironment() throws {
        try check("S06")
    }

    func testS07Subsystems() throws {
        try check("S07")
    }

    func testS08TacticalModes() throws {
        try check("S08")
    }

    func testS09WeaponSpool() throws {
        try check("S09")
    }

    func testS10RemoteRepair() throws {
        try check("S10")
    }

    func testS11Bastion() throws {
        try check("S11")
    }

    func testS12Siege() throws {
        try check("S12")
    }

    func testS13Fighters() throws {
        try check("S13")
    }

    func testS14CommandBursts() throws {
        try check("S14")
    }

    func testRemovingCommandProcessorRevalidatesBurstLimits() throws {
        let data = try data()
        let fixture = try data.fixture("S14-A重复效果")
        let fitting = LocalFitting(
            description: "", fitting_id: UUID(),
            items: fixture.fitting.items + [LocalFittingItem(
                flag: .hiSlot3, quantity: 1, type_id: 43554, status: 2,
                charge_type_id: 42835, charge_quantity: 300
            )],
            name: "CommandProcessorTest", ship_type_id: fixture.fitting.ship_type_id
        )
        let editor = FittingEditorViewModel(temporaryFitting: fitting, databaseManager: data.db, characterSkills: data.skills)
        let savedURL = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
            .appendingPathComponent("Fitting/local_fitting_\(fitting.fitting_id.uuidString).json")
        defer { try? FileManager.default.removeItem(at: savedURL) }
        let burstGroup = try XCTUnwrap(editor.simulationInput.modules.first { $0.flag == .hiSlot0 }?.groupID)
        XCTAssertEqual(editor.simulationInput.modules.filter { $0.groupID == burstGroup && $0.status > 0 }.count, 4)

        editor.removeModule(flag: .rigSlot0)

        let bursts = editor.simulationInput.modules.filter { $0.groupID == burstGroup }
        XCTAssertEqual(bursts.count, 4, "超限装备应保留在槽位中")
        XCTAssertEqual(bursts.filter { $0.status > 0 }.count, 3)
        XCTAssertEqual(bursts.first { $0.flag == .hiSlot3 }?.status, 0)
        let output = try XCTUnwrap(editor.simulationOutput)
        XCTAssertEqual(output.modules.first { $0.flag == .hiSlot3 }?.status, 0)
        let saved = try FitConvert.loadLocalFitting(fittingId: fitting.fitting_id)
        XCTAssertEqual(saved.items.first { $0.flag == .hiSlot3 }?.status, 0)

        // 自动降级后的结果应与以最终状态重新打开装配完全一致。
        let reloaded = FittingEditorViewModel(temporaryFitting: saved, databaseManager: data.db, characterSkills: data.skills)
        XCTAssertEqual(output.ship.attributes, reloaded.simulationOutput?.ship.attributes)
    }

    func testS15Industrial() throws {
        try check("S15")
    }

    func testS16Cargo() throws {
        try check("S16")
    }

    func testS17Bombs() throws {
        try check("S17")
    }

    func testS18BurstProjectors() throws {
        try check("S18")
    }

    func testS19StructureServiceBoundary() throws {
        try check("S19")
    }

    func testS20InvalidFittings() throws {
        try check("S20")
    }

    func testInfiniteReserveAndRealSupplyCycles() throws {
        let data = try data()
        func cap(_ id: String) throws -> FittingCapacitorCalculator.Result {
            let output = try data.output(id)
            return FittingCapacitorCalculator().calculate(ship: output.ship, modules: output.modules)
        }
        XCTAssertEqual(try cap("S02-A双供能"), try cap("S02-E零备用"), "Reserve cargo must not limit injection")
        XCTAssertGreaterThan(try cap("S02-B只吸电").lastsTime, try cap("S02-D无供能").lastsTime)
        XCTAssertGreaterThan(try cap("S02-C只注电").lastsTime, try cap("S02-D无供能").lastsTime)
        let output = try data.output("S02-A双供能")
        let cycles = FittingCapacitorCalculator.makeInput(ship: output.ship, modules: output.modules).cycles
        XCTAssertTrue(cycles.contains { $0.gain > 0 && $0.shotsPerReload > 0 && $0.reloadTime > 0 })
        XCTAssertTrue(cycles.contains { $0.gain > 0 && $0.shotsPerReload == 0 && $0.duration > 0 })
    }

    func testSpoolChangesChargeDamage() throws {
        let data = try data()
        let cold = try data.output("S09-A未预热")
        let hot = try data.output("S09-B完全预热")
        let before = try XCTUnwrap(cold.modules.first { $0.attributesByName["damageMultiplierBonusMax"] != nil })
        let after = try XCTUnwrap(hot.modules.first { $0.flag == before.flag })
        let factor = try 1 + XCTUnwrap(before.attributesByName["damageMultiplierBonusMax"])
        XCTAssertGreaterThan(factor, 1)
        let oldDamage = try XCTUnwrap(before.charge?.attributesByName["thermalDamage"])
        let newDamage = try XCTUnwrap(after.charge?.attributesByName["thermalDamage"])
        XCTAssertEqual(newDamage, oldDamage * factor, accuracy: 1e-8)
    }

    func testNegativeCasesHaveExplicitExpectations() throws {
        let data = try data()
        let incompatible = try data.fixture("S20-N1不兼容")
        _ = try data.output(incompatible.id)
        XCTAssertEqual(data.rejected[incompatible.id], incompatible.fitting.items.map(\.type_id).sorted())
        let duplicate = try data.output("S20-N2同组超限")
        XCTAssertEqual(duplicate.modules.count, 2, "Group overflow must retain fitted modules")
        XCTAssertEqual(duplicate.modules.filter { $0.status > 0 }.count, 1)
        XCTAssertEqual(duplicate.modules.first { $0.flag == .loSlot0 }?.status, 1)
        XCTAssertEqual(duplicate.modules.first { $0.flag == .loSlot1 }?.status, 0)
        let overloaded = try data.output("S20-N3资源超限")
        let usedPower = overloaded.modules.filter { $0.status > 0 }.reduce(0) { $0 + ($1.attributesByName["power"] ?? 0) }
        XCTAssertGreaterThan(usedPower, try XCTUnwrap(overloaded.ship.attributesByName["powerOutput"]))
    }

    func testReusedCalculatorMatchesFreshEditorInReverseOrder() throws {
        let data = try data()
        let calculator = AttributeCalculator(databaseManager: data.db)
        // All cases, including mutation, mode switching and same-type modules; re-use one calculator.
        for fixture in data.fixtures.reversed() {
            let expected = try data.output(fixture.id)
            let actual = try calculator.calculateAndGenerateOutput(input: XCTUnwrap(data.inputs[fixture.id]))
            var old = data.emptySnapshot()
            var new = data.emptySnapshot()
            try old.add(expected, caseID: fixture.id)
            try new.add(actual, caseID: fixture.id)
            XCTAssertTrue(new.differences(from: old).isEmpty, "State leaked across fittings: \(fixture.id)\n" + new.differences(from: old).prefix(10).joined(separator: "\n"))
        }
    }

    func testComparatorDetectsChangesAdditionsRemovalsAndNonFiniteNumbers() {
        var expected = FittingSnapshot(sdeSHA256: "sde", fixturesSHA256: "fixtures")
        expected.numbers = ["ship/mass": 100, "module/power": 10]
        expected.labels = ["module/status": "2"]
        var actual = expected
        actual.numbers["ship/mass"] = 100 + 1e-9
        XCTAssertTrue(actual.differences(from: expected).isEmpty)
        actual.numbers["ship/mass"] = 101
        actual.numbers.removeValue(forKey: "module/power")
        actual.numbers["charge/damage"] = 5
        actual.labels["module/status"] = "0"
        XCTAssertEqual(actual.differences(from: expected).count, 4)
        actual = expected
        actual.numbers["ship/mass"] = .nan
        XCTAssertEqual(actual.differences(from: expected).count, 1)
        actual = expected
        actual.sdeSHA256 = "updated"
        XCTAssertEqual(actual.differences(from: expected).count, 1)
    }

    func testMissingTacticalModeLoadsDefaultMode() throws {
        let data = try FittingRegressionData.shared.get()
        let reference = try data.fixture("S08-Defense").fitting
        XCTAssertNotNil(ModeSwitchingUtils.getDefaultModeId(for: reference.ship_type_id, databaseManager: data.db))
        let fitting = LocalFitting(description: "probe", fitting_id: UUID(), items: [], name: "probe",
                                   ship_type_id: reference.ship_type_id)
        let input = FitConvert.localFittingToSimulationInput(localFitting: fitting, databaseManager: data.db,
                                                             characterSkills: data.skills)
        XCTAssertEqual(input.modules.filter { $0.flag == .t3dModeSlot0 }.count, 1)
        let mode = try XCTUnwrap(input.modules.first { $0.flag == .t3dModeSlot0 })
        XCTAssertFalse(mode.attributes.isEmpty)
        XCTAssertFalse(mode.effects.isEmpty)
        XCTAssertEqual(mode.typeId, ModeSwitchingUtils.getDefaultModeId(for: reference.ship_type_id, databaseManager: data.db))
        let explicit = LocalFitting(description: "explicit", fitting_id: UUID(), items: [
            LocalFittingItem(flag: .t3dModeSlot0, quantity: 1, type_id: mode.typeId),
        ], name: "explicit", ship_type_id: reference.ship_type_id)
        let explicitInput = FitConvert.localFittingToSimulationInput(localFitting: explicit, databaseManager: data.db, characterSkills: data.skills)
        let calculator = AttributeCalculator(databaseManager: data.db)
        XCTAssertEqual(calculator.calculateAndGenerateOutput(input: input).ship.attributes,
                       calculator.calculateAndGenerateOutput(input: explicitInput).ship.attributes)
    }

    func testExplicitOnlineStateSurvivesNativeRoundTrip() throws {
        let data = try FittingRegressionData.shared.get()
        _ = try data.output("S04-A加力")
        var input = try XCTUnwrap(data.inputs["S04-A加力"])
        let index = try XCTUnwrap(input.modules.firstIndex { $0.effects.contains(6730) })
        for status in 0 ... 3 {
            input.modules[index] = input.modules[index].withStatus(status)
            let saved = FitConvert.simulationInputToLocalFitting(input: input)
            XCTAssertEqual(saved.items.first { $0.flag == input.modules[index].flag }?.status, status)
            let encoded = try JSONEncoder().encode(saved)
            let decoded = try JSONDecoder().decode(LocalFitting.self, from: encoded)
            let reloaded = FitConvert.localFittingToSimulationInput(localFitting: decoded, databaseManager: data.db,
                                                                    characterSkills: data.skills)
            XCTAssertEqual(reloaded.modules.first { $0.flag == input.modules[index].flag }?.status, status)
        }
    }

    func testRepairSpoolChangesOnlyRemoteRepairAmountAndRoundTrips() throws {
        let data = try data()
        let cold = try data.output("S10-A未预热")
        let hot = try data.output("S10-B完全预热")
        let coldModule = try XCTUnwrap(cold.modules.first { $0.flag == .hiSlot0 })
        let hotModule = try XCTUnwrap(hot.modules.first { $0.flag == .hiSlot0 })
        let amount = try XCTUnwrap(coldModule.attributes[84])
        let bonus = try XCTUnwrap(hotModule.attributes[2797])
        XCTAssertGreaterThan(bonus, 0)
        XCTAssertEqual(try XCTUnwrap(hotModule.attributes[84]), amount * (1 + bonus), accuracy: 1e-8)
        XCTAssertEqual(hotModule.attributes[84], hotModule.attributesByName["armorDamageAmount"])
        var unspooled = hotModule.attributes
        unspooled[84] = amount
        XCTAssertEqual(unspooled, coldModule.attributes, "Spool must not change capacitor need, cycle or range")
        XCTAssertEqual(hot.ship.attributes, cold.ship.attributes, "Remote repair must not change local tank")
        for module in cold.modules where module.flag != .hiSlot0 {
            XCTAssertEqual(module.attributes, hot.modules.first { $0.flag == module.flag }?.attributes)
        }
        for id in ["S10-A未预热", "S10-B完全预热"] {
            let input = try XCTUnwrap(data.inputs[id])
            let module = try XCTUnwrap(input.modules.first { $0.flag == .hiSlot0 })
            XCTAssertTrue(module.supportsSpoolUp, "The repairer must expose the spool toggle")
            XCTAssertFalse(try XCTUnwrap(input.modules.first { $0.flag == .hiSlot1 }).supportsSpoolUp)
            let saved = FitConvert.simulationInputToLocalFitting(input: input)
            let decoded = try JSONDecoder().decode(LocalFitting.self, from: JSONEncoder().encode(saved))
            let reloaded = FitConvert.localFittingToSimulationInput(localFitting: decoded, databaseManager: data.db, characterSkills: data.skills)
            XCTAssertEqual(reloaded.modules.first { $0.flag == .hiSlot0 }?.isSpoolUpFull, module.isSpoolUpFull)
        }
    }

    func testFighterFixtureTubeTypesAndSquadronLimits() throws {
        let data = try data()
        for fixture in data.fixtures.filter({ $0.scenario == "S13" }) {
            let output = try data.output(fixture.id)
            let fighters = output.fighters ?? []
            XCTAssertEqual(Set(fighters.map(\.tubeId)).count, fighters.count)
            XCTAssertLessThanOrEqual(fighters.count, Int(output.ship.attributesByName["fighterTubes"] ?? 0))
            for fighter in fighters {
                let expectedGroup = fighter.tubeId < 100 ? 1652 : (fighter.tubeId < 200 ? 1653 : 1537)
                XCTAssertEqual(fighter.groupID, expectedGroup, "Wrong tube type: \(fixture.id)/\(fighter.tubeId)")
                XCTAssertLessThanOrEqual(fighter.quantity, Int(fighter.attributesByName["fighterSquadronMaxSize"] ?? 0))
            }
            for (range, key) in [(0 ..< 100, "fighterLightSlots"), (100 ..< 200, "fighterHeavySlots"), (200 ..< 300, "fighterSupportSlots")] {
                XCTAssertLessThanOrEqual(fighters.filter { range.contains($0.tubeId) }.count,
                                         Int(output.ship.attributesByName[key] ?? 0))
            }
        }
    }

    func testSkillTemplatesDoNotRetainLevelOrOverrides() throws {
        let data = try data()
        _ = try data.output("S01-A")
        var input = try XCTUnwrap(data.inputs["S01-A"])
        input.characterSkills = [3300: 5]
        let step = Step3(databaseManager: data.db)
        func skill(_ input: SimulationInput) throws -> SimSkill {
            try XCTUnwrap(step.process(input: input, attributeModifiers: AttributeModifiers()).skills.first)
        }
        let original = try skill(input)
        input.characterSkills[3300] = 0
        input.characterSkillAttributes[3300] = [900_111: 42]
        input.characterSkillAttributesByName[3300] = ["testOverride": 42]
        let overridden = try skill(input)
        XCTAssertEqual(overridden.attributes[280], 0)
        XCTAssertEqual(overridden.attributes[900_111], 42)
        input.characterSkills[3300] = 5
        input.characterSkillAttributes = [:]
        input.characterSkillAttributesByName = [:]
        let restored = try skill(input)
        XCTAssertEqual(restored.attributes, original.attributes)
        XCTAssertEqual(restored.attributesByName, original.attributesByName)
        XCTAssertTrue(restored.attributeModifiers.isEmpty)
        XCTAssertNotEqual(restored.instanceId, original.instanceId)
    }

    func testSkillTemplatesInvalidateAfterSDEReload() throws {
        let data = try data()
        _ = try data.output("S01-A")
        var input = try XCTUnwrap(data.inputs["S01-A"])
        input.characterSkills = [3300: 5]
        let range = try XCTUnwrap(SDEMemoryStore.typeAttrRanges[3300])
        let index = try XCTUnwrap(range.first { SDEMemoryStore.typeAttrIDs[$0] != 280 })
        let attribute = Int(SDEMemoryStore.typeAttrIDs[index])
        let original = SDEMemoryStore.typeAttrValues[index]
        // Warm the template with a different SDE value, then reload the bundled database.
        // The process is isolated to the unit-test host; no database file is modified.
        SDEMemoryStore.typeAttrValues[index] = original + 123
        defer { SDEMemoryStore.typeAttrValues[index] = original }
        let step = Step3(databaseManager: data.db)
        let before = step.process(input: input, attributeModifiers: AttributeModifiers())
        XCTAssertEqual(before.skills.first?.attributes[attribute], original + 123)
        let generation = SDEMemoryStore.generation
        data.db.loadDatabase()
        XCTAssertNotEqual(SDEMemoryStore.generation, generation)
        let after = step.process(input: input, attributeModifiers: AttributeModifiers())
        XCTAssertEqual(after.skills.first?.attributes[attribute], original)
    }

    func testOnlineAutosavesUpdateOneLocalCopy() throws {
        let data = try data()
        let name = "OnlineAutosaveTest-\(UUID().uuidString)"
        let online = CharacterFitting(
            description: "", fitting_id: 123,
            items: [FittingItem(flag: .medSlot0, quantity: 1, type_id: 35656)],
            name: name, ship_type_id: 47466
        )
        let editor = FittingEditorViewModel(onlineFitting: online, databaseManager: data.db, characterSkills: data.skills)
        let directory = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
            .appendingPathComponent("Fitting")
        defer {
            // 仅清理本测试随机命名的副本，不影响其他装配。
            if let result = try? FitConvert.loadAllLocalFittings() {
                for fitting in result.fittings where fitting.name == name {
                    try? FileManager.default.removeItem(at: directory.appendingPathComponent("local_fitting_\(fitting.fitting_id.uuidString).json"))
                }
            }
        }
        XCTAssertTrue(editor.simulationInput.modules.contains { $0.typeId == 35656 })
        var savedId: UUID?
        for status in [1, 2, 0, 2, 1] {
            editor.updateModuleStatus(flag: .medSlot0, newStatus: status)
            let copies = try FitConvert.loadAllLocalFittings().fittings.filter { $0.name == name }
            XCTAssertEqual(copies.count, 1)
            let copy = try XCTUnwrap(copies.first)
            if let savedId { XCTAssertEqual(copy.fitting_id, savedId) }
            savedId = copy.fitting_id
            XCTAssertEqual(copy.items.first { $0.type_id == 35656 }?.status, status)
            XCTAssertEqual(editor.simulationInput.fittingId, .online(123))
            XCTAssertFalse(editor.isLocalFitting)
            XCTAssertFalse(editor.hasUnsavedChanges)
        }
    }

    func testImportsKeepDefaultActivationForUnspecifiedStates() throws {
        let data = try data()
        let dna = try XCTUnwrap(DNAParser.parseDNA("fitting:47466:35656;1:"))
        let dnaFitting = try XCTUnwrap(DNAParser.dnaResultToLocalFitting(dna, databaseManager: data.db))
        let offlineDNA = try XCTUnwrap(DNAParser.parseDNA("fitting:47466:35656;1_:"))
        let offlineFitting = try XCTUnwrap(DNAParser.dnaResultToLocalFitting(offlineDNA, databaseManager: data.db))
        let offlineInput = FitConvert.localFittingToSimulationInput(localFitting: offlineFitting, databaseManager: data.db, characterSkills: data.skills)
        XCTAssertEqual(offlineInput.modules.first { $0.typeId == 35656 }?.status, 0)
        let eftFitting = try FitConvert.eftToLocalFitting(eftText: "[Praxis, Default state]\n10MN Y-S8 Compact Afterburner\n", databaseManager: data.db)
        let online = OnlineFitting(
            description: "", fitting_id: 1,
            items: [
                FittingItem(flag: .medSlot0, quantity: 1, type_id: 35656),
                FittingItem(flag: .loSlot0, quantity: 1, type_id: 2048),
            ],
            name: "Default state", ship_type_id: 47466
        )
        let onlineFitting = try XCTUnwrap(FitConvert.online2local(jsonData: JSONEncoder().encode([online])).first)
        XCTAssertTrue(onlineFitting.items.allSatisfy { $0.status == nil })
        let onlineInput = FitConvert.localFittingToSimulationInput(localFitting: onlineFitting, databaseManager: data.db, characterSkills: data.skills)
        XCTAssertEqual(onlineInput.modules.first { $0.typeId == 2048 }?.status, 1)
        for fitting in [dnaFitting, eftFitting, onlineFitting] {
            let module = try XCTUnwrap(fitting.items.first { $0.type_id == 35656 })
            XCTAssertNil(module.status)
            let input = FitConvert.localFittingToSimulationInput(localFitting: fitting, databaseManager: data.db, characterSkills: data.skills)
            XCTAssertEqual(input.modules.first { $0.typeId == 35656 }?.status, 2)
        }
    }
}
