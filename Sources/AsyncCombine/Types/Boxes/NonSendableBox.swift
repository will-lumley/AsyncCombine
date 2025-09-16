//
//  NonSendableBox.swift
//  AsyncCombine
//
//  Created by William Lumley on 16/9/2025.
//


final class NonSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ v: T) {
        self.value = v
    }
}
