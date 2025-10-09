//
//  AdditionalResultWriter.swift
//  WhisperCaptionPro
//
//  Created by 조형구 on 4/1/25.
//

import Foundation

import WhisperKit
// TODO: - ASS, SCC, XML파일 형식에대한 로직 검증이 덜됨. 복잡성 증가하기때문에 지원보류

// MARK: - Helper Functions

/// 주어진 초를 프레임 레이트를 반영한 타임코드 (HH:MM:SS:FF) 문자열로 변환 (FCPXML, SCC 등에서 사용)
func timecodeString(from seconds: Float, frameRate: Double) -> String {
    let sec = Double(seconds)
    // 초 * frameRate를 계산하고 floor 함수를 이용해 내림 처리함.
    let totalFrames = Int(floor(sec * frameRate))
    let framesPerHour = Int(frameRate * 3600)
    let framesPerMinute = Int(frameRate * 60)

    let hours = totalFrames / framesPerHour
    let remainderAfterHours = totalFrames % framesPerHour
    let minutes = remainderAfterHours / framesPerMinute
    let remainderAfterMinutes = remainderAfterHours % framesPerMinute
    let secondsValue = remainderAfterMinutes / Int(frameRate)
    let frames = remainderAfterMinutes % Int(frameRate)

    return String(format: "%02d:%02d:%02d:%02d", hours, minutes, secondsValue, frames)
}

///// ASS 포맷용 타임코드 문자열 (H:MM:SS.cs)
// func assTimecodeString(from seconds: Float) -> String {
//    let sec = Double(seconds)
//    // 초를 센티초로 변환하고 내림 처리
//    let totalCs = Int(floor(sec * 100.0))
//    let hours = totalCs / 360000
//    let minutes = (totalCs % 360000) / 6000
//    let secondsValue = (totalCs % 6000) / 100
//    let centiseconds = totalCs % 100
//    return String(format: "%d:%02d:%02d.%02d", hours, minutes, secondsValue, centiseconds)
// }
//
///// XML용 타임스탬프 문자열 (HH:MM:SS.mmm)
// func xmlTimeString(from seconds: Float) -> String {
//    let sec = Double(seconds)
//    let hrs = Int(floor(sec / 3600))
//    let mins = Int(floor((sec.truncatingRemainder(dividingBy: 3600)) / 60))
//    let secs = sec.truncatingRemainder(dividingBy: 60)
//    // 소수점 3자리(밀리초)까지 표현. (오차를 줄이기 위해 floor 대신 truncatingRemainder 사용)
//    return String(format: "%02d:%02d:%06.3f", hrs, mins, secs)
// }

// MARK: - WriteFCPXML

open class WriteFCPXML: ResultWriting {
    public let outputDir: String
    public let frameRate: Double

    public init(outputDir: String, frameRate: Double) {
        self.outputDir = outputDir
        self.frameRate = frameRate
    }

    /// 초를 FCPXML 타임코드 형식으로 변환
    private func convertToFCPXMLTime(seconds: Float) -> String {
        let secondsDouble = Double(seconds)
        if secondsDouble == Double(Int(secondsDouble)) {
            return "\(Int(secondsDouble))s"
        }
        if abs(frameRate - 29.97) < 0.01 {
            let multiplier = 30000
            let denominator = 1001
            let frames = Int(floor(secondsDouble * Double(multiplier) / Double(denominator)))
            if frames % denominator == 0 {
                return "\(frames / denominator)s"
            }
            return "\(frames)/\(denominator)s"
        }
        let denominator = Int(frameRate)
        let frames = Int(floor(secondsDouble * Double(denominator)))
        if frames % denominator == 0 {
            return "\(frames / denominator)s"
        }
        return "\(frames)/\(denominator)s"
    }

