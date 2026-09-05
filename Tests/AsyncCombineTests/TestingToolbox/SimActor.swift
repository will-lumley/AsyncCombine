//
//  SimActor.swift
//  AsyncCombine
//
//  Created by William Lumley on 5/9/2026.
//

/// A global actor that isn't the main actor, for testing models that live somewhere
/// other than the UI.
@globalActor
actor SimActor {

    static let shared = SimActor()

    static func run<T: Sendable>(_ body: @SimActor () throws -> T) async rethrows -> T {
        return try await body()
    }

}
