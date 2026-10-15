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

import CryptoKit
import Foundation

struct SpeakerDiarizationModelValidationReport: Equatable {
    let rootURL: URL
    let missingRelativePaths: [String]

    var isValid: Bool {
        missingRelativePaths.isEmpty
    }
}

struct SpeakerDiarizationModelFailure: Equatable, Sendable {
    let rootURL: URL
    let invalidRelativePaths: [String]
    let fileSnapshot: [SpeakerDiarizationModelFileStamp]

    var matchesCurrentFiles: Bool {
        fileSnapshot == SpeakerDiarizationModelStore.fileSnapshot(for: rootURL)
    }

    var remainingFailure: Self? {
        let currentSnapshot = SpeakerDiarizationModelStore.fileSnapshot(for: rootURL)
        guard currentSnapshot.count == fileSnapshot.count else { return nil }
        let invalidPaths = Set(invalidRelativePaths)
        let unchangedInvalidPaths = SpeakerDiarizationModelStore.requiredRelativeFilePaths.enumerated()
            .compactMap { index, path in
                invalidPaths.contains(path) && fileSnapshot[index] == currentSnapshot[index] ? path : nil
            }
        guard !unchangedInvalidPaths.isEmpty else { return nil }
        return Self(rootURL: rootURL, invalidRelativePaths: unchangedInvalidPaths, fileSnapshot: currentSnapshot)
    }
}

struct SpeakerDiarizationModelFileStamp: Equatable, Sendable {
    let fileNumber: UInt64?
    let deviceNumber: UInt64?
    let size: UInt64?
    let modifiedAt: Date?
    let permissions: UInt16?
}

enum SpeakerDiarizationModelStore {
    static let repoName = "argmaxinc/speakerkit-coreml"
    static let downloadRevision = "86ec9c929b52208b6656eb6a6361ed0d822a1f78"
    static let storagePath = "huggingface/models/argmaxinc/speakerkit-coreml"
    static let displayName = "Speaker diarization"
    static let estimatedDownloadSize: Int64 = 11_243_231
    static let manifestVersion = 2
    private static let stagingDirectoryName = ".speakerkit-staging"
    private static let backupDirectoryName = ".speakerkit-backup"

    static let requiredRelativeFilePaths: [String] = [
        "speaker_segmenter/pyannote-v3/W8A16/SpeakerSegmenter.mlmodelc/metadata.json",
        "speaker_segmenter/pyannote-v3/W8A16/SpeakerSegmenter.mlmodelc/model.mil",
        "speaker_segmenter/pyannote-v3/W8A16/SpeakerSegmenter.mlmodelc/weights/weight.bin",
        "speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedder.mlmodelc/metadata.json",
        "speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedder.mlmodelc/model.mil",
        "speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedder.mlmodelc/weights/weight.bin",
        "speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedderPreprocessor.mlmodelc/metadata.json",
        "speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedderPreprocessor.mlmodelc/model.mil",
        "speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedderPreprocessor.mlmodelc/weights/weight.bin",
        "speaker_clusterer/pyannote-v4/W32A32/PldaProjector.mlmodelc/metadata.json",
        "speaker_clusterer/pyannote-v4/W32A32/PldaProjector.mlmodelc/model.mil",
        "speaker_clusterer/pyannote-v4/W32A32/PldaProjector.mlmodelc/weights/weight.bin",
    ]

    static let requiredFileSizes: [String: Int] = [
        "speaker_segmenter/pyannote-v3/W8A16/SpeakerSegmenter.mlmodelc/metadata.json": 3_757,
        "speaker_segmenter/pyannote-v3/W8A16/SpeakerSegmenter.mlmodelc/model.mil": 193_092,
        "speaker_segmenter/pyannote-v3/W8A16/SpeakerSegmenter.mlmodelc/weights/weight.bin": 1_520_986,
        "speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedder.mlmodelc/metadata.json": 2_367,
        "speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedder.mlmodelc/model.mil": 451_487,
        "speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedder.mlmodelc/weights/weight.bin": 6_661_888,
        "speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedderPreprocessor.mlmodelc/metadata.json": 1_979,
        "speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedderPreprocessor.mlmodelc/model.mil": 14_224,
        "speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedderPreprocessor.mlmodelc/weights/weight.bin": 2_181_696,
        "speaker_clusterer/pyannote-v4/W32A32/PldaProjector.mlmodelc/metadata.json": 1_766,
        "speaker_clusterer/pyannote-v4/W32A32/PldaProjector.mlmodelc/model.mil": 8_128,
        "speaker_clusterer/pyannote-v4/W32A32/PldaProjector.mlmodelc/weights/weight.bin": 199_040,
    ]

