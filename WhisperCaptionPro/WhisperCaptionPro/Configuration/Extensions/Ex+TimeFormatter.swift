import Foundation

extension TimeInterval {
    /// 시간을 "00:00:00.00" 형식(시:분:초.밀리초)으로 변환합니다
    func toHMSFormat() -> String {
        let totalSeconds = abs(self)
        let hours = Int(totalSeconds / 3600)
        let minutes = Int((totalSeconds.truncatingRemainder(dividingBy: 3600)) / 60)
        let seconds = Int(totalSeconds.truncatingRemainder(dividingBy: 60))
        let milliseconds = Int((totalSeconds.truncatingRemainder(dividingBy: 1)) * 100)
        
        return String(format: "%02d:%02d:%02d.%02d", hours, minutes, seconds, milliseconds)
    }
    
    /// 시간을 SRT 자막 형식의 타임스탬프(00:00:00,000)로 변환합니다
    func toSRTTimestamp() -> String {
        let totalSeconds = abs(self)
        let hours = Int(totalSeconds / 3600)
        let minutes = Int((totalSeconds.truncatingRemainder(dividingBy: 3600)) / 60)
        let seconds = Int(totalSeconds.truncatingRemainder(dividingBy: 60))
        let milliseconds = Int((totalSeconds.truncatingRemainder(dividingBy: 1)) * 1000)
        
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
    }
    
    /// 시간을 FCPXML 형식의 타임스탬프(rational number)로 변환합니다
    /// - Parameter frameRate: 비디오의 프레임 레이트 (예: 24, 25, 29.97, 30, 60 등)
    /// - Returns: FCPXML 형식의 타임스탬프 문자열 (예: "1001/30000s")
    func toFCPXMLTimestamp(frameRate: Double) -> String {
        let denominator: Int
        let numerator: Int
        
        // 일반적인 프레임 레이트에 따른 분모 설정
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
            // 기본값 - 분모를 10000으로 설정하여 높은 정밀도 유지
            denominator = 10000
            numerator = Int(self * Double(denominator))
        }
        
        // 정수 시간인 경우 단순화
        if self == Double(Int(self)) {
            return "\(Int(self))s"
        }
        
        return "\(numerator)/\(denominator)s"
    }
}

// 시작시간과 종료시간을 포함하는 범위에 대한 확장
extension TimeInterval {
    /// 시작시간과 종료시간을 hh:mm:ss.ms 형식으로 표현합니다
    /// - Parameter endTime: 종료 시간
    /// - Returns: "[00:00:00.00 --> 00:00:00.00]" 형식의 문자열
    func formatTimeRange(to endTime: TimeInterval) -> String {
        return "[\(self.toHMSFormat()) --> \(endTime.toHMSFormat())]"
    }
    
    /// 시작시간과 종료시간을 SRT 형식으로 표현합니다
    /// - Parameter endTime: 종료 시간
    /// - Returns: "[00:00:00,000 --> 00:00:00,000]" 형식의 문자열
    func formatSRTTimeRange(to endTime: TimeInterval) -> String {
        return "[\(self.toSRTTimestamp()) --> \(endTime.toSRTTimestamp())]"
    }
    
    /// 시작시간과 종료시간을 FCPXML 형식으로 표현합니다
    /// - Parameters:
    ///   - endTime: 종료 시간
    ///   - frameRate: 비디오 프레임 레이트
    /// - Returns: "[숫자/숫자s --> 숫자/숫자s]" 형식의 문자열
    func formatFCPXMLTimeRange(to endTime: TimeInterval, frameRate: Double) -> String {
        return "[\(self.toFCPXMLTimestamp(frameRate: frameRate)) --> \(endTime.toFCPXMLTimestamp(frameRate: frameRate))]"
    }
}

// 문자열 파싱을 위한 확장
extension String {
    /// "00:00:00.00" 형식의 문자열을 TimeInterval로 변환합니다
    func hmsToSeconds() -> TimeInterval? {
        let components = self.components(separatedBy: CharacterSet(charactersIn: ":."))
        guard components.count == 4,
              let hours = Int(components[0]),
              let minutes = Int(components[1]),
              let seconds = Int(components[2]),
              let centiseconds = Int(components[3]) else {
            return nil
        }
        
        let totalSeconds = TimeInterval(hours * 3600 + minutes * 60 + seconds) + TimeInterval(centiseconds) / 100
        return totalSeconds
    }
    
    /// SRT 형식의 타임스탬프 문자열("00:00:00,000")을 TimeInterval로 변환합니다
    func srtTimestampToSeconds() -> TimeInterval? {
        let components = self.components(separatedBy: CharacterSet(charactersIn: ":,"))
        guard components.count == 4,
              let hours = Int(components[0]),
              let minutes = Int(components[1]),
              let seconds = Int(components[2]),
              let milliseconds = Int(components[3]) else {
            return nil
        }
        
        let totalSeconds = TimeInterval(hours * 3600 + minutes * 60 + seconds) + TimeInterval(milliseconds) / 1000
        return totalSeconds
    }
    
    /// FCPXML 형식의 타임스탬프 문자열(예: "1001/30000s")을 TimeInterval로 변환합니다
    func fcpxmlTimestampToSeconds() -> TimeInterval? {
        // 끝의 's' 제거
        var cleanString = self
        if cleanString.hasSuffix("s") {
            cleanString.removeLast()
        }
        
        // 분수 형태인지 확인
        if cleanString.contains("/") {
            let components = cleanString.components(separatedBy: "/")
            guard components.count == 2,
                  let numerator = Double(components[0]),
                  let denominator = Double(components[1]) else {
                return nil
            }
            
            return numerator / denominator
        } else {
            // 단순 숫자 형태
            return Double(cleanString)
        }
    }
} 