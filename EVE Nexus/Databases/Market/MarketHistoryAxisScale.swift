import Foundation

/// Independent price and volume ranges sharing the same evenly spaced grid lines.
struct MarketHistoryAxisScale: Hashable {
    let priceLowerBound: Double
    let priceStep: Double
    let intervalCount: Int
    let volumeStep: Double

    var priceUpperBound: Double {
        priceLowerBound + priceStep * Double(intervalCount)
    }

    var priceRange: Double {
        priceStep * Double(intervalCount)
    }

    var volumeUpperBound: Double {
        volumeStep * Double(intervalCount)
    }

    var priceTicks: [Double] {
        (0 ... intervalCount).map { priceLowerBound + Double($0) * priceStep }
    }

    var volumeTicks: [Double] {
        (0 ... intervalCount).map { Double($0) * volumeStep }
    }

    /// Both axes use these same positions in the plot, independent of their units.
    var gridPositions: [Double] {
        (0 ... intervalCount).map { Double($0) / Double(intervalCount) }
    }

    func normalizedPrice(_ price: Double) -> Double {
        (price - priceLowerBound) / priceRange
    }

    func normalizedVolume(_ volume: Double) -> Double {
        max(0, volume) / volumeUpperBound
    }

    init(prices: [Double], volumes: [Double]) {
        let minPrice = prices.min() ?? 0
        let maxPrice = prices.max() ?? 0
        let range = maxPrice - minPrice
        let padding = range > 0 ? range * 0.15 : max(abs(maxPrice) * 0.15, 1)
        let lowerTarget = max(0, minPrice - padding)
        let upperTarget = maxPrice + padding
        // Choose the nearest tidy step; rounding only upward can double the empty range.
        let targetStep = (upperTarget - lowerTarget) / 4
        let magnitude = pow(10, floor(log10(targetStep)))
        let step = [1.0, 2, 2.5, 5, 10].map { $0 * magnitude }.min {
            abs(log($0 / targetStep)) < abs(log($1 / targetStep))
        } ?? targetStep
        let lower = floor(lowerTarget / step) * step
        let intervals = max(1, Int(ceil((upperTarget - lower) / step)))

        priceLowerBound = lower
        priceStep = step
        intervalCount = intervals

        // Keep modest headroom without a second large jump from coarse 1/2/5 rounding.
        let maxVolume = max(volumes.max() ?? 0, 0)
        let targetVolumeStep = max(1, maxVolume / (0.85 * Double(intervals)))
        let volumeQuantum = max(1, pow(10, floor(log10(targetVolumeStep)) - 1))
        volumeStep = ceil(targetVolumeStep / volumeQuantum) * volumeQuantum
    }

    /// Volume bars and right-axis ticks use this same conversion into price coordinates.
    func pricePosition(forVolume volume: Double) -> Double {
        priceLowerBound + max(0, volume) / volumeUpperBound * priceRange
    }
}
