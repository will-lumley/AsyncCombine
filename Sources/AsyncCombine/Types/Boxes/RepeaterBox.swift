//
//  RepeaterBox.swift
//  AsyncCombine
//
//  Created by William Lumley on 16/9/2025.
//

// A tiny trampoline so the @Sendable onChange closure doesn't capture a local function.
final class RepeaterBox: @unchecked Sendable {
    var call: (@MainActor () -> Void)?
}
