//
//  CurrentValueRelay.swift
//  AsyncCombine
//
//  Created by William Lumley on 15/9/2025.
//

import Foundation

public actor CurrentValueRelay<Value: Sendable> {

    // MARK: - Properties

    /// The most recent value broadcasted in this relay
    public private(set) var valueStorage: Value

    /// A hashmap of each continuation this relay will be use to broadcast
    private var continuations = [UUID: AsyncStream<Value>.Continuation]()

    // MARK: - Lifecycle

    public init(_ initial: Value) {
        self.valueStorage = initial
    }

}

// MARK: - Public

public extension CurrentValueRelay {

    /// Update the current value and notify all listeners.
    func send(_ newValue: Value) {
        valueStorage = newValue
        for continuation in continuations.values {
            continuation.yield(newValue)
        }
    }

    /// An AsyncSequence that:
    /// 1) immediately yields the current value (replay 1)
    /// 2) then yields every subsequent update
    func stream() -> AsyncStream<Value> {
        AsyncStream { continuation in
            let id = UUID()

            // Register our continuation so we can broadcast to it
            // later on.
            self.register(id: id, continuation: continuation)

            // If the continuation is terminated
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.unregister(id: id)
                }
            }
        }
    }

}

// MARK: - Private

private extension CurrentValueRelay {

    func register(id: UUID, continuation: AsyncStream<Value>.Continuation) {
        self.continuations[id] = continuation

        // Replay latest value to the continuation
        continuation.yield(self.valueStorage)
    }

    func unregister(id: UUID) {
        self.continuations.removeValue(forKey: id)
    }

}
