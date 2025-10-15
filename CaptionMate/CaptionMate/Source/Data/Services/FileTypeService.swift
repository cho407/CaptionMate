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

//
//  FileTypeService.swift
//  CaptionMate
//
//  Created by 조형구 on 3/21/25.
//

import UniformTypeIdentifiers

public enum SubtitleFileType: String, CaseIterable {
    case srt
    case fcpxml
    case vtt
    case json

    public var utType: UTType {
        switch self {
        case .srt:
            return UTType(filenameExtension: "srt") ?? .plainText
        case .fcpxml:
            return UTType.fcpxml
        case .vtt:
            return UTType(filenameExtension: "vtt") ?? .plainText
        case .json:
            return UTType.json
        }
    }

    public static func from(utType: UTType) -> SubtitleFileType? {
        return allCases.first { $0.utType.identifier == utType.identifier }
    }
}
