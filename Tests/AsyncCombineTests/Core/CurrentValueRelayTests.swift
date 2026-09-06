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
        let stream = await relay.stream()

        // THEN we should immediately receive the value of 42
        #expect(await stream.collect() == 42)
    }

    @Test("Emits Subsequent Updates to Existing Subscribers")
    func emitsSubsequentUpdates() async {
        // GIVEN we have a relay of 0
        let relay = CurrentValueRelay<Int>(0)

        // WHEN we subscribe to the relay
        let stream = await relay.stream()

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

    @Test("Value Reflects the Latest Sent Value")
    func valueTracksLatest() async {
        let relay = CurrentValueRelay<Int>(5)
        #expect(await relay.value == 5)

        await relay.send(9)
        #expect(await relay.value == 9)

        await relay.send(13)
        #expect(await relay.value == 13)
    }

}

// MARK: - values()

@Suite("CurrentValueRelay values() Tests", .timeLimit(.minutes(1)))
struct CurrentValueRelayValuesTests {

    @Test("Replays the Latest Value to a New Synchronous Subscriber")
    func replaysLatestValue() async {
        // GIVEN we have a relay that has already advanced past its initial value
        let relay = CurrentValueRelay<String>("A")
        await relay.send("B")

        // WHEN we subscribe from a synchronous context
        let stream = relay.values()

        // THEN we should immediately receive the latest value
        #expect(await stream.collect() == "B")
    }

    @Test("Emits Subsequent Updates to Existing Subscribers")
    func emitsSubsequentUpdates() async {
        // GIVEN we have a relay of 0 that we've subscribed to
        let relay = CurrentValueRelay<Int>(0)
        let stream = relay.values()

        // Registration happens one hop after `values()` returns, so wait for it
        // before sending; otherwise the updates below race the subscription.
        #expect(await relay.waitForSubscriberCount(1) == 1)

        // WHEN we send through 1 and 2
        await relay.send(1)
        await relay.send(2)

        // THEN we should receive the replayed 0, followed by 1 and 2
        let values = await stream.collect(count: 3)
        #expect(values == [0, 1, 2])
    }

    @Test("Terminating the Stream Unregisters its Continuation")
    func terminationUnregisters() async {
        // GIVEN we have a relay with a live synchronous subscription
        let relay = CurrentValueRelay<Int>(0)
        var stream: AsyncStream<Int>? = relay.values()
        #expect(await relay.waitForSubscriberCount(1) == 1)

        // WHEN the stream is dropped
        stream = nil
        _ = stream

        // THEN its continuation should be unregistered from the relay
        #expect(await relay.waitForSubscriberCount(0) == 0)
    }

    @Test("Dropping the Stream Before Registration Leaves no Orphaned Continuation")
    func droppingBeforeRegistrationLeavesNoOrphan() async {
        // GIVEN we have a relay of 0
        let relay = CurrentValueRelay<Int>(0)

        // WHEN we repeatedly create a stream and drop it immediately, before the
        // registration hop has had a chance to run. This is a race, so we run it
        // enough times to give the losing interleaving a chance to show up.
        for _ in 0..<1_000 {
            _ = relay.values()
        }

        // THEN every one of those registrations must be cleaned up again
        #expect(await relay.waitForSubscriberCount(0, attempts: 500) == 0)

        // AND sending afterwards should not trap on a terminated continuation
        await relay.send(1)
        #expect(await relay.subscriberCount == 0)
    }

    @Test("Multicasts the Same Updates to Multiple Synchronous Subscribers")
    func multicastsToMultipleSubscribers() async {
        // GIVEN we have a relay of 10 with two independent synchronous subscribers
        let relay = CurrentValueRelay<Int>(10)
        let stream1 = relay.values()
        let stream2 = relay.values()

        // Both register one hop after `values()` returns, so wait for them before
        // sending; otherwise the updates below race the subscriptions.
        #expect(await relay.waitForSubscriberCount(2) == 2)

        // WHEN we push two updates
        await relay.send(11)
        await relay.send(12)

        // THEN each subscriber should see the replayed 10, followed by 11 and 12
        let firstValues = await stream1.collect(count: 3)
        let secondValues = await stream2.collect(count: 3)

        #expect(firstValues == [10, 11, 12])
        #expect(secondValues == [10, 11, 12])
    }

