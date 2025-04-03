//
//  AdditionalResultWriter.swift
//  WhisperCaptionPro
//
//  Created by 조형구 on 4/1/25.
//

import Foundation
#if canImport(WhisperKit)
import WhisperKit
#endif

// MARK: - Helper Functions

/// 주어진 초를 프레임 레이트를 반영한 타임코드 (HH:MM:SS:FF) 문자열로 변환 (FCPXML, SCC 등에서 사용)
func timecodeString(from seconds: Float, frameRate: Double) -> String {
    let totalFrames = Int(round(Double(seconds) * frameRate))
    let hours = totalFrames / Int(frameRate * 3600)
    let minutes = (totalFrames % Int(frameRate * 3600)) / Int(frameRate * 60)
    let secondsValue = (totalFrames % Int(frameRate * 60)) / Int(frameRate)
    let frames = totalFrames % Int(frameRate)
    return String(format: "%02d:%02d:%02d:%02d", hours, minutes, secondsValue, frames)
}

/// ASS 포맷용 타임코드 문자열 (H:MM:SS.cs)
func assTimecodeString(from seconds: Float) -> String {
    let totalCentiseconds = Int(round(Double(seconds) * 100))
    let hours = totalCentiseconds / 360000
    let minutes = (totalCentiseconds % 360000) / 6000
    let secondsValue = (totalCentiseconds % 6000) / 100
    let centiseconds = totalCentiseconds % 100
    return String(format: "%d:%02d:%02d.%02d", hours, minutes, secondsValue, centiseconds)
}

/// XML용 타임스탬프 문자열 (HH:MM:SS.mmm)
func xmlTimeString(from seconds: Float) -> String {
    let hrs = Int(seconds / 3600)
    let mins = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
    let secs = seconds.truncatingRemainder(dividingBy: 60)
    return String(format: "%02d:%02d:%06.3f", hrs, mins, secs)
}

// MARK: - WriteFCPXML

open class WriteFCPXML: ResultWriting {
    public let outputDir: String
    public let frameRate: Double

    public init(outputDir: String, frameRate: Double) {
        self.outputDir = outputDir
        self.frameRate = frameRate
    }

