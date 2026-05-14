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

@testable import CaptionMate
import AVFoundation
import Foundation
import SwiftUI
import Testing
import UniformTypeIdentifiers
import WhisperKit
import XCTest

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
        viewModel.changeAppLanguage(to: "en-US")
        #expect(viewModel.appLanguage == "en-US")

        viewModel.changeAppLanguage(to: "en-GB")
        #expect(viewModel.appLanguage == "en-GB")

        // 한국어로 변경
        viewModel.changeAppLanguage(to: "ko")
        #expect(viewModel.appLanguage == "ko")

        viewModel.changeAppLanguage(to: "ja")
        #expect(viewModel.appLanguage == "ja")

        viewModel.changeAppLanguage(to: "es")
        #expect(viewModel.appLanguage == "es")

        viewModel.changeAppLanguage(to: "de")
        #expect(viewModel.appLanguage == "de")

        viewModel.changeAppLanguage(to: "fr")
        #expect(viewModel.appLanguage == "fr")

        viewModel.changeAppLanguage(to: "pt-BR")
        #expect(viewModel.appLanguage == "pt-BR")

        viewModel.changeAppLanguage(to: "hi")
        #expect(viewModel.appLanguage == "hi")

        viewModel.changeAppLanguage(to: "zh-Hans")
        #expect(viewModel.appLanguage == "zh-Hans")
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

        viewModel.changeAppLanguage(to: "en-US")
        #expect(viewModel.getCurrentLanguageDisplayName() == "English (US)")

        viewModel.changeAppLanguage(to: "en-GB")
        #expect(viewModel.getCurrentLanguageDisplayName() == "English (UK)")

        viewModel.changeAppLanguage(to: "ko")
        #expect(viewModel.getCurrentLanguageDisplayName() == "한국어")

        viewModel.changeAppLanguage(to: "ja")
        #expect(viewModel.getCurrentLanguageDisplayName() == "日本語")

        viewModel.changeAppLanguage(to: "es")
        #expect(viewModel.getCurrentLanguageDisplayName() == "Español")

        viewModel.changeAppLanguage(to: "de")
        #expect(viewModel.getCurrentLanguageDisplayName() == "Deutsch")

        viewModel.changeAppLanguage(to: "fr")
        #expect(viewModel.getCurrentLanguageDisplayName() == "Français")

        viewModel.changeAppLanguage(to: "pt-BR")
        #expect(viewModel.getCurrentLanguageDisplayName() == "Português (Brasil)")

        viewModel.changeAppLanguage(to: "hi")
        #expect(viewModel.getCurrentLanguageDisplayName() == "हिन्दी")

        viewModel.changeAppLanguage(to: "zh-Hans")
        #expect(viewModel.getCurrentLanguageDisplayName() == "简体中文")
    }

    @Test("언어 변경 동작 테스트") @MainActor
    func testLanguageChangeBehavior() throws {
        let viewModel = ContentViewModel()

        // 언어 변경이 그대로 적용되는지 확인 (폴백 로직 없음)
        viewModel.changeAppLanguage(to: "ja")
        #expect(viewModel.appLanguage == "ja")
        #expect(viewModel.supportedAppLanguages.map(\.code) == [
            "en-US",
            "en-GB",
            "ko",
            "ja",
            "es",
            "de",
            "fr",
            "pt-BR",
            "hi",
            "zh-Hans",
        ])

        // 다시 영어로 변경
        viewModel.changeAppLanguage(to: "en")
        #expect(viewModel.appLanguage == "en-US")
    }

    @Test("언어 변경은 앱 언어만 저장하고 AppleLanguages 오버라이드는 남기지 않는다") @MainActor
    func testLanguageChangeClearsLegacyAppleLanguagesOverride() throws {
        let suiteName = "CaptionMate.LanguageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))

        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(["zh-Hans"], forKey: "AppleLanguages")
        AppLanguageResolver.clearLegacyAppleLanguagesOverride(in: defaults)

        #expect(defaults.persistentDomain(forName: suiteName)?["AppleLanguages"] == nil)
    }

    @Test("첫 실행 앱 언어는 맥 기본 언어를 따르고 미지원 언어는 영어로 폴백한다")
    func testPreferredAppLanguageUsesSystemPrimaryThenEnglishFallback() throws {
        let supportedLanguages = [
            AppLanguageOption(code: "en-US", displayName: "English (US)"),
            AppLanguageOption(code: "en-GB", displayName: "English (UK)"),
            AppLanguageOption(code: "ko", displayName: "한국어"),
            AppLanguageOption(code: "ja", displayName: "日本語"),
            AppLanguageOption(code: "es", displayName: "Español"),
            AppLanguageOption(code: "de", displayName: "Deutsch"),
            AppLanguageOption(code: "fr", displayName: "Français"),
            AppLanguageOption(code: "pt-BR", displayName: "Português (Brasil)"),
            AppLanguageOption(code: "hi", displayName: "हिन्दी"),
            AppLanguageOption(code: "zh-Hans", displayName: "简体中文"),
        ]

        #expect(
            AppLanguageResolver.preferredAppLanguage(
                from: ["en-US"],
                supportedLanguages: supportedLanguages
            ) == "en-US"
        )
        #expect(
            AppLanguageResolver.preferredAppLanguage(
                from: ["en-GB"],
                supportedLanguages: supportedLanguages
            ) == "en-GB"
        )
        #expect(
            AppLanguageResolver.preferredAppLanguage(
                from: ["en-IN"],
                supportedLanguages: supportedLanguages
            ) == "en-US"
        )
        #expect(
            AppLanguageResolver.preferredAppLanguage(
                from: ["ko-KR", "en-US"],
                supportedLanguages: supportedLanguages
            ) == "ko"
        )
        #expect(
            AppLanguageResolver.preferredAppLanguage(
                from: ["ja-JP"],
                supportedLanguages: supportedLanguages
            ) == "ja"
        )
        #expect(
            AppLanguageResolver.preferredAppLanguage(
                from: ["es-MX"],
                supportedLanguages: supportedLanguages
            ) == "es"
        )
        #expect(
            AppLanguageResolver.preferredAppLanguage(
                from: ["de-DE"],
                supportedLanguages: supportedLanguages
            ) == "de"
        )
        #expect(
            AppLanguageResolver.preferredAppLanguage(
                from: ["fr-FR"],
                supportedLanguages: supportedLanguages
            ) == "fr"
        )
        #expect(
            AppLanguageResolver.preferredAppLanguage(
                from: ["pt-BR"],
                supportedLanguages: supportedLanguages
            ) == "pt-BR"
        )
        #expect(
            AppLanguageResolver.preferredAppLanguage(
                from: ["pt-PT"],
                supportedLanguages: supportedLanguages
            ) == "pt-BR"
        )
        #expect(
            AppLanguageResolver.preferredAppLanguage(
                from: ["hi-IN"],
                supportedLanguages: supportedLanguages
            ) == "hi"
        )
        #expect(
            AppLanguageResolver.preferredAppLanguage(
                from: ["zh-Hans-CN"],
                supportedLanguages: supportedLanguages
            ) == "zh-Hans"
        )
        #expect(
            AppLanguageResolver.preferredAppLanguage(
                from: ["zh-CN"],
                supportedLanguages: supportedLanguages
            ) == "zh-Hans"
        )
        #expect(
            AppLanguageResolver.preferredAppLanguage(
                from: ["it-IT", "ko-KR"],
                supportedLanguages: supportedLanguages
            ) == "en-US"
        )
        #expect(
            AppLanguageResolver.preferredAppLanguage(
                from: [],
                supportedLanguages: supportedLanguages
            ) == "en-US"
        )
    }

    @Test("전사 세그먼트 편집 결과 동기화 테스트") @MainActor
    func testUpdateTranscriptionSegmentTextSyncsEditableResult() throws {
        let viewModel = ContentViewModel()
        let segment = TranscriptionSegment(start: 0, end: 1, text: "original")
        let result = TranscriptionResult(
            text: "original",
            segments: [segment],
            language: "ko",
            timings: TranscriptionTimings()
        )

        viewModel.transcriptionResult = result
        viewModel.transcriptionState.confirmedSegments = [segment]

        viewModel.updateTranscriptionSegmentText(at: 0, text: "edited")

        #expect(viewModel.transcriptionState.confirmedSegments[0].text == "edited")
        #expect(viewModel.transcriptionResult?.segments[0].text == "edited")
    }

    @Test("전사 세그먼트 split merge delete 테스트") @MainActor
    func testSegmentSplitMergeDeleteActionsSyncResult() throws {
        let viewModel = ContentViewModel()
        let segment = TranscriptionSegment(start: 0, end: 4, text: "hello world again")
        let result = TranscriptionResult(
            text: segment.text,
            segments: [segment],
            language: "en",
            timings: TranscriptionTimings()
        )

        viewModel.transcriptionResult = result
        viewModel.transcriptionState.confirmedSegments = [segment]
        viewModel.transcriptionState.speakerAssignments = [SpeakerSegmentAssignment(speakerID: 0)]

        viewModel.splitTranscriptionSegment(at: 0)
        #expect(viewModel.transcriptionState.confirmedSegments.count == 2)
        #expect(viewModel.transcriptionResult?.segments.count == 2)
        #expect(viewModel.transcriptionState.confirmedSegments[0].end == 2)
        #expect(viewModel.transcriptionState.confirmedSegments[1].start == 2)
        #expect(viewModel.transcriptionState.speakerAssignments == [
            SpeakerSegmentAssignment(speakerID: 0),
            SpeakerSegmentAssignment(speakerID: 0),
        ])

        viewModel.mergeTranscriptionSegment(at: 0, withNext: true)
        #expect(viewModel.transcriptionState.confirmedSegments.count == 1)
        #expect(viewModel.transcriptionResult?.segments.count == 1)
        #expect(viewModel.transcriptionState.confirmedSegments[0].text.contains("hello"))
        #expect(viewModel.transcriptionState.speakerAssignments == [
            SpeakerSegmentAssignment(speakerID: 0),
        ])

        viewModel.deleteTranscriptionSegment(at: 0)
        #expect(viewModel.transcriptionState.confirmedSegments.isEmpty)
        #expect(viewModel.transcriptionResult?.segments.isEmpty == true)
        #expect(viewModel.transcriptionState.speakerAssignments.isEmpty)
    }

    @Test("전사 세그먼트 타이밍 nudge 테스트") @MainActor
    func testSegmentTimingNudgeKeepsBoundariesValid() throws {
        let viewModel = ContentViewModel()
        let segments = [
            TranscriptionSegment(start: 0, end: 1, text: "one"),
            TranscriptionSegment(start: 1.2, end: 2.2, text: "two"),
        ]
        viewModel.transcriptionResult = TranscriptionResult(
            text: "one two",
            segments: segments,
            language: "en",
            timings: TranscriptionTimings()
        )
        viewModel.transcriptionState.confirmedSegments = segments

        viewModel.nudgeTranscriptionSegment(at: 1, by: -0.5)
        #expect(viewModel.transcriptionState.confirmedSegments[1].start == 1)
        #expect(viewModel.transcriptionState.confirmedSegments[1].end == 2)

        viewModel.adjustTranscriptionSegmentEnd(at: 0, by: 1)
        #expect(viewModel.transcriptionState.confirmedSegments[0].end == 1)

        viewModel.setTranscriptionSegmentStart(at: 1, to: 1.4)
        #expect(abs(viewModel.transcriptionState.confirmedSegments[1].start - 1.4) < 0.001)

        viewModel.setTranscriptionSegmentEnd(at: 1, to: 2.0)
        #expect(viewModel.transcriptionState.confirmedSegments[1].end == 2.0)
    }

    @Test("자막 검색 치환 테스트") @MainActor
    func testSubtitleSearchReplaceUpdatesSegments() throws {
        let viewModel = ContentViewModel()
        let segments = [
            TranscriptionSegment(start: 0, end: 1, text: "hello world"),
            TranscriptionSegment(start: 1, end: 2, text: "hello caption"),
        ]
        viewModel.transcriptionResult = TranscriptionResult(
            text: "hello world hello caption",
            segments: segments,
            language: "en",
            timings: TranscriptionTimings()
        )
        viewModel.transcriptionState.confirmedSegments = segments
        viewModel.uiState.subtitleSearchText = "hello"
        viewModel.uiState.subtitleReplaceText = "hi"

        #expect(viewModel.subtitleSearchMatchCount() == 2)

        viewModel.replaceNextSubtitleMatch()
        #expect(viewModel.transcriptionState.confirmedSegments[0].text == "hi world")

        viewModel.replaceAllSubtitleMatches()
        #expect(viewModel.transcriptionState.confirmedSegments[1].text == "hi caption")
        #expect(viewModel.transcriptionResult?.segments[1].text == "hi caption")
    }

    @Test("Export preset 적용 테스트") @MainActor
    func testExportPresetAppliesFrameRate() throws {
        let viewModel = ContentViewModel()

        viewModel.selectedExportPreset = .finalCut
        viewModel.applySelectedExportPreset(showMessage: false)

        #expect(viewModel.frameRate == 29.97)
        #expect(viewModel.selectedExportPreset.displayName == "Final Cut Pro")

        viewModel.selectedExportPreset = .general
        viewModel.applySelectedExportPreset(showMessage: false)
    }

    @Test("Sidecar 복원 상태 적용 테스트") @MainActor
    func testRestoreTranscriptionSidecarAppliesSegmentsSpeakersAndExportSettings() throws {
        let viewModel = ContentViewModel()
        let originalPreset = viewModel.selectedExportPreset
        let originalFrameRate = viewModel.frameRate
        let originalIncludeSpeakerLabels = viewModel.includeSpeakerLabelsInExport
        let originalSpeakerCount = viewModel.speakerDiarizationSpeakerCount
        let originalEnableSpeakerDiarization = viewModel.enableSpeakerDiarization
        defer {
            viewModel.selectedExportPreset = originalPreset
            viewModel.frameRate = originalFrameRate
            viewModel.includeSpeakerLabelsInExport = originalIncludeSpeakerLabels
            viewModel.speakerDiarizationSpeakerCount = originalSpeakerCount
            viewModel.enableSpeakerDiarization = originalEnableSpeakerDiarization
        }

        let sidecar = CaptionMateSidecar(
            version: CaptionMateSidecar.currentVersion,
            audioFileName: "clip",
            language: "ko",
            segments: [
                .init(start: 0.25, end: 1.75, text: "안녕하세요", speakerID: 0),
                .init(start: 2.0, end: 3.5, text: "반갑습니다", speakerID: 1),
            ],
            speakerNames: [
                "0": "Host",
                "1": "Guest",
            ],
            exportSettings: .init(
                selectedExportPreset: SubtitleExportPreset.finalCut.rawValue,
                frameRate: 29.97,
                includeSpeakerLabelsInExport: false,
                speakerDiarizationSpeakerCount: 2
            )
        )

        viewModel.restoreTranscriptionSidecar(sidecar)

        #expect(viewModel.transcriptionState.confirmedSegments.map(\.text) == ["안녕하세요", "반갑습니다"])
        #expect(viewModel.transcriptionState.confirmedSegments.map(\.start) == [0.25, 2.0])
        #expect(viewModel.transcriptionState.confirmedSegments.map(\.end) == [1.75, 3.5])
        #expect(viewModel.transcriptionState.speakerAssignments == [
            SpeakerSegmentAssignment(speakerID: 0),
            SpeakerSegmentAssignment(speakerID: 1),
        ])
        #expect(viewModel.transcriptionState.speakerNames == [0: "Host", 1: "Guest"])
        #expect(viewModel.speakerDiarizationSpeakerCount == 2)
        #expect(viewModel.transcriptionState.speakerDiarization.detectedSpeakerCount == 2)
        #expect(viewModel.selectedExportPreset == .finalCut)
        #expect(viewModel.frameRate == 29.97)
        #expect(viewModel.includeSpeakerLabelsInExport == false)
        #expect(viewModel.transcriptionResult?.language == "ko")
        #expect(viewModel.uiState.isTranscribingView == true)
    }

    @Test("Sidecar 복원은 비정상 화자 ID를 허용 범위로 제한한다") @MainActor
    func testRestoreTranscriptionSidecarClampsUnsafeSpeakerIDs() throws {
        let viewModel = ContentViewModel()
        let sidecar = CaptionMateSidecar(
            version: CaptionMateSidecar.currentVersion,
            audioFileName: "clip",
            language: "ko",
            segments: [
                .init(start: 0, end: 1, text: "invalid", speakerID: Int.max),
                .init(start: 1, end: 2, text: "valid", speakerID: 7),
                .init(start: 2, end: 3, text: "negative", speakerID: -1),
            ],
            speakerNames: [
                "\(Int.max)": "Huge",
                "-1": "Negative",
                "7": "Panelist",
            ],
            exportSettings: .init(
                selectedExportPreset: SubtitleExportPreset.general.rawValue,
                frameRate: 30,
                includeSpeakerLabelsInExport: true,
                speakerDiarizationSpeakerCount: 0
            )
        )

        viewModel.restoreTranscriptionSidecar(sidecar)

        #expect(viewModel.transcriptionState.speakerAssignments == [
            nil,
            SpeakerSegmentAssignment(speakerID: 7),
            nil,
        ])
        #expect(viewModel.transcriptionState.speakerNames == [7: "Panelist"])
        #expect(viewModel.transcriptionState.speakerDiarization.detectedSpeakerCount == 8)
        #expect(viewModel.availableSpeakerIDs() == Array(0 ..< 8))
    }

    @Test("Batch queue 상태 테스트") @MainActor
    func testBatchQueueState() throws {
        let viewModel = ContentViewModel()
        let first = URL(fileURLWithPath: "/tmp/a.wav")
        let second = URL(fileURLWithPath: "/tmp/b.wav")

        viewModel.setBatchQueue([first, second], needsSecurityScopedAccess: false)

        #expect(viewModel.batchQueue.count == 2)
        #expect(viewModel.currentBatchIndex == 0)
        #expect(viewModel.batchProgressText == "1 of 2")

        viewModel.removeBatchItem(at: 0)
        #expect(viewModel.batchQueue.count == 1)

        viewModel.clearBatchQueue()
        #expect(viewModel.batchQueue.isEmpty)
        #expect(viewModel.currentBatchIndex == nil)
    }

    @Test("자막 export 줄바꿈 정리 테스트") @MainActor
    func testWrappedSubtitleTextUsesPresetLimits() throws {
        let wrapped = ContentViewModel.wrappedSubtitleText(
            "This is a long subtitle line that should be wrapped into short readable chunks",
            maxLineLength: 20,
            maxLines: 2
        )

        let lines = wrapped.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].count <= 20)
    }

    @Test("성능 자동 설정 테스트") @MainActor
    func testRecommendedPerformanceSettingsAppliesConservativeDefaults() throws {
        let viewModel = ContentViewModel()

        viewModel.concurrentWorkerCount = 32
        viewModel.applyRecommendedPerformanceSettings(showMessage: false)

        #expect(viewModel.concurrentWorkerCount >= 2)
        #expect(viewModel.concurrentWorkerCount <= 8)
        #expect(viewModel.chunkingStrategy == .vad)
    }

    @Test("화자 수 자동 기본값과 이름 지정 테스트") @MainActor
    func testSpeakerCountAndNameOptions() throws {
        let viewModel = ContentViewModel()
        let originalSpeakerCount = viewModel.speakerDiarizationSpeakerCount
        defer {
            viewModel.speakerDiarizationSpeakerCount = originalSpeakerCount
        }

        viewModel.speakerDiarizationSpeakerCount = 0
        #expect(viewModel.speakerDiarizationExpectedSpeakerCount() == nil)
        #expect(viewModel.speakerCountOptionTitle(for: 0) == "Auto")

        viewModel.speakerDiarizationSpeakerCount = 3
        #expect(viewModel.speakerDiarizationExpectedSpeakerCount() == 3)
        #expect(viewModel.availableSpeakerIDs() == [0, 1, 2])

        viewModel.setSpeakerName(" Host ", for: 0)
        #expect(viewModel.speakerDisplayName(for: 0) == "Host")
        #expect(viewModel.speakerDisplayName(for: SpeakerSegmentAssignment(speakerID: 0)) == "Host")

        viewModel.setSpeakerName(" ", for: 0)
        #expect(viewModel.speakerDisplayName(for: 0) == "Speaker 1")
    }

    @Test("화자 라벨 export 전 검토 이슈 테스트") @MainActor
    func testSpeakerReviewIssuesBeforeExport() throws {
        let viewModel = ContentViewModel()
        let segments = [
            TranscriptionSegment(start: 0, end: 1, text: "first"),
            TranscriptionSegment(start: 1, end: 2, text: "second"),
        ]
        let originalEnabled = viewModel.enableSpeakerDiarization
        let originalInclude = viewModel.includeSpeakerLabelsInExport
        let originalSpeakerCount = viewModel.speakerDiarizationSpeakerCount
        defer {
            viewModel.enableSpeakerDiarization = originalEnabled
            viewModel.includeSpeakerLabelsInExport = originalInclude
            viewModel.speakerDiarizationSpeakerCount = originalSpeakerCount
        }

        viewModel.transcriptionState.confirmedSegments = segments
        viewModel.transcriptionState.speakerAssignments = [
            nil,
            SpeakerSegmentAssignment(speakerID: 0),
        ]
        viewModel.enableSpeakerDiarization = true
        viewModel.includeSpeakerLabelsInExport = true
        viewModel.speakerDiarizationSpeakerCount = 1

        let issues = viewModel.refreshSubtitleQualityIssues()
        #expect(issues.contains { $0.kind == .missingSpeaker && $0.segmentIndex == 0 })
        #expect(issues.contains { $0.kind == .defaultSpeakerName && $0.segmentIndex == 1 })

        viewModel.setSpeakerAssignment(at: 0, speakerID: 0)
        viewModel.setSpeakerName("Host", for: 0)
        let fixedIssues = viewModel.refreshSubtitleQualityIssues()
        #expect(!fixedIssues.contains { $0.kind == .missingSpeaker })
        #expect(!fixedIssues.contains { $0.kind == .defaultSpeakerName })
    }

    @Test("자막 리뷰 Quick Fix가 빈 세그먼트, 겹침, 화자 누락을 보정하는지 테스트") @MainActor
    func testSubtitleQualityQuickFixesNormalizeSegmentsAndSpeakers() throws {
        let viewModel = ContentViewModel()
        let originalEnabled = viewModel.enableSpeakerDiarization
        let originalInclude = viewModel.includeSpeakerLabelsInExport
        let originalSpeakerCount = viewModel.speakerDiarizationSpeakerCount
        defer {
            viewModel.enableSpeakerDiarization = originalEnabled
            viewModel.includeSpeakerLabelsInExport = originalInclude
            viewModel.speakerDiarizationSpeakerCount = originalSpeakerCount
        }

        let longText = """
        This subtitle line is intentionally long so the quick fix can split it into two readable subtitle segments for review.
        """
        let segments = [
            TranscriptionSegment(start: 0.0, end: 1.0, text: "   "),
            TranscriptionSegment(start: 0.0, end: 2.0, text: " first speaker line "),
            TranscriptionSegment(start: 1.5, end: 1.4, text: "second speaker line"),
            TranscriptionSegment(start: 2.0, end: 12.0, text: longText),
        ]

        viewModel.transcriptionResult = TranscriptionResult(
            text: segments.map(\.text).joined(separator: " "),
            segments: segments,
            language: "en",
            timings: TranscriptionTimings()
        )
        viewModel.transcriptionState.confirmedSegments = segments
        viewModel.transcriptionState.speakerAssignments = [
            nil,
            SpeakerSegmentAssignment(speakerID: 0),
            nil,
            nil,
        ]
        viewModel.transcriptionState.speakerDiarization = SpeakerDiarizationState(
            detectedSpeakerCount: 1
        )
        viewModel.enableSpeakerDiarization = true
        viewModel.includeSpeakerLabelsInExport = true
        viewModel.speakerDiarizationSpeakerCount = 1

        let fixedCount = viewModel.applySubtitleQualityQuickFixes()

        #expect(fixedCount >= 5)
        #expect(!viewModel.transcriptionState.confirmedSegments.contains {
            $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })
        #expect(viewModel.transcriptionState.confirmedSegments.allSatisfy { $0.end > $0.start })
        #expect(!viewModel.transcriptionState.confirmedSegments.indices.dropLast().contains { index in
            viewModel.transcriptionState.confirmedSegments[index].end >
                viewModel.transcriptionState.confirmedSegments[index + 1].start
        })
        #expect(viewModel.transcriptionState.confirmedSegments.count == 4)
        #expect(viewModel.transcriptionState.speakerAssignments.allSatisfy { $0?.speakerID == 0 })
        #expect(viewModel.transcriptionResult?.segments.count == viewModel.transcriptionState.confirmedSegments.count)

        let remainingIssues = viewModel.refreshSubtitleQualityIssues()
        #expect(!remainingIssues.contains { $0.kind == .emptyText })
        #expect(!remainingIssues.contains { $0.kind == .invalidTiming })
        #expect(!remainingIssues.contains { $0.kind == .overlappingTiming })
        #expect(!remainingIssues.contains { $0.kind == .missingSpeaker })
    }

    @Test("화자 재분석 입력 가드 테스트") @MainActor
    func testReanalyzeSpeakersRequiresAudioAndSegments() throws {
        let viewModel = ContentViewModel()

        viewModel.reanalyzeSpeakersForCurrentAudio()

        #expect(viewModel.transcriptionState.speakerDiarization.isRunning == false)
        #expect(viewModel.uiState.userMessage?.title == "Speaker Analysis Unavailable")
    }

    @Test("화자분리 모델 캐시 검증 테스트")
    func testSpeakerDiarizationModelValidationRequiresDefaultFiles() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionMateSpeakerModel-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        for relativePath in SpeakerDiarizationModelStore.requiredRelativeFilePaths {
            let fileURL = rootURL.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data([0]).write(to: fileURL)
        }

        var report = SpeakerDiarizationModelStore.validationReport(for: rootURL)
        #expect(report.isValid)

        let missingFile = rootURL.appendingPathComponent(
            SpeakerDiarizationModelStore.requiredRelativeFilePaths[0]
        )
        try FileManager.default.removeItem(at: missingFile)

        report = SpeakerDiarizationModelStore.validationReport(for: rootURL)
        #expect(!report.isValid)
        #expect(report.missingRelativePaths == [SpeakerDiarizationModelStore.requiredRelativeFilePaths[0]])

        let directoryPath = SpeakerDiarizationModelStore.requiredRelativeFilePaths[1]
        let directoryURL = rootURL.appendingPathComponent(directoryPath)
        try FileManager.default.removeItem(at: directoryURL)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        report = SpeakerDiarizationModelStore.validationReport(for: rootURL)
        #expect(!report.isValid)
        #expect(report.missingRelativePaths == [
            SpeakerDiarizationModelStore.requiredRelativeFilePaths[0],
            directoryPath,
        ])
    }

    @Test("모델 카탈로그 크기 추정과 캐시 테스트")
    func testModelCatalogSizeEstimatesAndCache() throws {
        #expect(ModelCatalogService.estimatedDownloadSize(for: "openai_whisper-tiny") == 76_600_000)
        #expect(ModelCatalogService.estimatedDownloadSize(for: "openai_whisper-tiny.en") == 153_000_000)
        #expect(ModelCatalogService.estimatedDownloadSize(for: "openai_whisper-large-v3_turbo_954MB") == 954_000_000)

        let suiteName = "CaptionMateTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        ModelCatalogService.saveCachedRemoteSizes(
            ["openai_whisper-tiny": 76_600_000],
            repoName: "argmaxinc/whisperkit-coreml",
            userDefaults: defaults
        )

        #expect(ModelCatalogService.cachedRemoteSizes(
            repoName: "argmaxinc/whisperkit-coreml",
            userDefaults: defaults
        ) == ["openai_whisper-tiny": 76_600_000])
    }

    @Test("모델 폴더 경로는 저장소 루트 밖으로 벗어날 수 없다")
    func testModelFolderURLRejectsUnsafeNames() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionMateModelRoot-\(UUID().uuidString)", isDirectory: true)

        let safeURL = try ModelCatalogService.modelFolderURL(
            for: "openai_whisper-tiny.en",
            in: rootURL.path
        )
        #expect(safeURL == rootURL
            .standardizedFileURL
            .appendingPathComponent("openai_whisper-tiny.en", isDirectory: true)
            .standardizedFileURL)

        for unsafeName in ["../outside", "nested/model", #"nested\model"#, ":bad", "", " ", ".", "..", "bad\nname"] {
            do {
                _ = try ModelCatalogService.modelFolderURL(for: unsafeName, in: rootURL.path)
                Issue.record("Unsafe model name was accepted: \(unsafeName)")
            } catch ModelCatalogServiceError.unsafeModelName {
                continue
            } catch {
                Issue.record("Unexpected error for \(unsafeName): \(error)")
            }
        }
    }

    @Test("원격 모델 크기 응답이 과도하게 크면 디코딩 전에 거부한다")
    func testRemoteFolderSizeRejectsOversizedResponses() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OversizedRemoteSizeURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer {
            session.finishTasksAndInvalidate()
            OversizedRemoteSizeURLProtocol.responseData = Data()
        }

        OversizedRemoteSizeURLProtocol.responseData = Data(
            repeating: UInt8(ascii: "["),
            count: Int(ModelCatalogService.maxRemoteTreeResponseBytes) + 1
        )

        do {
            _ = try await ModelCatalogService.remoteFolderSize(
                repoName: "argmaxinc/whisperkit-coreml",
                model: "openai_whisper-tiny",
                session: session
            )
            Issue.record("Oversized remote model metadata should throw before JSON decode.")
        } catch let error as URLError {
            #expect(error.code == .dataLengthExceedsMaximum)
        }
    }

    @Test("로컬 모델 정렬 후에도 모델 크기 매핑은 유지된다")
    func testLocalModelSizeMappingSurvivesFormattedSort() throws {
        let folders = [
            LocalModelFolderInfo(name: "openai_whisper-large-v3-v20240930", size: 1_630_000_000),
            LocalModelFolderInfo(name: "openai_whisper-tiny", size: 76_600_000),
        ]

        let ordered = ModelCatalogService.orderedLocalModelFolders(folders) { _ in
            [
                "openai_whisper-tiny",
                "openai_whisper-large-v3-v20240930",
            ]
        }

        #expect(ordered.map(\.name) == [
            "openai_whisper-tiny",
            "openai_whisper-large-v3-v20240930",
        ])
        #expect(ordered.map(\.size) == [
            76_600_000,
            1_630_000_000,
        ])
    }

    @Test("스토리지 정리는 오래된 앱 임시 파일만 삭제한다")
    func testStorageCleanupPreservesRecentAndPinnedFiles() throws {
        let fileManager = FileManager.default
        let directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("CaptionMateTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: directoryURL)
        }

        let now = Date(timeIntervalSinceReferenceDate: 7_200)
        let oldURL = directoryURL.appendingPathComponent("old.wav")
        let recentURL = directoryURL.appendingPathComponent("recent.wav")
        let preservedURL = directoryURL.appendingPathComponent("preserved.wav")

        try Data("old".utf8).write(to: oldURL)
        try Data("recent".utf8).write(to: recentURL)
        try Data("preserved".utf8).write(to: preservedURL)

        try fileManager.setAttributes(
            [.modificationDate: Date(timeIntervalSinceReferenceDate: 0)],
            ofItemAtPath: oldURL.path
        )
        try fileManager.setAttributes(
            [.modificationDate: Date(timeIntervalSinceReferenceDate: 5_000)],
            ofItemAtPath: recentURL.path
        )
        try fileManager.setAttributes(
            [.modificationDate: Date(timeIntervalSinceReferenceDate: 0)],
            ofItemAtPath: preservedURL.path
        )

        let report = try StorageCleanupService.cleanupStaleItems(
            in: directoryURL,
            olderThan: 3_600,
            preserving: [preservedURL],
            now: now,
            fileManager: fileManager
        )

        #expect(report.removedItemCount == 1)
        #expect(!fileManager.fileExists(atPath: oldURL.path))
        #expect(fileManager.fileExists(atPath: recentURL.path))
        #expect(fileManager.fileExists(atPath: preservedURL.path))
    }

    @Test("모델 관리 다운로드 큐 상태 테스트") @MainActor
    func testModelManagementDownloadQueueState() throws {
        let state = ModelManagementState()
        #expect(state.maxConcurrentDownloads == 2)
        state.trackDownloadRequest("openai_whisper-base")
        state.queuedDownloadModels = ["openai_whisper-base"]

        #expect(state.isQueued(model: "openai_whisper-base"))
        #expect(!state.canStartDownload(model: "openai_whisper-base"))

        state.queuedDownloadModels.removeAll()
        state.currentDownloadingModels.insert("openai_whisper-base")

        #expect(state.isDownloading(model: "openai_whisper-base"))
        #expect(!state.canStartDownload(model: "openai_whisper-base"))
    }

    @Test("다운로드 status와 row progress는 같은 진행률/용량 계산을 사용한다") @MainActor
    func testDownloadDisplayProgressUsesSharedWeightedCalculation() throws {
        let state = ModelManagementState()
        let tinyModel = "openai_whisper-tiny"
        let largeModel = "openai_whisper-large-v3_turbo_954MB"
        let tinyEstimate = ModelCatalogService.estimatedDownloadSize(for: tinyModel)

        state.availableModels = [tinyModel, largeModel]
        state.downloadBatchModels = [tinyModel, largeModel]
        state.currentDownloadingModels = [largeModel]
        state.modelSizes[largeModel] = 1_000
        state.downloadProgress[tinyModel] = 1.5
        state.downloadProgress[largeModel] = 0.25

        #expect(state.trackedDownloadModels(orderedBy: state.availableModels) == [tinyModel, largeModel])
        #expect(state.downloadProgressValue(for: tinyModel) == 1.0)
        #expect(state.downloadDisplaySize(for: tinyModel) == tinyEstimate)
        #expect(state.totalDownloadByteCount(for: [tinyModel, largeModel]) == tinyEstimate + 1_000)
        #expect(state.downloadedByteCount(for: [tinyModel, largeModel]) == tinyEstimate + 250)
        #expect(
            state.weightedDownloadProgress(for: [tinyModel, largeModel]) ==
                Double(tinyEstimate + 250) / Double(tinyEstimate + 1_000)
        )
    }

    @Test("취소 중 다운로드는 다운로드 섹션에 남아 진행 상태 계산에 포함된다") @MainActor
    func testCancellingDownloadRemainsTrackedForDownloadSection() throws {
        let state = ModelManagementState()
        let cancellingModel = "openai_whisper-small"
        let queuedModel = "openai_whisper-tiny"
        let activeModel = "openai_whisper-base"

        state.availableModels = [cancellingModel, queuedModel, activeModel]
        state.downloadBatchModels = [activeModel]
        state.currentDownloadingModels = [activeModel]
        state.queuedDownloadModels = [queuedModel]
        state.cancellingModels = [cancellingModel]
        state.modelSizes[cancellingModel] = 100
        state.modelSizes[queuedModel] = 100
        state.modelSizes[activeModel] = 100
        state.downloadProgress[cancellingModel] = 0.5
        state.downloadProgress[queuedModel] = 0.75
        state.downloadProgress[activeModel] = 0.25

        let trackedModels = state.trackedDownloadModels(orderedBy: state.availableModels)

        #expect(trackedModels == [cancellingModel, queuedModel, activeModel])
        #expect(state.hasVisibleDownloadActivity)
        #expect(state.downloadProgressValue(for: queuedModel) == 0)
        #expect(state.downloadedByteCount(for: trackedModels) == 75)

        state.currentDownloadingModels.removeAll()
        state.queuedDownloadModels.removeAll()
        state.downloadBatchModels.removeAll()
        state.clearDownloadBatchIfIdle()

        #expect(state.trackedDownloadModels(orderedBy: state.availableModels) == [cancellingModel])

        state.cancellingModels.removeAll()
        state.clearDownloadBatchIfIdle()

        #expect(state.trackedDownloadModels(orderedBy: state.availableModels).isEmpty)
    }

    @Test("대기 중 다운로드 취소는 큐와 진행 상태를 즉시 정리한다") @MainActor
    func testQueuedDownloadCancellationClearsState() throws {
        let viewModel = ContentViewModel()
        let model = "openai_whisper-base"

        viewModel.modelManagementState.queuedDownloadModels = [model]
        viewModel.modelManagementState.downloadBatchModels = [model]
        viewModel.modelManagementState.downloadProgress[model] = 0.0
        viewModel.modelManagementState.downloadErrors[model] = "Previous error"

        viewModel.cancelDownload(model)

        #expect(!viewModel.modelManagementState.queuedDownloadModels.contains(model))
        #expect(!viewModel.modelManagementState.downloadBatchModels.contains(model))
        #expect(viewModel.modelManagementState.downloadProgress[model] == nil)
        #expect(viewModel.modelManagementState.downloadErrors[model] == nil)
    }

    @Test("화면 종료 준비는 다운로드 상태와 Progress 참조를 정리한다") @MainActor
    func testPrepareForCloseClearsDownloadState() throws {
        let viewModel = ContentViewModel()
        let model = "openai_whisper-base"
        let task = Task<Void, Never> {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
        }

        viewModel.modelManagementState.downloadTasks[model] = task
        viewModel.modelManagementState.downloadProgressObjects[model] = Progress(totalUnitCount: 100)
        viewModel.modelManagementState.lastProgressCallbackTime[model] = Date()
        viewModel.modelManagementState.currentDownloadingModels.insert(model)
        viewModel.modelManagementState.cancellingModels.insert(model)
        viewModel.modelManagementState.queuedDownloadModels = ["openai_whisper-small"]
        viewModel.modelManagementState.downloadBatchModels = [model, "openai_whisper-small"]
        viewModel.modelManagementState.downloadProgress[model] = 0.4
        viewModel.modelManagementState.isDownloading = true
        viewModel.modelManagementState.catalogLoadState = .loadingRemote
        viewModel.modelManagementState.isRemoteModelSizeLoading = true

        viewModel.prepareForClose()

        #expect(viewModel.modelManagementState.downloadTasks.isEmpty)
        #expect(viewModel.modelManagementState.downloadProgressObjects.isEmpty)
        #expect(viewModel.modelManagementState.lastProgressCallbackTime.isEmpty)
        #expect(viewModel.modelManagementState.currentDownloadingModels.isEmpty)
        #expect(viewModel.modelManagementState.cancellingModels.isEmpty)
        #expect(viewModel.modelManagementState.queuedDownloadModels.isEmpty)
        #expect(viewModel.modelManagementState.downloadBatchModels.isEmpty)
        #expect(viewModel.modelManagementState.downloadProgress.isEmpty)
        #expect(!viewModel.modelManagementState.isDownloading)
        #expect(viewModel.modelManagementState.catalogLoadState == .idle)
        #expect(!viewModel.modelManagementState.isRemoteModelSizeLoading)
    }

    @Test("화면 종료 준비는 모델 로딩 Task도 취소한다") @MainActor
    func testPrepareForCloseCancelsActiveModelLoadTask() throws {
        let viewModel = ContentViewModel()
        let task = Task<Void, Never> {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
        }

        viewModel.setModelLoadTaskForTesting(task)
        #expect(viewModel.hasActiveModelLoadTaskForTesting)

        viewModel.prepareForClose()

        #expect(!viewModel.hasActiveModelLoadTaskForTesting)
        #expect(task.isCancelled)
    }

    @Test("화면 종료 준비는 오디오 파형과 정규화 Task도 취소한다") @MainActor
    func testPrepareForCloseCancelsAudioProcessingTasks() throws {
        let viewModel = ContentViewModel()
        let waveformTask = Task<Void, Never> {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
        }
        let normalizationTask = Task<Void, Never> {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
        }

        viewModel.setAudioProcessingTasksForTesting(
            waveformTask: waveformTask,
            normalizationTask: normalizationTask
        )
        #expect(viewModel.hasActiveAudioProcessingTaskForTesting)

        viewModel.prepareForClose()

        #expect(!viewModel.hasActiveAudioProcessingTaskForTesting)
        #expect(waveformTask.isCancelled)
        #expect(normalizationTask.isCancelled)
    }

    @Test("활성 다운로드 취소 모니터는 화면 종료 준비에서 정리된다") @MainActor
    func testPrepareForCloseCancelsActiveDownloadCancellationMonitor() throws {
        let viewModel = ContentViewModel()
        let model = "openai_whisper-base"
        let task = Task<Void, Never> {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
        }

        viewModel.modelManagementState.downloadTasks[model] = task
        viewModel.modelManagementState.currentDownloadingModels.insert(model)
        viewModel.modelManagementState.downloadBatchModels = [model]

        viewModel.cancelDownload(model)

        #expect(viewModel.modelManagementState.isCancelling(model: model))
        #expect(viewModel.activeDownloadCancellationMonitorCountForTesting == 1)

        viewModel.prepareForClose()

        #expect(viewModel.activeDownloadCancellationMonitorCountForTesting == 0)
        #expect(viewModel.modelManagementState.cancellingModels.isEmpty)
        #expect(viewModel.modelManagementState.downloadTasks.isEmpty)
    }
}

