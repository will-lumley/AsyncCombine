//
//  AsyncSequence+Operators.swift
//  AsyncCombine
//
//  Created by William Lumley on 16/9/2025.
//

public extension AsyncSequence where Element: Sendable, Self: Sendable {

    /// Subscribes to the sequence, calling the provided closure for each element,
    /// and returns a cancellable task you can store or cancel.
    ///
    /// This operator works similarly to Combine’s ``Publisher/sink(receiveCompletion:receiveValue:)``.
    /// It consumes values from the asynchronous sequence, invoking `receiveValue` for
    /// each element. If the sequence terminates with an error, the `receiveError`
    /// closure is invoked instead.
    ///
    /// Use this to bridge an `AsyncSequence` into your application’s side effects
    /// or UI updates, while holding onto the returned ``SubscriptionTask`` to manage
    /// the subscription’s lifetime.
    ///
    /// - Parameters:
    ///   - receiveError: A closure to call if the sequence throws an error
    ///     (other than cancellation). Defaults to a no-op.
    ///   - receiveFinished: An asynchronous closure that is called once all values are emitted.
    ///   - receiveValue: An asynchronous closure to process each emitted element.
    ///     Executed for every value produced by the sequence.
    /// - Returns: A ``SubscriptionTask`` you can store in a collection
    ///   (e.g. `Set<SubscriptionTask>`) or cancel to end the subscription early.
    ///
    /// - Note: Cancelling the returned task stops iteration of the sequence.
    ///
    /// ## Example
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
    /// relay.send(2) // Prints "Got: 2"
    ///
    /// // Later, cancel the subscription
    /// subscriptions.first?.cancel()
    /// ```
    @discardableResult
    func sink(
        catching receiveError: @escaping ReceiveError<Error> = { _ in },
        finished receiveFinished: @escaping ReceiveFinished = {},
        _ receiveValue: @escaping ReceiveElement<Element>
    ) -> SubscriptionTask {
        return Task {
            do {
                for try await element in self {
                    await receiveValue(element)
                }
                await receiveFinished()
            } catch is CancellationError {
                // Expected on cancel
            } catch {
                // We received an error :(
                receiveError(error)
            }
        }
    }

    /// Like `sink`, but guarantees the value/finish handlers run on the main actor.
    @discardableResult
    func sinkOnMain(
        catching receiveError: @escaping MainActorReceiveError<Error> = { _ in },
        finished receiveFinished: @escaping MainActorReceiveFinished = {},
        _ receiveValue: @escaping MainActorReceiveElement<Element>
    ) -> SubscriptionTask {
        return Task {
            do {
                for try await element in self {
                    await receiveValue(element)
                }
                await receiveFinished()
            } catch is CancellationError {
                // Expected on cancel
            } catch {
                await receiveError(error)
            }
        }
    }

}
