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
    /// - Parameter keyPath: The key path of the property to observe.
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
    /// - Important: The returned stream should be consumed on the main actor,
    /// since the Observation system requires property access and registration
    /// to happen on the actor that owns the model.
    ///
    /// - Note: The stream is *not* de-duplicated. Because each change re-arms
    /// observation synchronously but reads the property one hop later (see below),
    /// a burst of rapid mutations can deliver the same value more than once — every
    /// change is reported, and several of those reports may resolve to the same
    /// latest value. Consumers that care about distinct values should compare them
    /// themselves; consumers that count events can rely on never missing one.
    ///
    /// - Note: The stream buffers with `.unbounded`, so a slow consumer on a
    /// frequently-mutated property accumulates a backlog rather than silently
    /// dropping values.
    func observed<Value: Sendable>(
        _ keyPath: KeyPath<Self, Value>
    ) -> AsyncStream<Value> {
        let object = WeakBox(self)
        let kp = NonSendableBox(keyPath)
        let repeater = RepeaterBox()

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
            Task { @MainActor in
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
                        // Re-arm synchronously. Tracking is cancelled the moment this
                        // closure returns, so anything deferred to a `Task` leaves the
                        // property unobserved in between — and a mutation landing in that
                        // window is never reported, because the next registration only
                        // fires on the mutation *after* it.
                        repeater.call?()

                        // The read stays deferred: `onChange` runs during `willSet`, so
                        // the new value has not been committed yet and reading here would
                        // yield the previous one.
                        Task { @MainActor in
                            guard let value = read.value() else {
                                continuation.finish()
                                return
                            }
                            continuation.yield(value)
                        }
                    }
                }

                // Start tracking
                repeater.call?()
            }
        }
    }

}
