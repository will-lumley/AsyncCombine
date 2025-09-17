//
//  Observable+Observed.swift
//  AsyncCombine
//
//  Created by William Lumley on 16/9/2025.
//

import Observation

@available(iOS 17.0, macOS 14.0, watchOS 10, *)
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
    func observed<Value: Sendable>(
        _ keyPath: KeyPath<Self, Value>
    ) -> AsyncStream<Value> {
        let object = WeakBox(self)
        let kp = NonSendableBox(keyPath)
        let repeater = RepeaterBox()

        return AsyncStream { continuation in
            Task { @MainActor in
                guard let value = object.value else {
                    continuation.finish()
                    return
                }

                // Replay current value
                continuation.yield(value[keyPath: kp.value])

                // Define the tracking body without creating a
                // nested function to capture.
                repeater.call = {
                    guard let obj = object.value else {
                        continuation.finish()
                        return
                    }
                    withObservationTracking {
                        // Register the read
                        _ = obj[keyPath: kp.value]
                    } onChange: {
                        Task { @MainActor in
                            guard let value = object.value else {
                                continuation.finish()
                                return
                            }
                            continuation.yield(value[keyPath: kp.value])

                            // Re-register for next change
                            repeater.call?()
                        }
                    }
                }

                // Start tracking
                repeater.call?()
            }
        }
    }

}
