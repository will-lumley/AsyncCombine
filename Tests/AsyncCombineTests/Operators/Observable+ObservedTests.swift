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
final class ObservedOperatorTests {

    // MARK: - Properties

    var tasks = Set<SubscriptionTask>()

    // MARK: - Types

    @Observable @MainActor
    final class Counter: @unchecked Sendable {
        var count: Int = 0
        init(_ count: Int = 0) {
            self.count = count
        }
    }

    // MARK: - Lifecycle

    deinit {
        self.tasks.cancelAll()
    }

    // MARK: - Tests

    @MainActor
    @Test("Replays Current Value and Then Emits on Subsequent Changes")
    func replayThenChanges() async {
        // Create a counter with a value of 41
        let counter = Counter(41)
        let recorder = Recorder<Int>()

        // GIVEN we listen to the value of our counter
        let stream = counter.observed(\.count)

        // Collect any values via sink
        stream
            .sink { value in
                await recorder.append(value)
            }
            .store(in: &tasks)

        // Give time for initial replay
        try? await Task.sleep(nanoseconds: 30_000_000)

        // THEN the observation first emits 41
        #expect(await recorder.snapshot() == [41])

        // WHEN we set the `count` of `counter` to a bunch of
        // new values.
        await MainActor.run { counter.count = 42 }
        await MainActor.run { counter.count = 43 }
        await MainActor.run { counter.count = 44 }

        try? await Task.sleep(nanoseconds: 80_000_000)

        // THEN our observation records all our new values
        #expect(await recorder.snapshot() == [41, 42, 43, 44])
    }

    @MainActor
    @Test("Does NOT Finish on Deinit; Consumer Should Cancel")
    func noRetainButNoAutoFinish() async {
        // GIVEN a stream from a short-lived Counter and a consumer that drains it
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

        // THEN the source is still alive while we haven't released it
        try? await Task.sleep(nanoseconds: 30_000_000)
        #expect(weakRef != nil)

        // WHEN we drop the last strong reference to the source
        strong = nil

        // THEN the source deallocates but the stream doesn't auto-finish
        #expect(weakRef == nil)
        try? await Task.sleep(nanoseconds: 80_000_000)
        #expect(await done.get() == false)

        // WHEN the caller cancels the consumer
        subs.cancelAll()
        try? await Task.sleep(nanoseconds: 30_000_000)

        // THEN the draining task observes completion
        #expect(await done.get() == true)
    }

    @MainActor
    @Test("Re-Registers Correctly, Multiple Changes All Emit in Order")
    func reregisterHandlesChanges() async {
        // GIVEN an observed counter stream and a recorder
        let counter = Counter(0)
        let stream = counter.observed(\.count)
        let recorder = Recorder<Int>()

        // AND we start collecting via sink
        stream.sink { value in
            await recorder.append(value)
        }
        .store(in: &tasks)

        // THEN we first replay the current value (0)
        try? await Task.sleep(nanoseconds: 30_000_000)
        #expect(await recorder.snapshot() == [0])

        // WHEN we mutate the counter several times on the main actor
        await MainActor.run { counter.count = 1 }
        await MainActor.run { counter.count = 2 }
        await MainActor.run { counter.count = 3 }
        await MainActor.run { counter.count = 4 }
        await MainActor.run { counter.count = 5 }

        // AND give time for the onChange → MainActor → yield loop to flush
        try? await Task.sleep(nanoseconds: 120_000_000)

        // THEN every intermediate value arrives in order
        #expect(await recorder.snapshot() == [0, 1, 2, 3, 4, 5])
    }

    @MainActor
    @Test("Re-Registers Correctly, Multiple Rapid Changes Emit First and Last")
    func reregisterHandlesRapidChanges() async {
        // GIVEN an observed counter stream and a recorder
        let counter = Counter(0)
        let stream = counter.observed(\.count)
        let recorder = Recorder<Int>()

        // AND we start collecting via sink
        stream.sink { value in
            await recorder.append(value)
        }
        .store(in: &tasks)

        // THEN we first replay the current value (0)
        try? await Task.sleep(nanoseconds: 30_000_000)
        #expect(await recorder.snapshot() == [0])

        // WHEN we apply a burst of rapid mutations within one MainActor turn
        await MainActor.run {
            counter.count = 1
            counter.count = 2
            counter.count = 3
            counter.count = 4
            counter.count = 5
        }

        // AND give time for the coalescing/re-registration path
        try? await Task.sleep(nanoseconds: 120_000_000)

        // THEN only the first replay and the final value are emitted
        #expect(await recorder.snapshot() == [0, 5])
    }

    @MainActor
    @Test("Safe to Start Observing After Several Changes - Still Replays the Latest")
    func replayLatestWhenSubscribingLate() async {
        // GIVEN a counter that has already changed before observation
        let counter = Counter(10)
        await MainActor.run {
            counter.count = 11
            counter.count = 12
        }

        // AND we start observing after those changes
        let stream = counter.observed(\.count)
        let rec = Recorder<Int>()

        stream.sink { value in
            await rec.append(value)
        }
        .store(in: &tasks)

        // THEN the current value (12) is replayed immediately
        try? await Task.sleep(nanoseconds: 40_000_000)
        #expect(await rec.snapshot() == [12])

        // WHEN a subsequent change occurs
        await MainActor.run { counter.count = 13 }
        try? await Task.sleep(nanoseconds: 40_000_000)

        // THEN it appends after the replay
        #expect(await rec.snapshot() == [12, 13])
    }

}
