//
//  FileService.swift
//  WhisperCaptionPro
//
//  Created by 조형구 on 3/21/25.
//

import UniformTypeIdentifiers

enum SubtitleFileType: String, CaseIterable {
    case srt
    case vtt
    case json

    var utType: UTType {
        switch self {
        case .srt: return UTType(filenameExtension: "srt")!
        case .vtt: return UTType(filenameExtension: "vtt")!
        case .json: return UTType.json
        }
    }

    /// UTType을 기반으로 SubtitleFileType을 생성하는 정적 메소드
    static func from(utType: UTType) -> SubtitleFileType? {
        return self.allCases.first { $0.utType.identifier == utType.identifier }
    }
}
