import XCTest
@testable import EVE_Nexus

final class FittingCalculationTests: XCTestCase {
    private let db = DatabaseManager.shared

    func testEnvironmentSummaryRelativePercent() throws {
        XCTAssertEqual(try XCTUnwrap(EnvironmentEffectSummary.relativePercent(operation: 4, value: 1.5)), 50, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(EnvironmentEffectSummary.relativePercent(operation: 4, value: 0.7)), -30, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(EnvironmentEffectSummary.relativePercent(operation: 5, value: 2)), -50, accuracy: 0.0001)
        // 共振修饰器保留正号，表示承受伤害增加，不能显示为抗性增加。
        XCTAssertEqual(EnvironmentEffectSummary.relativePercent(operation: 6, value: 30), 30)
        XCTAssertEqual(EnvironmentEffectSummary.relativePercent(operation: 6, value: -50), -50)
        XCTAssertNil(EnvironmentEffectSummary.relativePercent(operation: 4, value: 1))
        XCTAssertNil(EnvironmentEffectSummary.relativePercent(operation: 6, value: 0))
        XCTAssertNil(EnvironmentEffectSummary.relativePercent(operation: 5, value: 0))
        XCTAssertNil(EnvironmentEffectSummary.relativePercent(operation: 2, value: 50))
        XCTAssertNil(EnvironmentEffectSummary.relativePercent(operation: 4, value: .infinity))
    }

    private func input(modules: [SimModule] = [], attributes: [Int: Double] = [4: 1000, 263: 450, 37: 100]) -> SimulationInput {
        SimulationInput(ship: SimShip(typeId: 900001, baseAttributes: attributes,
            baseAttributesByName: [:], effects: [], groupID: 25, name: "ship",
            iconFileName: nil, requiredSkills: []), modules: modules, drones: [],
            cargo: SimCargo(items: []), implants: [], environmentEffects: [], characterSkills: [:])
    }

    private func module(type: Int = 900002, groupID: Int = 55, attributes: [Int: Double], status: Int = 2,
                        charge: SimCharge? = nil, mutation: [Int: Double] = [:]) -> SimModule {
        SimModule(typeId: type, attributes: attributes, attributesByName: [:], effects: [],
            groupID: groupID, status: status, charge: charge, quantity: 1, name: "module",
            requiredSkills: [], selectedMutaplasmidID: 900004, mutatedAttributes: mutation,
            mutatedTypeId: 900005, mutatedName: "mutated", mutatedIconFileName: "icon", isSpoolUpFull: false)
    }

    private func charge() -> SimCharge {
        SimCharge(typeId: 900003, attributes: [114: 10, 120: 0.5], attributesByName: [:],
            effects: [], groupID: 83, chargeQuantity: 40, requiredSkills: [], name: "charge", iconFileName: nil)
    }

    private func modifier(source: Int = 900002, target: Int, value: Int,
                          operation: OperationType = .modAdd, domain: ModifierDomain = .shipID,
                          category: EffectCategory = .passive, type: ModifierType = .itemModifier) -> AttributeModifier {
        AttributeModifier(effectId: 900010, effectName: "test", sourceTypeId: source,
            sourceTypeName: "source", sourceGroupId: 0, modifierType: type, domain: domain,
            effectCategory: category, operation: operation, modifiedAttributeId: target, modifyingAttributeId: value)
    }

    private func prepare(_ input: SimulationInput, _ modifiers: [AttributeModifier]) -> SimulationInput {
        var list = AttributeModifiers()
        for modifier in modifiers { list.addModifier(modifier) }
        return Step3(databaseManager: db).process(input: input, attributeModifiers: list)
    }

    private func calculate(_ input: SimulationInput) -> SimulationOutput {
        Step4(databaseManager: db, step3: Step3(databaseManager: db)).process(input: input)
    }

    private func simModifier(source: UUID, attribute: Int, operation: String, penalty: Bool = false) -> SimAttributeModifier {
        SimAttributeModifier(sourceTypeID: nil, sourceName: "source", operation: operation, value: 0,
            stackingPenalty: penalty, sourceAttributeId: attribute, sourceItemType: nil, sourceItemIndex: nil,
            sourceFlag: nil, effectId: 900010, effectCategory: 0, sourceInstanceId: source, targetInstanceId: nil)
    }

