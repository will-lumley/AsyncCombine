//
//  AsyncSequenceSinkOnMainTests.swift
//  AsyncCombine
//
//  Created by William Lumley on 29/9/2025.
//

@testable import AsyncCombine
import Foundation
import Testing

@Suite(
    "AsyncSequence+SinkOnMain Tests",
    .serialized,
    .timeLimit(.minutes(1))
)
@MainActor
final class AsyncSequenceSinkOnMainTests {

    // MARK: - Properties

    private var tasks = Set<SubscriptionTask>()

    deinit {
        self.tasks.cancelAll()
    }

    // MARK: - Tests

    @Test("Value and Finished handlers run on MainActor")
    func valueAndFinishOnMainActor() async {
        let (stream, cont) = AsyncStream<Int>.makeStream()
        let recorder = Recorder<Int>()
        let finishedOnMain = AsyncBox(false)

        // GIVEN a sinkOnMain that asserts main-thread execution
        stream
            .sinkOnMain(
                catching: { @MainActor _ in
                    // Intentionally left blank.
                },
                finished: { @MainActor in
                    Task {
                        await finishedOnMain.set(true)
                    }
                },
                { @MainActor value in
                    await recorder.append(value)
                }
            )
            .store(in: &tasks)

        // WHEN we emit and finish
        cont.yield(1)
        cont.yield(2)
        cont.yield(3)
        cont.finish()
        try? await Task.sleep(for: .milliseconds(60))

        // THEN values are recorded and finish ran on main
        #expect(await recorder.snapshot() == [1, 2, 3])
        #expect(await finishedOnMain.get() == true)
    }

    @Test("Error handler runs on MainActor and iteration stops")
    func errorOnMainActorStopsIteration() async {
        enum TestError: Error { case boom }

        let (stream, cont) = AsyncThrowingStream<String, Error>.makeStream()
        let recorder = Recorder<String>()
        let errorCaptured = AsyncBox(false)

        // GIVEN a throwing stream with sinkOnMain
        stream
            .sinkOnMain(
                catching: { @MainActor error in
                    #expect(error is TestError)
                    Task { await errorCaptured.set(true) }
                },
                finished: { @MainActor in
                    // Should not be called on error
                    Issue.record(
                        "Finished should not be called after error"
                    )
                },
                { @MainActor value in
                    await recorder.append(value)
                }
            )
            .store(in: &tasks)

        // WHEN we yield a value, then fail
        cont.yield("ok-1")
        try? await Task.sleep(for: .milliseconds(20))
        #expect(await recorder.snapshot() == ["ok-1"])

        cont.finish(throwing: TestError.boom)
        try? await Task.sleep(for: .milliseconds(40))

        // THEN error was captured and no further values processed
        #expect(await errorCaptured.get() == true)

        cont.yield("after-error")
        try? await Task.sleep(for: .milliseconds(20))
        #expect(await recorder.snapshot() == ["ok-1"])
    }

    @Test("Cancelling Prevents Further Values")
    func cancelPreventsFurtherValues_NoFinished() async {
        let (stream, cont) = AsyncStream<String>.makeStream()
        let recorder = Recorder<String>()
        let finishedCalled = AsyncBox(false)
        let errorCalled = AsyncBox(false)

        stream
            .sinkOnMain(
                catching: { @MainActor _ in
                    Task { await errorCalled.set(true) }
                },
                finished: { @MainActor in
                    Task { await finishedCalled.set(true) }
                },
                { @MainActor value in
                    await recorder.append(value)
                }
            )
            .store(in: &tasks)

        // WHEN one value is delivered
        cont.yield("A")
        try? await Task.sleep(for: .milliseconds(20))
        #expect(await recorder.snapshot() == ["A"])

        // AND we cancel all subscriptions
        tasks.cancelAll()
        try? await Task.sleep(for: .milliseconds(10))

        // AND we try to emit more and finish
        cont.yield("B")
        cont.yield("C")
        cont.finish()
        try? await Task.sleep(for: .milliseconds(40))

        // THEN only the first value is present, and no error, and
        // finished got called.
        #expect(await recorder.snapshot() == ["A"])
        #expect(await finishedCalled.get() == true)
        #expect(await errorCalled.get() == false)
    }

    @Test("receiveValue is awaited sequentially on MainActor (preserves order with suspension)")
    func sequentialAwaitOnMainActor() async {
        let (stream, cont) = AsyncStream<Int>.makeStream()
        let recorder = Recorder<Int>()

        // GIVEN per-element work in the main-actor value handler
        stream
            .sinkOnMain { @MainActor value in
                try? await Task.sleep(for: .milliseconds(15)) // simulate work
                await recorder.append(value)
            }
            .store(in: &tasks)

        // WHEN we push a quick burst and finish
        cont.yield(1)
        cont.yield(2)
        cont.yield(3)
        cont.finish()

        // THEN order is preserved and work is sequential
        try? await Task.sleep(for: .seconds(1))
        #expect(await recorder.snapshot() == [1, 2, 3])
    }

    @Test("Works with background producers but still delivers on MainActor")
    func backgroundProducer_DeliversOnMainActor() async {
        let (stream, cont) = AsyncStream<Int>.makeStream()
        let recorder = Recorder<Int>()
        let finishedOnMain = AsyncBox(false)

        stream
            .sinkOnMain(
                finished: { @MainActor in
                    Task { await finishedOnMain.set(true) }
                },
                { @MainActor value in
                    await recorder.append(value)
                }
            )
            .store(in: &tasks)

        // Produce from a background context
        let producer = Task.detached {
            cont.yield(42)
            cont.yield(43)
            cont.finish()
        }
        _ = await producer.result

        try? await Task.sleep(for: .milliseconds(80))

        #expect(await recorder.snapshot() == [42, 43])
        #expect(await finishedOnMain.get() == true)
    }

}
