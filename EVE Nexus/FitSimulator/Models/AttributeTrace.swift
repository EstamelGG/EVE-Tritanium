import Foundation

/// A record of the operations actually applied by the simulator, keyed by full instance UUID.
struct AttributeTrace {
    let baseValue: Double
    var steps: [AttributeTraceStep]
    var finalValue: Double
}

struct AttributeTraceStep {
    let modifier: SimAttributeModifier?
    let operation: String
    /// Original operand, before stacking penalties.
    let operand: Double
    let penalty: Double
    let before: Double
    let after: Double
    var dependencies: [AttributeTraceDependency] = []
}

struct AttributeTraceDependency {
    let instanceID: UUID
    let attributeID: Int
    let value: Double
}

struct FittingAttributeContext {
    let instanceID: UUID
    let traces: [UUID: [Int: AttributeTrace]]
    var sourceLabels: [UUID: String] = [:]
    var sourceIcons: [UUID: String] = [:]
    var baseAttributes: [Int: Double] = [:]
    var finalAttributes: [Int: Double] = [:]
    var itemName: String = ""
    var mutationIcon: String? = nil
    var sourceAssetIcons: [UUID: String] = [:]
}

extension SimulationOutput {
    func attributeContext(for instanceID: UUID?) -> FittingAttributeContext? {
        guard let instanceID else { return nil }
        var labels: [UUID: String] = [:]
        var icons: [UUID: String] = [:]
        var assetIcons: [UUID: String] = [:]
        labels[originalInput.ship.instanceId] = ship.name
        icons[originalInput.ship.instanceId] = ship.iconFileName
        for module in modules {
            labels[module.instanceId] = module.name
            icons[module.instanceId] = module.iconFileName
        }
        for skill in originalInput.skills {
            let name = DatabaseManager.shared.getTypeName(for: skill.typeId) ?? "\(skill.typeId)"
            labels[skill.instanceId] = "\(name) Lv \(skill.level)"
            icons[skill.instanceId] = DatabaseManager.shared.getItemIconFileName(for: skill.typeId) ?? "skills"
        }
        // Boosters share the implant collection; preserve the actual simulation source identity.
        for implant in originalInput.implants {
            labels[implant.instanceId] = implant.name
            icons[implant.instanceId] = implant.iconFileName
                ?? DatabaseManager.shared.getItemIconFileName(for: implant.typeId)
        }
        for environment in originalInput.environmentEffects {
            let item = EnvironmentEffectNaming.item(for: environment.typeId)
            labels[environment.instanceId] = item?.displayName ?? environment.name
            assetIcons[environment.instanceId] = item?.rowIconAssetName
            icons[environment.instanceId] = item?.iconFileName ?? environment.iconFileName
                ?? DatabaseManager.shared.getItemIconFileName(for: environment.typeId)
        }
        let values = attributeValues(for: instanceID)
        let mutaplasmidID = originalInput.modules.first { $0.instanceId == instanceID }?.selectedMutaplasmidID
            ?? originalInput.drones.first { $0.instanceId == instanceID }?.selectedMutaplasmidID
        return FittingAttributeContext(instanceID: instanceID, traces: attributeTraces, sourceLabels: labels,
                                       sourceIcons: icons, baseAttributes: values.base, finalAttributes: values.final,
                                       itemName: attributeItemName(for: instanceID),
                                       mutationIcon: mutaplasmidID.flatMap { DatabaseManager.shared.getItemIconFileName(for: $0) },
                                       sourceAssetIcons: assetIcons)
    }

    private func attributeItemName(for id: UUID) -> String {
        if originalInput.ship.instanceId == id {
            return ship.name
        }
        if let module = modules.first(where: { $0.instanceId == id }) {
            return module.name
        }
        if let charge = modules.compactMap(\.charge).first(where: { $0.instanceId == id }) {
            return charge.name
        }
        if let drone = drones.first(where: { $0.instanceId == id }) {
            return drone.name
        }
        if let fighter = fighters?.first(where: { $0.instanceId == id }) {
            return fighter.name
        }
        if let implant = implants.first(where: { $0.instanceId == id }) {
            return implant.name
        }
        return originalInput.environmentEffects.first(where: { $0.instanceId == id })?.name ?? ""
    }

    private func attributeValues(for id: UUID) -> (base: [Int: Double], final: [Int: Double]) {
        if originalInput.ship.instanceId == id {
            return (originalInput.ship.baseAttributes, ship.attributes)
        }
        for module in originalInput.modules {
            if module.instanceId == id {
                return (module.attributes, modules.first { $0.instanceId == id }?.attributes ?? module.attributes)
            }
            if let charge = module.charge, charge.instanceId == id {
                return (charge.attributes, modules.compactMap(\.charge).first { $0.instanceId == id }?.attributes ?? charge.attributes)
            }
        }
        if let drone = originalInput.drones.first(where: { $0.instanceId == id }) {
            return (drone.attributes, drones.first { $0.instanceId == id }?.attributes ?? drone.attributes)
        }
        if let fighter = originalInput.fighters?.first(where: { $0.instanceId == id }) {
            return (fighter.attributes, fighters?.first { $0.instanceId == id }?.attributes ?? fighter.attributes)
        }
        return ([:], [:])
    }
}
