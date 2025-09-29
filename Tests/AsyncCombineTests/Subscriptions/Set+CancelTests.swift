//
//  Set+CancelTests.swift
//  AsyncCombine
//
//  Created by William Lumley on 16/9/2025.
//

@testable import AsyncCombine
import Testing

@Suite(
    "Set+Cancel Tests",
    .serialized,
    .timeLimit(.minutes(1))
)
struct SetCancelTests {

    // MARK: - Helpers

    /// Waits until `condition` returns true or the timeout elapses.
    private func waitUntil(
        _ condition: @Sendable () async -> Bool,
        timeout: Duration = .seconds(1)
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while clock.now < deadline {
            if await condition() { return true }
            await Task.yield()
        }
        return await condition()
    }

    // MARK: - Tests

    @Test("Cancels All Tasks and Empties the Set")
    func cancelsAndEmpties() async {
        // GIVEN three live sentinels whose tasks are stored in the set
        let probes = (0..<3).map { _ in CancelProbe() }
        let sentinels = probes.map { CancellationSentinel(probe: $0) }

        var subscriptions = Set<SubscriptionTask>()
        for sentinel in sentinels {
            await sentinel.start().store(in: &subscriptions)
        }

        #expect(subscriptions.count == 3)

        // WHEN cancelling all
        subscriptions.cancelAll()

        // THEN set is empty and all tasks reported cancellation via the probes
        #expect(subscriptions.isEmpty)

        // Wait deterministically for all probes to observe cancellation
        let allCancelled = await waitUntil({
            for probe in probes {
                if !(await probe.wasCancelled()) { return false }
            }
            return true
        }, timeout: .seconds(1))

        #expect(allCancelled)
        _ = sentinels
    }

    @Test("Calling cancelAll on an Empty Set is a No-Op")
    func emptySetNoOp() {
        var subscriptions = Set<SubscriptionTask>()
        #expect(subscriptions.isEmpty)

        subscriptions.cancelAll()
        #expect(subscriptions.isEmpty)
    }

    @Test("cancelAll is Idempotent")
    func idempotent() async {
        let probe = CancelProbe()
        let sentinel = CancellationSentinel(probe: probe)

        var subscriptions = Set<SubscriptionTask>()
        await sentinel.start().store(in: &subscriptions)

        // WHEN cancelling once
        subscriptions.cancelAll()
        #expect(subscriptions.isEmpty)

        // AND cancelling again — should remain empty and not crash
        subscriptions.cancelAll()
        #expect(subscriptions.isEmpty)

        // THEN the sentinel's probe eventually observes cancellation
        let cancelled = await waitUntil({ await probe.wasCancelled() }, timeout: .seconds(1))
        #expect(cancelled)
        _ = sentinel
    }

    @Test("Removes Tasks Even if Some Already Completed")
    func removesAlreadyCompletedTasks() async {
        // GIVEN a task that finishes quickly (not cancelled)
        let quickTask: SubscriptionTask = Task {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        // AND a long-lived task owned by a sentinel that should be cancelled
        let longProbe = CancelProbe()
        let longSentinel = CancellationSentinel(probe: longProbe)
        let longTask = await longSentinel.start()

        var subscriptions = Set<SubscriptionTask>()
        quickTask.store(in: &subscriptions)
        longTask.store(in: &subscriptions)

        #expect(subscriptions.count == 2)

        // Give quickTask time to finish deterministically
        await quickTask.value

        // WHEN we cancel all
        subscriptions.cancelAll()

        // THEN the set is emptied and the long task reports cancellation
        #expect(subscriptions.isEmpty)

        let longWasCancelled = await waitUntil({ await longProbe.wasCancelled() }, timeout: .seconds(1))
        #expect(longWasCancelled)
        _ = longSentinel
    }

}
