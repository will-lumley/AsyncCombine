//
//  RecordingError.swift
//  AsyncCombineAsyncCombineTesting
//
//  Created by William Lumley on 7/10/2025.
//

public enum RecordingError: Error, Sendable {
    case timeout
    case sourceEnded

    var description: String {
        switch self {
        case .timeout:
            "Recorder timed out waiting for next()"
        case .sourceEnded:
            "Recorder's source ended before a value was received"
        }
    }
}
