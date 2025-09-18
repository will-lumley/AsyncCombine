//
//  CurrentValueRelay.swift
//  AsyncCombine
//
//  Created by William Lumley on 15/9/2025.
//

import Foundation

/// A concurrency-friendly, replay-1 relay for broadcasting the latest value
/// to multiple listeners using `AsyncStream`.
///
/// `CurrentValueRelay` behaves similarly to Combine’s `CurrentValueSubject`,
/// but is designed for Swift Concurrency. It stores the most recent value
/// and immediately replays it to new subscribers, followed by all subsequent
/// updates.
///
/// This makes it useful for bridging stateful streams of values between
/// domain logic and presentation layers.
///
/// ```swift
/// let relay = CurrentValueRelay(0)
/// var subscriptions = Set<SubscriptionTask>()
///
/// Task {
///     for await value in relay.stream() {
///         print("Received:", value)
///     }
/// }
///
/// relay.send(1) // prints "Received: 1"
/// relay.send(2) // prints "Received: 2"
/// ```
public actor CurrentValueRelay<Value: Sendable> {

    // MARK: - Properties

    /// The most recent value stored and replayed by this relay.
    ///
    /// When new listeners subscribe via ``stream()``, this value is emitted first,
    /// ensuring they always begin with the latest known state.
    public private(set) var valueStorage: Value

    /// The set of active continuations currently subscribed to updates from this relay.
    ///
    /// Each continuation is identified by a `UUID` and receives values through
    /// the `AsyncStream` produced by ``stream()``.
    private var continuations = [UUID: AsyncStream<Value>.Continuation]()

    // MARK: - Lifecycle

    /// Creates a new relay with the given initial value.
    ///
    /// - Parameter initial: The value to seed the relay with.
    ///   This value is immediately replayed to new subscribers.
    public init(_ initial: Value) {
        self.valueStorage = initial
    }

}

// MARK: - Public

public extension CurrentValueRelay {

    /// Sends a new value into the relay, updating its current value
    /// and broadcasting it to all active subscribers.
    ///
    /// - Parameter newValue: The value to set and propagate.
    ///
    /// Any listeners created with ``stream()`` will receive this value.
    func send(_ newValue: Value) {
        valueStorage = newValue
        for continuation in continuations.values {
            continuation.yield(newValue)
        }
    }

    /// Returns an `AsyncStream` that emits the relay’s current value immediately
    /// (replay-1), followed by all subsequent updates.
    ///
    /// - Returns: An `AsyncStream` of values from this relay.
    ///
    /// The stream terminates automatically when the caller’s task is cancelled,
    /// or when the continuation is explicitly terminated.
    ///
    /// ```swift
    /// let relay = CurrentValueRelay("initial")
    ///
    /// Task {
    ///     for await value in relay.stream() {
    ///         print("Got:", value)
    ///     }
    /// }
    ///
    /// relay.send("update")
    /// // Prints:
    /// // "Got: initial"
    /// // "Got: update"
    /// ```
    nonisolated func stream() -> AsyncStream<Value> {
        AsyncStream { continuation in
            let id = UUID()

            // Register our continuation so we can broadcast to it
            // later on.
            Task {
                await self.register(id: id, continuation: continuation)
            }

            // If the continuation is terminated
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.unregister(id: id)
                }
            }
        }
    }

}

// MARK: - Private

private extension CurrentValueRelay {

    /// Registers a continuation and immediately replays the current value to it.
    ///
    /// - Parameters:
    ///   - id: A unique identifier for this continuation.
    ///   - continuation: The continuation to register and notify.
    func register(id: UUID, continuation: AsyncStream<Value>.Continuation) {
        self.continuations[id] = continuation

        // Replay latest value to the continuation
        continuation.yield(self.valueStorage)
    }

    /// Unregisters and removes the continuation associated with the given ID.
    ///
    /// - Parameter id: The identifier of the continuation to remove.
    func unregister(id: UUID) {
        self.continuations.removeValue(forKey: id)
    }

}