    func testOperationOrderAndSeparatePenaltyDirections() {
        var value = input(attributes: [900100: 100, 900101: 200, 900102: 2, 900103: 4,
                                      900104: 10, 900105: 5, 900106: 1.2, 900107: 2,
                                      900108: 10, 900109: 20, 900110: -20])
        let id = value.ship.instanceId
        value.ship.attributeModifiers[900100] = [
            simModifier(source: id, attribute: 900108, operation: "PostPercent", penalty: true),
            simModifier(source: id, attribute: 900109, operation: "PostPercent", penalty: true),
            simModifier(source: id, attribute: 900110, operation: "PostPercent", penalty: true),
            simModifier(source: id, attribute: 900107, operation: "PostDiv"),
            simModifier(source: id, attribute: 900106, operation: "PostMul"),
            simModifier(source: id, attribute: 900105, operation: "ModSub"),
            simModifier(source: id, attribute: 900104, operation: "ModAdd"),
            simModifier(source: id, attribute: 900103, operation: "PreDiv"),
            simModifier(source: id, attribute: 900102, operation: "PreMul"),
            simModifier(source: id, attribute: 900101, operation: "PreAssign"),
        ]
        let expected = (200.0 * 2 / 4 + 10 - 5) * 1.2 / 2 * 1.2 * (1 + 0.1 * 0.8691199808003974) * 0.8
        XCTAssertEqual(calculate(value).ship.attributes[900100]!, expected, accuracy: 1e-10)
    }

    func testStatusFilteringKeepsModuleInstancesSeparate() {
        let modules = [module(attributes: [72: 100], status: 0), module(attributes: [72: 200], status: 2)]
        let value = prepare(input(modules: modules), [modifier(target: 263, value: 72, category: .active)])
        XCTAssertEqual(calculate(value).ship.attributes[263], 650)
    }

    func testMutationPropagatesOnceAndDoesNotChangeInput() {
        let original = input(modules: [module(attributes: [72: 520], mutation: [72: 1.2])])
        let value = prepare(original, [modifier(target: 263, value: 72)])
        for _ in 0 ..< 2 {
            let output = calculate(value)
            XCTAssertEqual(output.modules[0].attributes[72], 624)
            XCTAssertEqual(output.ship.attributes[263], 1074)
            XCTAssertEqual(Step5(databaseManager: db).process(output: output).modules[0].attributes[72], 624)
        }
        XCTAssertEqual(original.modules[0].attributes[72], 520)
    }

    func testChargeUpdatesPreserveIdentityAndAllModuleMutationFields() {
        let ammo = charge()
        let original = module(attributes: [114: 20, 900100: 2], charge: ammo, mutation: [114: 1.2])
        let value = prepare(input(modules: [original]), [
            modifier(target: 114, value: 900100, domain: .itemID),
            modifier(source: 900003, target: 37, value: 120, operation: .postMul),
        ])
        let updated = value.modules[0]
        XCTAssertEqual(updated.charge?.instanceId, ammo.instanceId)
        XCTAssertEqual(updated.instanceId, original.instanceId)
        XCTAssertEqual(updated.mutatedAttributes, original.mutatedAttributes)
        XCTAssertEqual(updated.selectedMutaplasmidID, original.selectedMutaplasmidID)
        XCTAssertEqual(updated.mutatedTypeId, original.mutatedTypeId)
        XCTAssertEqual(updated.mutatedName, original.mutatedName)
        XCTAssertEqual(updated.mutatedIconFileName, original.mutatedIconFileName)
        XCTAssertFalse(updated.isSpoolUpFull)
        XCTAssertEqual(calculate(value).ship.attributes[37], 50)
    }

