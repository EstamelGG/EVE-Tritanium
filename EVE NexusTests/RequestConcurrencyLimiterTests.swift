import XCTest

@testable import EVE_Nexus

final class RequestConcurrencyLimiterTests: XCTestCase {
    func testLimitsInFlightRequestsAndDrainsBurst() async throws {
        let limiter = await RequestConcurrencyLimiter(limit: 8)
        let requests = await InFlightRequests()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<64 {
                group.addTask {
                    try await requests.run(with: limiter)
                }
            }
            try await group.waitForAll()
        }

        let peak = await requests.peak
        XCTAssertEqual(peak, 8)
    }

    func testCancelsQueuedRequestWhileSlotIsStillOccupied() async throws {
        let limiter = await RequestConcurrencyLimiter(limit: 1)
        try await limiter.acquire()

        let started = expectation(description: "Request reached the limiter")
        let cancelled = expectation(description: "Queued request cancelled")
        let request = Task { @NetworkManagerActor in
            started.fulfill()
            do {
                try await limiter.acquire()
                limiter.release()
                XCTFail("The cancelled request acquired a slot")
            } catch is CancellationError {
                cancelled.fulfill()
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }

        await fulfillment(of: [started], timeout: 2)
        request.cancel()
        await fulfillment(of: [cancelled], timeout: 2)
        await limiter.release()
        await request.value

        try await limiter.acquire()
        await limiter.release()
    }
}

@NetworkManagerActor
private final class InFlightRequests {
    private var active = 0
    private(set) var peak = 0

    func run(with limiter: RequestConcurrencyLimiter) async throws {
        try await limiter.acquire()
        active += 1
        peak = max(peak, active)
        defer {
            active -= 1
            limiter.release()
        }

        try await Task.sleep(for: .milliseconds(30))
    }
}