// MARK: - Speaker Diarization Tests

struct SpeakerDiarizationTests {
    @Test("화자분리 세그먼트 매핑 테스트")
    func testSpeakerAssignmentMapperChoosesLargestOverlapAndCarriesPrevious() throws {
        let transcriptionSegments = [
            TranscriptionSegment(start: 0, end: 2, text: "first"),
            TranscriptionSegment(start: 2, end: 4, text: "second"),
            TranscriptionSegment(start: 4, end: 5, text: "carry"),
        ]
        let timelineSegments = [
            SpeakerTimelineSegment(speakerID: 0, start: 0, end: 2),
            SpeakerTimelineSegment(speakerID: 1, start: 2, end: 3.5),
        ]

        let assignments = SpeakerAssignmentMapper.assignments(
            for: transcriptionSegments,
            from: timelineSegments
        )

        #expect(assignments == [
            SpeakerSegmentAssignment(speakerID: 0),
            SpeakerSegmentAssignment(speakerID: 1),
            SpeakerSegmentAssignment(speakerID: 1),
        ])
    }

    @Test("화자 라벨 export prefix 테스트")
    func testSpeakerLabelFormatterPrefixesWithoutDuplication() throws {
        let assignment = SpeakerSegmentAssignment(speakerID: 0)

        #expect(SpeakerLabelFormatter.prefixedText(
            " hello ",
            assignment: assignment,
            includeSpeakerLabel: true
        ) == "Speaker 1: hello")
        #expect(SpeakerLabelFormatter.prefixedText(
            "Speaker 1: hello",
            assignment: assignment,
            includeSpeakerLabel: true
        ) == "Speaker 1: hello")
        #expect(SpeakerLabelFormatter.prefixedText(
            " hello ",
            assignment: assignment,
            speakerName: "Host",
            includeSpeakerLabel: true
        ) == "Host: hello")
        #expect(SpeakerLabelFormatter.prefixedText(
            "Host: hello",
            assignment: assignment,
            speakerName: "Host",
            includeSpeakerLabel: true
        ) == "Host: hello")
        #expect(SpeakerLabelFormatter.prefixedText(
            " hello ",
            assignment: assignment,
            includeSpeakerLabel: false
        ) == "hello")
    }
}