    public func write(result: TranscriptionResult, to file: String,
                      options: [String: Any]? = nil) -> Result<String, Error> {
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

        // 비디오 포맷 이름 결정
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

        // 유효한 세그먼트만 필터링 (앞뒤 공백 제거) 및 시작 시간 기준으로 정렬
        let validSegments = result.segments
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let sortedSegments = validSegments.sorted { $0.start < $1.start }

        // XML 템플릿의 타임라인 전체 길이 계산 (마지막 세그먼트 끝에 여유 추가)
        let lastSegmentEnd = sortedSegments.last?.end ?? 60.0
        let timelineDuration = convertToFCPXMLTime(seconds: lastSegmentEnd + 5.0)

        // 프로젝트 시작 시간은 0초로 고정
        let tcStartString = "0s"

        // FCPXML 템플릿 구성 시작
        var xmlContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE fcpxml>
        <fcpxml version="1.9">
            <resources>
                <format id="r1" name="\(formatName)" frameDuration="\(
                    frameDurationString
                )" width="1920" height="1080"/>
                <effect id="r2" name="Custom" uid=".../Titles.localized/Build In:Out.localized/Custom.localized/Custom.moti"/>
            </resources>
            <library>
                <event name="WhisperCaptionPro">
                    <project name="\(file)">
                        <sequence format="r1" duration="\(timelineDuration)" tcStart="\(
                            tcStartString
                        )" tcFormat="NDF">
                            <spine>
        """

        var counter = 1

        // 만약 첫 번째 세그먼트의 시작이 0초가 아니라면, gap clip을 삽입 (빈 텍스트 대신 <gap> 요소 사용)
        if let firstSegment = sortedSegments.first, firstSegment.start > 0 {
            let gapDuration = firstSegment.start - 0
            let gapDurationStr = convertToFCPXMLTime(seconds: gapDuration)
            let gapOffset = "0s" // 시작은 0초
            xmlContent += """

                                <gap offset="\(gapOffset)" duration="\(gapDurationStr)" start="\(
                                    gapOffset
                                )"/>
            """
        }

        // 각 세그먼트를 순회하며 타이틀 또는 단어 단위 타이틀 생성
        for segment in sortedSegments {
            let segmentDuration = segment.end - segment.start
            if segmentDuration < 0.1 {
                continue
            }

            let startOffset = convertToFCPXMLTime(seconds: segment.start)
            let duration = convertToFCPXMLTime(seconds: segmentDuration)

            // 단어 단위 분기
            if let wordTimings = segment.words,
               !wordTimings.isEmpty {
                let validWords = wordTimings
                    .filter { !$0.word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                if validWords.isEmpty { continue }
                let sortedWords = validWords.sorted { $0.start < $1.start }
                for (index, wordTiming) in sortedWords.enumerated() {
                    let wordDuration = wordTiming.end - wordTiming.start
                    if wordDuration < 0.01 { continue }

                    let wordStart = index == 0 ? segment.start : wordTiming.start

                    let wordStartOffset = convertToFCPXMLTime(seconds: wordStart)
                    let wordDurationStr = convertToFCPXMLTime(seconds: wordTiming.end - wordTiming
                        .start)
                    let wordTextStyleId = "ts\(counter)"

                    xmlContent += """

                                    <title name="Title\(counter)" offset="\(
                                        wordStartOffset
                                    )" ref="r2" duration="\(wordDurationStr)" start="\(wordStartOffset)">
                                        <param name="Position" key="9999/10199/10201/1/100/101" value="0 -418.279"/>
                                        <param name="Alignment" key="9999/10199/10201/2/354/1002961760/401" value="1 (Center)"/>
                                        <param name="Alignment" key="9999/10199/10201/2/373" value="0 (Left) 2 (Bottom)"/>
                                        <param name="Out Sequencing" key="9999/10199/10201/4/10233/201/202" value="0 (To)"/>
                                        <param name="Wrap Mode" key="9999/10199/10201/5/10203/21/25/5" value="1 (Repeat)"/>
                                        <param name="Color" key="9999/10199/10201/5/10203/30/32" value="0 0 0"/>
                                        <param name="Wrap Mode" key="9999/10199/10201/5/10203/30/34/5" value="1 (Repeat)"/>
                                        <param name="Width" key="9999/10199/10201/5/10203/30/36" value="3"/>
                                        <text>
                                            <text-style ref="\(wordTextStyleId)">\(wordTiming
                        .word)</text-style>
                                        </text>
                                        <text-style-def id="\(wordTextStyleId)">
                                            <text-style font="Arial" fontSize="50" fontFace="Regular" fontColor="0.999996 1 1 1" shadowColor="0 0 0 0.75" shadowOffset="5 315" alignment="center"/>
                                        </text-style-def>
                                    </title>
                    """
                    counter += 1
                }
            } else {
                let textStyleId = "ts\(counter)"
                xmlContent += """

                                <title name="Title\(counter)" offset="\(
                                    startOffset
                                )" ref="r2" duration="\(duration)" start="\(startOffset)">
                                    <param name="Position" key="9999/10199/10201/1/100/101" value="0 -418.279"/>
                                    <param name="Alignment" key="9999/10199/10201/2/354/1002961760/401" value="1 (Center)"/>
                                    <param name="Alignment" key="9999/10199/10201/2/373" value="0 (Left) 2 (Bottom)"/>
                                    <param name="Out Sequencing" key="9999/10199/10201/4/10233/201/202" value="0 (To)"/>
                                    <param name="Wrap Mode" key="9999/10199/10201/5/10203/21/25/5" value="1 (Repeat)"/>
                                    <param name="Color" key="9999/10199/10201/5/10203/30/32" value="0 0 0"/>
                                    <param name="Wrap Mode" key="9999/10199/10201/5/10203/30/34/5" value="1 (Repeat)"/>
                                    <param name="Width" key="9999/10199/10201/5/10203/30/36" value="3"/>
                                    <text>
                                        <text-style ref="\(textStyleId)">\(segment
                    .text)</text-style>
                                    </text>
                                    <text-style-def id="\(textStyleId)">
                                        <text-style font="Arial" fontSize="50" fontFace="Regular" fontColor="0.999996 1 1 1" shadowColor="0 0 0 0.75" shadowOffset="5 315" alignment="center"/>
                                    </text-style-def>
                                </title>
                """
                counter += 1
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
}

//// MARK: - WriteASS
//
// open class WriteASS: ResultWriting {
//    public let outputDir: String
//    public let frameRate: Double
//
//    public init(outputDir: String, frameRate: Double) {
//        self.outputDir = outputDir
//        self.frameRate = frameRate
//    }
//
//    public func write(result: TranscriptionResult, to file: String, options: [String: Any]? = nil)
//    -> Result<String, Error> {
//        // 프레임 레이트에 따른 Timer 조정 (기본 30fps 대비 비율 적용)
//        let adjustedTimer = 100.0 * (frameRate / 30.0)
//
//        var assContent = """
//        [Script Info]
//        Title: \(file)
//        ScriptType: v4.00+
//        Collisions: Normal
//        PlayResX: 1920
//        PlayResY: 1080
//        Timer: \(String(format: "%.4f", adjustedTimer))
//
//        [V4+ Styles]
//        Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
//        Style: Default,Arial,24,&H00FFFFFF,&H000000FF,&H00000000,&H64000000,0,0,0,0,100,100,0,0,1,2,0,2,10,10,10,1
//
//        [Events]
//        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
//        """
//
//        // 내용 있는 세그먼트만 필터링하고 시작 시간 기준으로 정렬
//        let validSegments = result.segments.filter { !$0.text.isEmpty }
//        let sortedSegments = validSegments.sorted(by: { $0.start < $1.start })
//
//        for segment in sortedSegments {
//            // 너무 짧은 세그먼트는 건너뜀 (0.1초 미만)
//            let segmentDuration = segment.end - segment.start
//            if segmentDuration < 0.1 {
//                continue
//            }
//
//            let startTime = assTimecodeString(from: segment.start)
//            let endTime = assTimecodeString(from: segment.end)
//
//            if let wordTimings = segment.words, !wordTimings.isEmpty {
//                // 유효한 단어만 필터링하고 시작 시간순으로 정렬
//                let validWords = wordTimings.filter { !$0.word.isEmpty }
//
//                if validWords.isEmpty {
//                    continue
//                }
//
//                // 단어 시작 시간 기준으로 정렬
//                let sortedWords = validWords.sorted { $0.start < $1.start }
//
//                for (index, wordTiming) in sortedWords.enumerated() {
//                    // 너무 짧은 단어는 건너뜀 (0.01초 미만)
//                    let duration = wordTiming.end - wordTiming.start
//                    if duration < 0.01 {
//                        continue
//                    }
//
//                    // ASS 포맷에 맞게 이스케이프 처리
//                    let escapedWord = wordTiming.word
//                        .replacingOccurrences(of: "\\", with: "\\\\")
//                        .replacingOccurrences(of: "{", with: "\\{")
//                        .replacingOccurrences(of: "}", with: "\\}")
//
//                    // 첫 단어는 세그먼트 시작 시간 사용, 나머지는 원래 시간 사용
//                    let wordStart = index == 0 ? segment.start : wordTiming.start
//                    let wordEnd = index == 0 ? segment.start + duration : wordTiming.end
//
//                    let wordStartTime = assTimecodeString(from: wordStart)
//                    let wordEndTime = assTimecodeString(from: wordEnd)
//
//                    assContent += "\nDialogue:
//                    0,\(wordStartTime),\(wordEndTime),Default,,0,0,0,,\(escapedWord)"
//                }
//            } else {
//                // 이스케이프 처리 (ASS 포맷은 특수 문자를 이스케이프해야 함)
//                let escapedText = segment.text
//                    .replacingOccurrences(of: "\\", with: "\\\\")
//                    .replacingOccurrences(of: "{", with: "\\{")
//                    .replacingOccurrences(of: "}", with: "\\}")
//
//                assContent += "\nDialogue:
//                0,\(startTime),\(endTime),Default,,0,0,0,,\(escapedText)"
//            }
//        }
//
//        let reportURL = URL(fileURLWithPath: outputDir).appendingPathComponent("\(file).ass")
//        do {
//            try assContent.write(to: reportURL, atomically: true, encoding: String.Encoding.utf8)
//            return .success(reportURL.absoluteString)
//        } catch {
//            return .failure(error)
//        }
//    }
// }
//
//// MARK: - WriteSCC
//
// open class WriteSCC: ResultWriting {
//    public let outputDir: String
//    public let frameRate: Double
//
//    public init(outputDir: String, frameRate: Double) {
//        self.outputDir = outputDir
//        self.frameRate = frameRate
//    }
//
//    public func write(result: TranscriptionResult, to file: String, options: [String: Any]? = nil)
//    -> Result<String, Error> {
//        var sccContent = "Scenarist_SCC V1.0\n\n"
//
//        // 내용 있는 세그먼트만 필터링하고 시작 시간 기준으로 정렬
//        let validSegments = result.segments.filter { !$0.text.isEmpty }
//        let sortedSegments = validSegments.sorted(by: { $0.start < $1.start })
//
//        for segment in sortedSegments {
//            // 너무 짧은 세그먼트는 건너뜀 (0.1초 미만)
//            let segmentDuration = segment.end - segment.start
//            if segmentDuration < 0.1 {
//                continue
//            }
//
//            let startTC = timecodeString(from: segment.start, frameRate: frameRate)
//            let endTC = timecodeString(from: segment.end, frameRate: frameRate)
//
//            if let wordTimings = segment.words, !wordTimings.isEmpty {
//                // 유효한 단어만 필터링하고 시작 시간순으로 정렬
//                let validWords = wordTimings.filter { !$0.word.isEmpty }
//
//                if validWords.isEmpty {
//                    continue
//                }
//
//                // 단어 시작 시간 기준으로 정렬
//                let sortedWords = validWords.sorted { $0.start < $1.start }
//
//                for (index, wordTiming) in sortedWords.enumerated() {
//                    // 너무 짧은 단어는 건너뜀 (0.01초 미만)
//                    let duration = wordTiming.end - wordTiming.start
//                    if duration < 0.01 {
//                        continue
//                    }
//
//                    // SCC 포맷에 맞게 특수문자 처리
//                    let processedWord = wordTiming.word
//                        .replacingOccurrences(of: "\n", with: " ")
//                        .replacingOccurrences(of: "\"", with: "''")
//
//                    // 첫 단어는 세그먼트 시작 시간 사용, 나머지는 원래 시간 사용
//                    let wordStart = index == 0 ? segment.start : wordTiming.start
//                    let wordEnd = index == 0 ? segment.start + duration : wordTiming.end
//
//                    let wordStartTC = timecodeString(from: wordStart, frameRate: frameRate)
//                    let wordEndTC = timecodeString(from: wordEnd, frameRate: frameRate)
//
//                    sccContent += "\(wordStartTC) --> \(wordEndTC)\n\(processedWord)\n\n"
//                }
//            } else {
//                // SCC 포맷에 맞게 특수문자 처리
//                let processedText = segment.text
//                    .replacingOccurrences(of: "\n", with: " ")
//                    .replacingOccurrences(of: "\"", with: "''")
//
//                sccContent += "\(startTC) --> \(endTC)\n\(processedText)\n\n"
//            }
//        }
//
//        let reportURL = URL(fileURLWithPath: outputDir).appendingPathComponent("\(file).scc")
//        do {
//            try sccContent.write(to: reportURL, atomically: true, encoding: String.Encoding.utf8)
//            return .success(reportURL.absoluteString)
//        } catch {
//            return .failure(error)
//        }
//    }
// }
//
//// MARK: - WriteXML
//
// open class WriteXML: ResultWriting {
//    public let outputDir: String
//
//    public init(outputDir: String) {
//        self.outputDir = outputDir
//    }
//
//    public func write(result: TranscriptionResult, to file: String, options: [String: Any]? = nil)
//    -> Result<String, Error> {
//        var xmlContent = """
//        <?xml version="1.0" encoding="UTF-8"?>
//        <subtitles>
//        """
//
//        // 내용 있는 세그먼트만 필터링하고 시작 시간 기준으로 정렬
//        let validSegments = result.segments.filter { !$0.text.isEmpty }
//        let sortedSegments = validSegments.sorted(by: { $0.start < $1.start })
//
//        for segment in sortedSegments {
//            // 너무 짧은 세그먼트는 건너뜀 (0.1초 미만)
//            let segmentDuration = segment.end - segment.start
//            if segmentDuration < 0.1 {
//                continue
//            }
//
//            let startTime = xmlTimeString(from: segment.start)
//            let endTime = xmlTimeString(from: segment.end)
//
//            if let wordTimings = segment.words, !wordTimings.isEmpty {
//                // 유효한 단어만 필터링하고 시작 시간순으로 정렬
//                let validWords = wordTimings.filter { !$0.word.isEmpty }
//
//                if validWords.isEmpty {
//                    continue
//                }
//
//                // 단어 시작 시간 기준으로 정렬
//                let sortedWords = validWords.sorted { $0.start < $1.start }
//
//                for (index, wordTiming) in sortedWords.enumerated() {
//                    // 너무 짧은 단어는 건너뜀 (0.01초 미만)
//                    let duration = wordTiming.end - wordTiming.start
//                    if duration < 0.01 {
//                        continue
//                    }
//
//                    // XML 특수문자 이스케이프 처리
//                    let escapedWord = wordTiming.word
//                        .replacingOccurrences(of: "&", with: "&amp;")
//                        .replacingOccurrences(of: "<", with: "&lt;")
//                        .replacingOccurrences(of: ">", with: "&gt;")
//                        .replacingOccurrences(of: "\"", with: "&quot;")
//                        .replacingOccurrences(of: "'", with: "&apos;")
//
//                    // 첫 단어는 세그먼트 시작 시간 사용, 나머지는 원래 시간 사용
//                    let wordStart = index == 0 ? segment.start : wordTiming.start
//                    let wordEnd = index == 0 ? segment.start + duration : wordTiming.end
//
//                    let wordStartTime = xmlTimeString(from: wordStart)
//                    let wordEndTime = xmlTimeString(from: wordEnd)
//
//                    xmlContent += "\n    <subtitle start=\"\(wordStartTime)\"
//                    end=\"\(wordEndTime)\">\(escapedWord)</subtitle>"
//                }
//            } else {
//                // XML 특수문자 이스케이프 처리
//                let escapedText = segment.text
//                    .replacingOccurrences(of: "&", with: "&amp;")
//                    .replacingOccurrences(of: "<", with: "&lt;")
//                    .replacingOccurrences(of: ">", with: "&gt;")
//                    .replacingOccurrences(of: "\"", with: "&quot;")
//                    .replacingOccurrences(of: "'", with: "&apos;")
//
//                xmlContent += "\n    <subtitle start=\"\(startTime)\"
//                end=\"\(endTime)\">\(escapedText)</subtitle>"
//            }
//        }
//
//        xmlContent += "\n</subtitles>"
//
//        let reportURL = URL(fileURLWithPath: outputDir).appendingPathComponent("\(file).xml")
//        do {
//            try xmlContent.write(to: reportURL, atomically: true, encoding: String.Encoding.utf8)
//            return .success(reportURL.absoluteString)
//        } catch {
//            return .failure(error)
//        }
//    }
// }
