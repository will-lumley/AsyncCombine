//
//  RecordingError.swift
//  AsyncCombine
//
//  Created by William Lumley on 7/10/2025.
//

#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

public enum RecordingError: Error, LocalizedError, Sendable {
    case timeout
    case sourceEnded

    public var errorDescription: String? {
        switch self {
        case .timeout:
            "Recorder timed out waiting for next()"
        case .sourceEnded:
            "Recorder's source ended before a value was received"
        }
    }
}
