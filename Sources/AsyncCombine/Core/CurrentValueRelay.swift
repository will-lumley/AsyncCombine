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
///
/// ## Subscribing
///
/// There are two ways to subscribe, and they differ only in *when* the
/// continuation is registered:
///
/// - ``stream()`` is `async`. It registers while isolated on the relay, so it
///   is ordered against any `send(_:)` you make afterwards.
/// - ``values()`` is synchronous. It returns immediately and registers one hop
///   later, which makes it usable from synchronous code such as
///   `configureBindings()` — at the cost of that ordering guarantee.
///
/// ```swift
/// // Synchronous context: `.store(in:)` stays synchronous.
/// relay.values()
///     .removeDuplicates()
///     .sinkOnMain { [weak self] value in
///         self?.apply(value)
///     }
///     .store(in: &self.subscriptions)
/// ```
///
/// - Note: Neither stream finishes when the relay itself deallocates; a
///   subscriber keeps waiting until it is cancelled. This matches
///   ``Observation/Observable/observed(_:)``, so cancel your subscriptions when
///   you are done with them — `store(in:)` them and call `cancelAll()`.
public actor CurrentValueRelay<Value: Sendable> {

    // MARK: - Properties

    /// The most recent value stored and replayed by this relay.
    ///
    /// When new listeners subscribe via ``stream()`` or ``values()``, this value
    /// is emitted first, ensuring they always begin with the latest known state.
    public private(set) var value: Value

    /// The set of active continuations currently subscribed to updates from this relay.
    ///
    /// Each continuation is identified by a `UUID` and receives values through
    /// the `AsyncStream` produced by ``stream()`` or ``values()``.
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
    /// Any listeners created with ``stream()`` or ``values()`` will receive this
    /// value.
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
    ///
    /// ## Choosing between `stream()` and `values()`
    ///
    /// Reach for `stream()` when the ordering against a subsequent `send(_:)`
    /// matters — tests, and any producer/consumer pair that is set up together.
    /// Reach for ``values()`` when you are in a synchronous context and the
    /// relay’s replay of its current value is the only initial state you need.
    func stream() -> AsyncStream<Value> {
        let (stream, continuation) = AsyncStream<Value>.makeStream()
        let id = UUID()

        // Register synchronously while isolated on the actor, then replay the
        // latest value, so no updates can race ahead of registration.
        self.register(id: id, continuation: continuation)

        // If the continuation is terminated
        continuation.onTermination = { [weak self] _ in
            Task {
                await self?.unregister(id: id)
            }
        }

        return stream
    }

    /// Returns an `AsyncStream` that emits the relay’s current value (replay-1)
    /// followed by all subsequent updates, without requiring an `await` at the
    /// call site.
    ///
    /// - Returns: An `AsyncStream` of values from this relay.
    ///
    /// This is the synchronous counterpart to ``stream()``. The stream is handed
    /// back immediately and the continuation is registered on the relay one hop
    /// later, which lets you build a subscription — and, crucially, `store(in:)`
    /// it — from synchronous code:
    ///
    /// ```swift
    /// override func configureBindings() {
    ///     self.nodeModel.voltageRelay.values()
    ///         .removeDuplicates()
    ///         .sinkOnMain { [weak self] signal in
    ///             self?.applyStyle(for: signal)
    ///         }
    ///         .store(in: &self.subscriptions)
    /// }
    /// ```
    ///
    /// - Important: Because registration happens one hop after this method
    ///   returns, a `send(_:)` issued in that window is **not** delivered to this
    ///   stream. The subscriber still receives the relay’s value as of the moment
    ///   it registers, so it never starts without state — but it may miss an
    ///   update made in between, and it may see that update folded into the
    ///   replayed value rather than as a separate element.
    ///
    /// ## Choosing between `values()` and `stream()`
    ///
    /// Reach for `values()` when you are in a synchronous context — UI bindings,
    /// view-model wiring — and the relay’s replay of its current value is the
    /// only initial state you need. Reach for ``stream()`` when the ordering
    /// against a subsequent `send(_:)` matters, such as in tests or when the
    /// producer and consumer are set up together.
    nonisolated func values() -> AsyncStream<Value> {
        let (stream, continuation) = AsyncStream<Value>.makeStream()
        let id = UUID()

        // We cannot touch the actor from here, so hop onto it to register.
        let registration = Task { [weak self] in
            // The subscription may already be gone; skip the pointless hop.
            guard Task.isCancelled == false else {
                return
            }

            await self?.register(id: id, continuation: continuation)
        }

        // The stream can be dropped before the registration above lands, so wait
        // for it to settle before unregistering. That way a registration that
        // wins the race can never leave an orphaned continuation behind.
        continuation.onTermination = { [weak self] _ in
            registration.cancel()

            Task {
                await registration.value
                await self?.unregister(id: id)
            }
        }

        return stream
    }

}

// MARK: - Internal

internal extension CurrentValueRelay {

    /// The number of continuations currently registered with this relay.
    ///
    /// - Important: This exists for the test suite, which asserts that
    ///   subscriptions are unregistered once their streams terminate.
    var subscriberCount: Int {
        self.continuations.count
    }

}

// MARK: - Private

private extension CurrentValueRelay {

    /// Registers the given continuation under `id` and replays the relay’s
    /// current value to it.
    ///
    /// - Parameters:
    ///   - id: The identifier to register the continuation under.
    ///   - continuation: The continuation to receive this relay’s values.
    func register(id: UUID, continuation: AsyncStream<Value>.Continuation) {
        self.continuations[id] = continuation
        continuation.yield(self.value)
    }

    /// Unregisters and removes the continuation associated with the given ID.
    ///
    /// - Parameter id: The identifier of the continuation to remove.
    func unregister(id: UUID) {
        self.continuations.removeValue(forKey: id)
    }

}
