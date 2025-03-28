//
//  ExportService.swift
//  WhisperCaptionPro
//
//  Created by 조형구 on 3/28/25.
//
import Foundation
import AppKit
import WhisperKit
import UniformTypeIdentifiers
import WhisperKit


struct ExportService {
    /// 파일 내보내기
    static func exportTranscriptionResult(result: TranscriptionResult,
                                          defaultFileName: String = "Subtitle") async {
        // 모든 허용 UTType을 가져옴
        let allowedContentTypes = SubtitleFileType.allCases.map { $0.utType }
        
        // NSSavePanel을 통해 파일 저장 경로와 선택된 파일 형식을 받아옴
        let (saveURL, selectedUTType) = await NSSavePanel.showSavePanel(allowedFileTypes: allowedContentTypes,
                                                                         defaultFileName: defaultFileName)
        
        guard let saveURL = saveURL, let selectedUTType = selectedUTType,
              let selectedFileType = SubtitleFileType.from(utType: selectedUTType) else {
            print("Export cancelled or file type not selected")
            return
        }
        
        // 전사 결과를 해당 파일 형식에 맞게 문자열로 변환
        var fileContent: String = ""
        switch selectedFileType {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            if let data = try? encoder.encode(result),
               let content = String(data: data, encoding: .utf8) {
                fileContent = content
            }
        case .srt:
            let writer = WriteSRT(outputDir: "") // outputDir은 saveURL에서 경로를 사용하므로 빈 문자열로 처리
            var srtContent = ""
            var index = 1
            for segment in result.segments {
                if let wordTimings = segment.words, !wordTimings.isEmpty {
                    for wordTiming in wordTimings {
                        srtContent += writer.formatSegment(index: index,
                                                           start: wordTiming.start,
                                                           end: wordTiming.end,
                                                           text: wordTiming.word)
                        index += 1
                    }
                } else {
                    srtContent += writer.formatSegment(index: index,
                                                       start: segment.start,
                                                       end: segment.end,
                                                       text: segment.text)
                    index += 1
                }
            }
            fileContent = srtContent
        case .vtt:
            let writer = WriteVTT(outputDir: "")
            var vttContent = "WEBVTT\n\n"
            for segment in result.segments {
                if let wordTimings = segment.words, !wordTimings.isEmpty {
                    for wordTiming in wordTimings {
                        vttContent += writer.formatTiming(start: wordTiming.start,
                                                          end: wordTiming.end,
                                                          text: wordTiming.word)
                    }
                } else {
                    vttContent += writer.formatTiming(start: segment.start,
                                                      end: segment.end,
                                                      text: segment.text)
                }
            }
            fileContent = vttContent
        }
        
        // 선택한 경로에 파일 내용을 저장
        do {
            try fileContent.write(to: saveURL, atomically: true, encoding: .utf8)
            print("Export succeeded: \(saveURL)")
        } catch {
            print("Export failed: \(error.localizedDescription)")
        }
    }
}
