//
//  CombineLatestTests.swift
//  AsyncCombine
//
//  Created by William Lumley on 29/9/2025.
//

@testable import AsyncCombine
import Testing

@Suite("AsyncCombine.Combine")
struct CombineLatestTests {

    // Small helper to hand-drive AsyncStreams from a test
    private struct StreamHandle<Element: Sendable> {
        let stream: AsyncStream<Element>
        let yield: (Element) -> Void
        let finish: () -> Void

        init() {
            var continuation: AsyncStream<Element>.Continuation!
            self.stream = AsyncStream<Element> { c in continuation = c }
            self.yield = { continuation.yield($0) }
            self.finish = { continuation.finish() }
        }
    }

    // MARK: - Tests

    @Test("Emits only after both have an initial value, then on each subsequent change")
    func emitsAfterPrimingThenLatest() async throws {
        // GIVEN two controllable streams
        let stream1 = StreamHandle<Int>()
        let stream2 = StreamHandle<String>()

        // WHEN we combine them
        let combined = AsyncCombine
            .combineLatest(stream1.stream, stream2.stream)

        var it = combined.makeAsyncIterator()

        // (No emission yet because only one side has produced)
        stream1.yield(1)

        // Prime the second; first emission now available
        stream2.yield("a")
        let value1 = await it.next()
        #expect(value1?.0 == 1 && value1?.1 == "a")

        // Change first only -> emits (latestFirst, latestSecond)
        stream1.yield(2)
        let value2 = await it.next()
        #expect(value2?.0 == 2 && value2?.1 == "a")

        // Change second only
        stream2.yield("b")
        let value3 = await it.next()
        #expect(value3?.0 == 2 && value3?.1 == "b")

        // THEN the sequence so far is [(1,"a"), (2,"a"), (2,"b")]
        // (Already asserted step-by-step above)
    }

    @Test("Finishes only when both upstreams finish")
    func finishesWhenAllFinish() async {
        // GIVEN two controllable streams, already primed so we can iterate
        let stream1 = StreamHandle<Int>()
        let stream2 = StreamHandle<Int>()
        let combined = AsyncCombine.combineLatest(
            stream1.stream,
            stream2.stream
        )

        var it = combined.makeAsyncIterator()

        stream1.yield(10)
        stream2.yield(20)
        _ = await it.next() // consume initial (10,20)

        // WHEN only the first finishes
        stream1.finish()

        // THEN the combined stream should NOT finish yet
        // (we can still get new tuples if s2 changes)
        stream2.yield(21)
        guard let value = await it.next() else {
            Issue.record("Iterator should have returned a value")
            return
        }

        #expect(value == (10, 21))

        // WHEN the second now finishes
        stream2.finish()

        // THEN the combined stream finishes (iterator returns nil)
        let end = await it.next()
        #expect(end == nil)
    }

}
