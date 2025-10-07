//
//  AsyncSequence+FirstTests.swift
//  AsyncCombine
//
//  Created by William Lumley on 7/10/2025.
//

@testable import AsyncCombine
import Testing

@Suite("AsyncSequence+First")
struct AsyncSequenceFirstTests {

    // MARK: - Plain `first(equalTo:)`

    @Test("Emits First Matching Element")
    func emitsFirstMatch() async throws {
        // GIVEN a stream that emits 1,2,3
        let stream = stream([1, 2, 3])

        // WHEN we ask for first(equalTo: 2)
        let result = await stream.first(equalTo: 2)

        // THEN we get 2
        #expect(result == 2)
    }

    @Test("Returns Nil If No Match Before Finish")
    func returnsNilWhenNoMatch() async throws {
        let stream = stream([1, 3, 5])
        let result = await stream.first(equalTo: 2)
        #expect(result == nil)
    }

    @Test("Stops At The First Match Even If More Follow")
    func stopsAtFirstEvenIfMoreFollow() async throws {
        let stream = stream([2, 2, 2, 3, 4])
        let result = await stream.first(equalTo: 2)
        #expect(result == 2)
    }

    @Test("Empty Sequence Returns Nil")
    func emptyReturnsNil() async throws {
        let stream = stream([Int]())
        let result = await stream.first(equalTo: 1)
        #expect(result == nil)
    }

    // MARK: - Timed `first(equalTo:timeout:clock:)`

    @available(iOS 16.0, macOS 13.0, *)
    @Test("Returns Value When It Arrives Before Timeout")
    func valueBeatsTimeout() async {
        // GIVEN values every 50ms; target (7) is second element at ~100ms
        let stream = delayedStream([1, 7, 9], delay: .milliseconds(50))
        let clock = ContinuousClock()

        // WHEN timeout is generous (300ms)
        let value = await stream.first(equalTo: 7, timeout: .milliseconds(300), clock: clock)

        // THEN we got it
        #expect(value == 7)
    }

    @available(iOS 16.0, macOS 13.0, *)
    @Test("Timeout Wins When Value Is Too Slow")
    func timeoutBeatsSlowValue() async {
        // GIVEN a single value after 200ms
        let stream = delayedStream([42], delay: .milliseconds(200))
        let clock = ContinuousClock()

        // WHEN timeout is only 50ms
        let value = await stream.first(equalTo: 42, timeout: .milliseconds(50), clock: clock)

        // THEN we time out (nil)
        #expect(value == nil)
    }

    @available(iOS 16.0, macOS 13.0, *)
    @Test("Returns Nil When Sequence Finishes Before a Match")
    func finishesBeforeMatch() async {
        // GIVEN a short stream with no matching value
        let stream = delayedStream([1, 3, 5], delay: .milliseconds(20))
        let clock = ContinuousClock()

        // WHEN timeout is long enough that finishing is the determining event
        let value = await stream.first(
            equalTo: 2,
            timeout: .seconds(1),
            clock: clock
        )

        // THEN nil because it finished with no match
        #expect(value == nil)
    }

    @available(iOS 16.0, macOS 13.0, *)
    @Test("Match Right At The Start Still Returns Immediately")
    func immediateMatch() async {
        // GIVEN the first element is already a match
        let stream = stream([99, 100, 101])
        let clock = ContinuousClock()

        let value = await stream.first(equalTo: 99, timeout: .seconds(1), clock: clock)
        #expect(value == 99)
    }

    @available(iOS 16.0, macOS 13.0, *)
    @Test("Multiple Matches: Returns The Earliest")
    func earliestOfMultipleMatches() async {
        // GIVEN multiple matches in the stream
        let stream = delayedStream([7, 7, 7], delay: .milliseconds(25))
        let clock = ContinuousClock()

        let value = await stream.first(
            equalTo: 7,
            timeout: .seconds(1),
            clock: clock
        )
        #expect(value == 7)
    }

}

// MARK: - Private

private extension AsyncSequenceFirstTests {

    /// Emits the given values then finishes (no delays).
    func stream<T: Sendable>(_ values: [T]) -> AsyncStream<T> {
        AsyncStream { cont in
            for v in values {
                cont.yield(v)
            }
            cont.finish()
        }
    }

    /// Emits each value separated by `delay`, then finishes.
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
