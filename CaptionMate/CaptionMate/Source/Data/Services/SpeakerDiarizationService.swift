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

enum SpeakerAssignmentGranularity: Equatable, Sendable {
    case segmentOverlap
}

enum SpeakerDiarizationServiceError: LocalizedError {
    case modelUnavailable(SpeakerDiarizationModelFailure)

    static let repairMessage = "Speaker model files need repair. Open Manage Models to repair them."

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            return Self.repairMessage
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
        try Task.checkCancellation()
        let fileSnapshot = SpeakerDiarizationModelStore.fileSnapshot(for: modelRootURL)
        let report = SpeakerDiarizationModelStore.validationReport(for: modelRootURL)
        guard report.isValid else {
            throw SpeakerDiarizationServiceError.modelUnavailable(SpeakerDiarizationModelFailure(
                rootURL: modelRootURL,
                invalidRelativePaths: report.missingRelativePaths,
                fileSnapshot: fileSnapshot
            ))
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

        var loadedSpeakerKit: SpeakerKit?
        do {
            let speakerKit = try await SpeakerKit(config)
            loadedSpeakerKit = speakerKit
            let result = try await speakerKit.diarize(
                audioArray: audioSamples,
                options: PyannoteDiarizationOptions(numberOfSpeakers: expectedSpeakerCount),
                progressCallback: progressHandler
            )
            await speakerKit.unloadModels()
            loadedSpeakerKit = nil
            try Task.checkCancellation()
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
            await loadedSpeakerKit?.unloadModels()
            throw Self.diagnosedError(error, modelRootURL: modelRootURL)
        }
    }

    static func diagnosedError(
        _ error: Error,
        modelRootURL: URL,
        expectedFileSHA256: [String: String] = SpeakerDiarizationModelStore.requiredFileSHA256
    ) -> Error {
        guard !(error is CancellationError), !Task.isCancelled else { return CancellationError() }
        if let failure = SpeakerDiarizationModelStore.integrityFailure(
            for: modelRootURL, expectedFileSHA256: expectedFileSHA256
        ) {
            return SpeakerDiarizationServiceError.modelUnavailable(failure)
        }
        return Task.isCancelled ? CancellationError() : error
    }
}

enum SpeakerAssignmentMapper {
    static let defaultGranularity: SpeakerAssignmentGranularity = .segmentOverlap

    static func assignments(
        for transcriptionSegments: [TranscriptionSegment],
        from timelineSegments: [SpeakerTimelineSegment]
    ) -> [SpeakerSegmentAssignment?] {
        let sortedTimelineSegments = timelineSegments.sorted {
            if $0.start == $1.start {
                return $0.end < $1.end
            }
            return $0.start < $1.start
        }
        let indexedSegments = transcriptionSegments.enumerated().sorted { lhs, rhs in
            if lhs.element.start == rhs.element.start {
                if lhs.element.end == rhs.element.end {
                    return lhs.offset < rhs.offset
                }
                return lhs.element.end < rhs.element.end
            }
            return lhs.element.start < rhs.element.start
        }
        var assignments = Array<SpeakerSegmentAssignment?>(
            repeating: nil,
            count: transcriptionSegments.count
        )
        var timelineCursor = 0

        for indexedSegment in indexedSegments {
            let segment = indexedSegment.element
            while timelineCursor < sortedTimelineSegments.count,
                  sortedTimelineSegments[timelineCursor].end <= segment.start {
                timelineCursor += 1
            }

            var scanIndex = timelineCursor
            var speakerScores: [Int: Float] = [:]
            while scanIndex < sortedTimelineSegments.count,
                  sortedTimelineSegments[scanIndex].start < segment.end {
                let timelineSegment = sortedTimelineSegments[scanIndex]
                let score = overlap(
                    start: segment.start,
                    end: segment.end,
                    otherStart: timelineSegment.start,
                    otherEnd: timelineSegment.end
                )
                if score > 0 {
                    speakerScores[timelineSegment.speakerID, default: 0] += score
                }
                scanIndex += 1
            }

            guard let assignment = bestAssignment(from: speakerScores) else {
                continue
            }
            assignments[indexedSegment.offset] = assignment
        }

        return assignments
    }

    // Cluster numbers are local to a run. Preserve a name only for an unchanged
    // group of subtitle turns, even when the new run permutes those numbers.
    static func reconciledNames(
        from previous: [SpeakerSegmentAssignment?],
        names: [Int: String],
        to current: [SpeakerSegmentAssignment?]
    ) -> [Int: String] {
        guard previous.count == current.count, !names.isEmpty else { return [:] }
        var previousGroups: [Int: Set<Int>] = [:]
        var currentGroups: [Int: Set<Int>] = [:]
        for index in current.indices {
            if let id = previous[index]?.speakerID { previousGroups[id, default: []].insert(index) }
            if let id = current[index]?.speakerID { currentGroups[id, default: []].insert(index) }
        }
        let namedGroups = Dictionary(uniqueKeysWithValues: previousGroups.compactMap { id, turns in
            names[id].map { (turns, $0) }
        })
        return currentGroups.reduce(into: [:]) { result, entry in
            if let name = namedGroups[entry.value] { result[entry.key] = name }
        }
    }

    static func preservedAssignments(
        for targetSegments: [TranscriptionSegment],
        from sourceSegments: [TranscriptionSegment],
        assignments: [SpeakerSegmentAssignment?]
    ) -> [SpeakerSegmentAssignment?] {
        let sortedSources = sourceSegments.indices.compactMap { sourceIndex -> (
            segment: TranscriptionSegment,
            assignment: SpeakerSegmentAssignment
        )? in
            guard assignments.indices.contains(sourceIndex),
                  let assignment = assignments[sourceIndex] else {
                return nil
            }
            return (sourceSegments[sourceIndex], assignment)
        }
        .sorted {
            if $0.segment.start == $1.segment.start {
                return $0.segment.end < $1.segment.end
            }
            return $0.segment.start < $1.segment.start
        }
        let indexedTargets = targetSegments.enumerated().sorted {
            if $0.element.start == $1.element.start {
                return $0.element.end < $1.element.end
            }
            return $0.element.start < $1.element.start
        }
        var preserved = Array<SpeakerSegmentAssignment?>(repeating: nil, count: targetSegments.count)
        var sourceCursor = 0

        for (targetIndex, segment) in indexedTargets {
            while sourceCursor < sortedSources.count,
                  sortedSources[sourceCursor].segment.end <= segment.start {
                sourceCursor += 1
            }

            var speakerScores: [Int: Float] = [:]
            var scanIndex = sourceCursor

            while scanIndex < sortedSources.count,
                  sortedSources[scanIndex].segment.start < segment.end {
                let score = overlap(
                    start: segment.start,
                    end: segment.end,
                    otherStart: sortedSources[scanIndex].segment.start,
                    otherEnd: sortedSources[scanIndex].segment.end
                )
                if score > 0 {
                    let speakerID = sortedSources[scanIndex].assignment.speakerID
                    speakerScores[speakerID, default: 0] += score
                }
                scanIndex += 1
            }

            preserved[targetIndex] = bestAssignment(from: speakerScores)
        }

        return preserved
    }

    private static func bestAssignment(from speakerScores: [Int: Float]) -> SpeakerSegmentAssignment? {
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
