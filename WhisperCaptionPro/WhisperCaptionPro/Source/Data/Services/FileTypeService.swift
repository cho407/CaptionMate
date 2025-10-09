//
//  FileTypeService.swift
//  WhisperCaptionPro
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
