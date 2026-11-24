import Foundation

/// 行星连接
struct PlanetaryLink: Codable, Equatable, Sendable {
    let destinationPinId: Int64
    let linkLevel: Int // maximum: 10, minimum: 0
    let sourcePinId: Int64

    enum CodingKeys: String, CodingKey {
        case destinationPinId = "destination_pin_id"
        case linkLevel = "link_level"
        case sourcePinId = "source_pin_id"
    }
}