// MARK: - CaptionMate Sidecar Tests

struct CaptionMateSidecarServiceTests {
    @Test("Sidecar URL naming 테스트")
    func testSidecarURLUsesCaptionMateJSONExtension() throws {
        let directoryURL = URL(fileURLWithPath: "/tmp/CaptionMateSidecarNaming", isDirectory: true)

        let wavURL = directoryURL.appendingPathComponent("clip.wav")
        let srtURL = directoryURL.appendingPathComponent("clip.srt")

        #expect(
            CaptionMateSidecarService.sidecarURL(forMediaURL: wavURL)
                .lastPathComponent == "clip.captionmate.json"
        )
        #expect(
            CaptionMateSidecarService.sidecarURL(forMediaURL: srtURL)
                .lastPathComponent == "clip.captionmate.json"
        )
    }

    @Test("Sidecar write/read roundtrip 테스트")
    func testSidecarWriteReadRoundtripPreservesSubtitleState() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionMateSidecar-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let mediaURL = directoryURL.appendingPathComponent("clip.wav")
        let segments = [
            TranscriptionSegment(start: 0.25, end: 1.75, text: "Hello"),
            TranscriptionSegment(start: 2.0, end: 3.5, text: "World"),
        ]
        let result = TranscriptionResult(
            text: "Hello World",
            segments: segments,
            language: "en",
            timings: TranscriptionTimings()
        )
        let expectedSidecar = CaptionMateSidecar(
            result: result,
            audioFileName: "clip",
            speakerAssignments: [
                SpeakerSegmentAssignment(speakerID: 0),
                SpeakerSegmentAssignment(speakerID: 1),
            ],
            speakerNames: [
                0: "Host",
                1: "Guest",
            ],
            selectedExportPreset: .premiereResolve,
            frameRate: 24.0,
            includeSpeakerLabelsInExport: false,
            speakerDiarizationSpeakerCount: 2
        )

        let writtenURL = try CaptionMateSidecarService.write(expectedSidecar, nextToMediaURL: mediaURL)
        let restoredSidecar = try CaptionMateSidecarService.read(from: writtenURL)
        let restoredViaMediaURL = try CaptionMateSidecarService.readIfPresent(nextToMediaURL: mediaURL)

        #expect(writtenURL.lastPathComponent == "clip.captionmate.json")
        #expect(FileManager.default.fileExists(atPath: writtenURL.path))
        #expect(restoredSidecar == expectedSidecar)
        #expect(restoredViaMediaURL == expectedSidecar)
        #expect(restoredSidecar.segments.map(\.speakerID) == [0, 1])
        #expect(restoredSidecar.speakerNames == ["0": "Host", "1": "Guest"])
        #expect(restoredSidecar.exportSettings.selectedExportPreset == SubtitleExportPreset.premiereResolve.rawValue)
        #expect(restoredSidecar.exportSettings.frameRate == 24.0)
        #expect(restoredSidecar.exportSettings.includeSpeakerLabelsInExport == false)
        #expect(restoredSidecar.exportSettings.speakerDiarizationSpeakerCount == 2)
    }

    @Test("Unsupported sidecar version throw 테스트")
    func testUnsupportedSidecarVersionThrows() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionMateSidecarVersion-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let sidecarURL = directoryURL.appendingPathComponent("clip.captionmate.json")
        let json = """
        {
          "audioFileName": "clip",
          "exportSettings": {
            "frameRate": 30,
            "includeSpeakerLabelsInExport": true,
            "selectedExportPreset": "general",
            "speakerDiarizationSpeakerCount": 0
          },
          "language": "en",
          "segments": [],
          "speakerNames": {},
          "version": 999
        }
        """
        try json.write(to: sidecarURL, atomically: true, encoding: .utf8)

        do {
            _ = try CaptionMateSidecarService.read(from: sidecarURL)
            Issue.record("Unsupported sidecar versions should throw.")
        } catch let error as CaptionMateSidecarError {
            #expect(error.localizedDescription.contains("999"))
        }
    }

    @Test("Oversized sidecar restore is rejected before decode")
    func testOversizedSidecarThrowsBeforeDecode() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionMateSidecarLarge-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let sidecarURL = directoryURL.appendingPathComponent("clip.captionmate.json")
        let oversizedData = Data(
            repeating: UInt8(ascii: " "),
            count: Int(CaptionMateSidecarService.maxReadableSidecarBytes) + 1
        )
        try oversizedData.write(to: sidecarURL, options: .atomic)

        do {
            _ = try CaptionMateSidecarService.read(from: sidecarURL)
            Issue.record("Oversized sidecars should throw before JSON decode.")
        } catch let error as CaptionMateSidecarError {
            guard case let .fileTooLarge(byteCount, limit) = error else {
                Issue.record("Expected fileTooLarge, got \(error).")
                return
            }
            #expect(byteCount > limit)
        }
    }
}

