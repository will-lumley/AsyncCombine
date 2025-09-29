//
//  AsyncSequence+SinkTests.swift
//  AsyncCombine
//
//  Created by William Lumley on 16/9/2025.
//

@testable import AsyncCombine
import Foundation
import Testing

@Suite("AsyncSequence+Sink Tests", .serialized, .timeLimit(.minutes(1)))
@MainActor
final class AsyncSequenceSinkTests {

    // MARK: - Properties

    /// A convenient place to store our tasks
    private var tasks = Set<SubscriptionTask>()

    // MARK: - Lifecycle

    deinit {
        // Clean up after ourselves
        self.tasks.cancelAll()
    }

    // MARK: - Tests

    @Test("Delivers Values in Order and Does Not Call receiveError on Normal Completion")
    func deliversInOrderNoErrorOnFinish() async {
        let (stream, cont) = AsyncStream<Int>.makeStream()
        let recorder = Recorder<Int>()
        let errorCalled = AsyncBox(false)

        // GIVEN we sink values, recording each one, and tracking error calls
        stream
            .sink(
                catching: { _ in
                    Task {
                        await errorCalled.set(true)
                    }
                }, { value in
                    await recorder.append(value)
                }
            )
        .store(in: &tasks)

        // WHEN we emit some values
        cont.yield(1)
        cont.yield(2)
        cont.yield(3)

        // Give the sink a moment to process, then finish cleanly
        try? await Task.sleep(for: .milliseconds(40))
        cont.finish()
        try? await Task.sleep(for: .milliseconds(40))

        // THEN values were delivered in order and no error callback was invoked
        #expect(await recorder.snapshot() == [1, 2, 3])
        #expect(await errorCalled.get() == false)
    }

    @Test("Cancelling the Returned Task Stops Further Values")
    func cancelStopsFurtherValues() async {
        let (stream, cont) = AsyncStream<String>.makeStream()
        let recorder = Recorder<String>()

        // GIVEN a sink storing into our task set
        stream.sink { value in
            await recorder.append(value)
        }
        .store(in: &tasks)

        // WHEN we emit an initial value
        cont.yield("A")
        try? await Task.sleep(for: .milliseconds(20))

        // THEN the recorder has the first value
        #expect(await recorder.snapshot() == ["A"])

        // WHEN we cancel all subscriptions
        self.tasks.cancelAll()
        try? await Task.sleep(for: .milliseconds(10))

        // AND try to emit more values after cancellation
        cont.yield("B")
        cont.yield("C")
        try? await Task.sleep(for: .milliseconds(40))

        // THEN no further values were recorded
        #expect(await recorder.snapshot() == ["A"])

        cont.finish()
    }

    @Test("Propagates Errors from AsyncThrowingStream to receiveError and Stops Iteration")
    func errorPropagation() async {
        enum TestError: Error { case boom }

        let (stream, cont) = AsyncThrowingStream<String, Error>.makeStream()
        let recorder = Recorder<String>()
        let capturedError = AsyncBox<Error?>(nil)

        // GIVEN a throwing stream whose errors are surfaced via `catching`
        stream.sink(catching: { error in
            Task { await capturedError.set(error) }
        }) { value in
            await recorder.append(value)
        }
        .store(in: &tasks)

        // WHEN we emit one value
        cont.yield("ok-1")
        try? await Task.sleep(for: .milliseconds(20))
        #expect(await recorder.snapshot() == ["ok-1"])

        // AND then fail the stream
        cont.finish(throwing: TestError.boom)
        try? await Task.sleep(for: .milliseconds(40))

        // THEN the error is captured
        let err = await capturedError.get()
        #expect(err is TestError)

        // AND further values (even if attempted) are ignored
        cont.yield("after-error")
        try? await Task.sleep(for: .milliseconds(20))
        #expect(await recorder.snapshot() == ["ok-1"])
    }

    @Test("Storing in a Set Allows Mass-Cancellation via cancelAll()")
    func storeThenCancelAll() async {
        let (stream, cont) = AsyncStream<Int>.makeStream()
        let recorder = Recorder<Int>()

        // GIVEN a sink stored in our shared task set
        stream.sink { value in
            await recorder.append(value)
        }
        .store(in: &tasks)

        #expect(tasks.isEmpty == false)

        // WHEN we emit values
        cont.yield(10)
        cont.yield(20)
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await recorder.snapshot() == [10, 20])

        // AND cancel everything
        self.tasks.cancelAll()

        // THEN further emissions are ignored
        cont.yield(30)
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await recorder.snapshot() == [10, 20])

        cont.finish()
    }

    @Test("receiveValue is Awaited Sequentially (preserves order even with suspension)")
    func receiveValueIsAwaitedSequentially() async {
        let (stream, cont) = AsyncStream<Int>.makeStream()
        let recorder = Recorder<Int>()

        // GIVEN a sink that simulates per-element work to test ordering
        stream.sink { value in
            try? await Task.sleep(for: .milliseconds(15)) // simulate work
            await recorder.append(value)
        }
        .store(in: &tasks)

        // WHEN we push a quick burst and then finish
        cont.yield(1)
        cont.yield(2)
        cont.yield(3)
        cont.finish()

        // THEN all three are processed in order despite suspension
        try? await Task.sleep(for: .seconds(1))
        #expect(await recorder.snapshot() == [1, 2, 3])
    }
}
