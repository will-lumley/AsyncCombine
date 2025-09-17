//
//  AsyncSequence+Assign.swift
//  AsyncCombine
//
//  Created by William Lumley on 16/9/2025.
//

public extension AsyncSequence where Element: Sendable, Self: Sendable {

    /// Assigns each element from the sequence to the given writable key path on an object,
    /// returning a cancellable task that manages the subscription’s lifetime.
    ///
    /// This mirrors Combine’s `assign(to:on:)`. Each emitted element
    /// updates `object[keyPath:]`.
    /// Updates are performed on the **main actor** to keep UI mutations safe.
    ///
    /// - Parameters:
    ///   - keyPath: A writable reference key path on `object` to receive each element.
    ///   - object: The target object whose property will be updated for every value.
    ///   - receiveError: A closure invoked if the sequence throws an error (other than
    ///     cancellation). Defaults to a no-op.
    /// - Returns: A ``SubscriptionTask`` you can store (eg. in
    /// a `Set<SubscriptionTask>`). and cancel to stop receiving values.
    ///
    /// - Important: Property writes occur on the main actor. This makes it suitable for
    ///   updating UI objects like `UILabel` or `NSView` subclasses.
    /// - Note: Cancelling the returned task stops iteration and further assignments.
    /// - SeeAlso: ``AsyncSequence/sink(catching:_:)``
    ///
    /// ## Example
    /// ```swift
    /// final class ViewHolder {
    ///     let label = UILabel()
    /// }
    ///
    /// let holder = ViewHolder()
    /// var subscriptions = Set<SubscriptionTask>()
    ///
    /// relay.stream()                // AsyncSequence<Element>
    ///     .assign(
    ///         to: \.text,            // ReferenceWritableKeyPath<UILabel, String>
    ///         on: holder.label
    ///     )
    ///     .store(in: &subscriptions)
    ///
    /// relay.send("Hello")           // label.text becomes "Hello" on main actor
    /// ```
    ///
    /// ## Error Handling
    /// If the sequence throws, `receiveError` is called:
    /// ```swift
    /// stream.assign(to: \.text, on: holder.label) { error in
    ///     print("Assignment failed:", error)
    /// }
    /// ```
    @discardableResult
    func assign<Root: AnyObject & Sendable>(
        to keyPath: ReferenceWritableKeyPath<Root, Element>,
        on object: Root,
        catching receiveError: @escaping ReceiveError<Error> = { _ in }
    ) -> SubscriptionTask {
        let kp = NonSendableBox(keyPath)

        return self.sink(catching: receiveError) { [weak object, kp] value in
            guard let object else { return }
            await MainActor.run {
                object[keyPath: kp.value] = value
            }
        }
    }

}
