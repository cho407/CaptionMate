//
//  Copyright 2026 Harrison Cho
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//       http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import WhisperKit

enum WhisperTranscriptionService {
    static func transcribe(
        samples: [Float],
        using kit: WhisperKit,
        options: DecodingOptions,
        callback: TranscriptionCallback?
    ) async throws -> [TranscriptionResult] {
        try Task.checkCancellation()
        let windowSamples = kit.featureExtractor.windowSamples ?? Constants.defaultWindowSamples
        guard options.chunkingStrategy == .vad, samples.count > windowSamples else {
            return try await kit.transcribe(audioArray: samples, decodeOptions: options, callback: callback)
        }

        // Keep the SDK's VAD boundaries and timing adjustment, but inspect every
        // chunk result before its convenience API can discard failed chunks.
        let chunker = VADAudioChunker(vad: kit.voiceActivityDetector ?? EnergyVAD())
        let chunks = try await chunker.chunkAll(
            audioArray: samples, maxChunkLength: windowSamples, decodeOptions: options
        )
        try Task.checkCancellation()
        kit.progress.totalUnitCount = max(kit.progress.totalUnitCount, Int64(chunks.count))
        var chunkOptions = options
        chunkOptions.clipTimestamps = []
        chunkOptions.chunkingStrategy = ChunkingStrategy.none
        let results = await kit.transcribeWithOptions(
            audioArrays: chunks.map(\.audioSamples),
            decodeOptionsArray: Array(repeating: chunkOptions, count: chunks.count),
            seekOffsets: chunks.map(\.seekOffsetIndex),
            callback: callback
        )
        try Task.checkCancellation()
        for result in results {
            if case let .failure(error) = result { throw error }
        }
        return chunker.updateSeekOffsetsForResults(chunkedResults: results, audioChunks: chunks)
    }
}
