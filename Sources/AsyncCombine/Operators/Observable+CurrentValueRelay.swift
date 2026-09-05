//
//  Observable+CurrentValueRelay.swift
//  AsyncCombine
//
//  Created by William Lumley on 18/9/2025.
//

import Observation

public extension Observable where Self: AnyObject {

    /// Zero-argument bridge: returns a `CurrentValueRelay` seeded from the first emission,
    /// plus the pumping task you should store to keep the bridge alive.
    ///
    /// This avoids “double initial” issues because your `observed(_:)` already replays
    /// the current value as the first element.
    ///
    /// - Parameters:
    ///   - keyPath: The key path of the property to observe.
    ///   - isolation: The actor that owns the observed object, forwarded to
    ///   ``observed(_:isolation:)``. See that operator for why the object must be
    ///   mutated on this actor.
    func observedRelay<Value: Sendable>(
        _ keyPath: KeyPath<Self, Value>,
        isolation: any Actor = MainActor.shared
    ) -> CurrentValueRelay<Value> {
        // Seed from the current value synchronously on the main actor
        let relay = CurrentValueRelay(self[keyPath: keyPath])

        // Start forwarding changes; keep the task alive by attaching it to the relay
        let stream = observed(keyPath, isolation: isolation)
        let feed: SubscriptionTask = Task {
            for await value in stream {
                await relay.send(value)
            }
        }

        Task {
            await relay.attach(feed: feed)
        }
        return relay

    }

}