    func testPostAssignedMissingAttributeCanBeDependencyBeforeModuleEvaluation() {
        var value = input(modules: [module(attributes: [:])])
        value.modules[0].attributeModifiers[900100] = [simModifier(source: value.ship.instanceId, attribute: 37, operation: "PostAssign")]
        value.ship.attributeModifiers[4] = [simModifier(source: value.modules[0].instanceId, attribute: 900100, operation: "ModAdd")]
        let output = calculate(value)
        XCTAssertEqual(output.modules[0].attributes[900100], 100)
        XCTAssertEqual(output.ship.attributes[4], 1100)
    }

    func testCyclicDependencyTerminatesWithoutPoisoningOtherAttributes() {
        var value = input(attributes: [900100: 10, 900101: 20, 37: 100])
        value.ship.attributeModifiers[900100] = [simModifier(source: value.ship.instanceId, attribute: 900101, operation: "ModAdd")]
        value.ship.attributeModifiers[900101] = [simModifier(source: value.ship.instanceId, attribute: 900100, operation: "ModAdd")]
        let output = calculate(value)
        XCTAssertTrue(output.ship.attributes[900100]!.isFinite)
        XCTAssertTrue(output.ship.attributes[900101]!.isFinite)
        XCTAssertEqual(output.ship.attributes[37], 100)
    }

    func testCachedJSONRemainsBoundToEachSourceAndTracksChangedContent() {
        let step = Step2(databaseManager: db)
        func effect(_ source: Int, _ target: Int) -> EffectDetail {
            EffectDetail(effectId: 900010, effectName: "test", effectCategory: 0, description: nil,
                typeId: source, typeName: "source", groupId: 0, isDefault: false, isOffensive: false,
                isAssistance: false, modifierInfo: "[{\"domain\":\"shipID\",\"func\":\"ItemModifier\",\"operation\":2,\"modifiedAttributeID\":\(target),\"modifyingAttributeID\":72}]")
        }
        let first = step.process(itemEffects: [1: [effect(1, 263)], 2: [effect(2, 263)]])
        XCTAssertEqual(first.modifiersBySourceTypeId[1]?.first?.sourceTypeId, 1)
        XCTAssertEqual(first.modifiersBySourceTypeId[2]?.first?.sourceTypeId, 2)
        let changed = step.process(itemEffects: [1: [effect(1, 37)]])
        XCTAssertEqual(changed.modifiersBySourceTypeId[1]?.first?.modifiedAttributeId, 37)
    }

    func testReloadDPSUsesMagazineQuantityAndChargeRate() {
        var output = SimModuleOutput(from: module(attributes: [:], charge: charge()))
        output.attributesByName = ["reloadTime": 10000, "chargeSize": 1, "chargeRate": 1]
        XCTAssertEqual(FittingWeaponStatistics.dpsIncludingReload(volley: 100, cycle: 2, module: output), 4000.0 / 90, accuracy: 1e-10)
        output.attributesByName["chargeRate"] = 2
        XCTAssertEqual(FittingWeaponStatistics.dpsIncludingReload(volley: 100, cycle: 2, module: output), 2000.0 / 50, accuracy: 1e-10)
    }

    func testCapacitorRejectsAverageStableButUnaffordableCycles() {
        let calc = FittingCapacitorCalculator()
        let value = FittingCapacitorCalculator.Input(capacity: 1000, rechargeTime: 100,
            cycles: [.init(duration: 40, need: 900)])
        let result = calc.calculate(input: value)
        XCTAssertGreaterThan(result.delta, 0)
        XCTAssertFalse(result.isStable)
        XCTAssertFalse(result.reachedLimit)
        XCTAssertEqual(result.lastsTime, 40)
        XCTAssertEqual(calc.calculate(input: value), result)
    }

    func testCapacitorSimultaneousActivationAndChangedInputs() {
        let calc = FittingCapacitorCalculator()
        let burst = FittingCapacitorCalculator.Input(capacity: 1000, rechargeTime: 100,
            cycles: [.init(duration: 100, need: 600), .init(duration: 100, need: 500)])
        XCTAssertEqual(calc.calculate(input: burst).lastsTime, 0)
        let sustainable = FittingCapacitorCalculator.Input(capacity: 1000, rechargeTime: 100,
            cycles: [.init(duration: 10, need: 10)])
        let result = calc.calculate(input: sustainable)
        XCTAssertTrue(result.isStable)
        XCTAssertGreaterThan(result.stableLevel, 0.9)
        XCTAssertEqual(calc.calculate(input: burst).lastsTime, 0)
    }

