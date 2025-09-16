//
//  AsyncSequence+SinkTests.swift
//  AsyncCombine
//
//  Created by William Lumley on 16/9/2025.
//

@testable import AsyncCombine
import Foundation
import Testing

@Suite("AsyncSequence+Sink Tests")
struct AsyncSequenceSinkTests {

    @Test("Delivers Values in Order and Does Not Call receiveError on Normal Completion")
    func deliversInOrderNoErrorOnFinish() async {
        let (stream, cont) = AsyncStream<Int>.makeStream()
        let recorder = Recorder<Int>()
        let errorCalled = AsyncBox(false)

        let task = stream.sink(catching: { _ in
            Task { await errorCalled.set(true) }
        }) { value in
            await recorder.append(value)
        }

        var subs = Set<SubscriptionTask>()
        task.store(in: &subs)

        cont.yield(1)
        cont.yield(2)
        cont.yield(3)

        try? await Task.sleep(nanoseconds: 40_000_000)
        cont.finish()

        try? await Task.sleep(nanoseconds: 40_000_000)

        #expect(await recorder.snapshot() == [1, 2, 3])
        #expect(await errorCalled.get() == false)

        subs.cancelAll()
    }

    @Test("Cancelling the Returned Task Stops Further Values")
    func cancelStopsFurtherValues() async {
        let (stream, cont) = AsyncStream<String>.makeStream()
        let recorder = Recorder<String>()

        let task = stream.sink { value in
            await recorder.append(value)
        }

        var subs = Set<SubscriptionTask>()
        task.store(in: &subs)

        cont.yield("A")
        try? await Task.sleep(nanoseconds: 20_000_000)
        #expect(await recorder.snapshot() == ["A"])

        // Cancel then try to send more values
        subs.cancelAll()
        try? await Task.sleep(nanoseconds: 10_000_000)

        cont.yield("B")
        cont.yield("C")
        try? await Task.sleep(nanoseconds: 40_000_000)

        // Still only the pre-cancel value(s)
        #expect(await recorder.snapshot() == ["A"])

        cont.finish()
    }

    @Test("Propagates Errors from AsyncThrowingStream to receiveError and Stops Iteration")
    func errorPropagation() async {
        enum TestError: Error { case boom }

        let (stream, cont) = AsyncThrowingStream<String, Error>.makeStream()
        let recorder = Recorder<String>()
        let capturedError = AsyncBox<Error?>(nil)

        let t = stream.sink(catching: { error in
            Task { await capturedError.set(error) }
        }) { value in
            await recorder.append(value)
        }

        var subs = Set<SubscriptionTask>()
        t.store(in: &subs)

        cont.yield("ok-1")
        try? await Task.sleep(nanoseconds: 20_000_000)
        #expect(await recorder.snapshot() == ["ok-1"])

        // Fail the stream
        cont.finish(throwing: TestError.boom)

        try? await Task.sleep(nanoseconds: 40_000_000)

        // Error should be surfaced, and no further values processed
        let err = await capturedError.get()
        #expect(err is TestError)

        // Even if we try to yield after failure (no-op), nothing should change
        cont.yield("after-error")
        try? await Task.sleep(nanoseconds: 20_000_000)
        #expect(await recorder.snapshot() == ["ok-1"])

        subs.cancelAll()
    }

    @Test("Storing in a Set Allows Mass-Cancellation via cancelAll()")
    func storeThenCancelAll() async {
        let (stream, cont) = AsyncStream<Int>.makeStream()
        let recorder = Recorder<Int>()

        var subs = Set<SubscriptionTask>()
        stream.sink { value in
            await recorder.append(value)
        }
        .store(in: &subs)

        #expect(subs.isEmpty == false)

        cont.yield(10)
        cont.yield(20)
        try? await Task.sleep(nanoseconds: 30_000_000)
        #expect(await recorder.snapshot() == [10, 20])

        subs.cancelAll()

        // Further values should be ignored after cancelAll
        cont.yield(30)
        try? await Task.sleep(nanoseconds: 30_000_000)
        #expect(await recorder.snapshot() == [10, 20])

        cont.finish()
    }

    @Test("receiveValue is Awaited Sequentially (preserves order even with suspension)")
    func receiveValueIsAwaitedSequentially() async {
        let (stream, cont) = AsyncStream<Int>.makeStream()
        let recorder = Recorder<Int>()

        let task = stream.sink { value in
            // Simulate a bit of work per element to ensure sequential awaiting
            try? await Task.sleep(nanoseconds: 15_000_000)
            await recorder.append(value)
        }

        var subs = Set<SubscriptionTask>()
        task.store(in: &subs)

        // Push a quick burst
        cont.yield(1)
        cont.yield(2)
        cont.yield(3)

        cont.finish()

        // Enough time for all three to be processed in order
        try? await Task.sleep(nanoseconds: 80_000_000)

        print("Snapshot: \(await recorder.snapshot())")

        #expect(await recorder.snapshot() == [1, 2, 3])

        subs.cancelAll()
    }

}
