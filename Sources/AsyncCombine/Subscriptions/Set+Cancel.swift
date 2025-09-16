//
//  Set+Cancel.swift
//  AsyncCombine
//
//  Created by William Lumley on 16/9/2025.
//

public extension Set where Element == SubscriptionTask {

    /// Cancels all subscription tasks in the set and removes them.
    ///
    /// This is a convenience for tearing down multiple active subscriptions at once.
    /// Each task in the set is cancelled, and the set is then emptied.
    ///
    /// - Note: Cancelling a subscription task stops the underlying
    ///   `AsyncSequence` iteration and prevents further values from being delivered.
    ///
    /// ## Example
    /// ```swift
    /// var subscriptions = Set<SubscriptionTask>()
    ///
    /// relay.stream()
    ///     .sink { value in print("Got:", value) }
    ///     .store(in: &subscriptions)
    ///
    /// relay.stream()
    ///     .assign(to: \.text, on: label)
    ///     .store(in: &subscriptions)
    ///
    /// // Later, when cleaning up:
    /// subscriptions.cancelAll()
    /// // All active subscriptions are cancelled and the set is empty.
    /// ```
    mutating func cancelAll() {
        for task in self {
            task.cancel()
        }

        self.removeAll()
    }

}