    func testCapacitorDoesNotCallSimulationLimitStable() {
        let calc = FittingCapacitorCalculator()
        let result = calc.calculate(input: .init(capacity: 1000, rechargeTime: 100,
            cycles: [.init(duration: 100000, need: 900)]))
        XCTAssertFalse(result.isStable)
        XCTAssertTrue(result.reachedLimit)
        XCTAssertEqual(result.lastsTime, 8 * 3600)
    }
    func testPulsedCapacitorGainCannotPayForAnEarlierCycleOrStoreOverflow() {
        let result = FittingCapacitorCalculator().calculate(input: .init(capacity: 100, rechargeTime: 0,
            cycles: [.init(duration: 10, need: 60), .init(duration: 30, need: 0, gain: 300)]))
        // 平均补能大于耗电，但 t=0 的溢出不能留给 t=10，t=30 的补能也不能提前到账。
        XCTAssertGreaterThan(result.delta, 0)
        XCTAssertFalse(result.isStable)
        XCTAssertFalse(result.reachedLimit)
        XCTAssertEqual(result.lastsTime, 10)
    }

    func testCapacitorReloadGapMustBeSimulatedBeforeDeclaringStability() {
        let result = FittingCapacitorCalculator().calculate(input: .init(capacity: 100, rechargeTime: 0,
            cycles: [.init(duration: 10, need: 40),
                     .init(duration: 10, need: 0, gain: 100, shotsPerReload: 2, reloadTime: 20)]))
        // t=0、10 电量相同，仍会在换弹窗口内的 t=30 断电。
        XCTAssertGreaterThan(result.delta, 0)
        XCTAssertFalse(result.isStable)
        XCTAssertFalse(result.reachedLimit)
        XCTAssertEqual(result.lastsTime, 30)
    }

    func testCapacitorReloadsIndefinitelyAndReportsCycleLowPoint() {
        let result = FittingCapacitorCalculator().calculate(input: .init(capacity: 100, rechargeTime: 0,
            cycles: [.init(duration: 10, need: 20),
                     .init(duration: 10, need: 0, gain: 100, shotsPerReload: 2, reloadTime: 20)]))
        // 每仓两次，换弹后继续；t=30 的 40 GJ 是重复周期低点。
        XCTAssertTrue(result.isStable)
        XCTAssertEqual(result.lastsTime, .infinity)
        XCTAssertEqual(result.stableLevel, 0.4, accuracy: 1e-10)
        XCTAssertEqual(result.delta, 3, accuracy: 1e-10)
    }

    func testCapacitorSimultaneousGainsAreClippedAndIndependentOfModuleOrder() {
        let calc = FittingCapacitorCalculator()
        let cycles: [FittingCapacitorCalculator.Cycle] = [
            .init(duration: 10, need: 80), .init(duration: 10, need: 0, gain: 60),
            .init(duration: 10, need: 0, gain: 60),
        ]
        let result = calc.calculate(input: .init(capacity: 100, rechargeTime: 0, cycles: cycles))
        XCTAssertTrue(result.isStable)
        XCTAssertEqual(result.stableLevel, 0.2, accuracy: 1e-10)
        XCTAssertEqual(calc.calculate(input: .init(capacity: 100, rechargeTime: 0,
            cycles: Array(cycles.reversed()))), result)
        let unaffordable = calc.calculate(input: .init(capacity: 100, rechargeTime: 0,
            cycles: [.init(duration: 10, need: 110), .init(duration: 10, need: 0, gain: 1000)]))
        XCTAssertFalse(unaffordable.isStable)
        XCTAssertEqual(unaffordable.lastsTime, 0)
    }

