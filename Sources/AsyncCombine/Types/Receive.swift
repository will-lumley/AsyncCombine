//
//  Untitled.swift
//  AsyncCombine
//
//  Created by William Lumley on 16/9/2025.
//

/// A closure type that asynchronously handles elements emitted by an `AsyncSequence`.
///
/// Used by operators like ``AsyncSequence/sink(catching:_:)`` to process
/// each value produced by the sequence.
///
/// - Parameter element: The element emitted by the sequence.
public typealias ReceiveElement<Element> = @Sendable (Element) async -> Void

/// A closure type that handles failures thrown during iteration of an `AsyncSequence`.
///
/// This is generic over the failure type, mirroring Combine-style APIs so you
/// can specialize error handling when you have a concrete error type.
///
/// - Parameter failure: The error thrown by the sequence.
public typealias ReceiveError<Failure: Error> = @Sendable (Failure) -> Void

/// A closure type that is invoked when an `AsyncSequence` finishes successfully.
///
/// Used by operators like ``AsyncSequence/sink(catching:finished:_:)`` to provide
/// a notification once the sequence has emitted all of its elements without error.
///
/// This closure is executed only once, after iteration ends normally. If the sequence
/// terminates due to cancellation or an error, the closure will not be called.
/// To handle errors, use ``ReceiveError`` instead.
///
/// The closure is `async` so you can perform asynchronous work when responding
/// to sequence completion (for example, saving state or updating UI).
///
/// ## Example
///
/// ```swift
/// let relay = CurrentValueRelay(0)
/// var subscriptions = Set<SubscriptionTask>()
///
/// relay.stream()
///     .sink(
///         finished: {
///             await print("Sequence finished!")
///         },
///         { value in
///             await print("Got value:", value)
///         }
///     )
///     .store(in: &subscriptions)
/// ```
public typealias ReceiveFinished = @Sendable () async -> Void

/// This is the same as the `ReceiveElement` alias but only executes on the
/// main thread.
public typealias MainActorReceiveElement<Element> = @MainActor @Sendable (Element) async -> Void

/// This is the same as the `ReceiveError` alias but only executes on the
/// main thread.
public typealias MainActorReceiveError<Failure: Error> = @MainActor @Sendable (Failure) -> Void

/// This is the same as the `ReceiveFinished` alias but only executes on the
/// main thread.
public typealias MainActorReceiveFinished = @MainActor @Sendable () async -> Void