final class SpeakerDiarizationIntegrationSmokeTests: XCTestCase {
    func testOfflineSpeakerDiarizationWithInstalledModelAndFixtureAudio() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["CAPTIONMATE_RUN_SPEAKER_DIARIZATION_SMOKE"] == "1" else {
            throw XCTSkip(
                "Set CAPTIONMATE_RUN_SPEAKER_DIARIZATION_SMOKE=1 and CAPTIONMATE_SPEAKER_SMOKE_AUDIO_PATH to run the offline model smoke test."
            )
        }

        guard let audioPath = environment["CAPTIONMATE_SPEAKER_SMOKE_AUDIO_PATH"],
              !audioPath.isEmpty,
              FileManager.default.fileExists(atPath: audioPath) else {
            throw XCTSkip("CAPTIONMATE_SPEAKER_SMOKE_AUDIO_PATH must point to a local audio file.")
        }

        guard let modelRoot = SpeakerDiarizationModelStore.defaultRootURL() else {
            throw XCTSkip("Document directory is unavailable.")
        }

        let report = SpeakerDiarizationModelStore.validationReport(for: modelRoot)
        guard report.isValid else {
            throw XCTSkip("Speaker diarization model is not installed or needs repair.")
        }

        let audioSamples = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioPath)
        XCTAssertGreaterThan(audioSamples.count, 16_000, "Use at least one second of audio.")

        let expectedSpeakerCount = environment["CAPTIONMATE_SPEAKER_SMOKE_COUNT"]
            .flatMap(Int.init)
        let service = SpeakerDiarizationService(modelRootURL: modelRoot)
        let timeline = try await service.diarize(
            audioSamples: audioSamples,
            expectedSpeakerCount: expectedSpeakerCount
        )

        XCTAssertFalse(timeline.isEmpty, "Diarization should return speaker timeline segments.")
        XCTAssertTrue(timeline.allSatisfy { $0.end > $0.start })
    }
}