    public func write(result: TranscriptionResult, to file: String, options: [String: Any]? = nil) -> Result<String, Error> {
        // 프레임 레이트에 따른 frameDuration 계산
        let frameDurationString: String
        if abs(frameRate - 29.97) < 0.01 {
            frameDurationString = "1001/30000s"
        } else if abs(frameRate - 24) < 0.01 {
            frameDurationString = "1/24s"
        } else if abs(frameRate - 25) < 0.01 {
            frameDurationString = "1/25s"
        } else if abs(frameRate - 30) < 0.01 {
            frameDurationString = "1/30s"
        } else if abs(frameRate - 60) < 0.01 {
            frameDurationString = "1/60s"
        } else {
            frameDurationString = "1/\(Int(frameRate))s"
        }
        
        // 비디오 포맷 이름
        let formatName: String
        if abs(frameRate - 29.97) < 0.01 {
            formatName = "FFVideoFormat1080p2997"
        } else if abs(frameRate - 24) < 0.01 {
            formatName = "FFVideoFormat1080p24"
        } else if abs(frameRate - 25) < 0.01 {
            formatName = "FFVideoFormat1080p25"
        } else if abs(frameRate - 30) < 0.01 {
            formatName = "FFVideoFormat1080p30"
        } else if abs(frameRate - 60) < 0.01 {
            formatName = "FFVideoFormat1080p60"
        } else {
            formatName = "FFVideoFormat1080p\(Int(frameRate))"
        }
        
        // 파이썬 템플릿을 기반으로 한 FCPXML 구조
        var xmlContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE fcpxml>
        <fcpxml version="1.9">
            <resources>
                <format id="r1" name="\(formatName)" frameDuration="\(frameDurationString)" width="1920" height="1080"/>
                <effect id="r2" name="Custom" uid=".../Titles.localized/Build In:Out.localized/Custom.localized/Custom.moti"/>
            </resources>
            <library>
                <event name="WhisperCaptionPro">
                    <project name="\(file)">
                        <sequence format="r1" duration="30s" tcStart="0s" tcFormat="NDF">
                            <spine>
        """
        
        // 각 세그먼트마다 타이틀 요소 생성
        // 각 세그먼트마다 타이틀 요소 생성
        for (counter, segment) in result.segments.enumerated() {
            // 시작 시간 및 지속 시간 계산
            let startOffset = convertToTimecode(seconds: segment.start, frameRate: frameRate)
            let startTime = startOffset
            let duration = convertToTimecode(seconds: segment.end - segment.start, frameRate: frameRate)
            
            // 텍스트 내용 - 앞뒤 공백 제거는 ViewModel에서 이미 처리됨
            if segment.text.isEmpty {
                continue
            }
            
            // 고유한 텍스트 스타일 ID (세그먼트 번호 기반)
            let textStyleId = "ts\(counter + 1)"
          
            if let wordTimings = segment.words, !wordTimings.isEmpty {
                // 유효한 단어만 필터링 - ViewModel에서 이미 처리됨
                let validWords = wordTimings.filter { !$0.word.isEmpty }
                
                // 유효한 단어가 없으면 세그먼트 자체도 건너뜀
                if validWords.isEmpty {
                    continue
                }
                
                // 각 단어마다 고유한 textStyleId를 생성
                for (wordIndex, wordTiming) in validWords.enumerated() {
                    // 고유한 텍스트 스타일 ID (세그먼트 번호 + 단어 번호 기반)
                    let wordStyleId = "ts\(counter + 1)_\(wordIndex + 1)"
                    
                    // 단어별 시작 시간과 종료 시간 계산 (세그먼트 기준 시간으로 조정)
                    let wordStart = convertToTimecode(seconds: wordTiming.start, frameRate: frameRate)
                    let wordDuration = convertToTimecode(seconds: wordTiming.end - wordTiming.start, frameRate: frameRate)
                    
                    xmlContent += """
                    
                                        <title name="Title \(counter + 1)_\(wordIndex + 1)" offset="\(wordStart)" ref="r2" duration="\(wordDuration)" start="\(wordStart)">
                                            <param name="Position" key="9999/10199/10201/1/100/101" value="0 -418.279"/>
                                            <param name="Alignment" key="9999/10199/10201/2/354/1002961760/401" value="1 (Center)"/>
                                            <param name="Alignment" key="9999/10199/10201/2/373" value="0 (Left) 2 (Bottom)"/>
                                            <param name="Out Sequencing" key="9999/10199/10201/4/10233/201/202" value="0 (To)"/>
                                            <param name="Wrap Mode" key="9999/10199/10201/5/10203/21/25/5" value="1 (Repeat)"/>
                                            <param name="Color" key="9999/10199/10201/5/10203/30/32" value="0 0 0"/>
                                            <param name="Wrap Mode" key="9999/10199/10201/5/10203/30/34/5" value="1 (Repeat)"/>
                                            <param name="Width" key="9999/10199/10201/5/10203/30/36" value="3"/>
                                            <text>
                                                <text-style ref="\(wordStyleId)">\(wordTiming.word)</text-style>
                                            </text>
                                            <text-style-def id="\(wordStyleId)">
                                                <text-style font="Arial" fontSize="50" fontFace="Regular" fontColor="0.999996 1 1 1" shadowColor="0 0 0 0.75" shadowOffset="5 315" alignment="center"/>
                                            </text-style-def>
                                        </title>
                    """
                }
            } else {
                xmlContent += """
                
                                    <title name="Title \(counter + 1)" offset="\(startOffset)" ref="r2" duration="\(duration)" start="\(startTime)">
                                        <param name="Position" key="9999/10199/10201/1/100/101" value="0 -418.279"/>
                                        <param name="Alignment" key="9999/10199/10201/2/354/1002961760/401" value="1 (Center)"/>
                                        <param name="Alignment" key="9999/10199/10201/2/373" value="0 (Left) 2 (Bottom)"/>
                                        <param name="Out Sequencing" key="9999/10199/10201/4/10233/201/202" value="0 (To)"/>
                                        <param name="Wrap Mode" key="9999/10199/10201/5/10203/21/25/5" value="1 (Repeat)"/>
                                        <param name="Color" key="9999/10199/10201/5/10203/30/32" value="0 0 0"/>
                                        <param name="Wrap Mode" key="9999/10199/10201/5/10203/30/34/5" value="1 (Repeat)"/>
                                        <param name="Width" key="9999/10199/10201/5/10203/30/36" value="3"/>
                                        <text>
                                            <text-style ref="\(textStyleId)">\(segment.text)</text-style>
                                        </text>
                                        <text-style-def id="\(textStyleId)">
                                            <text-style font="Arial" fontSize="50" fontFace="Regular" fontColor="0.999996 1 1 1" shadowColor="0 0 0 0.75" shadowOffset="5 315" alignment="center"/>
                                        </text-style-def>
                                    </title>
                """
            }
        }

        xmlContent += """
                            </spine>
                        </sequence>
                    </project>
                </event>
            </library>
        </fcpxml>
        """
        
        let reportURL = URL(fileURLWithPath: outputDir).appendingPathComponent("\(file).fcpxml")
        do {
            try xmlContent.write(to: reportURL, atomically: true, encoding: .utf8)
            return .success(reportURL.absoluteString)
        } catch {
            return .failure(error)
        }
    }
    
    // 초를 FCPXML 타임코드 형식으로 변환
    private func convertToTimecode(seconds: Float, frameRate: Double) -> String {
        let totalFrames = Int(round(Double(seconds) * frameRate))
        
        // 정수로 나누어떨어지는 경우 간단한 형식 사용
        if totalFrames % Int(frameRate) == 0 {
            return "\(totalFrames / Int(frameRate))s"
        }
        
        // NTSC (29.97fps) 특수 처리
        if abs(frameRate - 29.97) < 0.01 {
            let frames = Int(Double(totalFrames) * 1001.0 / 30000.0)
            return "\(frames * 30000)/30000s"
        }
        
        // 일반적인 경우 분수 형태로 표현
        return "\(totalFrames)/\(Int(frameRate))s"
    }
}

// MARK: - WriteASS

open class WriteASS: ResultWriting {
    public let outputDir: String
    public let frameRate: Double

    public init(outputDir: String, frameRate: Double) {
        self.outputDir = outputDir
        self.frameRate = frameRate
    }

    public func write(result: TranscriptionResult, to file: String, options: [String: Any]? = nil) -> Result<String, Error> {
        // 프레임 레이트에 따른 Timer 조정 (기본 30fps 대비 비율 적용)
        let adjustedTimer = 100.0 * (frameRate / 30.0)

        var assContent = """
        [Script Info]
        Title: \(file)
        ScriptType: v4.00+
        Collisions: Normal
        PlayResX: 1920
        PlayResY: 1080
        Timer: \(String(format: "%.4f", adjustedTimer))
        
        [V4+ Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
        Style: Default,Arial,24,&H00FFFFFF,&H000000FF,&H00000000,&H64000000,0,0,0,0,100,100,0,0,1,2,0,2,10,10,10,1
        
        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        """
        
        for segment in result.segments {
            if segment.text.isEmpty {
                continue
            }
            
            let startTime = assTimecodeString(from: segment.start)
            let endTime = assTimecodeString(from: segment.end)

            if let wordTimings = segment.words, !wordTimings.isEmpty {
                // 유효한 단어만 필터링
                let validWords = wordTimings.filter { !$0.word.isEmpty }
                
                // 유효한 단어가 없으면 세그먼트 자체도 건너뜀
                if validWords.isEmpty {
                    continue
                }
                
                for wordTiming in validWords {
                    // ASS 포맷에 맞게 이스케이프 처리
                    let escapedWord = wordTiming.word
                        .replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "{", with: "\\{")
                        .replacingOccurrences(of: "}", with: "\\}")
                    
                    assContent += "\nDialogue: 0,\(startTime),\(endTime),Default,,0,0,0,,\(escapedWord)"
                }
            } else {
                // 이스케이프 처리 (ASS 포맷은 특수 문자를 이스케이프해야 함)
                let escapedText = segment.text
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "{", with: "\\{")
                    .replacingOccurrences(of: "}", with: "\\}")
                
                assContent += "\nDialogue: 0,\(startTime),\(endTime),Default,,0,0,0,,\(escapedText)"
            }
        }
        
        let reportURL = URL(fileURLWithPath: outputDir).appendingPathComponent("\(file).ass")
        do {
            try assContent.write(to: reportURL, atomically: true, encoding: String.Encoding.utf8)
            return .success(reportURL.absoluteString)
        } catch {
            return .failure(error)
        }
    }
}

// MARK: - WriteSCC

open class WriteSCC: ResultWriting {
    public let outputDir: String
    public let frameRate: Double

    public init(outputDir: String, frameRate: Double) {
        self.outputDir = outputDir
        self.frameRate = frameRate
    }

    public func write(result: TranscriptionResult, to file: String, options: [String: Any]? = nil) -> Result<String, Error> {
        var sccContent = "Scenarist_SCC V1.0\n\n"
        
        for segment in result.segments {
            if segment.text.isEmpty {
                continue
            }
            
            let startTC = timecodeString(from: segment.start, frameRate: frameRate)
            let endTC = timecodeString(from: segment.end, frameRate: frameRate)

            if let wordTimings = segment.words, !wordTimings.isEmpty {
                // 유효한 단어만 필터링
                let validWords = wordTimings.filter { !$0.word.isEmpty }
                
                // 유효한 단어가 없으면 세그먼트 자체도 건너뜀
                if validWords.isEmpty {
                    continue
                }
                
                for wordTiming in validWords {
                    // SCC 포맷에 맞게 특수문자 처리
                    let processedWord = wordTiming.word
                        .replacingOccurrences(of: "\n", with: " ")
                        .replacingOccurrences(of: "\"", with: "''")
                    
                    sccContent += "\(startTC) --> \(endTC)\n\(processedWord)\n\n"
                }
            } else {
                // SCC 포맷에 맞게 특수문자 처리
                let processedText = segment.text
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "\"", with: "''")
                
                sccContent += "\(startTC) --> \(endTC)\n\(processedText)\n\n"
            }
        }
        
        let reportURL = URL(fileURLWithPath: outputDir).appendingPathComponent("\(file).scc")
        do {
            try sccContent.write(to: reportURL, atomically: true, encoding: String.Encoding.utf8)
            return .success(reportURL.absoluteString)
        } catch {
            return .failure(error)
        }
    }
}

// MARK: - WriteXML

open class WriteXML: ResultWriting {
    public let outputDir: String

    public init(outputDir: String) {
        self.outputDir = outputDir
    }

    public func write(result: TranscriptionResult, to file: String, options: [String: Any]? = nil) -> Result<String, Error> {
        var xmlContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <subtitles>
        """
        
        for segment in result.segments {
            if segment.text.isEmpty {
                continue
            }
            
            let startTime = xmlTimeString(from: segment.start)
            let endTime = xmlTimeString(from: segment.end)
            
            if let wordTimings = segment.words, !wordTimings.isEmpty {
                // 유효한 단어만 필터링
                let validWords = wordTimings.filter { !$0.word.isEmpty }
                
                // 유효한 단어가 없으면 세그먼트 자체도 건너뜀
                if validWords.isEmpty {
                    continue
                }
                
                for wordTiming in validWords {
                    // XML 특수문자 이스케이프 처리
                    let escapedWord = wordTiming.word
                        .replacingOccurrences(of: "&", with: "&amp;")
                        .replacingOccurrences(of: "<", with: "&lt;")
                        .replacingOccurrences(of: ">", with: "&gt;")
                        .replacingOccurrences(of: "\"", with: "&quot;")
                        .replacingOccurrences(of: "'", with: "&apos;")
                    
                    xmlContent += "\n    <subtitle start=\"\(startTime)\" end=\"\(endTime)\">\(escapedWord)</subtitle>"
                }
            } else {
                // XML 특수문자 이스케이프 처리
                let escapedText = segment.text
                    .replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "<", with: "&lt;")
                    .replacingOccurrences(of: ">", with: "&gt;")
                    .replacingOccurrences(of: "\"", with: "&quot;")
                    .replacingOccurrences(of: "'", with: "&apos;")
                
                xmlContent += "\n    <subtitle start=\"\(startTime)\" end=\"\(endTime)\">\(escapedText)</subtitle>"
            }
        }
        
        xmlContent += "\n</subtitles>"
        
        let reportURL = URL(fileURLWithPath: outputDir).appendingPathComponent("\(file).xml")
        do {
            try xmlContent.write(to: reportURL, atomically: true, encoding: String.Encoding.utf8)
            return .success(reportURL.absoluteString)
        } catch {
            return .failure(error)
        }
    }
}
