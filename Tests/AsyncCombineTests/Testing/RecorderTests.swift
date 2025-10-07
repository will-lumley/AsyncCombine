//
//  RecorderTests.swift
//  AsyncCombine
//
//  Created by William Lumley on 7/10/2025.
//

@testable import AsyncCombine
import Testing

@Suite("RecorderTests")
struct RecorderTests {

    @Test("Emits Values In Order")
    func emitsInOrder() async throws {
        // GIVEN we have a stream that emits 1,2,3
        let stream = stream([1, 2, 3])

        // WHEN we record it
        let recorder = stream.record()

        // THEN the next values are 1,2,3
        #expect(try await recorder.next() == 1)
        #expect(try await recorder.next() == 2)
        #expect(try await recorder.next() == 3)
    }

    @Test("Respects Timeout")
    func respectsTimeout() async throws {
        // GIVEN we have a stream that delays emitting 42
        // after 1 second has passed
        let stream = delayedStream([42], delay: .seconds(1))
        let recorder = stream.record()

        // THEN we get the timeout error
        await #expect(throws: RecordingError.timeout) {
            // WHEN we wait for the next value but only for
            // 100 milliseconds
            try await recorder.next(timeout: .milliseconds(100))
        }
    }

    @Test("Cancel Stops Further Delivery")
    func cancelStopsFurtherDelivery() async throws {
        // GIVEN we have a stream that delays emitting 1,2,3
        // after 50 milliseconds have passed
        let stream = delayedStream([1, 2, 3], delay: .milliseconds(50))
        let recorder = stream.record()

        // WHEN we listen to just one value
        let first = try await recorder.next(timeout: .seconds(1))

        // THEN it's the correct value
        #expect(first == 1)

        // GIVEN we cancel the recorder
        await recorder.cancel()

        // THEN the recorder throws an appropriate error
        await #expect(throws: RecordingError.sourceEnded) {
            // WHEN we request another value
            try await recorder.next(timeout: .milliseconds(200))
        }
    }

    @Test(
        "Works With Throwing Upstream (errors are swallowed and stream finishes)"
    )
    func swallowingUpstreamErrorsFinishes() async throws {
        enum Boom: Error {
            case boom
        }

        /// This sequence will emit just one value and then throw an error
        struct ThrowingSeq: AsyncSequence, Sendable {
            typealias Element = Int
            struct Iterator: AsyncIteratorProtocol {
                var emitted = false
                mutating func next() async throws -> Int? {
                    // Have we emitted our value yet?
                    if emitted == false {
                        // We have not, emit it now
                        emitted = true
                        return 1
                    } else {
                        // We have emitted before, let's bail
                        throw Boom.boom
                    }
                }
            }
            func makeAsyncIterator() -> Iterator { Iterator() }
        }

        // WHEN we start recording our sequence that can throw
        let recorder = ThrowingSeq().record()

        // WHEN we pull the next value out of our recorder
        let one = try await recorder.next(timeout: .seconds(1))

        // THEN the value is correct
        #expect(one == 1)

        // THEN we should get a sourceEnded error
        await #expect(throws: RecordingError.sourceEnded) {
            // WHEN we consume the next element
            try await recorder.next(timeout: .milliseconds(100))
        }
    }

    @Test(
        "Buffering Policy: Bounded Still Delivers Earliest Values"
    )
    func bufferingPolicyBounded() async throws {
        // Produce 5 quickly; bounded buffer should still deliver
        // earliest in order.
        let stream = AsyncStream<Int>(
            bufferingPolicy: .bufferingOldest(2)
        ) { cont in
            for i in 1...5 {
                cont.yield(i)
            }
            cont.finish()
        }

        // WHEN we record the bufferingOldest stream
        let recorder = Recorder(
            stream,
            bufferingPolicy: .bufferingOldest(2)
        )


        // WHEN we pull in the first two values
        let a = try await recorder.next()
        let b = try await recorder.next()

        #expect([1,2].contains(a))
        #expect([1,2,3].contains(b))

        // Depending on buffering semantics, earliest two are retained.
        // #expect([1,2,3].contains(b)) // conservative check across implementations

        await #expect(throws: RecordingError.sourceEnded) {
            _ = try await recorder.next(timeout: .milliseconds(50)) // C
            _ = try await recorder.next(timeout: .milliseconds(50)) // D
            _ = try await recorder.next(timeout: .milliseconds(50)) // E

            // Should now finish
            _ = try await recorder.next(timeout: .milliseconds(50)) // ?
        }
    }

    @Test("No Actor-Ownership Hazards On Next()")
    func noActorOwnershipHazards() async throws {
        // This is mostly a smoke test to ensure next() reads via the
        // box and doesn’t hold actor state across suspension.
        let stream = delayedStream([10], delay: .milliseconds(10))
        let recorder = stream.record()
        #expect(try await recorder.next() == 10)
    }

}

// MARK: - Private

@available(iOS 16.0, macOS 13.0, *)
private extension RecorderTests {

    /// Emits the given values then finishes.
    func stream<T: Sendable>(_ values: [T]) -> AsyncStream<T> {
        AsyncStream { cont in
            for value in values {
                cont.yield(value)
            }
            cont.finish()
        }
    }

    /// Emits values with per-item delay, then finishes.
    func delayedStream<T: Sendable>(
        _ values: [T],
        delay: Duration
    ) -> AsyncStream<T> {
        AsyncStream { cont in
            Task.detached {
                for v in values {
                    try? await Task.sleep(for: delay)
                    cont.yield(v)
                }
                cont.finish()
            }
        }
    }

}
