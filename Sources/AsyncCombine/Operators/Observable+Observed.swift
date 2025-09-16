//
//  Observable+Observed.swift
//  AsyncCombine
//
//  Created by William Lumley on 16/9/2025.
//

import Observation

@available(macOS 14.0, *)
public extension Observable where Self: AnyObject {

    func observed<Value: Sendable>(_ keyPath: KeyPath<Self, Value>) -> AsyncStream<Value> {
        let object = WeakBox(self)
        let kp = NonSendableBox(keyPath)
        let repeater = RepeaterBox()

        return AsyncStream { continuation in
            Task { @MainActor in
                guard let obj = object.value else {
                    continuation.finish()
                    return
                }

                // Replay current value
                continuation.yield(obj[keyPath: kp.value])

                // Define the tracking body without creating a nested function to capture.
                repeater.call = {
                    guard let obj = object.value else {
                        continuation.finish()
                        return
                    }
                    withObservationTracking {
                        _ = obj[keyPath: kp.value]           // register the read
                    } onChange: {
                        Task { @MainActor in
                            guard let obj = object.value else {
                                continuation.finish()
                                return
                            }
                            continuation.yield(obj[keyPath: kp.value])
                            repeater.call?()                   // re-register for next change
                        }
                    }
                }

                // Start tracking
                repeater.call?()
            }
        }
    }
}
