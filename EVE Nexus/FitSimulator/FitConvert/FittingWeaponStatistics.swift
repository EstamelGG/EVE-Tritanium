import Foundation

/// 使用实际装填数量（缺失时用容量/体积）计算含换弹的平均 DPS。
enum FittingWeaponStatistics {
    static func dpsIncludingReload(volley: Double, cycle: Double, module: SimModuleOutput) -> Double {
        guard cycle > 0 else { return 0 }
        guard let charge = module.charge else { return volley / cycle }
        let reload = max(0, module.attributesByName["reloadTime"] ?? 10000) / 1000
        if reload == 0 {
            return volley / cycle
        }
        let quantity: Double
        if let loaded = charge.chargeQuantity {
            quantity = Double(max(0, loaded))
        } else {
            let volume = charge.attributesByName["volume"] ?? 0
            let capacity = module.attributesByName["capacity"] ?? 0
            guard volume > 0 else { return volley / cycle }
            quantity = floor(capacity / volume + 1e-9)
        }
        let chargeRate = module.attributesByName["chargeRate"] ?? 1
        guard chargeRate > 0 else { return volley / cycle }
        let shots = floor(quantity / chargeRate)
        guard shots > 0 else { return 0 }
        return volley * shots / (cycle * shots + reload)
    }
}
