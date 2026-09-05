//
//  WithTimeout.swift
//  AsyncCombine
//
//  Created by William Lumley on 5/9/2026.
//

import Foundation

/// Runs `operation`, returning `nil` if it hasn't finished within `duration`.
///
/// Used by tests that would otherwise hang forever on a regression, so a failure
/// shows up as an assertion rather than a stalled suite.
func withTimeout<T: Sendable>(
    _ duration: Duration,
    _ operation: @escaping @Sendable () async -> T
) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask {
            await operation()
        }
        group.addTask {
            try? await Task.sleep(for: duration)
            return nil
        }

        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }
}