    static let requiredFileSHA256: [String: String] = [
        "speaker_segmenter/pyannote-v3/W8A16/SpeakerSegmenter.mlmodelc/metadata.json":
            "2fd6aaf6beb17b3758f5d0c5b2cf5feeacb0cc0c9267dbcd7536b247b1a5860e",
        "speaker_segmenter/pyannote-v3/W8A16/SpeakerSegmenter.mlmodelc/model.mil":
            "423c358915acab0d440c99f5162c17456936c2c02f7394b05ab226b9a34c122a",
        "speaker_segmenter/pyannote-v3/W8A16/SpeakerSegmenter.mlmodelc/weights/weight.bin":
            "75ff1725ef4e58dacf9176466ec274a8a13a6132c296d6b571fb78ddad5455c4",
        "speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedder.mlmodelc/metadata.json":
            "29ea3421161c8344f6ea95db9b472217638a869f686f2494d10e5d11f11f4cda",
        "speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedder.mlmodelc/model.mil":
            "5eee9f6aa380aef88fee604d75c5deaa23adc83c9480cb8f6dedc72803973e77",
        "speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedder.mlmodelc/weights/weight.bin":
            "a02861969f47cf3a67e3b0d276e54b3c8bc3a6e43d40d77d1cccbd57da0e5795",
        "speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedderPreprocessor.mlmodelc/metadata.json":
            "789f81c17dc04d469611d253684e534565fb4a008e54c722b925f1608bf87fce",
        "speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedderPreprocessor.mlmodelc/model.mil":
            "42e552ebd7efb12ea813eceb474018dd0f46168e84ad3a1c54945bfc47be7a82",
        "speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedderPreprocessor.mlmodelc/weights/weight.bin":
            "5f2c284bd22f1f7ab76901c1c6e57f82d4ebbf057fa0b924aad057f124f77a89",
        "speaker_clusterer/pyannote-v4/W32A32/PldaProjector.mlmodelc/metadata.json":
            "acc86b4a4f542d8e7eaf84fc290fe72bd8629b0ffcc16e5b1a9e13d777abd9d8",
        "speaker_clusterer/pyannote-v4/W32A32/PldaProjector.mlmodelc/model.mil":
            "209e641bf4d9c3868c9dc43ab8705094997917eb2df5f5d8c8fda09fed54b1d4",
        "speaker_clusterer/pyannote-v4/W32A32/PldaProjector.mlmodelc/weights/weight.bin":
            "a1dbbb651a0a67fcfe5334672f459df090fa960917a6ee3a5423245a7ab92ced",
    ]

    static func defaultRootURL(fileManager: FileManager = .default) -> URL? {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(storagePath, isDirectory: true)
    }

    static func stagingDownloadBaseURL(fileManager: FileManager = .default) -> URL? {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("huggingface", isDirectory: true)
            .appendingPathComponent(stagingDirectoryName, isDirectory: true)
    }

