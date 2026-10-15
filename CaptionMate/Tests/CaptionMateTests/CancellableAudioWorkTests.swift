@testable import CaptionMate
import Foundation
import XCTest

final class CancellableAudioWorkTests: XCTestCase {
    func testReturnsSuccessfulValue() async throws {
        let value = try await CancellableAudioWork.run { 42 }

        XCTAssertEqual(value, 42)
    }

    func testPreservesOperationError() async {
        do {
            let _: Int = try await CancellableAudioWork.run {
                throw AudioWorkTestError.decodeFailed
            }
            XCTFail("The decoder error must reach the caller.")
        } catch {
            XCTAssertEqual(error as? AudioWorkTestError, .decodeFailed)
        }
    }

    func testAlreadyCancelledCallerDoesNotStartOperation() async {
        let gate = AudioWorkTestGate()
        gate.resume()
        let caller = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await CancellableAudioWork.run {
                try gate.perform(cooperatesWithCancellation: false)
            }
        }

        await assertCancelled(caller)
        XCTAssertFalse(gate.snapshot.didStart)
    }

    func testCancellationReachesActualWorker() async {
        let gate = AudioWorkTestGate()
        let caller = Task {
            try await CancellableAudioWork.run {
                try gate.perform(cooperatesWithCancellation: true)
            }
        }
        defer {
            caller.cancel()
            gate.resume()
        }

        await fulfillment(of: [gate.started], timeout: 5)
        caller.cancel()
        gate.resume()

        await assertCancelled(caller)
        let snapshot = gate.snapshot
        XCTAssertEqual(snapshot.observedCancellation, true)
        XCTAssertTrue(snapshot.didFinish, "The worker must finish before its caller returns.")
    }

    func testDiscardsLateNoncooperativeResultAfterWorkerFinishes() async {
        let gate = AudioWorkTestGate()
        let caller = Task {
            try await CancellableAudioWork.run {
                try gate.perform(cooperatesWithCancellation: false)
            }
        }
        defer {
            caller.cancel()
            gate.resume()
        }

        await fulfillment(of: [gate.started], timeout: 5)
        caller.cancel()
        gate.resume()

        await assertCancelled(caller)
        XCTAssertTrue(gate.snapshot.didFinish, "Cancellation must not abandon the synchronous worker.")
    }

    private func assertCancelled(
        _ caller: Task<Int, Error>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await caller.value
            XCTFail("A cancelled result must not reach inference.", file: file, line: line)
        } catch {
            XCTAssertTrue(error is CancellationError, "Unexpected error: \(error)", file: file, line: line)
        }
    }
}

private enum AudioWorkTestError: Error, Equatable {
    case decodeFailed
    case gateTimedOut
}

// Only the detached worker blocks. The async test waits for an explicit start signal.
private final class AudioWorkTestGate: @unchecked Sendable {
    struct Snapshot {
        var didStart = false
        var observedCancellation: Bool?
        var didFinish = false
    }

    let started = XCTestExpectation(description: "Synchronous audio worker started")
    private let resumeSignal = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var state = Snapshot()

    var snapshot: Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    func resume() {
        resumeSignal.signal()
    }

    func perform(cooperatesWithCancellation: Bool) throws -> Int {
        lock.lock()
        state.didStart = true
        lock.unlock()
        started.fulfill()
        defer {
            lock.lock()
            state.didFinish = true
            lock.unlock()
        }

        guard resumeSignal.wait(timeout: .now() + 10) == .success else {
            throw AudioWorkTestError.gateTimedOut
        }
        lock.lock()
        state.observedCancellation = Task.isCancelled
        lock.unlock()
        if cooperatesWithCancellation {
            try Task.checkCancellation()
        }
        return 42
    }
}
