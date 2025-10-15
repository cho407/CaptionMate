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
//  CaptionMateTests.swift
//  CaptionMateTests
//
//  Created by 조형구 on 2/22/25.
//

import Foundation
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import CaptionMate

// MARK: - ContentViewModel Tests

struct ContentViewModelTests {
    @Test("ContentViewModel 초기화 테스트") @MainActor
    func testContentViewModelInitialization() throws {
        let viewModel = ContentViewModel()

        // 기본 상태 확인
        #expect(viewModel.whisperKit == nil)
        #expect(viewModel.modelManagementState.modelState == .unloaded)
        #expect(viewModel.audioState.isTranscribing == false)

        // 기본 설정 확인
        #expect(viewModel.enablePromptPrefill == true)
        #expect(viewModel.enableCachePrefill == true)
        #expect(viewModel.temperatureStart >= 0.0)
        #expect(viewModel.temperatureStart <= 1.0)
    }

    @Test("언어 변경 기능 테스트") @MainActor
    func testLanguageChange() throws {
        let viewModel = ContentViewModel()

        // 영어로 변경
        viewModel.changeAppLanguage(to: "en")
        #expect(viewModel.appLanguage == "en")

        // 한국어로 변경
        viewModel.changeAppLanguage(to: "ko")
        #expect(viewModel.appLanguage == "ko")
    }

    @Test("테마 변경 기능 테스트") @MainActor
    func testThemeChange() throws {
        let viewModel = ContentViewModel()

        // 라이트 모드로 변경
        viewModel.appTheme = .light
        #expect(viewModel.appTheme == .light)
        #expect(viewModel.appTheme.colorScheme == .light)

        // 다크 모드로 변경
        viewModel.appTheme = .dark
        #expect(viewModel.appTheme == .dark)
        #expect(viewModel.appTheme.colorScheme == .dark)

        // 자동 모드로 변경 (시스템 테마를 따름)
        viewModel.appTheme = .auto
        #expect(viewModel.appTheme == .auto)
        // auto는 현재 시스템 테마를 반환하므로 .light 또는 .dark 중 하나
        #expect(viewModel.appTheme.colorScheme == .light || viewModel.appTheme.colorScheme == .dark)
    }

    @Test("언어 표시명 테스트") @MainActor
    func testGetCurrentLanguageDisplayName() throws {
        let viewModel = ContentViewModel()

        viewModel.changeAppLanguage(to: "en")
        #expect(viewModel.getCurrentLanguageDisplayName() == "English")

        viewModel.changeAppLanguage(to: "ko")
        #expect(viewModel.getCurrentLanguageDisplayName() == "한국어")
    }

    @Test("언어 변경 동작 테스트") @MainActor
    func testLanguageChangeBehavior() throws {
        let viewModel = ContentViewModel()

        // 언어 변경이 그대로 적용되는지 확인 (폴백 로직 없음)
        viewModel.changeAppLanguage(to: "ja")
        #expect(viewModel.appLanguage == "ja")

        // 다시 영어로 변경
        viewModel.changeAppLanguage(to: "en")
        #expect(viewModel.appLanguage == "en")
    }
}

// MARK: - Subtitle File Type Tests

struct SubtitleFileTypeTests {
    @Test("SubtitleFileType allCases 테스트")
    func testSubtitleFileTypeAllCases() throws {
        let allCases = SubtitleFileType.allCases
        #expect(allCases.count == 4)
        #expect(allCases.contains(.srt))
        #expect(allCases.contains(.fcpxml))
        #expect(allCases.contains(.vtt))
        #expect(allCases.contains(.json))
    }

    @Test("SubtitleFileType UTType 변환 테스트")
    func testSubtitleFileTypeUTType() throws {
        // SRT - UTType 생성하여 비교
        let expectedSRT = UTType(filenameExtension: "srt")
        #expect(SubtitleFileType.srt.utType == expectedSRT || SubtitleFileType.srt
            .utType == .plainText)

        // JSON - 시스템 정의 UTType과 비교
        #expect(SubtitleFileType.json.utType == .json)

