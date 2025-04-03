//
//  FileService.swift
//  WhisperCaptionPro
//
//  Created by 조형구 on 3/21/25.
//

import UniformTypeIdentifiers

public enum SubtitleFileType: String, CaseIterable {
    case json
    case srt
    case vtt
    case fcpxml
    case xml
    case scc
    case ass

    public var utType: UTType {
        switch self {
        case .json:
            return UTType.json
        case .srt:
            return UTType(filenameExtension: "srt") ?? .plainText
        case .vtt:
            return UTType(filenameExtension: "vtt") ?? .plainText
        case .fcpxml:
            return UTType.fcpxml
        case .xml:
            return UTType.xml
        case .scc:
            return UTType(filenameExtension: "scc") ?? .plainText
        case .ass:
            return UTType(filenameExtension: "ass") ?? .plainText
        }
    }
    
    public static func from(utType: UTType) -> SubtitleFileType? {
        return self.allCases.first { $0.utType.identifier == utType.identifier }
    }
}
