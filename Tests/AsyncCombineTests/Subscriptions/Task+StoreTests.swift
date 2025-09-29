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
        // GIVEN a sentinel task stored in a set
        let probe = CancelProbe()
        let sentinel = CancellationSentinel(probe: probe)

        var subscriptions = Set<SubscriptionTask>()
        await sentinel.start()
            .store(in: &subscriptions)
        #expect(subscriptions.count == 1)

        // WHEN we cancel everything retained by the set
        subscriptions.cancelAll()

        // THEN the set is emptied and the task was cancelled
        #expect(subscriptions.isEmpty)

        try? await Task.sleep(nanoseconds: 80_000_000)
        #expect(await probe.wasCancelled())
    }

    @Test("Removing a Stored Task Simply Forgets It (no cancel)")
    func removingSingleTaskDoesNotCancel() async {
        // GIVEN a sentinel task stored in a set
        let probe = CancelProbe()
        let sentinel = CancellationSentinel(probe: probe)
        let task = await sentinel.start()

        var subscriptions = Set<SubscriptionTask>()
        task.store(in: &subscriptions)

        // WHEN we remove it from the set (without cancelling)
        let removed = subscriptions.remove(task)

        // THEN the set is empty, but the task is still alive
        #expect(removed != nil)
        #expect(subscriptions.isEmpty)

        try? await Task.sleep(nanoseconds: 80_000_000)
        #expect(await probe.wasCancelled() == false)

        // Cleanup
        subscriptions.cancelAll()
    }

    @Test("Storing the Same Task Twice Does Not Duplicate")
    func setDoesNotDuplicate() async {
        // GIVEN a sentinel task
        let probe = CancelProbe()
        let sentinel = CancellationSentinel(probe: probe)
        let task = await sentinel.start()

        var subscriptions = Set<SubscriptionTask>()

        // WHEN we store the same task twice
        task.store(in: &subscriptions)
        task.store(in: &subscriptions)

        // THEN the set contains only one instance
        #expect(subscriptions.count == 1)

        subscriptions.cancelAll()
        #expect(subscriptions.isEmpty)

        try? await Task.sleep(nanoseconds: 80_000_000)
        #expect(await probe.wasCancelled())
        _ = sentinel
    }

    @Test("Storing a Naturally Finishing Task is Safe")
    func storingCompletedTaskIsSafe() async {
        // GIVEN a short task that finishes on its own
        let quick: SubscriptionTask = Task {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        var subscriptions = Set<SubscriptionTask>()
        quick.store(in: &subscriptions)
        #expect(subscriptions.count == 1)

        // WHEN we give it time to finish naturally
        try? await Task.sleep(nanoseconds: 30_000_000)

        // THEN cleanup via cancelAll still works safely
        subscriptions.cancelAll()
        #expect(subscriptions.isEmpty)
    }
}
