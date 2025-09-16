//
//  Observable+ObservedTests.swift
//  AsyncCombine
//
//  Created by William Lumley on 16/9/2025.
//

@testable import AsyncCombine
import Foundation
import Observation
import Testing

@Suite("Observable+Observed Tests")
struct ObservedOperatorTests {

    // MARK: - Types

    @Observable @MainActor
    final class Counter: @unchecked Sendable {
        var count: Int = 0
        init(_ count: Int = 0) { self.count = count }
    }

    // MARK: - Tests

    @MainActor
    @Test("Replays current value and then emits on subsequent changes")
    func replayThenChanges() async {
        let counter = Counter(41)
        let stream = counter.observed(\.count)

        let rec = Recorder<Int>()
        var subs = Set<SubscriptionTask>()

        // Collect via sink
        stream.sink { value in
            await rec.append(value)
        }
        .store(in: &subs)

        // Give time for initial replay
        try? await Task.sleep(nanoseconds: 30_000_000)
        #expect(await rec.snapshot() == [41])

        // Mutate a few times on main actor
        await MainActor.run { counter.count = 42 }
        await MainActor.run { counter.count = 43 }
        await MainActor.run { counter.count = 44 }

        try? await Task.sleep(nanoseconds: 80_000_000)
        #expect(await rec.snapshot() == [41, 42, 43, 44])

        subs.cancelAll()
    }

    @MainActor
    @Test("Does NOT Finish on Deinit; Consumer Should Cancel")
    func noRetainButNoAutoFinish() async {
        var strong: Counter? = Counter(1)
        weak var weakRef = strong
        let stream = strong!.observed(\.count)

        let done = AsyncBox(false)
        let consumer: SubscriptionTask = Task {
            for await _ in stream { /* drain */ }
            await done.set(true)
        }
        var subs = Set<SubscriptionTask>()
        consumer.store(in: &subs)

        try? await Task.sleep(nanoseconds: 30_000_000)
        #expect(weakRef != nil)

        strong = nil
        #expect(weakRef == nil)

        // Give it time — still not finished because no more change events
        try? await Task.sleep(nanoseconds: 80_000_000)
        #expect(await done.get() == false)

        // Caller cancels to end consumption
        subs.cancelAll()
        try? await Task.sleep(nanoseconds: 30_000_000)
        #expect(await done.get() == true)
    }


    @MainActor
    @Test("Re-Registers Correctly, Multiple Changes All Emit in Order")
    func reregisterHandlesChanges() async {
        let counter = Counter(0)
        let stream = counter.observed(\.count)

        let recorder = Recorder<Int>()
        var subs = Set<SubscriptionTask>()
        stream.sink { value in
            await recorder.append(value)
        }
        .store(in: &subs)

        // Allow initial replay (0)
        try? await Task.sleep(nanoseconds: 30_000_000)
        #expect(await recorder.snapshot() == [0])

        // Burst of quick changes on the main actor
        await MainActor.run { counter.count = 1 }
        await MainActor.run { counter.count = 2 }
        await MainActor.run { counter.count = 3 }
        await MainActor.run { counter.count = 4 }
        await MainActor.run { counter.count = 5 }

        // Give time for the onChange->MainActor->yield loop to process all
        try? await Task.sleep(nanoseconds: 120_000_000)

        #expect(await recorder.snapshot() == [0, 1, 2, 3, 4, 5])

        subs.cancelAll()
    }

    @MainActor
    @Test("Re-Registers Correctly, Multiple Rapid Changes Emit First and Last")
    func reregisterHandlesRapidChanges() async {
        let counter = Counter(0)
        let stream = counter.observed(\.count)

        let recorder = Recorder<Int>()
        var subs = Set<SubscriptionTask>()
        stream.sink { value in
            await recorder.append(value)
        }
        .store(in: &subs)

        // Allow initial replay (0)
        try? await Task.sleep(nanoseconds: 30_000_000)
        #expect(await recorder.snapshot() == [0])

        // Burst of quick changes on the main actor
        await MainActor.run {
            counter.count = 1
            counter.count = 2
            counter.count = 3
            counter.count = 4
            counter.count = 5
        }

        // Give time for the onChange->MainActor->yield loop to process all
        try? await Task.sleep(nanoseconds: 120_000_000)

        #expect(await recorder.snapshot() == [0, 5])

        subs.cancelAll()
    }

    @MainActor
    @Test("Safe to Start Observing After Several Changes - Still Replays the Latest")
    func replayLatestWhenSubscribingLate() async {
        let counter = Counter(10)

        // Change the value a few times before observing
        await MainActor.run {
            counter.count = 11
            counter.count = 12
        }

        let stream = counter.observed(\.count)
        let rec = Recorder<Int>()
        var subs = Set<SubscriptionTask>()
        stream.sink { value in
            await rec.append(value)
        }
        .store(in: &subs)

        // Should replay current value (12) immediately
        try? await Task.sleep(nanoseconds: 40_000_000)
        #expect(await rec.snapshot() == [12])

        // Further changes should append
        await MainActor.run { counter.count = 13 }
        try? await Task.sleep(nanoseconds: 40_000_000)
        #expect(await rec.snapshot() == [12, 13])

        subs.cancelAll()
    }

}