    static func fileSnapshot(for rootURL: URL) -> [SpeakerDiarizationModelFileStamp] {
        requiredRelativeFilePaths.map { relativePath in
            let attributes = try? FileManager.default.attributesOfItem(
                atPath: rootURL.appendingPathComponent(relativePath).path
            )
            return SpeakerDiarizationModelFileStamp(
                fileNumber: (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value,
                deviceNumber: (attributes?[.systemNumber] as? NSNumber)?.uint64Value,
                size: (attributes?[.size] as? NSNumber)?.uint64Value,
                modifiedAt: attributes?[.modificationDate] as? Date,
                permissions: (attributes?[.posixPermissions] as? NSNumber)?.uint16Value
            )
        }
    }

    // Used after a failed inference, never on every catalog refresh. Read failures
    // are inconclusive: they must not turn a resource/access error into corruption.
    static func integrityFailure(
        for rootURL: URL,
        expectedFileSHA256: [String: String] = requiredFileSHA256
    ) -> SpeakerDiarizationModelFailure? {
        let snapshot = fileSnapshot(for: rootURL)
        guard Set(expectedFileSHA256.keys) == Set(requiredRelativeFilePaths),
              let mismatches = try? checksumMismatches(for: rootURL, expectedFileSHA256: expectedFileSHA256),
              !mismatches.isEmpty,
              !Task.isCancelled,
              snapshot == fileSnapshot(for: rootURL) else { return nil }
        return SpeakerDiarizationModelFailure(
            rootURL: rootURL,
            invalidRelativePaths: mismatches,
            fileSnapshot: snapshot
        )
    }

    static func validationReport(
        for rootURL: URL,
        fileManager: FileManager = .default
    ) -> SpeakerDiarizationModelValidationReport {
        let missingPaths = requiredRelativeFilePaths.filter { relativePath in
            let fileURL = rootURL.appendingPathComponent(relativePath)
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory)
            guard exists, !isDirectory.boolValue else { return true }

            let resourceValues = try? fileURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .fileSizeKey,
            ])
            guard resourceValues?.isRegularFile == true,
                  let fileSize = resourceValues?.fileSize,
                  fileSize == requiredFileSizes[relativePath] else {
                return true
            }

            if relativePath.hasSuffix("metadata.json") {
                guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe),
                      (try? JSONSerialization.jsonObject(with: data)) != nil else {
                    return true
                }
            }

            return false
        }

        return SpeakerDiarizationModelValidationReport(
            rootURL: rootURL,
            missingRelativePaths: missingPaths
        )
    }

    static func installValidatedModel(
        from stagedRootURL: URL,
        to destinationRootURL: URL,
        fileManager: FileManager = .default,
        expectedFileSHA256: [String: String] = requiredFileSHA256
    ) throws {
        guard stagedRootURL.standardizedFileURL != destinationRootURL.standardizedFileURL,
              validationReport(for: stagedRootURL, fileManager: fileManager).isValid,
              Set(expectedFileSHA256.keys) == Set(requiredRelativeFilePaths),
              try checksumMismatches(
                  for: stagedRootURL,
                  expectedFileSHA256: expectedFileSHA256
              ).isEmpty else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let parentURL = destinationRootURL.deletingLastPathComponent()
        let backupURL = parentURL.appendingPathComponent(backupDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        try recoverBackupIfNeeded(for: destinationRootURL, fileManager: fileManager)

        let hadExistingModel = fileManager.fileExists(atPath: destinationRootURL.path)
        if hadExistingModel {
            try fileManager.moveItem(at: destinationRootURL, to: backupURL)
        }

        do {
            try fileManager.moveItem(at: stagedRootURL, to: destinationRootURL)
        } catch {
            if fileManager.fileExists(atPath: destinationRootURL.path) {
                try? fileManager.removeItem(at: destinationRootURL)
            }
            if hadExistingModel, fileManager.fileExists(atPath: backupURL.path) {
                try? fileManager.moveItem(at: backupURL, to: destinationRootURL)
            }
            throw error
        }

        if fileManager.fileExists(atPath: backupURL.path) {
            try? fileManager.removeItem(at: backupURL)
        }
    }

    static func recoverBackupIfNeeded(
        for destinationRootURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let parentURL = destinationRootURL.deletingLastPathComponent()
        let backupURL = parentURL.appendingPathComponent(backupDirectoryName, isDirectory: true)
        guard fileManager.fileExists(atPath: backupURL.path) else { return }

        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destinationRootURL.path) {
            try fileManager.removeItem(at: backupURL)
        } else {
            try fileManager.moveItem(at: backupURL, to: destinationRootURL)
        }
    }

    private static func checksumMismatches(
        for rootURL: URL,
        expectedFileSHA256: [String: String]
    ) throws -> [String] {
        try requiredRelativeFilePaths.filter { relativePath in
            try Task.checkCancellation()
            guard let expectedChecksum = expectedFileSHA256[relativePath] else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let data = try Data(contentsOf: rootURL.appendingPathComponent(relativePath), options: .mappedIfSafe)
            let checksum = SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
            return checksum != expectedChecksum
        }
    }

}
