//
//  CancellableTask.swift
//  AsyncCombine
//
//  Created by William Lumley on 16/9/2025.
//

@testable import AsyncCombine
import Foundation

/// Owns a long-lived cancellable task that stays alive until cancelled,
/// then marks the provided `CancelProbe`.
actor CancellationSentinel {

    // MARK: - Properties

    private let probe: CancelProbe
    private var task: SubscriptionTask?

    // MARK: - Lifecycle

    init(probe: CancelProbe) {
        self.probe = probe
    }

    deinit {
        self.task?.cancel()
    }

}

// MARK: - Public

extension CancellationSentinel {

    /// Starts (or restarts) the sentinel task.
    /// - Returns: The underlying `SubscriptionTask` so you can `.store(in:)`
    /// if desired.
    @discardableResult
    func start() -> SubscriptionTask {
        // Cancel any previous run before starting anew.
        self.task?.cancel()

        let newTask: SubscriptionTask = Task {
            await withTaskCancellationHandler {
                // Stay alive until cancelled, but don't spin.
                while Task.isCancelled == false {
                    // ~20ms tick to avoid a tight loop.
                    try? await Task.sleep(nanoseconds: 20_000_000)
                }
            } onCancel: {
                // onCancel must be synchronous — hop to an async context.
                Task { [probe] in
                    await probe.mark()
                }
            }
        }

        self.task = newTask
        return newTask
    }

    /// Cancels the sentinel if running.
    func cancel() {
        self.task?.cancel()
        self.task = nil
    }

}
