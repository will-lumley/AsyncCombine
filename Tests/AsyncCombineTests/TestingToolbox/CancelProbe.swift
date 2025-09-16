//
//  CancelProbe.swift
//  AsyncCombine
//
//  Created by William Lumley on 16/9/2025.
//


actor CancelProbe {
    private(set) var didCancel = false

    func mark() {
        self.didCancel = true
    }

    func wasCancelled() -> Bool {
        return self.didCancel
    }
}