// MARK: - Performance Smoke Tests

struct PerformanceSmokeTests {
    @Test("긴 자막 전체 치환 성능 스모크") @MainActor
    func testReplaceAllLargeSubtitleBatchPerformance() throws {
        let viewModel = ContentViewModel()
        let segmentCount = 8_000
        let segments = (0 ..< segmentCount).map { index in
            TranscriptionSegment(
                start: Float(index) * 2.5,
                end: Float(index) * 2.5 + 2.0,
                text: "hello caption \(index)"
            )
        }

        viewModel.transcriptionResult = TranscriptionResult(
            text: segments.map(\.text).joined(separator: " "),
            segments: segments,
            language: "en",
            timings: TranscriptionTimings()
        )
        viewModel.transcriptionState.confirmedSegments = segments
        viewModel.transcriptionState.speakerAssignments = Array(
            repeating: SpeakerSegmentAssignment(speakerID: 0),
            count: segmentCount
        )
        viewModel.transcriptionState.speakerNames = [0: "Narrator"]
        viewModel.uiState.subtitleSearchText = "hello"
        viewModel.uiState.subtitleReplaceText = "hi"

        let start = Date()
        viewModel.replaceAllSubtitleMatches()
        let elapsed = Date().timeIntervalSince(start)

        #expect(viewModel.transcriptionState.confirmedSegments.count == segmentCount)
        #expect(viewModel.transcriptionState.confirmedSegments[0].text.hasPrefix("hi"))
        #expect(viewModel.transcriptionResult?.segments.last?.text.hasPrefix("hi") == true)
        #expect(viewModel.uiState.subtitleQualityIssues.isEmpty)
        #expect(elapsed < 2.5)
    }

