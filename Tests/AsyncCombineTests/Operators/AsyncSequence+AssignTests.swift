//
//  AsyncSequence+AssignTests.swift
//  AsyncCombine
//
//  Created by William Lumley on 16/9/2025.
//

@testable import AsyncCombine
import Foundation
import Testing

@Suite("AsyncSequence+Assign Tests", .serialized, .timeLimit(.minutes(1)))
@MainActor
class AssignToOnTests {

    // MARK: - Properties

    /// A convenient place to store our tasks
    var tasks = Set<SubscriptionTask>()

    /// A test label that holds a `String` value and is a `MainActor`
    let label = Label()

    // MARK: - Lifecycle

    deinit {
        // Clean up after ourselves
        self.tasks.cancelAll()
    }

    // MARK: - Tests

    @Test("Assigns values to the object on MainActor")
    func assignsValuesOnMainActor() async {
        let (stream, cont) = AsyncStream<String>.makeStream()

        // GIVEN we assign our stream value to `.text` to our `label`
        stream
            .assign(to: \.text, on: label)
            .store(in: &tasks)

        // Wait for the label to actually receive "Three"
        let done = Task {
            return await label.observed(\.text)
                .first { @Sendable in $0 == "Three" }
        }

        // THEN we emit some values
        cont.yield("One")
        cont.yield("Two")
        cont.yield("Three")

        cont.finish()

        // Wait for the assigning to be completed
        _ = await done.value

        // THEN the last value emitted is assigned
        #expect(label.text == "Three")
    }

    @Test("Cancelling the Returned Task Stops Further Assignments")
    func cancelStopsAssignments() async throws {
        let (stream, cont) = AsyncStream<String>.makeStream()

        // GIVEN we assign our stream value to `.text` to our `label`
        stream
            .assign(to: \.text, on: label)
            .store(in: &tasks)

        // Wait for the label to actually receive "Before Cancel"
        let done = Task {
            return await label.observed(\.text)
                .first { @Sendable in $0 == "Before Cancel" }
        }

        // WHEN we emit a "Before Cancel" string
        cont.yield("Before Cancel")

        // Wait for the assigning to be completed
        _ = await done.value

        // THEN our label is "Before Cancel"
        #expect(label.text == "Before Cancel")

        // WHEN we cancel our tasks
        self.tasks.cancelAll()

        // WHEN we emit an "After Cancel" string
        cont.yield("After Cancel")

        // We'll use a hacky `.sleep()` here because we don't have a
        // handle on the task anymore as we cancelled it
        try await Task.sleep(for: .milliseconds(500))

        // THEN our label shouldn't be updated because we
        // cancelled our tasks
        #expect(label.text == "Before Cancel")

        cont.finish()
    }

    @Test("No Crash or Assignment After Target Deallocation (weak capture)")
    func noAssignmentAfterDeinit() async throws {
        weak var weakLabel: Label?
        var strongLabel: Label? = Label()

        weakLabel = strongLabel

        let (stream, cont) = AsyncStream<String>.makeStream()

        // GIVEN we create an assignment while the object is alive
        stream
            .assign(to: \.text, on: strongLabel!)
            .store(in: &tasks)

        // Wait for the label to actually receive "Alive"
        let done = Task {
            return await strongLabel!.observed(\.text)
                .first { @Sendable in $0 == "Alive" }
        }

        // WHEN we emit "Alive"
        cont.yield("Alive")

        // Wait for the assigning to be completed
        _ = await done.value

        // THEN the `strongLabel` is assigned "Alive"
        #expect(strongLabel?.text == "Alive")

        // GIVEN we drop the strong reference - assignment closure captures [weak object]
        strongLabel = nil
        #expect(weakLabel == nil)

        // WHEN we emit more values — should be ignored (and not crash)
        cont.yield("Ignored")
        cont.yield("Also Ignored")

        // We'll use a hacky `.sleep()` here because we don't have a
        // handle on the task anymore as we cancelled it
        try await Task.sleep(for: .milliseconds(500))

        cont.finish()

        // Nothing to assert on the deallocated label; test passes if no crash
        self.tasks.cancelAll()
    }

    @Test("Propagates Sequence Errors to the Catching Closure")
    func errorPropagation() async throws {
        // Build an AsyncThrowingStream that emits then fails
        let (stream, cont) = AsyncThrowingStream<String, Error>.makeStream()

        // Track the error callback
        let errorBox = AsyncBox<Error?>(nil)

        // GIVEN we create an assignment while the object is alive
        stream
            .assign(to: \.text, on: label) { error in
                Task {
                    await errorBox.set(error)
                }
            }
            .store(in: &tasks)

        // Wait for the label to actually receive "Hello"
        let done = Task {
            return await label.observed(\.text)
                .first { @Sendable in $0 == "Hello" }
        }

        // WHEN we emit one value, then fail
        cont.yield("Hello")

        // Wait for the assigning to be completed
        _ = await done.value

        #expect(label.text == "Hello")

        // WHEN we finish with an error
        cont.finish(throwing: TestError.boom)

        // Wait a hot minute for the error to propogate
        try await Task.sleep(for: .milliseconds(500))

        // THEN the error we have
        let receivedError = await errorBox.get()
        #expect(receivedError is TestError)

        // Cleanup
        self.tasks.cancelAll()
    }

}