        // VTT - UTType 생성하여 비교
        let expectedVTT = UTType(filenameExtension: "vtt")
        #expect(SubtitleFileType.vtt.utType == expectedVTT || SubtitleFileType.vtt
            .utType == .plainText)

        // FCPXML - 커스텀 UTType 확인
        let fcpxmlType = SubtitleFileType.fcpxml.utType
        #expect(fcpxmlType == .fcpxml)
    }
}

// MARK: - Time Formatter Tests

struct TimeFormatterTests {
    @Test("시간 범위 포맷팅 테스트")
    func testTimeRangeFormatting() throws {
        // 0초 ~ 1.5초
        let result1 = TimeInterval(0.0).formatTimeRange(to: 1.5)
        #expect(result1.contains("00:00:00"))
        #expect(result1.contains("00:00:01"))

        // 1분 ~ 1분 30초
        let result2 = TimeInterval(60.0).formatTimeRange(to: 90.0)
        #expect(result2.contains("00:01:00"))
        #expect(result2.contains("00:01:30"))

        // 1시간 ~ 1시간 5분
        let result3 = TimeInterval(3600.0).formatTimeRange(to: 3900.0)
        #expect(result3.contains("01:00:00"))
        #expect(result3.contains("01:05:00"))
    }

    @Test("HMS 포맷 변환 테스트")
    func testToHMSFormat() throws {
        // 1.5초
        let result1 = TimeInterval(1.5).toHMSFormat()
        #expect(result1 == "00:00:01.50")

        // 1분 30초
        let result2 = TimeInterval(90.0).toHMSFormat()
        #expect(result2 == "00:01:30.00")

        // 1시간 5분 3초
        let result3 = TimeInterval(3903.0).toHMSFormat()
        #expect(result3 == "01:05:03.00")
    }

    @Test("SRT 타임스탬프 변환 테스트")
    func testToSRTTimestamp() throws {
        // 1.5초
        let result1 = TimeInterval(1.5).toSRTTimestamp()
        #expect(result1 == "00:00:01,500")

        // 1분 30초 250ms
        let result2 = TimeInterval(90.25).toSRTTimestamp()
        #expect(result2 == "00:01:30,250")

        // 1시간 5분 3초 100ms (부동소수점 오차로 099가 나올 수 있음)
        let result3 = TimeInterval(3903.1).toSRTTimestamp()
        #expect(result3 == "01:05:03,099" || result3 == "01:05:03,100")
    }

    @Test("음수 시간 처리 테스트")
    func testNegativeTimeHandling() throws {
        // 음수 시간도 절대값으로 처리되어야 함
        let result = TimeInterval(-10.5).toHMSFormat()
        #expect(result == "00:00:10.50")
    }

    @Test("매우 큰 시간 값 테스트")
    func testLargeTimeValue() throws {
        // 10시간 이상
        let result = TimeInterval(36000.0).toHMSFormat() // 10시간
        #expect(result.hasPrefix("10:00:00"))
    }
}

// MARK: - State Models Tests

struct StateModelsTests {
    @Test("TranscriptionState 초기화 테스트")
    func testTranscriptionStateInitialization() throws {
        let state = TranscriptionState()

        #expect(state.currentText == "")
        #expect(state.currentChunks.isEmpty)
        #expect(state.tokensPerSecond == 0)
        #expect(state.confirmedSegments.isEmpty)
        #expect(state.effectiveRealTimeFactor == 0)
        #expect(state.effectiveSpeedFactor == 0)
    }

    @Test("ModelManagementState 초기화 테스트") @MainActor
    func testModelManagementStateInitialization() throws {
        let state = ModelManagementState()

        #expect(state.modelState == .unloaded)
        #expect(state.localModels.isEmpty)
        #expect(state.availableModels.isEmpty)
        #expect(state.isDownloading == false)
        #expect(state.downloadProgress.isEmpty)
        #expect(state.currentDownloadingModels.isEmpty)
    }