    func testCapacitorInputUsesModifiedCycleAmmoAndReactivationAttributes() {
        var ship = SimShipOutput(from: input().ship)
        ship.attributesByName = ["capacitorCapacity": 1000, "rechargeRate": 100000]
        let ammo = SimCharge(typeId: 900003, attributes: [:],
            attributesByName: ["capacitorBonus": 80, "volume": 2], effects: [], groupID: 87,
            chargeQuantity: 5, requiredSkills: [], name: "charge", iconFileName: nil)
        var injector = SimModuleOutput(from: module(groupID: 76, attributes: [:], charge: ammo))
        injector.attributesByName = ["speed": 12000, "chargeRate": 2, "reloadTime": 10000,
                                    "moduleReactivationDelay": 1000]
        var nos = SimModuleOutput(from: module(groupID: 68, attributes: [:]))
        nos.attributesByName = ["duration": 6000, "moduleReactivationDelay": 2000,
                                "powerTransferAmount": 30, "capacitorNeed": 2]
        let value = FittingCapacitorCalculator.makeInput(ship: ship, modules: [injector, nos])
        XCTAssertEqual(value.capacity, 1000)
        XCTAssertEqual(value.rechargeTime, 100)
        XCTAssertEqual(value.cycles, [
            .init(duration: 13, need: 0, gain: 160, shotsPerReload: 2, reloadTime: 10),
            .init(duration: 8, need: 2, gain: 30),
        ])
    }

    func testCapacitorInputHandlesMissingQuantityEmptyAndInactiveInjectors() {
        let ship = SimShipOutput(from: input().ship)
        let ammo = SimCharge(typeId: 900003, attributes: [:],
            attributesByName: ["capacitorBonus": 80, "volume": 2], effects: [], groupID: 87,
            chargeQuantity: nil, requiredSkills: [], name: "charge", iconFileName: nil)
        var injector = SimModuleOutput(from: module(groupID: 76, attributes: [:], charge: ammo))
        injector.attributesByName = ["duration": 10000, "capacity": 6, "reloadTime": 10000]
        var empty = SimModuleOutput(from: module(groupID: 76, attributes: [:]))
        empty.attributesByName = injector.attributesByName
        var inactive = SimModuleOutput(from: module(groupID: 76, attributes: [:], status: 1, charge: ammo))
        inactive.attributesByName = injector.attributesByName
        let value = FittingCapacitorCalculator.makeInput(ship: ship, modules: [injector, empty, inactive])
        XCTAssertEqual(value.cycles, [.init(duration: 10, need: 0, gain: 80, shotsPerReload: 3, reloadTime: 10)])
    }

    func testCapacitorCacheTracksGainAndReloadChanges() {
        let calc = FittingCapacitorCalculator()
        func value(gain: Double, reload: Double) -> FittingCapacitorCalculator.Input {
            .init(capacity: 100, rechargeTime: 0, cycles: [.init(duration: 10, need: 40),
                .init(duration: 10, need: 0, gain: gain, shotsPerReload: 2, reloadTime: reload)])
        }
        XCTAssertTrue(calc.calculate(input: value(gain: 100, reload: 0)).isStable)
        XCTAssertFalse(calc.calculate(input: value(gain: 10, reload: 0)).isStable)
        XCTAssertFalse(calc.calculate(input: value(gain: 100, reload: 20)).isStable)
        XCTAssertTrue(calc.calculate(input: value(gain: 100, reload: 0)).isStable)
    }

    func testTargetIndexesFilterSkillsWithoutDuplicateContributionsAndReset() {
        let step = Step3(databaseManager: db)
        var target = module(type: 900020, attributes: [263: 100])
        target.requiredSkills = [900050, 900050]
        let source = module(attributes: [72: 20])
        var mods = AttributeModifiers()
        mods.addModifier(modifier(target: 263, value: 72,
            type: .locationRequiredSkillModifier(skillTypeID: 900050)))
        let first = step.process(input: input(modules: [source, target]), attributeModifiers: mods)
        XCTAssertEqual(calculate(first).modules[1].attributes[263], 120)
        target.requiredSkills = []
        let second = step.process(input: input(modules: [target, source]), attributeModifiers: mods)
        XCTAssertEqual(calculate(second).modules[0].attributes[263], 100)
    }