    @Test("파형 계산 대용량 샘플 성능 스모크")
    func testWaveformComputationHandlesLargeBuffers() throws {
        let sampleCount = 16_000 * 60
        let samples = (0 ..< sampleCount).map { index in
            Float((index % 200) - 100) / 100
        }

        let start = Date()
        let waveform = ContentViewModel.computeWaveform(from: samples)
        let elapsed = Date().timeIntervalSince(start)

        #expect(waveform.count == Int(ceil(Double(sampleCount) / 1024.0)))
        #expect(waveform.allSatisfy { $0.isFinite && $0 >= 0 })
        #expect(elapsed < 1.5)
    }

    @Test("스트리밍 파형 계산은 전체 Float 배열 없이 파일에서 계산")
    func testStreamingWaveformComputationFromAudioFile() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionMateWaveform-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let audioURL = directoryURL.appendingPathComponent("waveform.caf")
        let sampleRate: Double = 16_000
        let frameCount = AVAudioFrameCount(2_048)
        let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 1
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        let channel = buffer.floatChannelData![0]
        for index in 0 ..< Int(frameCount) {
            channel[index] = index < 1_024 ? 1.0 : 0.5
        }

        let audioFile = try AVAudioFile(forWriting: audioURL, settings: format.settings)
        try audioFile.write(from: buffer)

