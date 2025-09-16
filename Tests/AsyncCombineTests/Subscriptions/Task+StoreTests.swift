//
//  Task+StoreTests.swift
//  AsyncCombine
//
//  Created by William Lumley on 16/9/2025.
//

@testable import AsyncCombine
import Foundation
import Testing

@Suite("Task+Store Tests")
struct TaskStoreInTests {

    @Test("Inserts Into the Set and Cancels via cancelAll()")
    func insertsAndCancelsAll() async {
        let probe = CancelProbe()
        let sentinel = CancellationSentinel(probe: probe)

        var subscriptions = Set<SubscriptionTask>()
        await sentinel.start()
            .store(in: &subscriptions)

        #expect(subscriptions.count == 1)

        // Cancel everything retained by the set
        subscriptions.cancelAll()
        #expect(subscriptions.isEmpty)

        // ~80 ms
        try? await Task.sleep(nanoseconds: 80_000_000)

        #expect(await probe.wasCancelled())
    }

    @Test("Removing a Stored Task Simply Forgets It (no cancel)")
    func removingSingleTaskDoesNotCancel() async {
        let probe = CancelProbe()
        let sentinel = CancellationSentinel(probe: probe)
        let task = await sentinel.start()

        var subscriptions = Set<SubscriptionTask>()
        task.store(in: &subscriptions)

        let removed = subscriptions.remove(task)
        #expect(removed != nil)
        #expect(subscriptions.isEmpty)

        try? await Task.sleep(nanoseconds: 80_000_000)

        // Task is still alive, so probe has NOT been cancelled
        #expect(await probe.wasCancelled() == false)

        // Cleanup
        subscriptions.cancelAll()
    }

    @Test("Storing the Same Task Twice Does Not Duplicate")
    func setDoesNotDuplicate() async {
        let probe = CancelProbe()
        let sentinel = CancellationSentinel(probe: probe)
        let task = await sentinel.start()

        var subscriptions = Set<SubscriptionTask>()
        task.store(in: &subscriptions)
        task.store(in: &subscriptions)

        #expect(subscriptions.count == 1)

        subscriptions.cancelAll()
        #expect(subscriptions.isEmpty)

        // ~80 ms
        try? await Task.sleep(nanoseconds: 80_000_000)

        #expect(await probe.wasCancelled())
        _ = sentinel
    }

    @Test("Storing a Naturally Finishing Task is Safe")
    func storingCompletedTaskIsSafe() async {
        // A short task that finishes on its own (not cancelled)
        let quick: SubscriptionTask = Task {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        var subscriptions = Set<SubscriptionTask>()
        quick.store(in: &subscriptions)

        #expect(subscriptions.count == 1)

        // Give it time to finish naturally
        try? await Task.sleep(nanoseconds: 30_000_000)

        // Should not crash; set cleanup should still work
        subscriptions.cancelAll()
        #expect(subscriptions.isEmpty)
    }
}