    func testDroneMutationIsAppliedExactlyOnce() {
        var value = input()
        var drone = SimDrone(typeId: 900060, attributes: [114: 10], attributesByName: [:],
            effects: [], quantity: 5, activeCount: 3, groupID: 100, requiredSkills: [],
            name: "drone", iconFileName: nil)
        drone.mutatedAttributes = [114: 1.2]
        value.drones = [drone]
        let output = Step5(databaseManager: db).process(output: calculate(value))
        XCTAssertEqual(output.drones[0].attributes[114], 12)
        XCTAssertEqual(value.drones[0].attributes[114], 10)
    }

    func testAttributeTraceRecordsOrderedPenaltyAndExactFinalValue() throws {
        var value = input(attributes: [37: 100, 900101: 10, 900102: 20])
        let id = value.ship.instanceId
        value.ship.attributeModifiers[37] = [
            simModifier(source: id, attribute: 900101, operation: "PostPercent", penalty: true),
            simModifier(source: id, attribute: 900102, operation: "PostPercent", penalty: true),
        ]
        let output = calculate(value)
        let trace = try XCTUnwrap(output.attributeTraces[id]?[37])
        XCTAssertEqual(trace.baseValue, 100)
        XCTAssertEqual(trace.steps.count, 2)
        XCTAssertEqual(trace.steps[0].operand, 20)
        XCTAssertEqual(trace.steps[0].after, 120)
        XCTAssertEqual(trace.steps[1].before, 120)
        XCTAssertEqual(trace.steps[1].penalty, 0.8691199808003974, accuracy: 1e-12)
        XCTAssertEqual(trace.finalValue, 120 * (1 + 0.1 * 0.8691199808003974), accuracy: 1e-10)
        XCTAssertEqual(trace.finalValue, output.ship.attributes[37])
    }

    func testAttributeTraceFiltersInactiveInstancesAndFollowsMutation() throws {
        let modules = [module(attributes: [72: 100], status: 0),
                       module(attributes: [72: 200], status: 2, mutation: [72: 1.2])]
        let value = prepare(input(modules: modules), [modifier(target: 263, value: 72, category: .active)])
        let output = calculate(value)
        let trace = try XCTUnwrap(output.attributeTraces[value.ship.instanceId]?[263])
        XCTAssertEqual(trace.steps.count, 1)
        XCTAssertEqual(trace.steps[0].modifier?.sourceInstanceId, modules[1].instanceId)
        XCTAssertEqual(trace.steps[0].operand, 240)
        XCTAssertEqual(trace.finalValue, 690)
        let mutation = try XCTUnwrap(output.attributeTraces[modules[1].instanceId]?[72])
        XCTAssertEqual(mutation.steps.last?.operation, "Mutation")
        XCTAssertEqual(mutation.finalValue, 240)
        XCTAssertNil(output.attributeTraces[modules[0].instanceId]?[72])
    }

    func testAttributeTraceIncludesSpoolAndResetsBetweenCalculations() throws {
        var module = module(attributes: [114: 10, 2734: 1.5])
        module.isSpoolUpFull = true
        let value = input(modules: [module])
        let calculator = Step4(databaseManager: db, step3: Step3(databaseManager: db))
        let output = calculator.process(input: value)
        let trace = try XCTUnwrap(output.attributeTraces[module.instanceId]?[114])
        XCTAssertEqual(trace.steps.last?.operation, "Spool")
        XCTAssertEqual(trace.baseValue, 10)
        XCTAssertEqual(trace.finalValue, 25)
        XCTAssertEqual(trace.finalValue, output.modules[0].attributes[114])
        XCTAssertTrue(calculator.process(input: input()).attributeTraces.isEmpty)
    }

