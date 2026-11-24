import BackgroundTasks
import Foundation

enum WidgetBackgroundRefresh {
    static let identifier = "com.evenexus.datarefresh"

    static func shouldSubmit(earliest date: Date, pending: BGTaskRequest?, replaceExisting: Bool = false) -> Bool {
        guard let pending else { return true }
        guard let existing = pending.earliestBeginDate else { return replaceExisting }
        if replaceExisting {
            return abs(existing.timeIntervalSince(date)) >= 60
        }
        return date < existing
    }

    static func schedule(
        earliest date: Date, replaceExisting: Bool = false, completion: @escaping @Sendable () -> Void = {}
    ) {
        let scheduler = BGTaskScheduler.shared
        scheduler.getPendingTaskRequests { requests in
            let pending = requests.first { $0.identifier == identifier }
            guard shouldSubmit(earliest: date, pending: pending, replaceExisting: replaceExisting) else {
                completion()
                return
            }
            let request = BGAppRefreshTaskRequest(identifier: identifier)
            request.earliestBeginDate = date

            if #available(iOS 27, *) {
                scheduler.submitTaskRequest(request) { error in
                    recordSubmission(at: date, error: error)
                    completion()
                }
            } else {
                do {
                    try scheduler.submit(request)
                    recordSubmission(at: date, error: nil)
                } catch {
                    recordSubmission(at: date, error: error)
                }
                completion()
            }
        }
    }

    private static func recordSubmission(at date: Date, error: Error?) {
        if let error {
            NSLog("Widget background refresh request rejected: %@", (error as NSError).description)
        } else {
            NSLog("Widget background refresh requested, earliest: %@", date as NSDate)
        }
    }
}
