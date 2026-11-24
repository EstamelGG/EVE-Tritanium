import XCTest
@testable import EVE_Nexus

final class AppDataRequestsTests: XCTestCase {
    private actor RequestGate {
        private var started = false
        private var canFinish = false
        private var startWaiter: CheckedContinuation<Void, Never>?
        private var finishWaiter: CheckedContinuation<Void, Never>?

        func waitForStart() async {
            guard !started else { return }
            await withCheckedContinuation { startWaiter = $0 }
        }

        func fetch() async -> Int {
            started = true
            startWaiter?.resume()
            startWaiter = nil
            if !canFinish {
                await withCheckedContinuation { finishWaiter = $0 }
            }
            return 42
        }

        func release() {
            canFinish = true
            finishWaiter?.resume()
            finishWaiter = nil
        }
    }

    private enum TestError: Error {
        case failed
    }

    func testConcurrentCallersShareTheSameRequest() async throws {
        let requests = AppDataRequests<Int, Int>()
        let gate = RequestGate()
        let first = Task { try await requests.run(1) { await gate.fetch() } }
        await gate.waitForStart()

        let second = Task { try await requests.run(1) { XCTFail("Duplicate request"); return 0 } }
        let unrelated = try await requests.run(2) { 99 }
        XCTAssertEqual(unrelated, 99)
        try await Task.sleep(for: .milliseconds(25))
        await gate.release()

        let values = try await [first.value, second.value]
        XCTAssertEqual(values, [42, 42])
    }

    func testFailedRequestCanBeRetried() async throws {
        let requests = AppDataRequests<Int, Int>()
        do {
            _ = try await requests.run(1) { throw TestError.failed }
            XCTFail("Expected the request to fail")
        } catch TestError.failed {
            let value = try await requests.run(1) { 42 }
            XCTAssertEqual(value, 42)
        }
    }
}
