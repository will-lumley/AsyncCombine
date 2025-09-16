//
//  AsyncSequence+Collect.swift
//  AsyncCombine
//
//  Created by William Lumley on 16/9/2025.
//

public extension AsyncSequence where Element: Sendable {

    /// Collect exactly 1 elements from this sequence.
    /// Uses `prefix(_:)` so it won’t hang on infinite streams.
    ///
    /// - Important: This is only intended to be used in testing.
    @inlinable
    func collect() async rethrows -> Element? {
        var output: [Element] = []
        for try await value in self.prefix(1) {
            output.append(value)
        }
        return output.first
    }

    /// Collect exactly `count` elements from this sequence.
    /// Uses `prefix(_:)` so it won’t hang on infinite streams.
    ///
    /// - Important: This is only intended to be used in testing.
    @inlinable
    func collect(count: Int) async rethrows -> [Element] {
        var output: [Element] = []
        for try await value in self.prefix(count) {
            output.append(value)
        }
        return output
    }

}
