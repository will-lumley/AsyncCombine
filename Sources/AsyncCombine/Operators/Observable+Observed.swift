//
//  Observable+Observed.swift
//  AsyncCombine
//
//  Created by William Lumley on 16/9/2025.
//

import Observation

public extension Observable where Self: AnyObject {

    /// Creates an `AsyncStream` that emits values of a given property whenever
    /// it changes, using Swift's Observation framework.
    ///
    /// This is the Async/await equivalent of Combine’s `Publisher`-based key-path
    /// observation, but designed to integrate seamlessly with Swift Concurrency.
    /// The returned stream:
    ///  - Immediately yields the current value of the property.
    ///  - Emits a new value each time the property changes.
    ///  - Finishes automatically if the observed object is deallocated.
    ///
    /// - Parameters:
    ///   - keyPath: The key path of the property to observe.
    ///   - isolation: The actor that owns the observed object. Values are read and
    ///   emitted on this actor, so it **must** be the same actor the object is mutated
    ///   on. Defaults to the main actor, which is correct for the usual `@MainActor`
    ///   `@Observable` model; pass your own actor if the model lives on one instead.
    /// - Returns: An `AsyncStream` that produces values whenever the property changes.
    ///
    /// ### Example
    ///
    /// ```swift
    /// import AsyncCombine
    /// import Observation
    ///
    /// @Observable @MainActor
    /// final class CounterViewModel {
    ///     var count: Int = 0
    /// }
    ///
    /// let viewModel = CounterViewModel()
    ///
    /// Task {
    ///     for await value in viewModel.observed(\.count) {
    ///         print("Count changed:", value)
    ///     }
    /// }
    ///
    /// viewModel.count += 1
    /// // Prints: "Count changed: 1"
    /// ```
    ///
    /// The stream ends automatically when `viewModel` is deallocated:
    ///
    /// ```swift
    /// var vm = CounterViewModel()
    ///
    /// Task {
    ///     for await _ in vm.observed(\.count) {
    ///         print("Change observed")
    ///     }
    ///     print("Stream finished") // called when vm is released
    /// }
    ///
    /// vm = nil
    /// ```
    ///
    /// - Important: The observed object must be mutated on `isolation`. Observation
    /// reports a change *before* the new value is stored, so the stream reads the
    /// property one hop later, on `isolation`; that read is ordered after the store
    /// only when the mutation happened on the same actor. A model mutated from some
    /// other context - a bare `Task`, a different actor - can be read before its new
    /// value lands, and that value is then never reported. An `@Observable` with no
    /// isolation at all, written from arbitrary threads, cannot be observed safely by
    /// this operator.
    ///
    /// - Note: The stream is *not* de-duplicated. Because each change re-arms
    /// observation synchronously but reads the property one hop later, a burst of
    /// rapid mutations can deliver the same value more than once — every change is
    /// reported, and several of those reports may resolve to the same latest value.
    /// Consumers that care about distinct values should compare them themselves;
    /// consumers that count events can rely on never missing one.
    ///
    /// - Note: The stream buffers with `.unbounded`, so a slow consumer on a
    /// frequently-mutated property accumulates a backlog rather than silently
    /// dropping values.
    func observed<Value: Sendable>(
        _ keyPath: KeyPath<Self, Value>,
        isolation: any Actor = MainActor.shared
    ) -> AsyncStream<Value> {
        let object = WeakBox(self)
        let kp = NonSendableBox(keyPath)
        let repeater = RepeaterBox()
        let owner = isolation

        // `Self` is a generic parameter, so capturing `object` and `kp` directly inside
        // the `@Sendable` re-arming closure below would capture its metatype too. Erase
        // the read behind one box instead; `nil` means the object has gone away.
        let read = NonSendableBox<() -> Value?>({
            guard let object = object.value else {
                return nil
            }
            return object[keyPath: kp.value]
        })

        return AsyncStream(bufferingPolicy: .unbounded) { continuation in
            Task {
                await perform(on: owner) {
                    guard let value = read.value() else {
                        continuation.finish()
                        return
                    }

                    // Replay current value
                    continuation.yield(value)

                    // Define the tracking body without creating a
                    // nested function to capture.
                    repeater.call = {
                        guard read.value() != nil else {
                            continuation.finish()
                            return
                        }

                        withObservationTracking {
                            // Register the read
                            _ = read.value()
                        } onChange: {
                            // Re-arm synchronously. Tracking is cancelled the moment
                            // this closure returns, so anything deferred to a `Task`
                            // leaves the property unobserved in between — and a mutation
                            // landing in that window is never reported, because the next
                            // registration only fires on the mutation *after* it.
                            repeater.call?()

                            // The read stays deferred: `onChange` runs during `willSet`,
                            // so the new value has not been committed yet and reading
                            // here would yield the previous one. Hopping to `owner` is
                            // what orders this read after the store - the mutating job
                            // holds that actor until it has finished writing.
                            Task {
                                await perform(on: owner) {
                                    guard let value = read.value() else {
                                        continuation.finish()
                                        return
                                    }
                                    continuation.yield(value)
                                }
                            }
                        }
                    }

                    // Start tracking
                    repeater.call?()
                }
            }
        }
    }

}

// MARK: - Private

/// Runs `body` on `actor`'s executor.
///
/// The `isolated` parameter is what does the work: it makes this function run on
/// whichever actor is passed in, letting the caller hop to an actor chosen at runtime
/// rather than one baked in at compile time.
private func perform<T>(
    on actor: isolated any Actor,
    _ body: () -> T
) async -> T {
    return body()
}
