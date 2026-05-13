//
//  Copyright 2025 Harrison Cho
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

import Foundation
import SpeakerKit
import WhisperKit

struct SpeakerTimelineSegment: Equatable, Sendable {
    let speakerID: Int
    let start: Float
    let end: Float
}

enum SpeakerDiarizationServiceError: LocalizedError {
    case modelUnavailable([String])

    var errorDescription: String? {
        switch self {
        case let .modelUnavailable(missingPaths):
            let summary = missingPaths.prefix(3).joined(separator: ", ")
            return summary.isEmpty ? "Speaker model is not ready." : "Missing speaker model files: \(summary)"
        }
    }
}

struct SpeakerDiarizationService {
    let modelRootURL: URL

    func diarize(
        audioSamples: [Float],
        expectedSpeakerCount: Int? = nil,
        progressHandler: (@Sendable (Progress) -> Void)? = nil
    ) async throws -> [SpeakerTimelineSegment] {
        let report = SpeakerDiarizationModelStore.validationReport(for: modelRootURL)
        guard report.isValid else {
            throw SpeakerDiarizationServiceError.modelUnavailable(report.missingRelativePaths)
        }

        let config = PyannoteConfig(
            modelRepo: SpeakerDiarizationModelStore.repoName,
            modelFolder: modelRootURL.path,
            download: false,
            load: false,
            verbose: false,
            fullRedundancy: false,
            concurrentSegmenterWorkers: 1,
            concurrentEmbedderWorkers: 1
        )

        let speakerKit = try await SpeakerKit(config)
        do {
            let result = try await speakerKit.diarize(
                audioArray: audioSamples,
                options: PyannoteDiarizationOptions(numberOfSpeakers: expectedSpeakerCount),
                progressCallback: progressHandler
            )
            await speakerKit.unloadModels()
            return result.segments.compactMap { segment in
                guard let speakerID = segment.speaker.speakerId,
                      segment.endTime > segment.startTime else {
                    return nil
                }
                return SpeakerTimelineSegment(
                    speakerID: speakerID,
                    start: segment.startTime,
                    end: segment.endTime
                )
            }
        } catch {
            await speakerKit.unloadModels()
            throw error
        }
    }
}

enum SpeakerAssignmentMapper {
    static func assignments(
        for transcriptionSegments: [TranscriptionSegment],
        from timelineSegments: [SpeakerTimelineSegment]
    ) -> [SpeakerSegmentAssignment?] {
        var previousAssignment: SpeakerSegmentAssignment?

        return transcriptionSegments.map { segment in
            guard let assignment = bestAssignment(for: segment, timelineSegments: timelineSegments) else {
                return previousAssignment
            }
            previousAssignment = assignment
            return assignment
        }
    }

    static func preservedAssignments(
        for targetSegments: [TranscriptionSegment],
        from sourceSegments: [TranscriptionSegment],
        assignments: [SpeakerSegmentAssignment?]
    ) -> [SpeakerSegmentAssignment?] {
        targetSegments.map { segment in
            var bestScore: Float = 0
            var bestAssignment: SpeakerSegmentAssignment?

            for sourceIndex in sourceSegments.indices {
                guard assignments.indices.contains(sourceIndex),
                      let assignment = assignments[sourceIndex] else {
                    continue
                }

                let score = overlap(
                    start: segment.start,
                    end: segment.end,
                    otherStart: sourceSegments[sourceIndex].start,
                    otherEnd: sourceSegments[sourceIndex].end
                )
                if score > bestScore {
                    bestScore = score
                    bestAssignment = assignment
                }
            }

            return bestScore > 0 ? bestAssignment : nil
        }
    }

    private static func bestAssignment(
        for segment: TranscriptionSegment,
        timelineSegments: [SpeakerTimelineSegment]
    ) -> SpeakerSegmentAssignment? {
        var speakerScores: [Int: Float] = [:]

        for timelineSegment in timelineSegments {
            let score = overlap(
                start: segment.start,
                end: segment.end,
                otherStart: timelineSegment.start,
                otherEnd: timelineSegment.end
            )
            guard score > 0 else { continue }
            speakerScores[timelineSegment.speakerID, default: 0] += score
        }

        guard let bestSpeaker = speakerScores.max(by: { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key > rhs.key
            }
            return lhs.value < rhs.value
        }) else {
            return nil
        }

        return SpeakerSegmentAssignment(speakerID: bestSpeaker.key)
    }

    private static func overlap(
        start: Float,
        end: Float,
        otherStart: Float,
        otherEnd: Float
    ) -> Float {
        max(0, min(end, otherEnd) - max(start, otherStart))
    }
}

enum SpeakerLabelFormatter {
    static func prefixedText(
        _ text: String,
        assignment: SpeakerSegmentAssignment?,
        speakerName: String? = nil,
        includeSpeakerLabel: Bool
    ) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard includeSpeakerLabel,
              let assignment,
              !trimmedText.isEmpty else {
            return trimmedText
        }

        let customName = speakerName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = (customName?.isEmpty == false ? customName : nil) ??
            assignment.displayName
        let prefix = "\(displayName):"
        let compactText = trimmedText
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
        let compactPrefix = prefix
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
        guard !compactText.hasPrefix(compactPrefix) else {
            return trimmedText
        }

        return "\(prefix) \(trimmedText)"
    }
}
