//
//  AsyncBox.swift
//  AsyncCombine
//
//  Created by William Lumley on 16/9/2025.
//

/// Minimal async box to pass values across tasks in tests.
actor AsyncBox<T> {
    private var value: T?

    init(_ initial: T? = nil) {
        self.value = initial
    }

    func set(_ newValue: T) {
        self.value = newValue
    }

    func get() -> T? {
        return self.value
    }
}
