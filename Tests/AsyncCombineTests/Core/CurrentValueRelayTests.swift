//
//  CurrentValueRelayTests.swift
//  AsyncCombine
//
//  Created by William Lumley on 15/9/2025.
//

@testable import AsyncCombine
import Foundation
import Testing

@Suite("CurrentValueRelayTests", .timeLimit(.minutes(1)))
struct CurrentValueRelayTests {

    @Test("Replays Initial Value to a New Subscriber")
    func replayInitialValue() async {
        // GIVEN we have a relay of 42
        let relay = CurrentValueRelay<Int>(42)

        // WHEN we subscribe to the relay
        let stream = relay.stream()

        // THEN we should immediately receive the value of 42
        #expect(await stream.collect() == 42)
    }

    @Test("Emits Subsequent Updates to Existing Subscribers")
    func emitsSubsequentUpdates() async {
        // GIVEN we have a relay of 0
        let relay = CurrentValueRelay<Int>(0)

        // WHEN we subscribe to the relay
        let stream = relay.stream()

        try? await Task.sleep(nanoseconds: 40_000_000)

        // WHEN we send through 1 and 2
        await relay.send(1)
        await relay.send(2)

        // THEN we should receive 1, 2, and 3
        let values = await stream.collect(count: 3)
        #expect(values == [0, 1, 2])
    }

    @Test("Replays the Latest Value to Late Subscribers (replay 1 semantics)")
    func replaysLatestToLateSubscriber() async {
        let relay = CurrentValueRelay<String>("A")

        // Advance state before anyone subscribes
        await relay.send("B")
        await relay.send("C")

        // New subscriber should immediately get "C"
        let value = await relay.stream().collect()
        #expect(value == "C")
    }

    @Test("Multicasts the Same Updates to Multiple Subscribers")
    func multicastsToMultipleSubscribers() async {
        let relay = CurrentValueRelay<Int>(10)

        // Two independent subscribers
        let stream1 = relay.stream()
        let stream2 = relay.stream()

        try? await Task.sleep(nanoseconds: 40_000_000)

        // Push two updates
        await relay.send(11)
        await relay.send(12)

        // Each should see: initial 10, then 11, 12
        let aValues = await stream1.collect(count: 3)
        let bValues = await stream2.collect(count: 3)

        #expect(aValues == [10, 11, 12])
        #expect(bValues == [10, 11, 12])
    }

    @Test("ValueStorage Reflects the Latest Sent Value")
    func valueStorageTracksLatest() async {
        let relay = CurrentValueRelay<Int>(5)
        #expect(await relay.valueStorage == 5)

        await relay.send(9)
        #expect(await relay.valueStorage == 9)

        await relay.send(13)
        #expect(await relay.valueStorage == 13)
    }

}
