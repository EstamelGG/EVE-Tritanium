import Foundation

struct ESIIndustryJob: Codable, Identifiable, Hashable, Sendable {
    let activity_id: Int
    let blueprint_id: Int64
    let blueprint_location_id: Int64
    let blueprint_type_id: Int
    let completed_character_id: Int?
    let completed_date: Date?
    let cost: Double
    let duration: Int
    let end_date: Date
    let facility_id: Int64
    let installer_id: Int
    let job_id: Int
    let licensed_runs: Int?
    let output_location_id: Int64
    let pause_date: Date?
    let probability: Float?
    let product_type_id: Int?
    let runs: Int
    let start_date: Date
    let station_id: Int64
    let status: String
    let successful_runs: Int?

    var id: Int {
        job_id
    }

    var isOpen: Bool {
        status == "active" || status == "paused" || status == "ready"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(job_id)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.job_id == rhs.job_id
    }

    func widgetJob(characterID: Int, name: String?) -> WidgetIndustryJob? {
        guard let activity = WidgetIndustryActivity(rawValue: activity_id),
              let status = WidgetIndustryJob.Status(rawValue: status) else { return nil }
        return WidgetIndustryJob(
            id: job_id,
            typeID: blueprint_type_id,
            name: name,
            activity: activity,
            status: status,
            end: end_date,
            start: start_date,
            duration: Double(duration),
            pausedAt: pause_date,
            runs: runs,
            characterID: characterID,
            licensedRuns: licensed_runs
        )
    }
}
