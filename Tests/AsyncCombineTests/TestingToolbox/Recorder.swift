//
//  Recorder.swift
//  AsyncCombine
//
//  Created by William Lumley on 16/9/2025.
//

/// Thread-safe value recorder for test assertions.
actor Recorder<T: Sendable> {

    private var values: [T] = []

    func append(_ value: T) {
        self.values.append(value)
    }

    func snapshot() -> [T] {
        return self.values
    }

}