    @Test("Cancelling the Returned Task Stops Further Values")
    func cancellingReturnedTaskStopsDelivery() async {
        // GIVEN we have a relay of 0, subscribed to from a synchronous context
        let relay = CurrentValueRelay<Int>(0)
        let recording = RecordingBox<Int>()

        let subscription = relay.values()
            .sink { value in
                await recording.append(value)
            }

        #expect(await relay.waitForSubscriberCount(1) == 1)

        // WHEN we cancel the task that `sink` handed back
        subscription.cancel()

        // THEN the subscription should be unregistered from the relay
        #expect(await relay.waitForSubscriberCount(0) == 0)

        // AND further values should not be delivered
        await relay.send(1)
        #expect(await recording.snapshot().contains(1) == false)
    }

    @Test("A Live Subscription Does Not Retain the Relay")
    func liveSubscriptionDoesNotRetainRelay() async {
        // GIVEN we have a live stream taken from a relay that nothing else retains
        var relay: CurrentValueRelay<Int>? = CurrentValueRelay<Int>(0)
        weak var weakRelay = relay
        let stream = relay?.values()

        // WHEN we drop our own reference to the relay
        relay = nil

        // THEN neither the registration hop nor the termination handler that the
        // stream holds may keep it alive. The registration briefly holds a strong
        // reference while it runs, so poll rather than sampling once.
        for _ in 0..<100 where weakRelay != nil {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(weakRelay == nil)

        // Keep the stream alive across the assertion above: that is the whole
        // point, as a terminated stream releases its handler either way.
        _ = stream
    }

    @Test("Cancelling a Stored Subscription Stops Delivery")
    func cancellingStoredSubscriptionStopsDelivery() async {
        // GIVEN we have a relay of 0, subscribed to from a synchronous context
        let relay = CurrentValueRelay<Int>(0)
        let recording = RecordingBox<Int>()
        var subscriptions = Set<SubscriptionTask>()

        relay.values()
            .sink { value in
                await recording.append(value)
            }
            .store(in: &subscriptions)

        #expect(await relay.waitForSubscriberCount(1) == 1)
        await relay.send(1)

        // Wait for the value we've sent to land before tearing down
        #expect(await recording.waitForCount(2).count == 2)

        // WHEN we cancel everything we've stored
        subscriptions.cancelAll()
        #expect(await relay.waitForSubscriberCount(0) == 0)

        // THEN further values should not be delivered
        await relay.send(2)
        #expect(await recording.snapshot() == [0, 1])
    }

}

// MARK: - Helpers

private extension CurrentValueRelay {

    /// Polls ``subscriberCount`` until it reaches `expected`, giving the
    /// registration and unregistration hops a chance to land.
    ///
    /// Waiting for the count to *arrive* at a value, rather than sampling it
    /// across a fixed window, keeps this robust on a loaded CI machine: a hop
    /// that lands late only delays the result, it never fails the assertion.
    ///
    /// - Parameters:
    ///   - expected: The subscriber count to wait for.
    ///   - attempts: How many 10ms polls to make before giving up.
    /// - Returns: The last count observed, so callers can assert on it.
    func waitForSubscriberCount(_ expected: Int, attempts: Int = 100) async -> Int {
        var count = self.subscriberCount

        for _ in 0..<attempts where count != expected {
            try? await Task.sleep(for: .milliseconds(10))
            count = self.subscriberCount
        }

        return count
    }

}

private extension RecordingBox {

    /// Polls the recorded values until at least `expected` of them have arrived.
    ///
    /// - Parameter expected: The number of values to wait for.
    /// - Returns: The last snapshot observed, so callers can assert on it.
    func waitForCount(_ expected: Int) async -> [T] {
        var values = self.snapshot()

        for _ in 0..<100 where values.count < expected {
            try? await Task.sleep(for: .milliseconds(10))
            values = self.snapshot()
        }

        return values
    }

}
