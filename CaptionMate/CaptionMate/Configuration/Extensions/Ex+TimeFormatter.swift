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

// MARK: - TimeInterval Extensions

extension TimeInterval {
    /// 시간을 "00:00:00.00" 형식(시:분:초.밀리초)으로 변환합니다.
    func toHMSFormat() -> String {
        let totalSeconds = abs(self)
        let hours = Int(totalSeconds / 3600)
        let minutes = Int((totalSeconds.truncatingRemainder(dividingBy: 3600)) / 60)
        let seconds = Int(totalSeconds.truncatingRemainder(dividingBy: 60))
        let milliseconds = Int((totalSeconds.truncatingRemainder(dividingBy: 1)) * 100)

        return String(format: "%02d:%02d:%02d.%02d", hours, minutes, seconds, milliseconds)
    }

    /// 시간을 SRT 자막 형식("00:00:00,000")의 타임스탬프로 변환합니다.
    func toSRTTimestamp() -> String {
        let totalSeconds = abs(self)
        let hours = Int(totalSeconds / 3600)
        let minutes = Int((totalSeconds.truncatingRemainder(dividingBy: 3600)) / 60)
        let seconds = Int(totalSeconds.truncatingRemainder(dividingBy: 60))
        let milliseconds = Int((totalSeconds.truncatingRemainder(dividingBy: 1)) * 1000)

        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
    }

    /// 시간을 FCPXML 형식의 타임스탬프(분수형태, 예: "1001/30000s")로 변환합니다.
    func toFCPXMLTimestamp(frameRate: Double) -> String {
        let denominator: Int
        let numerator: Int

        switch frameRate {
        case 23.976, 23.98:
            denominator = 24000
            numerator = Int(self * Double(denominator))
        case 24:
            denominator = 24
            numerator = Int(self * Double(denominator))
        case 25:
            denominator = 25
            numerator = Int(self * Double(denominator))
        case 29.97:
            denominator = 30000
            numerator = Int(self * Double(denominator) * 1001 / 1000)
        case 30:
            denominator = 30
            numerator = Int(self * Double(denominator))
        case 50:
            denominator = 50
            numerator = Int(self * Double(denominator))
        case 59.94:
            denominator = 60000
            numerator = Int(self * Double(denominator) * 1001 / 1000)
        case 60:
            denominator = 60
            numerator = Int(self * Double(denominator))
        default:
            denominator = 10000
            numerator = Int(self * Double(denominator))
        }

        if self == Double(Int(self)) {
            return "\(Int(self))s"
        }

        return "\(numerator)/\(denominator)s"
    }

    /// 시작시간과 종료시간을 "[00:00:00.00 --> 00:00:00.00]" 형식으로 표현합니다.
    func formatTimeRange(to endTime: TimeInterval) -> String {
        return "[\(toHMSFormat()) --> \(endTime.toHMSFormat())]"
    }

    /// 시작시간과 종료시간을 "[00:00:00,000 --> 00:00:00,000]" 형식으로 표현합니다.
    func formatSRTTimeRange(to endTime: TimeInterval) -> String {
        return "[\(toSRTTimestamp()) --> \(endTime.toSRTTimestamp())]"
    }

    /// 시작시간과 종료시간을 FCPXML 형식으로 표현합니다.
    func formatFCPXMLTimeRange(to endTime: TimeInterval, frameRate: Double) -> String {
        return "[\(toFCPXMLTimestamp(frameRate: frameRate)) --> \(endTime.toFCPXMLTimestamp(frameRate: frameRate))]"
    }
}

// MARK: - String Extensions

extension String {
    /// "00:00:00.00" 형식의 문자열을 TimeInterval로 변환합니다.
    func hmsToSeconds() -> TimeInterval? {
        let components = self.components(separatedBy: CharacterSet(charactersIn: ":."))
        guard components.count == 4,
              let hours = Int(components[0]),
              let minutes = Int(components[1]),
              let seconds = Int(components[2]),
              let centiseconds = Int(components[3]) else {
            return nil
        }
        return TimeInterval(hours * 3600 + minutes * 60 + seconds) + TimeInterval(centiseconds) /
            100
    }

    /// SRT 형식("00:00:00,000")의 타임스탬프 문자열을 TimeInterval로 변환합니다.
    func srtTimestampToSeconds() -> TimeInterval? {
        let components = self.components(separatedBy: CharacterSet(charactersIn: ":,"))
        guard components.count == 4,
              let hours = Int(components[0]),
              let minutes = Int(components[1]),
              let seconds = Int(components[2]),
              let milliseconds = Int(components[3]) else {
            return nil
        }
        return TimeInterval(hours * 3600 + minutes * 60 + seconds) + TimeInterval(milliseconds) /
            1000
    }

    /// FCPXML 형식("1001/30000s")의 타임스탬프 문자열을 TimeInterval로 변환합니다.
    func fcpxmlTimestampToSeconds() -> TimeInterval? {
        var cleanString = self
        if cleanString.hasSuffix("s") {
            cleanString.removeLast()
        }
        if cleanString.contains("/") {
            let components = cleanString.components(separatedBy: "/")
            guard components.count == 2,
                  let numerator = Double(components[0]),
                  let denominator = Double(components[1]) else {
                return nil
            }
            return numerator / denominator
        } else {
            return Double(cleanString)
        }
    }
}
