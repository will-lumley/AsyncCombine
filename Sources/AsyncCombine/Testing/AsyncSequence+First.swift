//
//  AsyncSequence+First.swift
//  AsyncCombineTesting
//
//  Created by William Lumley on 6/10/2025.
//

public extension AsyncSequence where Element: Equatable & Sendable {

    /// Returns the first element equal to `value`, or `nil` if the sequence finishes first.
    @inlinable
    func first(
        equalTo value: Element
    ) async rethrows -> Element? {
        // Explicitly-typed @Sendable predicate to satisfy Swift 6.
        let predicate: @Sendable (Element) -> Bool = { $0 == value }
        return try await self.first(where: predicate)
    }

}

@available(iOS 16.0, macOS 13.0, *)
public extension AsyncSequence where Element: Equatable & Sendable, Self: Sendable {
    /// Like above, but gives up after `timeout` and returns `nil`.
    @inlinable
    func first(
        equalTo value: Element,
        timeout: Duration,
        clock: ContinuousClock = .init()
    ) async -> Element? {
        let predicate: @Sendable (Element) -> Bool = { $0 == value }

        // Race the match against the timeout; whichever finishes first wins.
        return await withTaskGroup(of: Element?.self) { group in
            group.addTask {
                try? await self.first(where: predicate)
            }
            group.addTask {
                try? await clock.sleep(for: timeout)
                return nil
            }

            let result = await group.next() ?? nil
            group.cancelAll()

            return result
        }
    }
}
