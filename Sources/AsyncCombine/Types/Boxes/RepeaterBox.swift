//
//  RepeaterBox.swift
//  AsyncCombine
//
//  Created by William Lumley on 16/9/2025.
//

// A tiny trampoline so the @Sendable onChange closure doesn't capture a local function.
//
// The stored closure is deliberately *not* actor-isolated. `withObservationTracking`
// tears down its registration the instant the `onChange` closure returns, so re-arming
// has to happen synchronously inside that closure — which means it has to be callable
// from whatever context performed the mutation, with no actor hop in between.
final class RepeaterBox: @unchecked Sendable {
    var call: (@Sendable () -> Void)?
}
