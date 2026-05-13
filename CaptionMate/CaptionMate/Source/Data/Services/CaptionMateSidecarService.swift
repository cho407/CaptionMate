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
import WhisperKit

struct CaptionMateSidecar: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let audioFileName: String
    let language: String
    let segments: [Segment]
    let speakerNames: [String: String]
    let exportSettings: ExportSettings

    struct Segment: Codable, Equatable, Sendable {
        let start: Float
        let end: Float
        let text: String
        let speakerID: Int?
    }

    struct ExportSettings: Codable, Equatable, Sendable {
        let selectedExportPreset: String
        let frameRate: Double
        let includeSpeakerLabelsInExport: Bool
        let speakerDiarizationSpeakerCount: Int
    }
}

enum CaptionMateSidecarError: LocalizedError {
    case unsupportedVersion(Int)
    case fileTooLarge(byteCount: Int64, limit: Int64)

    var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(version):
            return "This CaptionMate sidecar version is not supported: \(version)."
        case let .fileTooLarge(byteCount, limit):
            let actual = ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
            let maximum = ByteCountFormatter.string(fromByteCount: limit, countStyle: .file)
            return "CaptionMate sidecar is too large to restore safely: \(actual). Maximum: \(maximum)."
        }
    }
}

enum CaptionMateSidecarService {
    static let pathExtension = "captionmate.json"
    static let maxReadableSidecarBytes: Int64 = 16 * 1024 * 1024

    static func sidecarURL(forMediaURL mediaURL: URL) -> URL {
        mediaURL
            .deletingPathExtension()
            .appendingPathExtension(pathExtension)
    }

    @discardableResult
    static func write(_ sidecar: CaptionMateSidecar, nextToMediaURL mediaURL: URL) throws -> URL {
        let sidecarURL = sidecarURL(forMediaURL: mediaURL)
        let parentURL = sidecarURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parentURL,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(sidecar)
        try data.write(to: sidecarURL, options: .atomic)
        return sidecarURL
    }

    static func read(from sidecarURL: URL) throws -> CaptionMateSidecar {
        try validateReadableSize(of: sidecarURL)
        let data = try Data(contentsOf: sidecarURL)
        let sidecar = try JSONDecoder().decode(CaptionMateSidecar.self, from: data)
        guard (1 ... CaptionMateSidecar.currentVersion).contains(sidecar.version) else {
            throw CaptionMateSidecarError.unsupportedVersion(sidecar.version)
        }
        return sidecar
    }

    static func readIfPresent(nextToMediaURL mediaURL: URL) throws -> CaptionMateSidecar? {
        let sidecarURL = sidecarURL(forMediaURL: mediaURL)
        guard FileManager.default.fileExists(atPath: sidecarURL.path) else {
            return nil
        }
        return try read(from: sidecarURL)
    }

    private static func validateReadableSize(of sidecarURL: URL) throws {
        let values = try sidecarURL
            .resolvingSymlinksInPath()
            .resourceValues(forKeys: [.fileSizeKey])
        guard let byteCount = values.fileSize.map(Int64.init),
              byteCount > maxReadableSidecarBytes else {
            return
        }
        throw CaptionMateSidecarError.fileTooLarge(
            byteCount: byteCount,
            limit: maxReadableSidecarBytes
        )
    }
}

extension CaptionMateSidecar {
    init(
        result: TranscriptionResult,
        audioFileName: String,
        speakerAssignments: [SpeakerSegmentAssignment?],
        speakerNames: [Int: String],
        selectedExportPreset: SubtitleExportPreset,
        frameRate: Double,
        includeSpeakerLabelsInExport: Bool,
        speakerDiarizationSpeakerCount: Int
    ) {
        self.version = Self.currentVersion
        self.audioFileName = audioFileName
        self.language = result.language
        self.segments = result.segments.enumerated().map { index, segment in
            Segment(
                start: segment.start,
                end: segment.end,
                text: segment.text,
                speakerID: speakerAssignments.indices.contains(index) ?
                    speakerAssignments[index]?.speakerID : nil
            )
        }
        self.speakerNames = Dictionary(
            uniqueKeysWithValues: speakerNames.map { key, value in
                (String(key), value)
            }
        )
        self.exportSettings = ExportSettings(
            selectedExportPreset: selectedExportPreset.rawValue,
            frameRate: frameRate,
            includeSpeakerLabelsInExport: includeSpeakerLabelsInExport,
            speakerDiarizationSpeakerCount: speakerDiarizationSpeakerCount
        )
    }
}