        let waveform = try ContentViewModel.computeWaveform(fromAudioURL: audioURL)

        #expect(waveform.count == 2)
        #expect(abs(waveform[0] - 1.0) < 0.001)
        #expect(abs(waveform[1] - 0.5) < 0.001)
    }
}

// MARK: - Subtitle Quality Tests

struct SubtitleQualityCheckerTests {
    @Test("자막 품질 검사 경고와 에러 테스트")
    func testSubtitleQualityCheckerFindsCommonIssues() throws {
        let issues = SubtitleQualityChecker.check(segments: [
            TranscriptionSegment(start: 0, end: 0.4, text: "This subtitle is far too fast to read comfortably"),
            TranscriptionSegment(start: 0.3, end: 2.0, text: ""),
            TranscriptionSegment(start: 3.0, end: 2.0, text: "bad timing"),
        ])

        #expect(issues.contains { $0.kind == .shortDuration })
        #expect(issues.contains { $0.kind == .highReadingSpeed })
        #expect(issues.contains { $0.kind == .overlappingTiming })
        #expect(issues.contains { $0.kind == .emptyText })
        #expect(issues.contains { $0.kind == .invalidTiming && $0.severity == .error })
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

// MARK: - FCPXML Writer Tests

struct FCPXMLWriterTests {
    @Test("FCPXML 특수문자 이스케이프 테스트")
    func testFCPXMLWriterEscapesXMLSpecialCharacters() throws {
        let subtitleText = "A&B <C> \"quote\""
        let xml = try writeFCPXML(
            segments: [
                TranscriptionSegment(start: 0, end: 1.5, text: subtitleText),
            ],
            frameRate: 30,
            fileName: "fcpxml_escape_test"
        )

        #expect(xml.contains("A&amp;B &lt;C&gt; &quot;quote&quot;"))
        #expect(!xml.contains("<text-style ref=\"ts1\">A&B <C> \"quote\"</text-style>"))

        let document = try XMLDocument(xmlString: xml)
        let textStyleNodes = try document.nodes(forXPath: "//text-style")
        #expect(textStyleNodes.first?.stringValue == subtitleText)
    }

    @Test("FCPXML 29.97fps fractional seconds 테스트")
    func testFCPXMLWriterUsesReasonableFractionalSecondsFor2997FPS() throws {
        let xml = try writeFCPXML(
            segments: [
                TranscriptionSegment(start: 0.5, end: 1.0, text: "half second"),
            ],
            frameRate: 29.97,
            fileName: "fcpxml_2997_test"
        )

        #expect(xml.contains("frameDuration=\"1001/30000s\""))

        let document = try XMLDocument(xmlString: xml)
        let titleNodes = try document.nodes(forXPath: "//title")
        guard let title = titleNodes.first as? XMLElement else {
            Issue.record("FCPXML should contain a title element.")
            return
        }

        guard let offsetString = title.attribute(forName: "offset")?.stringValue,
              let durationString = title.attribute(forName: "duration")?.stringValue,
              let offset = seconds(fromFCPXMLTime: offsetString),
              let duration = seconds(fromFCPXMLTime: durationString) else {
            Issue.record("FCPXML title should contain parseable offset and duration values.")
            return
        }

        #expect(offsetString.contains("/") || offsetString.contains("."))
        #expect(durationString.contains("/") || durationString.contains("."))
        #expect(offset >= 0.4)
        #expect(offset <= 0.6)
        #expect(duration >= 0.4)
        #expect(duration <= 0.6)
    }

    @Test("FCPXML 공백 세그먼트 처리 테스트")
    func testFCPXMLWriterSkipsBlankSegmentsWithoutCrashing() throws {
        let xml = try writeFCPXML(
            segments: [
                TranscriptionSegment(start: 0, end: 1, text: ""),
                TranscriptionSegment(start: 1, end: 2, text: " \n\t "),
            ],
            frameRate: 30,
            fileName: "fcpxml_blank_segments_test"
        )

        #expect(xml.contains("<fcpxml version=\"1.9\">"))
        #expect(!xml.contains("<title "))
        _ = try XMLDocument(xmlString: xml)
    }

    @Test("FCPXML writer는 저장 파일명이 출력 폴더 밖으로 벗어나지 못하게 한다")
    func testFCPXMLWriterRejectsPathTraversalFileName() throws {
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionMateFCPXML-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: outputDirectory)
            try? FileManager.default.removeItem(
                at: outputDirectory.deletingLastPathComponent().appendingPathComponent("escape.fcpxml")
            )
        }

        let writer = WriteFCPXML(outputDir: outputDirectory.path, frameRate: 30)
        let result = TranscriptionResult(
            text: "escape",
            segments: [TranscriptionSegment(start: 0, end: 1, text: "escape")],
            language: "en",
            timings: TranscriptionTimings()
        )

        switch writer.write(result: result, to: "../escape", options: nil) {
        case .success:
            Issue.record("Path traversal file names should not be accepted.")
        case .failure:
            #expect(!FileManager.default.fileExists(
                atPath: outputDirectory.deletingLastPathComponent()
                    .appendingPathComponent("escape.fcpxml")
                    .path
            ))
        }
    }

    @Test("FCPXML writer는 비정상 프레임레이트를 거부한다")
    func testFCPXMLWriterRejectsInvalidFrameRates() throws {
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionMateFCPXML-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: outputDirectory)
        }

        for frameRate in [0.0, -24.0, Double.nan, Double.infinity] {
            let writer = WriteFCPXML(outputDir: outputDirectory.path, frameRate: frameRate)
            let result = TranscriptionResult(
                text: "invalid",
                segments: [TranscriptionSegment(start: 0, end: 1, text: "invalid")],
                language: "en",
                timings: TranscriptionTimings()
            )

            switch writer.write(result: result, to: "invalid", options: nil) {
            case .success:
                Issue.record("Invalid frame rate should not be accepted: \(frameRate)")
            case .failure:
                continue
            }
        }
    }

    private func writeFCPXML(
        segments: [TranscriptionSegment],
        frameRate: Double,
        fileName: String
    ) throws -> String {
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionMateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory,
                                                withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: outputDirectory)
        }

        let result = TranscriptionResult(
            text: segments.map { $0.text }.joined(separator: " "),
            segments: segments,
            language: "ko",
            timings: TranscriptionTimings()
        )
        let writer = WriteFCPXML(outputDir: outputDirectory.path, frameRate: frameRate)

        switch writer.write(result: result, to: fileName, options: nil) {
        case .success:
            let outputURL = outputDirectory.appendingPathComponent("\(fileName).fcpxml")
            return try String(contentsOf: outputURL, encoding: .utf8)
        case let .failure(error):
            throw error
        }
    }

    private func seconds(fromFCPXMLTime value: String) -> Double? {
        guard value.hasSuffix("s") else { return nil }

        let timeValue = String(value.dropLast())
        if let seconds = Double(timeValue) {
            return seconds
        }

        let parts = timeValue.split(separator: "/")
        guard parts.count == 2,
              let numerator = Double(parts[0]),
              let denominator = Double(parts[1]),
              denominator != 0 else {
            return nil
        }
        return numerator / denominator
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
        #expect(state.speakerAssignments.isEmpty)
        #expect(state.speakerNames.isEmpty)
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
        #expect(state.isWaveformProcessing == false)
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
        #expect(state.userMessage == nil)
        #expect(state.subtitleQualityIssues.isEmpty)
        #expect(state.showSubtitleReview == false)
        #expect(state.focusedSubtitleSegmentIndex == nil)
        #expect(state.subtitleIssueFilter == .all)
        #expect(state.showFirstRunGuide == false)
        #expect(state.subtitleSearchText.isEmpty)
        #expect(state.subtitleReplaceText.isEmpty)
    }
}

