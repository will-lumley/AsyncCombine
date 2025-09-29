//
//  AsyncStream+Combine.swift
//  AsyncCombine
//
//  Created by William Lumley on 29/9/2025.
//

import Combine
import AsyncAlgorithms

// For the namespace
public enum AsyncCombine { }

public extension AsyncCombine {

    static func combine<Stream1, Stream2>(
        _ stream1: Stream1,
        _ stream2: Stream2
    ) -> AsyncStream<(Stream1.Element, Stream2.Element)>
    where Stream1: AsyncSequence & Sendable,
          Stream2: AsyncSequence & Sendable,
          Stream1.Element: Sendable,
          Stream2.Element: Sendable
    {
        return AsyncStream<(Stream1.Element, Stream2.Element)> { continuation in

            let state = _Combine2State<Stream1.Element, Stream2.Element>(
                continuation: continuation
            )

            let task1 = Task {
                do {
                    for try await value in stream1 {
                        await state.updateElement1(value)
                    }
                } catch {

                }
                await state.finishFirst()
            }

            let task2 = Task {
                do {
                    for try await value in stream2 {
                        await state.updateElement2(value)
                    }
                } catch {

                }
                await state.finishSecond()
            }

            continuation.onTermination = { _ in
                task1.cancel()
                task2.cancel()

                Task {
                    await state.cancel()
                }
            }
        }
    }
}

// MARK: - Combine2State

fileprivate actor _Combine2State<
    Element1: Sendable,
    Element2: Sendable
> {
    private var latestElement1: Element1?
    private var latestElement2: Element2?

    private var finishedFirst = false
    private var finishedSecond = false

    private var cancelled = false

    private let continuation: AsyncStream<(Element1, Element2)>.Continuation

    init(
        continuation: AsyncStream<(
            Element1,
            Element2
        )>.Continuation
    ) {
        self.continuation = continuation
    }

    func updateElement1(_ value: Element1) {
        guard cancelled == false else {
            return
        }

        self.latestElement1 = value
        self.yieldIfPossible()
    }

    func updateElement2(_ value: Element2) {
        guard cancelled == false else {
            return
        }

        self.latestElement2 = value
        self.yieldIfPossible()
    }

    func finishFirst() {
        self.finishedFirst = true
        self.finishIfPossible()
    }

    func finishSecond() {
        self.finishedSecond = true
        self.finishIfPossible()
    }

    func cancel() {
        self.cancelled = true
        self.continuation.finish()
    }

    private func yieldIfPossible() {
        guard
            let latestElement1,
            let latestElement2
        else {
            return
        }

        self.continuation.yield((latestElement1, latestElement2))
    }

    private func finishIfPossible() {
        // Finish when *all* upstreams have finished
        // (CombineLatest semantics)
        if self.finishedFirst && self.finishedSecond {
            continuation.finish()
        }
    }

}
