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
///     for await value in await relay.stream() {
///         print("Received:", value)
///     }
/// }
///
/// await relay.send(1) // prints "Received: 1"
/// await relay.send(2) // prints "Received: 2"
/// ```
public actor CurrentValueRelay<Value: Sendable> {

    // MARK: - Properties

    /// The most recent value stored and replayed by this relay.
    ///
    /// When new listeners subscribe via ``stream()``, this value is emitted first,
    /// ensuring they always begin with the latest known state.
    public private(set) var value: Value

    /// The set of active continuations currently subscribed to updates from this relay.
    ///
    /// Each continuation is identified by a `UUID` and receives values through
    /// the `AsyncStream` produced by ``stream()``.
    private var continuations = [UUID: AsyncStream<Value>.Continuation]()

    /// Active background tasks that feed values into the relay.
    ///
    /// Each task forwards values from an external `AsyncSequence` into the relay
    /// via ``send(_:)``. Tasks are retained for the lifetime of the relay and
    /// automatically cancelled when the relay is deallocated.
    private var feeds = [UUID: SubscriptionTask]()

    // MARK: - Lifecycle

    /// Creates a new relay with the given initial value.
    ///
    /// - Parameter initial: The value to seed the relay with.
    ///   This value is immediately replayed to new subscribers.
    public init(_ initial: Value) {
        self.value = initial
    }

    deinit {
        // Best effort, cancel any active pumps
        for feed in self.feeds.values {
            feed.cancel()
        }
        self.feeds.removeAll()
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
        self.value = newValue
        for continuation in continuations.values {
            continuation.yield(newValue)
        }
    }

    /// Attaches a background task as a feed for this relay.
    ///
    /// The feed is retained for the relay’s lifetime and cancelled
    /// automatically when the relay is deallocated.
    func attach(feed: SubscriptionTask) {
        self.feeds[UUID()] = feed
    }

    /// Returns an `AsyncStream` that emits the relay’s current value immediately
    /// (replay-1), followed by all subsequent updates.
    ///
    /// - Returns: An `AsyncStream` of values from this relay.
    ///
    /// The stream terminates automatically when the caller’s task is cancelled,
    /// or when the continuation is explicitly terminated.
    ///
    /// Because the relay is an actor, the continuation is registered and the
    /// current value replayed *before* this method returns. This guarantees
    /// deterministic replay-then-updates ordering with no dropped values, even
    /// if you `send(_:)` immediately afterwards.
    ///
    /// ```swift
    /// let relay = CurrentValueRelay("initial")
    ///
    /// Task {
    ///     for await value in await relay.stream() {
    ///         print("Got:", value)
    ///     }
    /// }
    ///
    /// await relay.send("update")
    /// // Prints:
    /// // "Got: initial"
    /// // "Got: update"
    /// ```
    func stream() -> AsyncStream<Value> {
        let (stream, continuation) = AsyncStream<Value>.makeStream()
        let id = UUID()

        // Register synchronously while isolated on the actor, then replay the
        // latest value, so no updates can race ahead of registration.
        self.continuations[id] = continuation
        continuation.yield(self.value)

        // If the continuation is terminated
        continuation.onTermination = { [weak self] _ in
            Task {
                await self?.unregister(id: id)
            }
        }

        return stream
    }

}

// MARK: - Private

private extension CurrentValueRelay {

    /// Unregisters and removes the continuation associated with the given ID.
    ///
    /// - Parameter id: The identifier of the continuation to remove.
    func unregister(id: UUID) {
        self.continuations.removeValue(forKey: id)
    }

}
