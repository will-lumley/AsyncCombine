//
//  Set+CancelTests.swift
//  AsyncCombine
//
//  Created by William Lumley on 16/9/2025.
//

@testable import AsyncCombine
import Testing

@Suite("Set+Cancel Tests")
struct SetCancelTests {

    @Test("Cancels All Tasks and Empties the Set")
    func cancelsAndEmpties() async {
        // GIVEN three live sentinels whose tasks are stored in the set
        let probes = (0..<3).map { _ in CancelProbe() }
        let sentinels = probes.map { CancellationSentinel(probe: $0) }

        var subscriptions = Set<SubscriptionTask>()
        for sentinel in sentinels {
            await sentinel.start()
                .store(in: &subscriptions)
        }

        #expect(subscriptions.count == 3)

        // WHEN cancelling all
        subscriptions.cancelAll()

        // THEN set is empty and all tasks reported cancellation
        // via the probes.
        #expect(subscriptions.isEmpty)

        // ~80 ms
        try? await Task.sleep(nanoseconds: 80_000_000)

        for probe in probes {
            #expect(await probe.wasCancelled())
        }
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
        await sentinel.start()
            .store(in: &subscriptions)

        subscriptions.cancelAll()
        #expect(subscriptions.isEmpty)

        // Call again — should remain empty and not crash
        subscriptions.cancelAll()
        #expect(subscriptions.isEmpty)

        // ~80 ms
        try? await Task.sleep(nanoseconds: 80_000_000)

        #expect(await probe.wasCancelled())
        _ = sentinel
    }

    @Test("Removes Tasks Even if Some Already Completed")
    func removesAlreadyCompletedTasks() async {
        // A task that finishes quickly (not cancelled)
        let quickTask: SubscriptionTask = Task {
            // finish naturally
            try? await Task.sleep(nanoseconds: 10_000_000)
            // No cancellation mark expected
        }

        // A long-lived task owned by a sentinel that should be cancelled
        let longProbe = CancelProbe()
        let longSentinel = CancellationSentinel(probe: longProbe)
        let longTask = await longSentinel.start()

        var subscriptions = Set<SubscriptionTask>()
        quickTask.store(in: &subscriptions)
        longTask.store(in: &subscriptions)

        #expect(subscriptions.count == 2)

        // Give quickTask time to finish on its own
        try? await Task.sleep(nanoseconds: 30_000_000)

        subscriptions.cancelAll()
        #expect(subscriptions.isEmpty)

        // ~80 ms
        try? await Task.sleep(nanoseconds: 80_000_000)

        // quickTask should have completed (not cancelled); only longSentinel marks its probe
        #expect(await longProbe.wasCancelled())
        _ = longSentinel
    }
}
