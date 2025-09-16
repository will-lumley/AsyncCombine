//
//  AsyncThrowingStream+MakeStream.swift
//  AsyncCombine
//
//  Created by William Lumley on 16/9/2025.
//

extension AsyncThrowingStream where Failure == Error {

    /// Convenience to create a throwing stream + continuation pair.
    static func makeStream() -> (
        AsyncThrowingStream<Element, Failure>,
        AsyncThrowingStream<
            Element,
            Failure
        >.Continuation
    ) {
        var continuation: AsyncThrowingStream<Element, Failure>.Continuation!
        let stream = AsyncThrowingStream<Element, Failure> {
            continuation = $0
        }
        return (stream, continuation)
    }

}
