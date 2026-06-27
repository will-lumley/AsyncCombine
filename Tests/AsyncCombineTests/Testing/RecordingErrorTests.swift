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

    @Test("Error Description")
    func errorDescription() {
        #expect(RecordingError.timeout.errorDescription == "Recorder timed out waiting for next()")
        #expect(RecordingError.sourceEnded.errorDescription == "Recorder's source ended before a value was received")
    }

}