    @Test("AudioState 초기화 테스트")
    func testAudioStateInitialization() throws {
        let state = AudioState()

        #expect(state.isTranscribing == false)
        #expect(state.audioFileName == "Subtitle")
        #expect(state.waveformSamples.isEmpty)
        #expect(state.importedAudioURL == nil)
        #expect(state.isPlaying == false)
        #expect(state.totalDuration == 0.0)
    }

    @Test("UIState 초기화 테스트")
    func testUIStateInitialization() throws {
        let state = UIState()

        #expect(state.isFilePickerPresented == false)
        #expect(state.showComputeUnits == true)
        #expect(state.showAdvancedOptions == false)
        #expect(state.isTranscribingView == false)
        #expect(state.isModelmanagerViewPresented == false)
        #expect(state.isTargeted == false)
        #expect(state.isLanguageChanged == false)
    }
}

// MARK: - Theme Tests

struct ThemeTests {
    @Test("AppTheme 케이스 테스트")
    func testAppThemeCases() throws {
        #expect(AppTheme.light.colorScheme == .light)
        #expect(AppTheme.dark.colorScheme == .dark)
        // auto는 현재 시스템 테마를 반환하므로 .light 또는 .dark 중 하나
        let autoScheme = AppTheme.auto.colorScheme
        #expect(autoScheme == .light || autoScheme == .dark)
    }

    @Test("AppTheme 로컬라이제이션 키 테스트")
    func testAppThemeLocalizedNames() throws {
        #expect(AppTheme.light.localizedName == "theme.light")
        #expect(AppTheme.dark.localizedName == "theme.dark")
        #expect(AppTheme.auto.localizedName == "theme.auto")
    }

    @Test("AppTheme allCases 테스트")
    func testAppThemeAllCases() throws {
        let allCases = AppTheme.allCases
        #expect(allCases.count == 3)
        #expect(allCases.contains(.light))
        #expect(allCases.contains(.dark))
        #expect(allCases.contains(.auto))
    }
}

// MARK: - Color Extension Tests

struct ColorExtensionTests {
    @Test("다크모드 색상 생성 테스트")
    func testDarkModeColors() throws {
        // TranscriptionView 배경색
        let darkBg = Color.transcriptionBackground(for: .dark)
        let lightBg = Color.transcriptionBackground(for: .light)
        #expect(darkBg != lightBg)

        // AudioControlView 배경색
        let darkAudio = Color.audioControlBackground(for: .dark)
        let lightAudio = Color.audioControlBackground(for: .light)
        #expect(darkAudio != lightAudio)

        // ModelSelectorView 텍스트 색상
        let darkText = Color.modelSelectorText(for: .dark)
        let lightText = Color.modelSelectorText(for: .light)
        #expect(darkText != lightText)
    }
}

// MARK: - String Extension Tests

struct StringExtensionTests {
    @Test("HMS 문자열을 초로 변환 테스트")
    func testHMSToSeconds() throws {
        // 1분 30초 50
        let seconds1 = "00:01:30.50".hmsToSeconds()
        #expect(seconds1 == 90.5)

        // 1시간 5분 3초
        let seconds2 = "01:05:03.00".hmsToSeconds()
        #expect(seconds2 == 3903.0)
    }

    @Test("SRT 타임스탬프를 초로 변환 테스트")
    func testSRTTimestampToSeconds() throws {
        // 1.5초
        let seconds1 = "00:00:01,500".srtTimestampToSeconds()
        #expect(seconds1 == 1.5)

        // 1분 30초 250ms
        let seconds2 = "00:01:30,250".srtTimestampToSeconds()
        #expect(seconds2 == 90.25)
    }

    @Test("잘못된 형식의 타임스탬프 처리 테스트")
    func testInvalidTimestampHandling() throws {
        // 잘못된 형식
        let invalid1 = "invalid".hmsToSeconds()
        #expect(invalid1 == nil)

        let invalid2 = "99:99:99.99".hmsToSeconds()
        #expect(invalid2 != nil) // 파싱은 되지만 유효하지 않은 값

        let invalid3 = "".srtTimestampToSeconds()
        #expect(invalid3 == nil)
    }
}

