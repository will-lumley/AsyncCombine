//
//  WeakBox.swift
//  AsyncCombine
//
//  Created by William Lumley on 16/9/2025.
//

// Helpers used only to make @Sendable captures safe.
// We only *use* these contents on MainActor.
final class WeakBox<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
    init(_ v: T) {
        self.value = v
    }
}
