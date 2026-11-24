import Foundation
import WidgetKit

struct NexusWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    var marketTrendColors = WidgetMarketTrendColors.defaultStyle
    var isPlaceholder = false
}
