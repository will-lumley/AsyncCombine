//
//  AsyncSequence+AssignTests.swift
//  AsyncCombine
//
//  Created by William Lumley on 16/9/2025.
//

@testable import AsyncCombine
import Foundation
import Testing

// A simple UI-like target that must be mutated on the main actor.
@MainActor
final class Label: @unchecked Sendable {
    var text: String = ""
}

@Suite("AsyncSequence+Assign Tests")
struct AssignToOnTests {

    @MainActor
    @Test("Assigns values to the object on MainActor")
    func assignsValuesOnMainActor() async {
        let label = Label()
        let (stream, cont) = AsyncStream<String>.makeStream()

        var subs = Set<SubscriptionTask>()

        // Start assignment
        stream
            .assign(to: \.text, on: label)
            .store(in: &subs)

        // Emit a few values
        cont.yield("One")
        cont.yield("Two")
        cont.yield("Three")

        // Give the sink time to hop to MainActor and assign
        try? await Task.sleep(nanoseconds: 50_000_000)
        cont.finish()

        // Verify last value is assigned (read on main actor)
        let finalText = label.text
        #expect(finalText == "Three")

        // Cleanup
        subs.cancelAll()
    }

    @MainActor
    @Test("Cancelling the Returned Task Stops Further Assignments")
    func cancelStopsAssignments() async {
        let label = Label()
        let (stream, cont) = AsyncStream<String>.makeStream()

        let task = stream.assign(to: \.text, on: label)

        var subs = Set<SubscriptionTask>()
        task.store(in: &subs)

        // First value should apply
        cont.yield("Before Cancel")
        try? await Task.sleep(nanoseconds: 40_000_000)
        #expect(label.text == "Before Cancel")

        // Cancel and then send more
        subs.cancelAll() // or: task.cancel()
        try? await Task.sleep(nanoseconds: 10_000_000)

        cont.yield("After Cancel")
        try? await Task.sleep(nanoseconds: 40_000_000)

        // Should not update after cancellation
        #expect(label.text == "Before Cancel")

        cont.finish()
    }

    @MainActor
    @Test("No Crash or Assignment After Target Deallocation (weak capture)")
    func noAssignmentAfterDeinit() async {
        weak var weakLabel: Label?
        var strongLabel: Label? = Label()
        weakLabel = strongLabel

        let (stream, cont) = AsyncStream<String>.makeStream()

        var subs = Set<SubscriptionTask>()
        // Start assignment while object is alive
        stream.assign(to: \.text, on: strongLabel!).store(in: &subs)

        cont.yield("Alive")
        try? await Task.sleep(nanoseconds: 40_000_000)
        #expect(strongLabel?.text == "Alive")

        // Drop the strong reference — assignment closure captures [weak object]
        strongLabel = nil
        #expect(weakLabel == nil)

        // Emit more values — should be ignored (and not crash)
        cont.yield("Ignored")
        cont.yield("Also Ignored")
        try? await Task.sleep(nanoseconds: 40_000_000)
        cont.finish()

        // Nothing to assert on the deallocated label; test passes if no crash
        subs.cancelAll()
    }

    @MainActor
    @Test("Propagates Sequence Errors to the Catching Closure")
    func errorPropagation() async {
        enum TestError: Error, Equatable {
            case boom
        }

        // Build an AsyncThrowingStream that emits then fails
        let (stream, cont) = AsyncThrowingStream<String, Error>.makeStream()

        // Track the error callback
        let errorBox = AsyncBox<Error?>(nil)
        let label = Label()

        var subs = Set<SubscriptionTask>()
        stream.assign(to: \.text, on: label) { error in
            Task { await errorBox.set(error) }
        }
        .store(in: &subs)

        // Emit one value, then fail
        cont.yield("Hello")
        try? await Task.sleep(nanoseconds: 40_000_000)
        #expect(label.text == "Hello")

        cont.finish(throwing: TestError.boom)

        // Give the error closure time to run
        try? await Task.sleep(nanoseconds: 40_000_000)

        // Validate error surfaced
        let receivedError = await errorBox.get()
        #expect(receivedError is TestError)

        // Cleanup
        subs.cancelAll()
    }

}