    @MainActor
    func testAttributeTraceIncludesBoosterAndEnvironmentSources() throws {
        _ = try FittingRegressionData.shared.get()
        let penaltyID = try XCTUnwrap(SDEMemoryStore.boosterSideEffectPenaltyAttributeIDs.sorted().first)
        var value = input()
        value.implants = [SimImplant(typeId: 900020,
            attributes: [900100: 20, penaltyID: -10], attributesByName: [:], effects: [],
            requiredSkills: [], groupID: 303, name: "booster", iconFileName: "booster-icon")]
        value.environmentEffects = [SimEnvironmentEffect(typeId: 900021, name: "environment",
            attributes: [900101: 30], attributesByName: [:], effects: [], iconFileName: "environment-icon")]
        let modifiers = [
            modifier(source: 900020, target: 37, value: 900100),
            modifier(source: 900020, target: 263, value: penaltyID),
            modifier(source: 900021, target: 37, value: 900101),
        ]
        let output = calculate(prepare(value, modifiers))
        let trace = try XCTUnwrap(output.attributeTraces[value.ship.instanceId]?[37])
        XCTAssertEqual(trace.baseValue, 100)
        XCTAssertEqual(trace.finalValue, 150)
        XCTAssertEqual(Set(trace.steps.compactMap { $0.modifier?.sourceInstanceId }),
            Set([value.implants[0].instanceId, value.environmentEffects[0].instanceId]))
        XCTAssertNil(output.attributeTraces[value.ship.instanceId]?[263])
        let context = try XCTUnwrap(output.attributeContext(for: value.ship.instanceId))
        XCTAssertEqual(context.sourceLabels[value.implants[0].instanceId], "booster")
        XCTAssertEqual(context.sourceIcons[value.implants[0].instanceId], "booster-icon")
        XCTAssertEqual(context.sourceLabels[value.environmentEffects[0].instanceId], "environment")
        XCTAssertEqual(context.sourceIcons[value.environmentEffects[0].instanceId], "environment-icon")

        value.implants[0].enabledSideEffectAttributeIDs = [penaltyID]
        let enabledOutput = calculate(prepare(value, modifiers))
        let sideEffect = try XCTUnwrap(enabledOutput.attributeTraces[value.ship.instanceId]?[263])
        XCTAssertEqual(sideEffect.steps.count, 1)
        XCTAssertEqual(sideEffect.steps[0].modifier?.sourceInstanceId, value.implants[0].instanceId)
        XCTAssertEqual(sideEffect.baseValue, 450)
        XCTAssertEqual(sideEffect.finalValue, 440)
    }

    func testAttributeTraceIncludesPropulsionCorrection() throws {
        var output = SimulationOutput(from: input(modules: [module(attributes: [:])]))
        output.ship.attributesByName = ["mass": 1000, "maxVelocity": 100]
        // Use a fresh output module with the propulsion effect.
        let propulsion = SimModule(typeId: 900002, attributes: [:],
            attributesByName: ["speedFactor": 100, "speedBoostFactor": 1000], effects: [6730],
            groupID: 46, status: 2, quantity: 1, name: "propulsion", requiredSkills: [])
        output.modules = [SimModuleOutput(from: propulsion)]
        let final = Step5(databaseManager: db).process(output: output)
        let trace = try XCTUnwrap(final.attributeTraces[output.originalInput.ship.instanceId]?[37])
        XCTAssertEqual(trace.steps.last?.operation, "Propulsion")
        XCTAssertEqual(trace.steps.last?.modifier?.sourceInstanceId, propulsion.instanceId)
        XCTAssertEqual(trace.baseValue, 100)
        XCTAssertEqual(trace.finalValue, 200)
        XCTAssertEqual(trace.finalValue, final.ship.attributes[37])
    }

    func testReloadDPSFallsBackToCapacityAndHandlesNoAmmo() {
        let ammo = SimCharge(typeId: 900003, attributes: [:], attributesByName: ["volume": 0.03],
            effects: [], groupID: 83, chargeQuantity: nil, requiredSkills: [], name: "charge", iconFileName: nil)
        var output = SimModuleOutput(from: module(attributes: [:], charge: ammo))
        output.attributesByName = ["capacity": 1.2, "reloadTime": 10000]
        XCTAssertEqual(FittingWeaponStatistics.dpsIncludingReload(volley: 100, cycle: 2, module: output), 4000.0 / 90, accuracy: 1e-10)
        output.charge = nil
        XCTAssertEqual(FittingWeaponStatistics.dpsIncludingReload(volley: 100, cycle: 2, module: output), 50)
    }

}
