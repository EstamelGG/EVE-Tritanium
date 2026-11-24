import Darwin
import Foundation

/// A process-wide actor cannot serialize the app and its extension. Keep the
/// descriptor open across the operation so the OS releases the lock on termination.
final class WidgetFileLock: @unchecked Sendable {
    private let descriptor: Int32

    private init(descriptor: Int32) { self.descriptor = descriptor }

    static func acquire(_ name: String, timeout: TimeInterval = 20) async throws -> WidgetFileLock {
        guard let root = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: WidgetStore.appGroup
        ) else { throw CocoaError(.fileNoSuchFile) }
        let directory = root.appendingPathComponent("WidgetLocks", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = open(directory.appendingPathComponent(name).path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        let deadline = Date().addingTimeInterval(timeout)
        do {
            while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
                guard errno == EWOULDBLOCK || errno == EAGAIN else { throw CocoaError(.fileLocking) }
                try Task.checkCancellation()
                guard Date() < deadline else { throw URLError(.timedOut) }
                try await Task.sleep(for: .milliseconds(100))
            }
            try Task.checkCancellation()
            return WidgetFileLock(descriptor: descriptor)
        } catch {
            close(descriptor)
            throw error
        }
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
