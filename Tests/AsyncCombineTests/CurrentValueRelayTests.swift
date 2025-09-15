//
//  CurrentValueRelayTests.swift
//  AsyncCombine
//
//  Created by William Lumley on 15/9/2025.
//

import Foundation
import Testing

@Suite("CurrentValueRelayTests")
struct CurrentValueRelayTests {

    @Test("Replays Initial Value to a New Subscriber")
    func replayInitialValue() async {
        let relay = CurrentValueRelay<Int>(42)

        // First subscriber should immediately receive 42
        let value = await relay.stream().collect()
        #expect(value == 42)
    }

    @Test("Emits Subsequent Updates to Existing Subscribers")
    func emitsSubsequentUpdates() async {
        let relay = CurrentValueRelay<Int>(0)

        // Start consuming before sending updates
        let stream = await relay.stream()

        // Produce a few values
        await relay.send(1)
        await relay.send(2)

        // Expect: replay(1) of initial 0, then 1 and 2
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
        let stream1 = await relay.stream()
        let stream2 = await relay.stream()

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
