//
//  Recorder.swift
//  AsyncCombineTesting
//
//  Created by William Lumley on 6/10/2025.
//

/// A helper that captures elements from an `AsyncSequence` and lets you pull them one-by-one.
///
/// The `Recorder` continuously consumes the source sequence on a background task
/// and buffers emitted elements into an `AsyncStream`, allowing callers to await
/// each value via `next()`.
///
/// - Important: This was designed with unit testing in mind and is not suitable for
/// production use.

@available(iOS 16.0, macOS 13.0, *)
public actor Recorder<S: AsyncSequence & Sendable> where S.Element: Sendable {

    // MARK: - Types

    private final class IteratorBox: @unchecked Sendable {
        private var iterator: AsyncStream<S.Element>.Iterator

        init(_ iterator: AsyncStream<S.Element>.Iterator) {
            self.iterator = iterator
        }

        // Mutating+async happens here, away from the actor's stored state
        func next() async -> S.Element? {
            await iterator.next()
        }
    }

    // MARK: - Properties

    /// The continuation used to feed elements from the source sequence into the internal stream.
    private let continuation: AsyncStream<S.Element>.Continuation

    /// The internal `AsyncStream` that buffers elements emitted by the source sequence.
    private let stream: AsyncStream<S.Element>

    /// The iterator box used to retrieve elements from the buffered stream.
    private var iterator: IteratorBox

    /// The background task responsible for pumping values from the source sequence into the stream.
    private var pump: Task<Void, Never>?

    // MARK: Lifecycle

    public init(
        _ sequence: S,
        bufferingPolicy: AsyncStream<S.Element>.Continuation.BufferingPolicy = .unbounded
    ) {
        var cont: AsyncStream<S.Element>.Continuation!
        let stream = AsyncStream<S.Element>(
            bufferingPolicy: bufferingPolicy
        ) {
            cont = $0
        }

        self.continuation = cont
        self.stream = stream
        self.iterator = IteratorBox(stream.makeAsyncIterator())

        // Pump the source sequence into the stream.
        self.pump = Task {
            do {
                for try await value in sequence {
                    cont.yield(value)
                }
                cont.finish()
            } catch {
                // Swallow errors; finish the stream
                cont.finish()
            }
        }
    }

    deinit {
        self.pump?.cancel()
        self.continuation.finish()
    }

    /// Returns the next element emitted after the last `next()` call, or `nil`
    /// if the source finishes.
    private func next() async -> S.Element? {
        // Read the reference (allowed), then await on it; we are
        // not holding a mutable actor-stored value across the suspension.
        let box = self.iterator
        return await box.next()
    }

    /// Like `next()`, but gives up after `timeout` and returns `nil`.
    public func next(
        timeout: Duration = .seconds(1),
        clock: ContinuousClock = .init(),
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) async throws -> S.Element {
        return try await withThrowingTaskGroup(of: S.Element?.self) { group in

            group.addTask {
                await self.next()
            }
            group.addTask {
                try await clock.sleep(for: timeout)
                throw RecordingError.timeout
            }

            // First finished child wins
            guard let first = try await group.next() else {
                // There are two children, so this should be impossible
                preconditionFailure("Task group returned no results")
            }
            group.cancelAll()

            guard let result = first else {
                throw RecordingError.sourceEnded
            }
            return result
        }

    }

    /// Stop recording early; completes the stream and cancels the pump.
    public func cancel() {
        self.pump?.cancel()
        self.continuation.finish()
    }

}

// MARK: - AsyncSequence

@available(iOS 16.0, macOS 13.0, *)
public extension AsyncSequence where Element: Sendable, Self: Sendable {

    /// Creates a `Recorder` that captures elements and lets you pull them one-by-one via `next()`.
    @inlinable
    func record(
        bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy = .unbounded
    ) -> Recorder<Self> {
        Recorder(self, bufferingPolicy: bufferingPolicy)
    }

}
