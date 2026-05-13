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

struct SpeakerDiarizationModelValidationReport: Equatable {
    let rootURL: URL
    let missingRelativePaths: [String]

    var isValid: Bool {
        missingRelativePaths.isEmpty
    }
}

enum SpeakerDiarizationModelStore {
    static let repoName = "argmaxinc/speakerkit-coreml"
    static let storagePath = "huggingface/models/argmaxinc/speakerkit-coreml"
    static let displayName = "Speaker diarization"
    static let estimatedDownloadSize: Int64 = 11_243_231
    static let manifestVersion = 1

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

    static func defaultRootURL(fileManager: FileManager = .default) -> URL? {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(storagePath, isDirectory: true)
    }

    static func validationReport(
        for rootURL: URL,
        fileManager: FileManager = .default
    ) -> SpeakerDiarizationModelValidationReport {
        let missingPaths = requiredRelativeFilePaths.filter { relativePath in
            let fileURL = rootURL.appendingPathComponent(relativePath)
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory)
            return !exists || isDirectory.boolValue
        }

        return SpeakerDiarizationModelValidationReport(
            rootURL: rootURL,
            missingRelativePaths: missingPaths
        )
    }
}
