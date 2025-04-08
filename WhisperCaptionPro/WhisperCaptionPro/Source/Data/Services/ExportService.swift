//
//  ExportService.swift
//  WhisperCaptionPro
//
//  Created by 조형구 on 3/28/25.
//

import Foundation
import AppKit
import UniformTypeIdentifiers
import WhisperKit

// MARK: - ExportService

struct ExportService {
    /// 파일 내보내기 함수
    static func exportTranscriptionResult(result: TranscriptionResult,
                                          defaultFileName: String = "Subtitle",
                                          frameRate: Double = 30.0) async {
        // 모든 허용 UTType (추가된 파일 형식 포함)
        let allowedContentTypes = SubtitleFileType.allCases.map { $0.utType }
        print("\(allowedContentTypes)")
        // NSSavePanel을 통해 파일 저장 경로와 선택된 파일 형식을 받아옴
        let (saveURL, selectedUTType) = await NSSavePanel.showSavePanel(allowedFileTypes: allowedContentTypes,
                                                                         defaultFileName: defaultFileName)
        guard let saveURL = saveURL,
              let selectedUTType = selectedUTType,
              let selectedFileType = SubtitleFileType.from(utType: selectedUTType) else {
            print("Export cancelled or file type not selected")
            return
        }
        
        // 저장 경로에서 outputDir와 파일 이름을 분리
        let outputDir = saveURL.deletingLastPathComponent().path
        let baseFileName = saveURL.deletingPathExtension().lastPathComponent
        
        // 선택된 파일 형식에 따라 적절한 writer 생성
        var writer: ResultWriting?
        switch selectedFileType {
        case .json:
            writer = WriteJSON(outputDir: outputDir)
        case .srt:
            writer = WriteSRT(outputDir: outputDir)
        case .vtt:
            writer = WriteVTT(outputDir: outputDir)
        case .fcpxml:
            writer = WriteFCPXML(outputDir: outputDir, frameRate: frameRate)
        case .ass:
            writer = WriteASS(outputDir: outputDir, frameRate: frameRate)
        case .scc:
            writer = WriteSCC(outputDir: outputDir, frameRate: frameRate)
        case .xml:
            writer = WriteXML(outputDir: outputDir)
        }
        
        if let writer = writer {
            let exportResult = writer.write(result: result, to: baseFileName, options: nil)
            switch exportResult {
            case .success(let path):
                print("Export succeeded: \(path)")
            case .failure(let error):
                print("Export failed: \(error.localizedDescription)")
            }
        }
    }
}
