//
//  AsyncStream+MakeStream.swift
//  AsyncCombine
//
//  Created by William Lumley on 16/9/2025.
//

extension AsyncStream {

    /// Convenience to create a stream + continuation pair.
    static func makeStream() -> (
        AsyncStream<Element>,
        AsyncStream<Element>.Continuation
    ) {
        var continuation: AsyncStream<Element>.Continuation!

        let stream = AsyncStream<Element> {
            continuation = $0
        }

        return (stream, continuation)
    }

}
