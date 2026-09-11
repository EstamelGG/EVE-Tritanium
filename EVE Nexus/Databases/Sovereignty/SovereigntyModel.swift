import Foundation
import SwiftUI

// MARK: - Models

class PreparedSovereignty: NSObject, Identifiable, @unchecked Sendable, ObservableObject {
    let id: Int
    let campaign: EVE_Nexus.SovereigntyCampaign
    let location: LocationInfo
    @Published var icon: Image?
    @Published var isLoadingIcon = false

    init(campaign: EVE_Nexus.SovereigntyCampaign, location: LocationInfo) {
        id = campaign.campaign_id
        self.campaign = campaign
        self.location = location
        super.init()
    }

    struct LocationInfo: Codable {
        let systemId: Int
        let systemName: String
        let security: Double
        let constellationName: String
        let regionName: String
        let regionId: Int
    }

    /// 计算距离开始还有多久
    var remainingTimeText: String {
        // 解析开始时间
        let dateFormatter = ISO8601DateFormatter()
        guard let startDate = dateFormatter.date(from: campaign.start_time) else {
            return ""
        }

        // 计算从现在到开始时间还有多久
        let timeUntilStart = startDate.timeIntervalSince(Date())

        // 如果时间已经过了，说明已经开始
        if timeUntilStart <= 0 {
            return NSLocalizedString("Main_Sovereignty_Started", comment: "")
        }

        let days = Int(timeUntilStart / (24 * 60 * 60))
        let hours = Int((timeUntilStart.truncatingRemainder(dividingBy: 24 * 60 * 60)) / (60 * 60))
        let minutes = Int((timeUntilStart.truncatingRemainder(dividingBy: 60 * 60)) / 60)

        if days > 0 {
            return String(
                format: NSLocalizedString("Main_Sovereignty_Time_Days", comment: ""), days, hours
            )
        } else if hours > 0 {
            return String(
                format: NSLocalizedString("Main_Sovereignty_Time_Hours", comment: ""), hours,
                minutes
            )
        } else {
            return String(
                format: NSLocalizedString("Main_Sovereignty_Time_Minutes", comment: ""), minutes
            )
        }
    }
}
