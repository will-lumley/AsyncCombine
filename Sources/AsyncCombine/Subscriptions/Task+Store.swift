//
//  Task+Store.swift
//  AsyncCombine
//
//  Created by William Lumley on 16/9/2025.
//

public extension Task where Success == Void, Failure == Never {

    /// Stores this subscription task in the given set, keeping it alive
    /// for as long as the set retains it.
    ///
    /// Use this to manage the lifetime of multiple subscriptions in one place.
    /// When you later call ``Set/cancelAll()`` or remove the task from the set,
    /// the subscription is cancelled.
    ///
    /// - Parameter set: The set to insert this subscription task into.
    ///
    /// ## Example
    /// ```swift
    /// var subscriptions = Set<SubscriptionTask>()
    ///
    /// relay.stream()
    ///     .sink { value in
    ///         print("Got:", value)
    ///     }
    ///     .store(in: &subscriptions)
    ///
    /// // The subscription stays active until:
    /// subscriptions.cancelAll()
    /// ```
    func store(in set: inout Set<SubscriptionTask>) {
        set.insert(self)
    }

}
