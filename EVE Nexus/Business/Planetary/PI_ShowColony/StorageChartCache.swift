import Foundation

/// Equality includes values and capacity, so a simulation with unchanged sample times still refreshes.
struct StorageChartInput: Equatable {
    let pinId: Int64
    let capacity: Double
    let volumes: [Int: Double]
}

struct StorageChartCache {
    struct Sample: Equatable {
        let hour: Int // Sampling time in minutes, matching the chart's existing coordinates.
        let volume: Double
    }

    private var input: StorageChartInput?
    private(set) var samples: [Sample] = []
    private(set) var maxVolume: Double = 1

    @discardableResult
    mutating func update(_ newInput: StorageChartInput) -> Bool {
        guard input != newInput else { return false }
        input = newInput
        samples = newInput.volumes.keys.sorted().map {
            Sample(hour: $0, volume: newInput.volumes[$0] ?? 0)
        }

        // A positive range also keeps empty and zero-capacity facilities safe to plot.
        let fixedMax = max(1, newInput.capacity * 1.2)
        let peak = samples.map(\.volume).max() ?? 0
        let dynamicMax = min(Self.roundUpToTens(peak * 1.2), fixedMax)
        let lowCount = samples.filter { $0.volume < newInput.capacity * 0.1 }.count
        let lowRatio = samples.isEmpty ? 0 : Double(lowCount) / Double(samples.count)
        maxVolume = lowRatio > 0.6 ? dynamicMax : fixedMax
        return true
    }

    private static func roundUpToTens(_ value: Double) -> Double {
        guard value > 0 else { return 10 }
        let magnitude = pow(10, floor(log10(value)))
        return ceil(value / magnitude) * magnitude
    }
}
