//
//  Untitled.swift
//  AsyncCombine
//
//  Created by William Lumley on 16/9/2025.
//

/// A closure type that asynchronously handles elements emitted by an `AsyncSequence`.
///
/// Used by operators like ``AsyncSequence/sink(catching:_:)`` to process
/// each value produced by the sequence.
///
/// - Parameter element: The element emitted by the sequence.
public typealias ReceiveElement<Element> = @Sendable (Element) async -> Void

/// A closure type that handles failures thrown during iteration of an `AsyncSequence`.
///
/// This is generic over the failure type, mirroring Combine-style APIs so you
/// can specialize error handling when you have a concrete error type.
///
/// - Parameter failure: The error thrown by the sequence.
public typealias ReceiveError<Failure: Error> = @Sendable (Failure) -> Void
