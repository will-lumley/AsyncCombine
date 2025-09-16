//
//  SubscriptionTask.swift
//  AsyncCombine
//
//  Created by William Lumley on 16/9/2025.
//

/// A cancellable task representing an active subscription to an `AsyncSequence`.
///
/// `SubscriptionTask` is returned by operators such as
/// ``AsyncSequence/sink(catching:_:)`` and
/// ``AsyncSequence/assign(to:on:catching:)``.
/// Store these tasks in a collection (for example, a `Set<SubscriptionTask>`)
/// to keep the subscription alive, and cancel them when you no longer
/// need to receive values.
///
/// ```swift
/// let relay = CurrentValueRelay(0)
/// var subscriptions = Set<SubscriptionTask>()
///
/// relay.stream()
///     .sink { value in
///         print("Got:", value)
///     }
///     .store(in: &subscriptions)
///
/// relay.send(1) // Prints "Got: 1"
/// ```
///
/// Cancel the task to stop the subscription:
///
/// ```swift
/// subscriptions.first?.cancel()
/// ```
///
/// - Note: This is a convenience alias for ``Task`` with the signature
///   `Task<Void, Never>`.
public typealias SubscriptionTask = Task<Void, Never>
