//
//  RecordingError.swift
//  AsyncCombine
//
//  Created by William Lumley on 7/10/2025.
//

@testable import AsyncCombine
import Testing

@Suite("RecordingError")
struct RecordingErrorTests {

    @Test("Description")
    func description() {
        #expect(RecordingError.timeout.description == "Recorder timed out waiting for next()")
        #expect(RecordingError.sourceEnded.description == "Recorder's source ended before a value was received")
    }

}