// MARK: - Localization Catalog Tests

struct LocalizationCatalogTests {
    private let supportedLocales = [
        "de",
        "en",
        "en-GB",
        "es",
        "fr",
        "hi",
        "ja",
        "ko",
        "pt-BR",
        "zh-Hans",
    ]

    private let requiredStatusDetailKeys = [
        "All segments are empty.",
        "Cannot check disk space.",
        "Document directory not found.",
        "Download cancelled.",
        "No imported audio file.",
        "No speakers detected.",
        "No subtitles are ready.",
        "Open the listed segment to adjust it manually.",
        "Speaker model is not ready.",
        "Speaker model is still preparing.",
    ]

    private let requiredCriticalUIKeys = [
        "App Version: %@ (%@)",
        "Audio Encoder",
        "Audio",
        "Auto Language",
        "Compute Units",
        "Default offline model · %@",
        "Download Model",
        "Downloading",
        "Drag and drop a file here",
        "Fix quality warnings before export.",
        "Import Files",
        "Import one file or a batch queue.",
        "Language Changed",
        "Later",
        "Load Model",
        "Manage Models",
        "Models",
        "Offline model is ready",
        "Ready CaptionMate",
        "Recommended model",
        "Recommended model is local",
        "Settings",
        "Speaker diarization",
        "Source Language",
        "Start Transcription",
        "Subtitle review",
        "Text Decoder",
        "The language has been changed.",
        "Transcribe",
        "Translate",
    ]

    private let requiredMenuAndModelManagementKeys = [
        "available_models",
        "Current Language: %@",
        "decoding_options",
        "decoding_quality",
        "downloaded_models",
        "downloading_models",
        "downloading_models_count %lld",
        "downloading_status",
        "error.cannot_connect_to_server",
        "error.disk_space_full",
        "error.file_not_found",
        "error.network_lost",
        "error.network_offline",
        "error.permission_denied",
        "error.timeout",
        "format_and_preview",
        "Language",
        "loading_model_list",
        "manage_models",
        "model_info",
        "performance",
        "privacy_policy",
        "search_models",
        "security_policy",
        "Shortcuts",
        "speaker_diarization_model",
        "Theme",
        "theme.auto",
        "theme.dark",
        "theme.light",
        "third_party_notices",
        "total_models",
        "Volume Down",
        "Volume Up",
    ]

    private let rawKeySensitiveKeys = [
        "available_models",
        "decoding_options",
        "decoding_quality",
        "downloaded_models",
        "downloading_models",
        "downloading_models_count %lld",
        "downloading_status",
        "error.cannot_connect_to_server",
        "error.disk_space_full",
        "error.file_not_found",
        "error.network_lost",
        "error.network_offline",
        "error.permission_denied",
        "error.timeout",
        "format_and_preview",
        "loading_model_list",
        "manage_models",
        "model_info",
        "performance",
        "privacy_policy",
        "search_models",
        "security_policy",
        "speaker_diarization_model",
        "theme.auto",
        "theme.dark",
        "theme.light",
        "third_party_notices",
        "total_models",
    ]

    @Test("사용자 상태 메시지 detail 문구는 지원 언어 catalog에 존재해야 한다")
    func testStatusMessageDetailKeysAreLocalized() throws {
        try assertKeysAreLocalized(requiredStatusDetailKeys)
    }

    @Test("첫 실행 및 핵심 UI 문구는 지원 언어 catalog에 존재해야 한다")
    func testCriticalUIKeysAreLocalized() throws {
        try assertKeysAreLocalized(requiredCriticalUIKeys)
    }

    @Test("메뉴와 모델 관리 문구는 지원 언어 catalog에 존재해야 한다")
    func testMenuAndModelManagementKeysAreLocalized() throws {
        try assertKeysAreLocalized(requiredMenuAndModelManagementKeys)
    }

    @Test("내부 localization key가 사용자 화면에 그대로 노출되지 않아야 한다")
    func testRawLocalizationKeysAreNotDisplayed() throws {
        let strings = try catalogStrings()

        for key in rawKeySensitiveKeys {
            let entry = try #require(strings[key] as? [String: Any], "\(key) is missing")
            let localizations = try #require(
                entry["localizations"] as? [String: Any],
                "\(key) has no localizations"
            )

            for locale in supportedLocales {
                let localization = try #require(
                    localizations[locale] as? [String: Any],
                    "\(key) is missing \(locale)"
                )
                let stringUnit = try #require(
                    localization["stringUnit"] as? [String: Any],
                    "\(key) has no stringUnit for \(locale)"
                )
                let value = try #require(
                    stringUnit["value"] as? String,
                    "\(key) has no value for \(locale)"
                )
                #expect(value != key, "\(key) renders raw key in \(locale)")
            }
        }
    }

    private func assertKeysAreLocalized(_ requiredKeys: [String]) throws {
        let strings = try catalogStrings()

        for key in requiredKeys {
            let entry = try #require(strings[key] as? [String: Any], "\(key) is missing")
            let localizations = try #require(
                entry["localizations"] as? [String: Any],
                "\(key) has no localizations"
            )

            for locale in supportedLocales {
                #expect(localizations[locale] != nil, "\(key) is missing \(locale)")
            }
        }
    }

    private func catalogStrings() throws -> [String: Any] {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let catalogURL = projectRoot
            .appendingPathComponent("CaptionMate")
            .appendingPathComponent("Localizable.xcstrings")

        let data = try Data(contentsOf: catalogURL)
        let root = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        return try #require(root["strings"] as? [String: Any])
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

// MARK: - Release Gate Tests

struct ReleaseGateTests {
    @Test("v2 릴리스 버전과 빌드 번호가 프로젝트 설정에 반영되어야 한다")
    func testProjectVersionIsPreparedForV2Release() throws {
        let project = try Self.readRepositoryFile("CaptionMate/CaptionMate.xcodeproj/project.pbxproj")

        #expect(project.contains("MARKETING_VERSION = 2.0.0;"))
        #expect(!project.contains("MARKETING_VERSION = 1.0;"))
        #expect(!project.contains("CURRENT_PROJECT_VERSION = 1;"))
    }

    @Test("ContentViewModel은 UI 상태를 MainActor에 격리하고 장시간 다운로드는 detached worker로 실행한다")
    func testContentViewModelConcurrencyReleaseGate() throws {
        let source = try Self.readRepositoryFile(
            "CaptionMate/CaptionMate/Source/Presentation/ViewModels/ContentViewModel.swift"
        )

        #expect(source.contains("@MainActor\nclass ContentViewModel"))
        #expect(source.contains("speakerDiarizationModelTask = Task.detached(priority: .background)"))
        #expect(source.contains("let task = Task.detached(priority: .background)"))
        #expect(source.contains("try Task.checkCancellation()"))
    }

    private static func readRepositoryFile(_ relativePath: String) throws -> String {
        let url = try repositoryRoot().appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func repositoryRoot() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fileManager = FileManager.default

        while directory.path != "/" {
            if fileManager.fileExists(atPath: directory.appendingPathComponent(".git").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }

        throw CocoaError(.fileNoSuchFile)
    }
}

final class OversizedRemoteSizeURLProtocol: URLProtocol {
    static var responseData = Data()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://huggingface.co")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: [
                "Content-Length": "\(Self.responseData.count)",
            ]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
