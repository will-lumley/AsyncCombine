//
//  Label.swift
//  AsyncCombine
//
//  Created by William Lumley on 23/9/2025.
//

import Observation

/// A simple UI-like target that must be mutated on the main actor.
@MainActor
@Observable
final class Label: @unchecked Sendable {
    var text: String = ""
    var error: Error? = nil
}
