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
//  ExportService.swift
//  CaptionMate
//
//  Created by 조형구 on 3/28/25.
//

import AppKit
import Foundation
import UniformTypeIdentifiers
import WhisperKit

// MARK: - ExportService

enum ExportOutcome {
    case success(path: String)
    case cancelled
    case failure(Error)
}

struct ExportService {
    /// 파일 내보내기 함수
    static func exportTranscriptionResult(result: TranscriptionResult,
                                          defaultFileName: String = "Subtitle",
                                          frameRate: Double = 30.0,
                                          fileType: SubtitleFileType) async -> ExportOutcome {
        let allowedContentTypes = [fileType.utType]
        let (saveURL, _) = await NSSavePanel.showSavePanel(
            allowedFileTypes: allowedContentTypes,
            defaultFileName: defaultFileName
        )
        guard let saveURL else {
            return .cancelled
        }

        // 저장 경로에서 outputDir와 파일 이름을 분리
        let outputDir = saveURL.deletingLastPathComponent().path
        let baseFileName = saveURL.deletingPathExtension().lastPathComponent

        // 선택된 파일 형식에 따라 적절한 writer 생성
        let writer: any ResultWriting
        switch fileType {
        case .srt:
            writer = WriteSRT(outputDir: outputDir)
        case .fcpxml:
            writer = WriteFCPXML(outputDir: outputDir, frameRate: frameRate)
        case .vtt:
            writer = WriteVTT(outputDir: outputDir)
        case .json:
            writer = WriteJSON(outputDir: outputDir)
        case .txt:
            writer = WritePlainText(outputDir: outputDir)
        case .doc:
            writer = WriteDOC(outputDir: outputDir)
        }

        switch writer.write(result: result, to: baseFileName, options: nil) {
        case let .success(path):
            return .success(path: path)
        case let .failure(error):
            return .failure(error)
        }
    }
}
