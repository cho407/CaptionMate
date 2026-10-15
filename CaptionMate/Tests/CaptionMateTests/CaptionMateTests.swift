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
import Combine
import CryptoKit
import Foundation
import SwiftUI
import Testing
import UniformTypeIdentifiers
import WhisperKit
import XCTest

// MARK: - ContentViewModel Tests

private actor SuspendedTestValue<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Never>?
    private var observers: [CheckedContinuation<Void, Never>] = []

    func value() async -> Value {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            observers.forEach { $0.resume() }
            observers.removeAll()
        }
    }

    func waitUntilRequested() async {
        if continuation != nil { return }
        await withCheckedContinuation { observers.append($0) }
    }

    func resume(returning value: Value) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}

private final class TestWindowCloseDelegate: NSObject, NSWindowDelegate {
    var allowsClose = false
    var closeRequestCount = 0
    var willCloseCount = 0

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        closeRequestCount += 1
        return allowsClose
    }

    func windowWillClose(_ notification: Notification) {
        willCloseCount += 1
    }
}

@Suite(.serialized)
struct ContentViewModelTests {
    private func makeCancellableTask() -> Task<Void, Never> {
        Task.detached {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
            }
        }
    }

    private func writeValidSpeakerModelFixture(at rootURL: URL) throws {
        for relativePath in SpeakerDiarizationModelStore.requiredRelativeFilePaths {
            let fileURL = rootURL.appendingPathComponent(relativePath)
            let expectedSize = SpeakerDiarizationModelStore.requiredFileSizes[relativePath] ?? 0
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if relativePath.hasSuffix("metadata.json") {
                var data = Data("[{}]".utf8)
                data.append(Data(repeating: 0x20, count: max(expectedSize - data.count, 0)))
                try data.write(to: fileURL)
            } else {
                try Data(repeating: 1, count: expectedSize).write(to: fileURL)
            }
        }
    }

    private func speakerModelFixtureChecksums(at rootURL: URL) throws -> [String: String] {
        try Dictionary(uniqueKeysWithValues: SpeakerDiarizationModelStore.requiredRelativeFilePaths.map {
            relativePath in
            let data = try Data(contentsOf: rootURL.appendingPathComponent(relativePath))
            let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return (relativePath, checksum)
        })
    }

    @Test("ContentViewModel 초기화 테스트") @MainActor
    func testContentViewModelInitialization() throws {
        let viewModel = ContentViewModel()

        // 기본 상태 확인
        #expect(viewModel.whisperKit == nil)
        #expect(viewModel.modelManagementState.modelState == .unloaded)
        #expect(viewModel.audioState.isTranscribing == false)

        // 기본 설정 확인
        #expect(viewModel.enablePromptPrefill == true)
        #expect(viewModel.temperatureStart >= 0.0)
        #expect(viewModel.temperatureStart <= 1.0)
    }

    private func drainDecoderPreviewQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @Test("Obsolete decoder callbacks cannot change another document's preview",
          arguments: ["cancel", "cancelTask", "reset", "restart"]) @MainActor
    func testObsoleteDecoderPreviewIsIgnored(transition: String) async {
        let viewModel = ContentViewModel()
        let originalTask = viewModel.selectedTask
        defer {
            viewModel.prepareForClose()
            viewModel.selectedTask = originalTask
        }
        viewModel.selectedTask = "transcribe"
        viewModel.setTranscriptionTaskForTesting(makeCancellableTask())
        let oldCallback = viewModel.decodingCallbackForTesting()
        let progress = TranscriptionProgress(
            timings: TranscriptionTimings(totalDecodingFallbacks: 3),
            text: "Obsolete preview", tokens: [], windowId: 7
        )
        // Queue publication, then revoke ownership before the main queue can publish.
        _ = oldCallback(progress)
        if transition == "cancelTask" {
            viewModel.transcriptionTaskForTesting?.cancel()
        } else if transition == "cancel" {
            viewModel.cancelTranscription()
        } else {
            viewModel.resetState()
        }
        if transition == "restart" {
            viewModel.setTranscriptionTaskForTesting(makeCancellableTask())
        }
        viewModel.selectedTask = "translate"
        viewModel.transcriptionState.currentText = "Current document"
        viewModel.transcriptionState.currentChunks = [9: (["Current document"], 2)]
        viewModel.transcriptionState.currentFallbacks = 2
        viewModel.transcriptionState.currentDecodingLoops = 11
        // Also release a callback retained by the decoder after cancellation.
        _ = oldCallback(progress)
        await drainDecoderPreviewQueue()
        #expect(viewModel.transcriptionState.currentText == "Current document")
        #expect(viewModel.transcriptionState.currentChunks.keys.sorted() == [9])
        #expect(viewModel.transcriptionState.currentChunks[9]?.chunkText == ["Current document"])
        #expect(viewModel.transcriptionState.currentChunks[9]?.fallbacks == 2)
        #expect(viewModel.transcriptionState.currentFallbacks == 2)
        #expect(viewModel.transcriptionState.currentDecodingLoops == 11)
        #expect(viewModel.selectedTask == "translate")
        if transition == "restart" {
            let currentCallback = viewModel.decodingCallbackForTesting()
            _ = currentCallback(TranscriptionProgress(
                timings: TranscriptionTimings(totalDecodingFallbacks: 4),
                text: "New preview", tokens: [], windowId: 7
            ))
            await drainDecoderPreviewQueue()
            #expect(viewModel.transcriptionState.currentText == "New preview\nCurrent document")
            #expect(viewModel.transcriptionState.currentChunks.keys.sorted() == [7, 9])
            #expect(viewModel.transcriptionState.currentChunks[7]?.chunkText == ["New preview"])
            #expect(viewModel.transcriptionState.currentChunks[7]?.fallbacks == 4)
            #expect(viewModel.transcriptionState.currentFallbacks == 4)
            #expect(viewModel.transcriptionState.currentDecodingLoops == 12)
        }
    }

    @Test("Current decoder callbacks use the captured decoding mode",
          arguments: ["transcribe", "translate"]) @MainActor
    func testCurrentDecoderPreviewCapturesMode(mode: String) async {
        let viewModel = ContentViewModel()
        let originalTask = viewModel.selectedTask
        defer {
            viewModel.prepareForClose()
            viewModel.selectedTask = originalTask
        }
        viewModel.selectedTask = mode
        viewModel.setTranscriptionTaskForTesting(makeCancellableTask())
        let callback = viewModel.decodingCallbackForTesting()
        viewModel.selectedTask = mode == "transcribe" ? "translate" : "transcribe"
        _ = callback(TranscriptionProgress(
            timings: TranscriptionTimings(totalDecodingFallbacks: 2),
            text: "Current preview", tokens: [], windowId: 7
        ))
        await drainDecoderPreviewQueue()
        let chunkID = mode == "transcribe" ? 0 : 7
        #expect(viewModel.transcriptionState.currentText == "Current preview")
        #expect(viewModel.transcriptionState.currentChunks.keys.sorted() == [chunkID])
        #expect(viewModel.transcriptionState.currentChunks[chunkID]?.chunkText == ["Current preview"])
        #expect(viewModel.transcriptionState.currentChunks[chunkID]?.fallbacks == 2)
        #expect(viewModel.transcriptionState.currentFallbacks == 2)
        #expect(viewModel.transcriptionState.currentDecodingLoops == 1)
    }

    @Test("A decoder callback created without an active run never acquires preview ownership",
          arguments: [false, true]) @MainActor
    func testUnownedDecoderPreviewIsIgnored(startNewRun: Bool) async {
        let viewModel = ContentViewModel()
        defer { viewModel.prepareForClose() }
        let callback = viewModel.decodingCallbackForTesting()
        if startNewRun { viewModel.setTranscriptionTaskForTesting(makeCancellableTask()) }
        viewModel.transcriptionState.currentText = "Keep preview"
        viewModel.transcriptionState.currentChunks = [4: (["Keep preview"], 1)]
        viewModel.transcriptionState.currentFallbacks = 1
        viewModel.transcriptionState.currentDecodingLoops = 5
        _ = callback(TranscriptionProgress(
            timings: TranscriptionTimings(totalDecodingFallbacks: 3),
            text: "Unowned", tokens: [], windowId: 7
        ))
        await drainDecoderPreviewQueue()
        #expect(viewModel.transcriptionState.currentText == "Keep preview")
        #expect(viewModel.transcriptionState.currentChunks.keys.sorted() == [4])
        #expect(viewModel.transcriptionState.currentChunks[4]?.chunkText == ["Keep preview"])
        #expect(viewModel.transcriptionState.currentChunks[4]?.fallbacks == 1)
        #expect(viewModel.transcriptionState.currentFallbacks == 1)
        #expect(viewModel.transcriptionState.currentDecodingLoops == 5)
    }

    @Test("Cancellation before the transcription task starts cannot revive a run") @MainActor
    func testCancelledTranscriptionDoesNotStartDelayedBody() async throws {
        let viewModel = ContentViewModel()
        defer { viewModel.prepareForClose() }
        viewModel.transcribeFile(path: "/nonexistent/cancelled-captionmate-preview.wav")
        let task = try #require(viewModel.transcriptionTaskForTesting)
        viewModel.cancelTranscription()
        await task.value
        #expect(!viewModel.audioState.isTranscribing)
        #expect(viewModel.transcriptionState.currentText.isEmpty)
        #expect(viewModel.transcriptionState.currentChunks.isEmpty)
    }

    @Test("모델 언어 목록이 준비되지 않으면 언어 선택은 placeholder 상태를 사용한다")
    func testTranscriptionLanguageSelectionUsesPlaceholderUntilModelIsReady() {
        #expect(
            TranscriptionLanguageSelection.resolvedValue(
                selectedLanguage: "english",
                availableLanguages: []
            ) == nil
        )
        #expect(
            TranscriptionLanguageSelection.resolvedValue(
                selectedLanguage: "english",
                availableLanguages: ["english", "korean"]
            ) == "english"
        )
        #expect(
            TranscriptionLanguageSelection.resolvedValue(
                selectedLanguage: "legacy-language",
                availableLanguages: ["english", "korean"]
            ) == nil
        )
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

        viewModel.changeAppLanguage(to: "ar")
        #expect(viewModel.appLanguage == "ar")

        viewModel.changeAppLanguage(to: "zh-Hans")
        #expect(viewModel.appLanguage == "zh-Hans")
    }

    @Test("빠른 언어 변경은 지연 알림 작업을 하나로 합친다") @MainActor
    func testRapidLanguageChangesCoalesceDelayedNotification() async throws {
        let viewModel = ContentViewModel()
        var languageChangedValues: [Bool] = []

        let cancellable = viewModel.$uiState
            .map(\.isLanguageChanged)
            .removeDuplicates()
            .sink { value in
                languageChangedValues.append(value)
            }

        viewModel.changeAppLanguage(to: "ko")
        viewModel.changeAppLanguage(to: "ja")
        viewModel.changeAppLanguage(to: "es")

        for _ in 0 ..< 20 {
            if languageChangedValues.count >= 2 {
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        try await Task.sleep(nanoseconds: 250_000_000)

        #expect(languageChangedValues == [false, true])

        _ = cancellable
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

        viewModel.changeAppLanguage(to: "ar")
        #expect(viewModel.getCurrentLanguageDisplayName() == "العربية")

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
            "ar",
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
            AppLanguageOption(code: "ar", displayName: "العربية"),
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
                from: ["ar-SA"],
                supportedLanguages: supportedLanguages
            ) == "ar"
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

    @Test("자막 편집 적용 후 읽기 모드로 복귀한다") @MainActor
    func testApplyingSubtitleEditsReturnsToCompletedPresentation() throws {
        let viewModel = ContentViewModel()
        let segment = TranscriptionSegment(start: 0, end: 1, text: "original")
        viewModel.transcriptionResult = TranscriptionResult(
            text: segment.text,
            segments: [segment],
            language: "en",
            timings: TranscriptionTimings()
        )
        viewModel.transcriptionState.confirmedSegments = [segment]

        #expect(viewModel.uiState.isSubtitleEditing == false)

        viewModel.beginSubtitleEditing()
        #expect(viewModel.uiState.isSubtitleEditing)

        viewModel.updateTranscriptionSegmentText(at: 0, text: "edited")
        viewModel.applySubtitleEdits()

        #expect(viewModel.uiState.isSubtitleEditing == false)
        #expect(viewModel.transcriptionState.confirmedSegments[0].text == "edited")
        #expect(viewModel.transcriptionResult?.text == "edited")
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

    @Test("A never-saved transcript requires confirmation before replacement") @MainActor
    func testNewTranscriptRequiresSaveConfirmation() {
        let viewModel = ContentViewModel()
        #expect(!viewModel.hasUnsavedProjectChanges)
        viewModel.transcriptionState.confirmedSegments = [
            TranscriptionSegment(start: 0, end: 1, text: "New meeting"),
        ]
        #expect(viewModel.hasUnsavedProjectChanges)
        #expect(viewModel.shouldConfirmOpeningProject(id: "another-project"))
    }

    @Test("Cancel and a failed save both preserve the current transcript") @MainActor
    func testFailedSaveAndCancelDoNotAuthorizeReplacement() throws {
        let invalidRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionMateInvalidStore-\(UUID().uuidString)")
        try Data("not a directory".utf8).write(to: invalidRoot)
        defer { try? FileManager.default.removeItem(at: invalidRoot) }
        let viewModel = ContentViewModel(projectStore: CaptionMateProjectStore(rootURL: invalidRoot))
        viewModel.transcriptionState.confirmedSegments = [
            TranscriptionSegment(start: 0, end: 1, text: "Keep me"),
        ]
        let audioURL = URL(fileURLWithPath: "/tmp/current-meeting.wav")
        viewModel.audioState.importedAudioURL = audioURL
        #expect(!viewModel.resolveUnsavedProjectChanges(.cancel))
        #expect(!viewModel.resolveUnsavedProjectChanges(.save))
        #expect(viewModel.transcriptionState.confirmedSegments.first?.text == "Keep me")
        #expect(viewModel.audioState.importedAudioURL == audioURL)
        #expect(viewModel.hasUnsavedProjectChanges)
    }

    @Test("Delayed speaker reanalysis never overwrites a manual correction") @MainActor
    func testDelayedSpeakerAnalysisPreservesManualCorrection() async throws {
        let gate = SuspendedTestValue<[SpeakerTimelineSegment]>()
        let viewModel = ContentViewModel(speakerAnalyzer: { _, _, _ in await gate.value() })
        let wasEnabled = viewModel.enableSpeakerDiarization
        defer {
            viewModel.prepareForClose()
            viewModel.enableSpeakerDiarization = wasEnabled
        }
        viewModel.enableSpeakerDiarization = true
        viewModel.modelManagementState.speakerDiarizationModelState = .downloaded
        viewModel.transcriptionState.confirmedSegments = [
            TranscriptionSegment(start: 0, end: 1, text: "A turn"),
        ]
        viewModel.setSpeakerAssignment(at: 0, speakerID: 0)
        let startedTask = viewModel.beginSpeakerDiarization(audioSamplesProvider: { [0] })
        let task = try #require(startedTask)
        await gate.waitUntilRequested()
        viewModel.setSpeakerAssignment(at: 0, speakerID: 1)
        viewModel.setSpeakerName("Corrected", for: 1)
        await gate.resume(returning: [SpeakerTimelineSegment(speakerID: 0, start: 0, end: 1)])
        await task.value
        #expect(viewModel.speakerAssignment(forSegmentAt: 0)?.speakerID == 1)
        #expect(viewModel.speakerName(for: 1) == "Corrected")
        #expect(!viewModel.transcriptionState.speakerDiarization.isRunning)
    }

    @Test("A repeated analysis remaps names when clustering IDs are swapped") @MainActor
    func testSpeakerNamesFollowEquivalentTurnsInsteadOfClusterNumbers() async throws {
        let viewModel = ContentViewModel(speakerAnalyzer: { _, _, _ in
            [SpeakerTimelineSegment(speakerID: 1, start: 0, end: 1),
             SpeakerTimelineSegment(speakerID: 0, start: 1, end: 2)]
        })
        let wasEnabled = viewModel.enableSpeakerDiarization
        defer { viewModel.enableSpeakerDiarization = wasEnabled }
        viewModel.enableSpeakerDiarization = true
        viewModel.modelManagementState.speakerDiarizationModelState = .downloaded
        viewModel.transcriptionState.confirmedSegments = [
            TranscriptionSegment(start: 0, end: 1, text: "Host turn"),
            TranscriptionSegment(start: 1, end: 2, text: "Guest turn"),
        ]
        viewModel.setSpeakerAssignment(at: 0, speakerID: 0)
        viewModel.setSpeakerAssignment(at: 1, speakerID: 1)
        viewModel.setSpeakerName("Host", for: 0)
        viewModel.setSpeakerName("Guest", for: 1)
        let startedTask = viewModel.beginSpeakerDiarization(audioSamplesProvider: { [0] })
        let task = try #require(startedTask)
        await task.value
        #expect(viewModel.transcriptionState.speakerNames == [1: "Host", 0: "Guest"])
    }

    @Test("A confirmed speaker-model failure offers repair without losing existing labels") @MainActor
    func testSpeakerModelFailureEnablesRepair() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionMateSpeakerRepairState-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try writeValidSpeakerModelFixture(at: rootURL)
        let checksums = try speakerModelFixtureChecksums(at: rootURL)
        let relativePath = SpeakerDiarizationModelStore.requiredRelativeFilePaths[1]
        let size = try #require(SpeakerDiarizationModelStore.requiredFileSizes[relativePath])
        let fileURL = rootURL.appendingPathComponent(relativePath)
        try Data(repeating: 2, count: size).write(to: fileURL)
        let secondRelativePath = SpeakerDiarizationModelStore.requiredRelativeFilePaths[4]
        let secondSize = try #require(SpeakerDiarizationModelStore.requiredFileSizes[secondRelativePath])
        let secondFileURL = rootURL.appendingPathComponent(secondRelativePath)
        try Data(repeating: 2, count: secondSize).write(to: secondFileURL)
        let failure = try #require(SpeakerDiarizationModelStore.integrityFailure(
            for: rootURL, expectedFileSHA256: checksums
        ))
        let viewModel = ContentViewModel(speakerAnalyzer: { _, _, _ in
            throw SpeakerDiarizationServiceError.modelUnavailable(failure)
        }, speakerModelRootURL: rootURL)
        let wasEnabled = viewModel.enableSpeakerDiarization
        defer { viewModel.enableSpeakerDiarization = wasEnabled }
        viewModel.enableSpeakerDiarization = true
        viewModel.modelManagementState.speakerDiarizationModelState = .downloaded
        viewModel.transcriptionState.confirmedSegments = [
            TranscriptionSegment(start: 0, end: 1, text: "Keep my labels"),
        ]
        viewModel.setSpeakerAssignment(at: 0, speakerID: 1)
        viewModel.setSpeakerName("Guest", for: 1)
        let startedTask = viewModel.beginSpeakerDiarization(audioSamplesProvider: { [0] })
        let task = try #require(startedTask)
        await task.value
        #expect(viewModel.modelManagementState.speakerDiarizationModelNeedsRepair)
        #expect(!viewModel.isSpeakerDiarizationAvailable)
        #expect(viewModel.transcriptionState.speakerAssignments == [SpeakerSegmentAssignment(speakerID: 1)])
        #expect(viewModel.transcriptionState.speakerNames == [1: "Guest"])

        viewModel.refreshSpeakerDiarizationModelState()
        #expect(viewModel.modelManagementState.speakerDiarizationModelNeedsRepair)
        #expect(!viewModel.isSpeakerDiarizationAvailable)

        let healthyFileURL = rootURL.appendingPathComponent(SpeakerDiarizationModelStore.requiredRelativeFilePaths[0])
        let healthyData = try Data(contentsOf: healthyFileURL)
        try healthyData.write(to: healthyFileURL, options: .atomic)
        viewModel.refreshSpeakerDiarizationModelState()
        #expect(viewModel.modelManagementState.speakerDiarizationModelNeedsRepair)
        #expect(!viewModel.isSpeakerDiarizationAvailable)

        let repairTask = makeCancellableTask()
        defer { repairTask.cancel() }
        viewModel.modelManagementState.beginSpeakerDiarizationModelDownload(path: rootURL.path)
        let repairID = viewModel.setSpeakerDiarizationModelTaskForTesting(repairTask)
        viewModel.cancelDefaultSpeakerDiarizationModelDownload()
        viewModel.finishSpeakerModelDownloadForTesting(operationID: repairID, errorMessage: "Download cancelled.")
        #expect(viewModel.modelManagementState.speakerDiarizationModelNeedsRepair)
        #expect(!viewModel.isSpeakerDiarizationAvailable)
        #expect(!viewModel.ownsSpeakerModelDownloadForTesting(operationID: repairID))

        try Data(repeating: 1, count: size).write(to: fileURL, options: .atomic)
        viewModel.refreshSpeakerDiarizationModelState()
        #expect(viewModel.modelManagementState.speakerDiarizationModelNeedsRepair)
        #expect(!viewModel.isSpeakerDiarizationAvailable)

        try Data(repeating: 1, count: secondSize).write(to: secondFileURL, options: .atomic)
        viewModel.refreshSpeakerDiarizationModelState()
        #expect(!viewModel.modelManagementState.speakerDiarizationModelNeedsRepair)
        #expect(viewModel.isSpeakerDiarizationAvailable)
    }

    @Test("Stale or cancelled model diagnostics cannot mark repaired files damaged", arguments: [false, true]) @MainActor
    func testLateSpeakerModelDiagnosisIsIgnored(cancel: Bool) async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionMateStaleDiagnosis-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try writeValidSpeakerModelFixture(at: rootURL)
        let relativePath = SpeakerDiarizationModelStore.requiredRelativeFilePaths[1]
        let failure = SpeakerDiarizationModelFailure(
            rootURL: rootURL, invalidRelativePaths: [relativePath],
            fileSnapshot: SpeakerDiarizationModelStore.fileSnapshot(for: rootURL)
        )
        let gate = SuspendedTestValue<Bool>()
        let viewModel = ContentViewModel(speakerAnalyzer: { _, _, _ in
            _ = await gate.value()
            throw SpeakerDiarizationServiceError.modelUnavailable(failure)
        }, speakerModelRootURL: rootURL)
        let wasEnabled = viewModel.enableSpeakerDiarization
        defer { viewModel.enableSpeakerDiarization = wasEnabled }
        viewModel.enableSpeakerDiarization = true
        viewModel.modelManagementState.speakerDiarizationModelState = .downloaded
        viewModel.transcriptionState.confirmedSegments = [TranscriptionSegment(start: 0, end: 1, text: "Keep me")]
        let startedTask = viewModel.beginSpeakerDiarization(audioSamplesProvider: { [0] })
        let task = try #require(startedTask)
        await gate.waitUntilRequested()
        if cancel {
            viewModel.cancelSpeakerDiarization()
        } else {
            let fileURL = rootURL.appendingPathComponent(relativePath)
            let data = try Data(contentsOf: fileURL)
            try data.write(to: fileURL, options: .atomic)
        }
        await gate.resume(returning: true)
        await task.value
        #expect(!viewModel.modelManagementState.speakerDiarizationModelNeedsRepair)
        #expect(viewModel.isSpeakerDiarizationAvailable)
        #expect(viewModel.transcriptionState.speakerDiarization.errorMessage == nil)
    }

    @Test("An audio decoding error must not offer a speaker-model redownload") @MainActor
    func testAudioFailureDoesNotMarkSpeakerModelDamaged() async throws {
        let viewModel = ContentViewModel(speakerAnalyzer: { _, _, _ in
            Issue.record("Audio decoding failed before inference should run")
            return []
        })
        let wasEnabled = viewModel.enableSpeakerDiarization
        defer { viewModel.enableSpeakerDiarization = wasEnabled }
        viewModel.enableSpeakerDiarization = true
        viewModel.modelManagementState.speakerDiarizationModelState = .downloaded
        viewModel.transcriptionState.confirmedSegments = [
            TranscriptionSegment(start: 0, end: 1, text: "Keep me"),
        ]
        let startedTask = viewModel.beginSpeakerDiarization(audioSamplesProvider: {
            throw CocoaError(.fileReadCorruptFile)
        })
        let task = try #require(startedTask)
        await task.value
        #expect(!viewModel.modelManagementState.speakerDiarizationModelNeedsRepair)
        #expect(viewModel.isSpeakerDiarizationAvailable)
        #expect(viewModel.transcriptionState.speakerDiarization.errorMessage != nil)
        #expect(viewModel.transcriptionState.confirmedSegments.first?.text == "Keep me")
    }

    @Test("A late import is discarded after another document has been opened") @MainActor
    func testLateImportCannotReplaceNewerDocument() async throws {
        let gate = SuspendedTestValue<ContentViewModel.PreparedAudioImport>()
        let viewModel = ContentViewModel(audioImportPreparer: { _, _ in await gate.value() })
        let localURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionMateStaleImport-\(UUID().uuidString).wav")
        try Data("obsolete audio".utf8).write(to: localURL)
        defer {
            viewModel.prepareForClose()
            try? FileManager.default.removeItem(at: localURL)
        }
        let task = Task { await viewModel.processSelectedFile(localURL, needsSecurityScopedAccess: false) }
        await gate.waitUntilRequested()
        viewModel.resetState()
        viewModel.transcriptionState.confirmedSegments = [
            TranscriptionSegment(start: 0, end: 1, text: "Newer document"),
        ]
        viewModel.audioState.audioFileName = "Newer"
        await gate.resume(returning: .init(
            localURL: localURL, sourceURL: localURL, sourceBookmarkData: nil,
            displayName: "Obsolete", sidecar: nil, sidecarURL: nil, sidecarRestoreError: nil
        ))
        await task.value
        #expect(viewModel.transcriptionState.confirmedSegments.first?.text == "Newer document")
        #expect(viewModel.audioState.audioFileName == "Newer")
        #expect(!FileManager.default.fileExists(atPath: localURL.path))
    }

    @Test("Edits made while a dropped URL is resolving remain protected") @MainActor
    func testReservedImportProtectsEditsBeforePreparationStarts() async throws {
        let localURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionMateDelayedDrop-\(UUID().uuidString).wav")
        try Data("staged".utf8).write(to: localURL)
        let viewModel = ContentViewModel(audioImportPreparer: { url, _ in
            .init(localURL: url, sourceURL: url, sourceBookmarkData: nil,
                  displayName: "Dropped", sidecar: nil, sidecarURL: nil, sidecarRestoreError: nil)
        })
        defer { viewModel.prepareForClose(); try? FileManager.default.removeItem(at: localURL) }
        viewModel.transcriptionState.confirmedSegments = [
            TranscriptionSegment(start: 0, end: 1, text: "Before drop"),
        ]
        let operationID = viewModel.beginAudioImportOperation()
        viewModel.updateTranscriptionSegmentText(at: 0, text: "Edited while resolving")
        await viewModel.processSelectedFile(localURL, needsSecurityScopedAccess: false, operationID: operationID)
        #expect(viewModel.transcriptionState.confirmedSegments.first?.text == "Edited while resolving")
        #expect(!FileManager.default.fileExists(atPath: localURL.path))
    }

    @Test("Batch imports respect the latest selection and queue cancellation", arguments: [false, true]) @MainActor
    func testBatchImportCompletionOrderAndCancellation(clearQueue: Bool) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionMateBatchRace-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let firstURL = root.appendingPathComponent("first.wav")
        let secondURL = root.appendingPathComponent("second.wav")
        try Data("first".utf8).write(to: firstURL)
        try Data("second".utf8).write(to: secondURL)
        let firstGate = SuspendedTestValue<ContentViewModel.PreparedAudioImport>()
        let secondGate = SuspendedTestValue<ContentViewModel.PreparedAudioImport>()
        let viewModel = ContentViewModel(audioImportPreparer: { url, _ in
            if url == firstURL { return await firstGate.value() }
            return await secondGate.value()
        })
        defer { viewModel.resetState(); try? FileManager.default.removeItem(at: root) }
        func prepared(_ url: URL) -> ContentViewModel.PreparedAudioImport {
            .init(localURL: url, sourceURL: url, sourceBookmarkData: nil,
                  displayName: url.lastPathComponent, sidecar: nil, sidecarURL: nil, sidecarRestoreError: nil)
        }
        viewModel.setBatchQueue([firstURL, secondURL], needsSecurityScopedAccess: false)
        let first = Task { await viewModel.loadBatchItem(at: 0, confirmingChanges: false) }
        await firstGate.waitUntilRequested()
        let second = Task { await viewModel.loadBatchItem(at: 1, confirmingChanges: false) }
        await secondGate.waitUntilRequested()
        if clearQueue { viewModel.clearBatchQueue() }
        await secondGate.resume(returning: prepared(secondURL))
        await second.value
        await firstGate.resume(returning: prepared(firstURL))
        await first.value
        #expect(viewModel.currentBatchIndex == (clearQueue ? nil : 1))
        #expect(viewModel.audioState.importedAudioURL == (clearQueue ? nil : secondURL))
        #expect(!FileManager.default.fileExists(atPath: firstURL.path))
        #expect(FileManager.default.fileExists(atPath: secondURL.path) == !clearQueue)
    }

    @Test("Unavailable original audio stays linked when subtitles are edited and saved") @MainActor
    func testMissingOriginalAudioReferenceSurvivesSave() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionMateMissingAudio-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CaptionMateProjectStore(rootURL: root)
        let viewModel = ContentViewModel(projectStore: store)
        let missingURL = root.appendingPathComponent("temporarily-offline.wav")
        viewModel.audioState.sourceAudioURL = missingURL
        viewModel.transcriptionState.confirmedSegments = [
            TranscriptionSegment(start: 0, end: 1, text: "Saved"),
        ]
        let summary = try #require(viewModel.saveCurrentProject(showMessage: false))
        let reopened = ContentViewModel(projectStore: store)
        reopened.openProject(id: summary.id, showMessage: false)
        #expect(reopened.audioState.importedAudioURL == nil)
        #expect(!reopened.hasUnsavedProjectChanges)
        reopened.updateTranscriptionSegmentText(at: 0, text: "Edited offline")
        #expect(reopened.saveCurrentProject(showMessage: false) != nil)
        #expect(try store.load(id: summary.id).sourceAudioPath == missingURL.path)
    }

    @Test("Export and its recovery sidecar describe the same document snapshot") @MainActor
    func testExportSidecarKeepsOriginalSnapshotAcrossAwait() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionMateExportSnapshot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let exportURL = root.appendingPathComponent("original.txt")
        let gate = SuspendedTestValue<String>()
        let viewModel = ContentViewModel()
        let segments = [TranscriptionSegment(start: 0, end: 2, text: "Original meeting")]
        viewModel.transcriptionState.confirmedSegments = segments
        viewModel.transcriptionResult = TranscriptionResult(
            text: "Original meeting", segments: segments, language: "en", timings: TranscriptionTimings()
        )
        viewModel.audioState.audioFileName = "Original"
        let task = Task {
            await viewModel.exportTranscription(skipQualityReview: true) { result, name, _ in
                #expect(result.segments.first?.text.contains("Original meeting") == true)
                #expect(name == "Original")
                return .success(path: await gate.value())
            }
        }
        await gate.waitUntilRequested()
        viewModel.resetState()
        viewModel.transcriptionState.confirmedSegments = [
            TranscriptionSegment(start: 0, end: 2, text: "Another meeting"),
        ]
        viewModel.audioState.audioFileName = "Another"
        await gate.resume(returning: exportURL.path)
        await task.value
        let sidecar = try CaptionMateSidecarService.read(
            from: CaptionMateSidecarService.sidecarURL(forMediaURL: exportURL)
        )
        #expect(sidecar.audioFileName == "Original")
        #expect(sidecar.segments.first?.text == "Original meeting")
    }

    @Test("A cancelled speaker job keeps the previous assignments and names") @MainActor
    func testCancelledSpeakerJobKeepsExistingAttribution() async throws {
        let gate = SuspendedTestValue<[SpeakerTimelineSegment]>()
        let viewModel = ContentViewModel(speakerAnalyzer: { _, _, _ in await gate.value() })
        let wasEnabled = viewModel.enableSpeakerDiarization
        defer { viewModel.enableSpeakerDiarization = wasEnabled }
        viewModel.enableSpeakerDiarization = true
        viewModel.modelManagementState.speakerDiarizationModelState = .downloaded
        viewModel.transcriptionState.confirmedSegments = [
            TranscriptionSegment(start: 0, end: 1, text: "Original"),
        ]
        viewModel.setSpeakerAssignment(at: 0, speakerID: 1)
        viewModel.setSpeakerName("Host", for: 1)
        viewModel.transcriptionState.speakerDiarization = .init(
            progress: 1, detectedSpeakerCount: 2, errorMessage: "Previous review warning"
        )
        let startedTask = viewModel.beginSpeakerDiarization(audioSamplesProvider: { [0] })
        let task = try #require(startedTask)
        await gate.waitUntilRequested()
        viewModel.cancelSpeakerDiarization()
        await gate.resume(returning: [SpeakerTimelineSegment(speakerID: 0, start: 0, end: 1)])
        await task.value
        #expect(viewModel.speakerAssignment(forSegmentAt: 0)?.speakerID == 1)
        #expect(viewModel.speakerName(for: 1) == "Host")
        #expect(!viewModel.transcriptionState.speakerDiarization.isRunning)
        #expect(viewModel.transcriptionState.speakerDiarization.progress == 1)
        #expect(viewModel.transcriptionState.speakerDiarization.detectedSpeakerCount == 2)
        #expect(viewModel.transcriptionState.speakerDiarization.errorMessage == "Previous review warning")
    }

    @Test("Close cancellation, re-entry and close-to-quit reuse the same decision") @MainActor
    func testProjectCloseDecisionLifecycle() {
        let closeGuard = ProjectCloseGuard()
        closeGuard.confirmDiscardingChanges = { false }
        #expect(!closeGuard.confirmClose())
        #expect(closeGuard.applicationShouldTerminate(NSApplication.shared) == .terminateCancel)
        closeGuard.confirmDiscardingChanges = { [weak closeGuard] in
            #expect(closeGuard?.confirmClose() == false)
            return true
        }
        #expect(closeGuard.confirmClose())
        closeGuard.projectWindowDidClose()
        closeGuard.confirmDiscardingChanges = { false }
        #expect(closeGuard.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
        closeGuard.projectWindowDidOpen()
        #expect(closeGuard.applicationShouldTerminate(NSApplication.shared) == .terminateCancel)
    }

    @Test("The close coordinator preserves and restores the existing window delegate") @MainActor
    func testProjectCloseCoordinatorForwardsVetoAndRestoresDelegate() {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let original = TestWindowCloseDelegate()
        window.delegate = original
        let closeGuard = ProjectCloseGuard()
        closeGuard.confirmDiscardingChanges = { true }
        let first = ProjectWindowCloseGuard.Coordinator(closeGuard: closeGuard)
        first.attach(to: window)
        #expect(!first.windowShouldClose(window))
        #expect(original.closeRequestCount == 1)
        original.allowsClose = true
        #expect(first.windowShouldClose(window))
        first.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
        #expect(original.willCloseCount == 1)
        let replacement = ProjectWindowCloseGuard.Coordinator(closeGuard: closeGuard)
        replacement.attach(to: window)
        first.detach()
        #expect(window.delegate === replacement)
        closeGuard.confirmDiscardingChanges = { false }
        #expect(!replacement.windowShouldClose(window))
        #expect(original.closeRequestCount == 2)
        replacement.detach()
        #expect(window.delegate === original)
        window.delegate = nil
    }

    @Test("Deleting the last cue can be saved and reopened without resurrecting it") @MainActor
    func testEmptyEditedProjectCanBeSavedAndReopened() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionMateEmptyProject-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = CaptionMateProjectStore(rootURL: rootURL)
        let viewModel = ContentViewModel(projectStore: store)
        viewModel.transcriptionState.confirmedSegments = [
            TranscriptionSegment(start: 0, end: 1, text: "Remove me"),
        ]
        let original = try #require(viewModel.saveCurrentProject(showMessage: false))
        viewModel.deleteTranscriptionSegment(at: 0)
        #expect(viewModel.hasUnsavedProjectChanges)
        let saved = try #require(viewModel.saveCurrentProject(showMessage: false))
        #expect(saved.id == original.id)
        #expect(!viewModel.hasUnsavedProjectChanges)
        let reopened = ContentViewModel(projectStore: store)
        reopened.openProject(id: saved.id, showMessage: false)
        #expect(reopened.transcriptionState.confirmedSegments.isEmpty)
        #expect(!reopened.hasUnsavedProjectChanges)
    }

    @Test("Automatic speaker IDs beyond the manual count picker survive save and reopen") @MainActor
    func testAutomaticNinthSpeakerSurvivesProjectRoundTrip() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionMateManySpeakers-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = CaptionMateProjectStore(rootURL: rootURL)
        let viewModel = ContentViewModel(projectStore: store)
        viewModel.transcriptionState.confirmedSegments = [
            TranscriptionSegment(start: 0, end: 1, text: "Ninth participant"),
        ]
        viewModel.setSpeakerAssignment(at: 0, speakerID: 8)
        viewModel.setSpeakerName("Panelist", for: 8)
        let saved = try #require(viewModel.saveCurrentProject(showMessage: false))
        let reopened = ContentViewModel(projectStore: store)
        reopened.openProject(id: saved.id, showMessage: false)
        #expect(reopened.speakerAssignment(forSegmentAt: 0)?.speakerID == 8)
        #expect(reopened.speakerName(for: 8) == "Panelist")
        #expect(reopened.availableSpeakerIDs().contains(8))
    }

    @Test("전사 프로젝트는 앱 안에 저장, 재열기, 삭제가 가능하다") @MainActor
    func testSaveOpenAndDeleteTranscriptionProject() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionMateViewModelProject-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let audioURL = rootURL.appendingPathComponent("interview-local-copy.wav")
        let sourceAudioURL = rootURL.appendingPathComponent("interview-original.wav")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: audioURL)
        try Data("source-audio".utf8).write(to: sourceAudioURL)

        let store = CaptionMateProjectStore(rootURL: rootURL.appendingPathComponent("Projects", isDirectory: true))
        let viewModel = ContentViewModel(projectStore: store)
        let segments = [
            TranscriptionSegment(start: 0.0, end: 1.25, text: "Hello"),
            TranscriptionSegment(start: 1.25, end: 2.5, text: "World"),
        ]
        viewModel.transcriptionResult = TranscriptionResult(
            text: "Hello World",
            segments: segments,
            language: "en",
            timings: TranscriptionTimings()
        )
        viewModel.transcriptionState.confirmedSegments = segments
        viewModel.transcriptionState.speakerAssignments = [
            SpeakerSegmentAssignment(speakerID: 0),
            SpeakerSegmentAssignment(speakerID: 1),
        ]
        viewModel.transcriptionState.speakerNames = [0: "Host", 1: "Guest"]
        viewModel.transcriptionState.speakerDiarization = SpeakerDiarizationState(
            detectedSpeakerCount: 2
        )
        viewModel.audioState.audioFileName = "Interview"
        viewModel.audioState.importedAudioURL = audioURL
        viewModel.audioState.sourceAudioURL = sourceAudioURL
        viewModel.audioState.sourceAudioBookmarkData = Data("bookmark".utf8)
        viewModel.selectedExportPreset = .finalCut
        viewModel.frameRate = 29.97
        viewModel.includeSpeakerLabelsInExport = true
        viewModel.speakerDiarizationSpeakerCount = 2

        let summary = viewModel.saveCurrentProject(showMessage: false)
        #expect(summary?.displayName == "Interview")
        #expect(viewModel.projectLibraryState.summaries.count == 1)
        #expect(viewModel.projectLibraryState.activeProjectID == summary?.id)
        let savedProject = try store.load(id: summary?.id ?? "")
        #expect(savedProject.sourceAudioPath == sourceAudioURL.path)
        #expect(savedProject.sourceAudioBookmarkData == Data("bookmark".utf8))

        viewModel.updateTranscriptionSegmentText(at: 0, text: "Hello again")
        _ = viewModel.saveCurrentProject(showMessage: false)

        let restoredViewModel = ContentViewModel(projectStore: store)
        restoredViewModel.refreshProjectLibrary()
        #expect(restoredViewModel.projectLibraryState.summaries.map(\.id) == [summary?.id])

        restoredViewModel.openProject(id: summary?.id ?? "", showMessage: false)
        #expect(restoredViewModel.hasUnsavedProjectChanges == false)
        #expect(restoredViewModel.transcriptionState.confirmedSegments.map(\.text) == [
            "Hello again",
            "World",
        ])
        #expect(restoredViewModel.transcriptionState.speakerNames == [0: "Host", 1: "Guest"])
        #expect(restoredViewModel.selectedExportPreset == .finalCut)
        #expect(restoredViewModel.frameRate == 29.97)
        #expect(restoredViewModel.includeSpeakerLabelsInExport == true)
        #expect(restoredViewModel.speakerDiarizationSpeakerCount == 2)
        #expect(restoredViewModel.audioState.importedAudioURL == sourceAudioURL)
        #expect(restoredViewModel.audioState.sourceAudioURL == sourceAudioURL)
        #expect(restoredViewModel.audioState.sourceAudioBookmarkData == Data("bookmark".utf8))

        restoredViewModel.updateTranscriptionSegmentText(at: 1, text: "World again")
        #expect(restoredViewModel.hasUnsavedProjectChanges == true)

        _ = restoredViewModel.saveCurrentProject(showMessage: false)
        #expect(restoredViewModel.hasUnsavedProjectChanges == false)

        restoredViewModel.setSpeakerName("Producer", for: 1)
        #expect(restoredViewModel.hasUnsavedProjectChanges == true)

        let renamed = restoredViewModel.renameProject(
            id: summary?.id ?? "",
            displayName: "Client Review",
            showMessage: false
        )
        #expect(renamed == true)
        #expect(try store.load(id: summary?.id ?? "").displayName == "Client Review")
        #expect(restoredViewModel.projectLibraryState.activeProjectDisplayName == "Client Review")

        _ = restoredViewModel.saveCurrentProject(showMessage: false)
        #expect(try store.load(id: summary?.id ?? "").displayName == "Client Review")

        let reconnectedAudioURL = rootURL.appendingPathComponent("interview-reconnected.wav")
        try Data("reconnected-source-audio".utf8).write(to: reconnectedAudioURL)
        let reconnected = restoredViewModel.relinkProjectAudio(
            id: summary?.id ?? "",
            to: reconnectedAudioURL,
            needsSecurityScopedAccess: false,
            showMessage: false
        )
        #expect(reconnected == true)
        #expect(try store.load(id: summary?.id ?? "").sourceAudioPath == reconnectedAudioURL.path)
        #expect(restoredViewModel.audioState.sourceAudioURL == reconnectedAudioURL)
        #expect(restoredViewModel.audioState.importedAudioURL == reconnectedAudioURL)
        #expect(restoredViewModel.hasUnsavedProjectChanges == false)

        let duplicateSummary = try #require(restoredViewModel.duplicateProject(
            id: summary?.id ?? "",
            showMessage: false
        ))
        #expect(duplicateSummary.id != summary?.id)
        #expect(duplicateSummary.displayName == "Client Review Copy")
        #expect(try store.load(id: duplicateSummary.id).sidecar.segments.map(\.text) == [
            "Hello again",
            "World again",
        ])

        restoredViewModel.deleteProject(id: summary?.id ?? "", showMessage: false)
        #expect(restoredViewModel.projectLibraryState.summaries.map(\.id) == [duplicateSummary.id])
        #expect(restoredViewModel.projectLibraryState.activeProjectID == nil)
        // The remaining in-memory transcript is now an unsaved document.
        #expect(restoredViewModel.hasUnsavedProjectChanges == true)
    }

    @Test("저장된 프로젝트에 수정 사항이 있으면 열기 전에 확인하고 저장 후 열 수 있다") @MainActor
    func testOpeningProjectWithUnsavedChangesCanSaveFirst() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionMateViewModelOpenConfirm-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let store = CaptionMateProjectStore(rootURL: rootURL.appendingPathComponent("Projects", isDirectory: true))
        let viewModel = ContentViewModel(projectStore: store)
        let firstSegments = [
            TranscriptionSegment(start: 0.0, end: 1.0, text: "First project"),
        ]
        viewModel.transcriptionResult = TranscriptionResult(
            text: "First project",
            segments: firstSegments,
            language: "en",
            timings: TranscriptionTimings()
        )
        viewModel.transcriptionState.confirmedSegments = firstSegments
        viewModel.audioState.audioFileName = "First"

        let firstSummary = try #require(viewModel.saveCurrentProject(showMessage: false))
        let secondProject = CaptionMateProject(
            id: "second-project",
            displayName: "Second",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100),
            sourceAudioPath: nil,
            lastExportedAt: nil,
            sidecar: CaptionMateSidecar(
                version: CaptionMateSidecar.currentVersion,
                audioFileName: "Second",
                language: "en",
                segments: [.init(start: 0.0, end: 1.0, text: "Second project", speakerID: nil)],
                speakerNames: [:],
                exportSettings: .init(
                    selectedExportPreset: SubtitleExportPreset.general.rawValue,
                    frameRate: 30,
                    includeSpeakerLabelsInExport: false,
                    speakerDiarizationSpeakerCount: 0
                )
            )
        )
        try store.save(secondProject)
        viewModel.refreshProjectLibrary()

        viewModel.updateTranscriptionSegmentText(at: 0, text: "First project edited")
        #expect(viewModel.hasUnsavedProjectChanges == true)
        #expect(viewModel.shouldConfirmOpeningProject(id: firstSummary.id) == true)
        #expect(viewModel.shouldConfirmOpeningProject(id: secondProject.id) == true)

        let opened = viewModel.openProjectSavingCurrentChangesFirst(
            id: secondProject.id,
            showMessage: false
        )

        #expect(opened == true)
        #expect(viewModel.projectLibraryState.activeProjectID == secondProject.id)
        #expect(viewModel.transcriptionState.confirmedSegments.map(\.text) == ["Second project"])
        #expect(viewModel.hasUnsavedProjectChanges == false)
        #expect(try store.load(id: firstSummary.id).sidecar.segments.map(\.text) == ["First project edited"])
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

    @Test("자막 검토 이슈로 이동하면 편집 모드를 연다") @MainActor
    func testFocusingSubtitleIssueEntersEditingMode() throws {
        let viewModel = ContentViewModel()
        viewModel.transcriptionState.confirmedSegments = [
            TranscriptionSegment(start: 0, end: 0, text: ""),
        ]
        let issue = try #require(viewModel.refreshSubtitleQualityIssues().first)

        viewModel.focusSubtitleIssue(issue)

        #expect(viewModel.uiState.isSubtitleEditing)
        #expect(viewModel.uiState.focusedSubtitleSegmentIndex == issue.segmentIndex)
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

    @Test("화자분리 모델이 준비되지 않으면 기능을 활성화하지 않는다") @MainActor
    func testSpeakerDiarizationCannotBeEnabledBeforeModelIsReady() throws {
        let viewModel = ContentViewModel()
        let originalEnabled = viewModel.enableSpeakerDiarization
        defer {
            viewModel.enableSpeakerDiarization = originalEnabled
        }

        viewModel.enableSpeakerDiarization = false
        viewModel.modelManagementState.speakerDiarizationModelState = .unloaded
        viewModel.setSpeakerDiarizationEnabled(true)

        #expect(viewModel.enableSpeakerDiarization == false)
        #expect(viewModel.uiState.userMessage?.title == "Speaker Analysis Unavailable")
    }

    @Test("준비된 화자분리 모델이 있으면 기능을 활성화할 수 있다") @MainActor
    func testSpeakerDiarizationCanBeEnabledWhenModelIsReady() throws {
        let viewModel = ContentViewModel()
        let originalEnabled = viewModel.enableSpeakerDiarization
        defer {
            viewModel.enableSpeakerDiarization = originalEnabled
        }

        viewModel.enableSpeakerDiarization = false
        viewModel.modelManagementState.speakerDiarizationModelState = .downloaded
        viewModel.modelManagementState.speakerDiarizationModelNeedsRepair = false
        viewModel.setSpeakerDiarizationEnabled(true)

        #expect(viewModel.enableSpeakerDiarization)
    }

    @Test("화자분리를 꺼도 사용자가 편집한 화자 정보는 보존한다") @MainActor
    func testDisablingSpeakerDiarizationPreservesSpeakerEdits() throws {
        let viewModel = ContentViewModel()
        let originalEnabled = viewModel.enableSpeakerDiarization
        defer {
            viewModel.enableSpeakerDiarization = originalEnabled
        }

        viewModel.transcriptionState.confirmedSegments = [
            TranscriptionSegment(start: 0, end: 1, text: "Hello"),
        ]
        viewModel.transcriptionState.speakerAssignments = [
            SpeakerSegmentAssignment(speakerID: 0),
        ]
        viewModel.transcriptionState.speakerNames = [0: "Host"]
        viewModel.enableSpeakerDiarization = true

        viewModel.setSpeakerDiarizationEnabled(false)

        #expect(viewModel.transcriptionState.speakerAssignments == [
            SpeakerSegmentAssignment(speakerID: 0),
        ])
        #expect(viewModel.transcriptionState.speakerNames == [0: "Host"])
    }

    @Test("화자분리 모델 캐시 검증 테스트")
    func testSpeakerDiarizationModelValidationRequiresDefaultFiles() throws {
        #expect(SpeakerDiarizationModelStore.estimatedDownloadSize == 11_243_231)
        #expect(
            SpeakerDiarizationModelStore.downloadRevision ==
                "86ec9c929b52208b6656eb6a6361ed0d822a1f78"
        )
        #expect(
            Set(SpeakerDiarizationModelStore.requiredFileSHA256.keys) ==
                Set(SpeakerDiarizationModelStore.requiredRelativeFilePaths)
        )

        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionMateSpeakerModel-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        func validFixtureData(for relativePath: String) -> Data {
            let expectedSize = SpeakerDiarizationModelStore.requiredFileSizes[relativePath] ?? 0
            if relativePath.hasSuffix("metadata.json") {
                var data = Data("[{}]".utf8)
                data.append(Data(repeating: 0x20, count: max(expectedSize - data.count, 0)))
                return data
            }
            return Data(repeating: 1, count: expectedSize)
        }

        for relativePath in SpeakerDiarizationModelStore.requiredRelativeFilePaths {
            let fileURL = rootURL.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try validFixtureData(for: relativePath).write(to: fileURL)
        }

        var report = SpeakerDiarizationModelStore.validationReport(for: rootURL)
        #expect(report.isValid)

        let emptyFile = rootURL.appendingPathComponent(
            SpeakerDiarizationModelStore.requiredRelativeFilePaths[0]
        )
        try Data().write(to: emptyFile)
        report = SpeakerDiarizationModelStore.validationReport(for: rootURL)
        #expect(!report.isValid)
        try validFixtureData(
            for: SpeakerDiarizationModelStore.requiredRelativeFilePaths[0]
        ).write(to: emptyFile)

        let truncatedRelativePath = SpeakerDiarizationModelStore.requiredRelativeFilePaths[1]
        let truncatedFile = rootURL.appendingPathComponent(truncatedRelativePath)
        let truncatedData = validFixtureData(for: truncatedRelativePath).dropLast()
        try Data(truncatedData).write(to: truncatedFile)
        report = SpeakerDiarizationModelStore.validationReport(for: rootURL)
        #expect(!report.isValid)
        #expect(report.missingRelativePaths == [truncatedRelativePath])
        try validFixtureData(for: truncatedRelativePath).write(to: truncatedFile)

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

    @Test("검증된 화자분리 staging 모델은 기존 설치본을 교체한다")
    func testInstallingValidatedSpeakerModelReplacesExistingModel() throws {
        let testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionMateSpeakerInstall-\(UUID().uuidString)", isDirectory: true)
        let stagedRoot = testRoot.appendingPathComponent("staged", isDirectory: true)
        let destinationRoot = testRoot.appendingPathComponent("installed", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: testRoot)
        }

        try FileManager.default.createDirectory(
            at: destinationRoot,
            withIntermediateDirectories: true
        )
        let oldMarker = destinationRoot.appendingPathComponent("old-model.txt")
        try Data("old".utf8).write(to: oldMarker)

        try writeValidSpeakerModelFixture(at: stagedRoot)

        let fixtureChecksums = try speakerModelFixtureChecksums(at: stagedRoot)
        try SpeakerDiarizationModelStore.installValidatedModel(
            from: stagedRoot,
            to: destinationRoot,
            expectedFileSHA256: fixtureChecksums
        )

        #expect(SpeakerDiarizationModelStore.validationReport(for: destinationRoot).isValid)
        #expect(!FileManager.default.fileExists(atPath: oldMarker.path))
        #expect(!FileManager.default.fileExists(atPath: stagedRoot.path))
    }

    @Test("화자 모델 설치 후에도 staging 정리가 끝나기 전에는 재시도를 허용하지 않는다") @MainActor
    func testSpeakerModelInstallRetainsDownloadOwnershipUntilCleanup() throws {
        let testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionMateSpeakerLifecycle-\(UUID().uuidString)", isDirectory: true)
        let stagingBase = testRoot.appendingPathComponent("staging", isDirectory: true)
        let stagedRoot = stagingBase.appendingPathComponent("model", isDirectory: true)
        let destinationRoot = testRoot.appendingPathComponent("installed", isDirectory: true)
        let viewModel = ContentViewModel()
        let previousManifest = UserDefaults.standard.object(forKey: "speakerDiarizationModelManifestVersion")
        let task = makeCancellableTask()
        defer {
            task.cancel()
            viewModel.prepareForClose()
            UserDefaults.standard.set(previousManifest, forKey: "speakerDiarizationModelManifestVersion")
            try? FileManager.default.removeItem(at: testRoot)
        }
        try writeValidSpeakerModelFixture(at: stagedRoot)
        let checksums = try speakerModelFixtureChecksums(at: stagedRoot)
        viewModel.modelManagementState.beginSpeakerDiarizationModelDownload(path: destinationRoot.path)
        let operationID = viewModel.setSpeakerDiarizationModelTaskForTesting(task)

        try viewModel.installSpeakerModelForTesting(
            from: stagedRoot, to: destinationRoot, operationID: operationID, checksums: checksums
        )

        #expect(FileManager.default.fileExists(atPath: stagingBase.path))
        #expect(SpeakerDiarizationModelStore.validationReport(for: destinationRoot).isValid)
        #expect(viewModel.ownsSpeakerModelDownloadForTesting(operationID: operationID))
        #expect(viewModel.modelManagementState.isSpeakerDiarizationModelPreparing)
        viewModel.refreshSpeakerDiarizationModelState()
        #expect(viewModel.modelManagementState.isSpeakerDiarizationModelPreparing)
    }

    @Test("동일 크기 손상 staging 모델은 기존 설치본을 교체하지 않는다")
    func testInstallingSpeakerModelRejectsSameSizeCorruption() throws {
        let testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionMateSpeakerChecksum-\(UUID().uuidString)", isDirectory: true)
        let stagedRoot = testRoot.appendingPathComponent("staged", isDirectory: true)
        let destinationRoot = testRoot.appendingPathComponent("installed", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: testRoot)
        }

        try writeValidSpeakerModelFixture(at: stagedRoot)
        let fixtureChecksums = try speakerModelFixtureChecksums(at: stagedRoot)
        try FileManager.default.createDirectory(
            at: destinationRoot,
            withIntermediateDirectories: true
        )
        let oldMarker = destinationRoot.appendingPathComponent("old-model.txt")
        try Data("old".utf8).write(to: oldMarker)

        let corruptedRelativePath = SpeakerDiarizationModelStore.requiredRelativeFilePaths[1]
        let corruptedURL = stagedRoot.appendingPathComponent(corruptedRelativePath)
        let expectedSize = try #require(
            SpeakerDiarizationModelStore.requiredFileSizes[corruptedRelativePath]
        )
        try Data(repeating: 2, count: expectedSize).write(to: corruptedURL)

        var rejected = false
        do {
            try SpeakerDiarizationModelStore.installValidatedModel(
                from: stagedRoot,
                to: destinationRoot,
                expectedFileSHA256: fixtureChecksums
            )
        } catch {
            rejected = true
        }

        #expect(rejected)
        #expect(FileManager.default.fileExists(atPath: oldMarker.path))
        #expect(FileManager.default.fileExists(atPath: stagedRoot.path))
    }

    @Test("화자 분석 실패 진단은 동일 크기 손상만 복구로 안내한다")
    func testSpeakerFailureDiagnosisDistinguishesCorruptionFromRuntimeErrors() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionMateSpeakerDiagnosis-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try writeValidSpeakerModelFixture(at: rootURL)
        let checksums = try speakerModelFixtureChecksums(at: rootURL)
        let runtimeError = NSError(domain: "TestAudioResources", code: 42)

        let healthyFailure = SpeakerDiarizationService.diagnosedError(
            runtimeError, modelRootURL: rootURL, expectedFileSHA256: checksums
        )
        #expect((healthyFailure as NSError) == runtimeError)

        let relativePath = SpeakerDiarizationModelStore.requiredRelativeFilePaths[1]
        let corruptedURL = rootURL.appendingPathComponent(relativePath)
        let size = try #require(SpeakerDiarizationModelStore.requiredFileSizes[relativePath])
        try Data(repeating: 2, count: size).write(to: corruptedURL)
        #expect(SpeakerDiarizationModelStore.validationReport(for: rootURL).isValid)

        let damagedFailure = SpeakerDiarizationService.diagnosedError(
            runtimeError, modelRootURL: rootURL, expectedFileSHA256: checksums
        )
        if case let .modelUnavailable(failure) = damagedFailure as? SpeakerDiarizationServiceError {
            #expect(failure.invalidRelativePaths == [relativePath])
            #expect(failure.matchesCurrentFiles)
            try Data(repeating: 1, count: size).write(to: corruptedURL, options: .atomic)
            #expect(!failure.matchesCurrentFiles)
        } else {
            Issue.record("Confirmed byte damage must offer repair")
        }

        let cancellation = SpeakerDiarizationService.diagnosedError(
            CancellationError(), modelRootURL: rootURL, expectedFileSHA256: checksums
        )
        #expect(cancellation is CancellationError)
        try FileManager.default.removeItem(at: corruptedURL)
        let inconclusiveFailure = SpeakerDiarizationService.diagnosedError(
            runtimeError, modelRootURL: rootURL, expectedFileSHA256: checksums
        )
        #expect((inconclusiveFailure as NSError) == runtimeError)
    }

    @Test("중단된 화자 모델 교체의 backup은 다음 refresh 전에 복구한다")
    func testSpeakerModelStoreRecoversOrphanedBackup() throws {
        let testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionMateSpeakerRecovery-\(UUID().uuidString)", isDirectory: true)
        let destinationRoot = testRoot.appendingPathComponent("speakerkit-coreml", isDirectory: true)
        let backupRoot = testRoot.appendingPathComponent(".speakerkit-backup", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: testRoot)
        }

        try writeValidSpeakerModelFixture(at: backupRoot)

        try SpeakerDiarizationModelStore.recoverBackupIfNeeded(for: destinationRoot)

        #expect(SpeakerDiarizationModelStore.validationReport(for: destinationRoot).isValid)
        #expect(!FileManager.default.fileExists(atPath: backupRoot.path))
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

    @Test("빈 Whisper 폴더는 설치 목록에서 제외하고 디스크에는 보존한다")
    func testEmptyLocalModelFolderIsNotInstalled() throws {
        let fileManager = FileManager.default
        let modelStorage = "CaptionMateEmptyModelTest-\(UUID().uuidString)"
        let rootURL = try #require(ModelCatalogService.localModelDirectoryURL(
            modelStorage: modelStorage,
            fileManager: fileManager
        ))
        defer { try? fileManager.removeItem(at: rootURL) }

        let emptyURL = rootURL.appendingPathComponent("openai_whisper-tiny", isDirectory: true)
        let populatedURL = rootURL.appendingPathComponent("openai_whisper-base", isDirectory: true)
        try fileManager.createDirectory(at: emptyURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: populatedURL, withIntermediateDirectories: true)
        let markerURL = populatedURL.appendingPathComponent("model-data.marker")
        try Data("present".utf8).write(to: markerURL)

        let result = try ModelCatalogService.loadLocalModelFolders(
            modelStorage: modelStorage,
            fileManager: fileManager
        )
        #expect(result.directoryURL == rootURL)
        #expect(result.folders.map(\.name) == ["openai_whisper-base"])
        #expect((result.folders.first?.size ?? 0) > 0)
        #expect(fileManager.fileExists(atPath: emptyURL.path))
        #expect(fileManager.fileExists(atPath: markerURL.path))
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

    @Test("원격 모델 크기 조회는 제한된 병렬성으로 실행한다")
    func testRemoteFolderSizesUseBoundedConcurrency() async throws {
        let models = ["model-a", "model-b", "model-c", "model-d", "model-e"]
        let probe = RemoteSizeConcurrencyProbe()
        let collector = RemoteSizeResultCollector()

        await ModelCatalogService.fetchRemoteFolderSizes(
            repoName: "argmaxinc/whisperkit-coreml",
            models: models,
            maxConcurrentRequests: 2,
            fetchSize: { _, model in
                try await probe.fetchSize(for: model)
            },
            onResult: { model, result in
                await collector.record(model: model, result: result)
            }
        )

        #expect(await probe.maxObservedActiveRequests() == 2)
        #expect(await collector.successfulSizes() == [
            "model-a": 1_000,
            "model-b": 1_000,
            "model-c": 1_000,
            "model-d": 1_000,
            "model-e": 1_000,
        ])
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

    @Test("설치되지 않은 모델은 활성 선택으로 표시하지 않는다") @MainActor
    func testUninstalledModelIsNotPresentedAsActiveSelection() throws {
        let state = ModelManagementState()
        let model = "openai_whisper-large-v3"

        #expect(!state.hasVisibleModelSelection(for: model))

        state.localModels = [model]
        #expect(state.hasVisibleModelSelection(for: model))

        state.localModels.removeAll()
        state.currentDownloadingModels = [model]
        #expect(state.hasVisibleModelSelection(for: model))

        state.currentDownloadingModels.removeAll()
        state.queuedDownloadModels = [model]
        #expect(state.hasVisibleModelSelection(for: model))
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

    @Test("완료된 모델은 진행 중 배치가 남아 있어도 다운로드 완료 섹션으로 이동한다") @MainActor
    func testCompletedBatchModelMovesToDownloadedSectionDuringActiveDownloads() throws {
        let state = ModelManagementState()
        let completedModel = "openai_whisper-tiny"
        let activeModel = "openai_whisper-base"
        let remoteModel = "openai_whisper-small"

        state.availableModels = [completedModel, activeModel, remoteModel]
        state.localModels = [completedModel]
        state.downloadBatchModels = [completedModel, activeModel]
        state.currentDownloadingModels = [activeModel]
        state.downloadProgress[completedModel] = 1.0
        state.downloadProgress[activeModel] = 0.35

        #expect(state.trackedDownloadModels(orderedBy: state.availableModels) == [
            completedModel,
            activeModel,
        ])
        #expect(state.downloadActivityModels(orderedBy: state.availableModels) == [activeModel])
        #expect(state.downloadedSectionModels(orderedBy: state.availableModels) == [completedModel])
        #expect(state.availableSectionModels(orderedBy: state.availableModels) == [remoteModel])
    }

    @Test("동시 다운로드 슬롯은 maxConcurrentDownloads까지 즉시 시작을 허용한다") @MainActor
    func testDownloadSlotsAllowParallelStartsBeforeQueueing() throws {
        let state = ModelManagementState()
        state.maxConcurrentDownloads = 2

        #expect(state.availableDownloadSlotCount == 2)
        #expect(state.hasAvailableDownloadSlot)

        state.currentDownloadingModels.insert("openai_whisper-tiny")

        #expect(state.availableDownloadSlotCount == 1)
        #expect(state.hasAvailableDownloadSlot)

        state.currentDownloadingModels.insert("openai_whisper-base")

        #expect(state.availableDownloadSlotCount == 0)
        #expect(!state.hasAvailableDownloadSlot)
    }

    @Test("취소 중인 다운로드도 worker 종료 전까지 병렬 슬롯을 점유한다") @MainActor
    func testCancellingDownloadsKeepTheirConcurrencySlot() throws {
        let state = ModelManagementState()
        state.maxConcurrentDownloads = 2
        state.currentDownloadingModels = ["model-a"]
        state.cancellingModels = ["model-b"]

        #expect(state.availableDownloadSlotCount == 0)
        #expect(!state.hasAvailableDownloadSlot)
    }

    @Test("모델 다운로드 진행률 publisher는 공유 상태 변경을 전달한다") @MainActor
    func testDownloadProgressPublisherEmitsSharedStateChanges() async throws {
        let state = ModelManagementState()
        let model = "openai_whisper-large-v2"
        var values: [Float] = []

        let cancellable = state.downloadProgressPublisher(for: model)
            .sink { progress in
                values.append(progress)
            }

        state.downloadProgress[model] = 0.493
        try await Task.sleep(nanoseconds: 10_000_000)

        #expect(values.first == 0)
        #expect(values.last == 0.493)

        state.downloadProgress[model] = 1.5
        try await Task.sleep(nanoseconds: 10_000_000)

        #expect(values.last == 1.0)

        _ = cancellable
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

    @Test("원격 모델 선택은 공통 다운로드 큐에 등록한다") @MainActor
    func testSelectingRemoteModelRoutesThroughManagedDownloadQueue() throws {
        let viewModel = ContentViewModel()
        let model = "openai_whisper-base"
        viewModel.selectedModel = "openai_whisper-tiny"
        viewModel.modelManagementState.availableModels = [model]
        viewModel.modelManagementState.maxConcurrentDownloads = 0

        viewModel.selectModel(model)

        #expect(viewModel.selectedModel == "openai_whisper-tiny")
        #expect(viewModel.modelManagementState.queuedDownloadModels == [model])
        #expect(viewModel.modelManagementState.downloadBatchModels == [model])
    }

    @Test("Whisper prewarm 런타임 실패는 설치된 모델 데이터를 보존한다") @MainActor
    func testWhisperPrewarmRuntimeFailurePreservesInstalledModel() async throws {
        let fileManager = FileManager.default
        let model = "openai_whisper-tiny"
        let parentURL = fileManager.temporaryDirectory
            .appendingPathComponent("CaptionMateWhisperPrewarm-\(UUID().uuidString)", isDirectory: true)
        let modelFolderURL = parentURL.appendingPathComponent(model, isDirectory: true)
        let markerURL = modelFolderURL.appendingPathComponent("installed-model.marker")
        let viewModel = ContentViewModel()
        let previousSelectedModel = viewModel.selectedModel
        defer {
            viewModel.prepareForClose()
            viewModel.selectedModel = previousSelectedModel
            try? fileManager.removeItem(at: parentURL)
        }

        try fileManager.createDirectory(at: modelFolderURL, withIntermediateDirectories: true)
        try Data("installed".utf8).write(to: markerURL)
        viewModel.modelManagementState.localModelPath = parentURL.path
        viewModel.modelManagementState.localModels = [model]
        viewModel.modelManagementState.maxConcurrentDownloads = 0
        viewModel.modelManagementState.modelState = .prewarming
        viewModel.modelManagementState.loadingProgressValue = 0.5
        viewModel.selectedModel = model
        let taskID = viewModel.beginModelLoadOperationForTesting()

        await viewModel.simulateWhisperPrewarmFailureForTesting(model: model, taskID: taskID)

        #expect(fileManager.fileExists(atPath: modelFolderURL.path))
        #expect(fileManager.fileExists(atPath: markerURL.path))
        #expect(viewModel.modelManagementState.localModels == [model])
        #expect(viewModel.selectedModel == model)
        #expect(viewModel.modelManagementState.queuedDownloadModels.isEmpty)
        #expect(viewModel.pendingModelRepairForTesting == nil)
        #expect(viewModel.modelManagementState.modelState == .unloaded)
        #expect(viewModel.modelManagementState.hasModelLoadError)
        let errorMessage = try #require(viewModel.modelManagementState.modelLoadError)
        #expect(errorMessage.contains("Model optimization failed"))
        #expect(errorMessage.contains("Simulated prewarm runtime failure"))
        #expect(!errorMessage.localizedCaseInsensitiveContains("retrying"))
        #expect(viewModel.modelManagementState.loadingProgressValue == 0)
    }

    @Test("오래된 Whisper prewarm 실패는 새 모델 로드 상태를 덮어쓰지 않는다") @MainActor
    func testStaleWhisperPrewarmFailurePreservesNewerOperation() async throws {
        let fileManager = FileManager.default
        let model = "openai_whisper-tiny"
        let parentURL = fileManager.temporaryDirectory
            .appendingPathComponent("CaptionMateStaleWhisperPrewarm-\(UUID().uuidString)", isDirectory: true)
        let modelFolderURL = parentURL.appendingPathComponent(model, isDirectory: true)
        let markerURL = modelFolderURL.appendingPathComponent("installed-model.marker")
        let viewModel = ContentViewModel()
        let previousSelectedModel = viewModel.selectedModel
        defer {
            viewModel.prepareForClose()
            viewModel.selectedModel = previousSelectedModel
            try? fileManager.removeItem(at: parentURL)
        }

        try fileManager.createDirectory(at: modelFolderURL, withIntermediateDirectories: true)
        try Data("installed".utf8).write(to: markerURL)
        viewModel.modelManagementState.localModelPath = parentURL.path
        viewModel.modelManagementState.localModels = [model]
        viewModel.modelManagementState.maxConcurrentDownloads = 0
        viewModel.selectedModel = model
        let staleTaskID = viewModel.beginModelLoadOperationForTesting()
        _ = viewModel.beginModelLoadOperationForTesting()
        viewModel.modelManagementState.modelState = .prewarming
        viewModel.modelManagementState.loadingProgressValue = 0.5
        viewModel.modelManagementState.hasModelLoadError = false
        viewModel.modelManagementState.modelLoadError = nil

        await viewModel.simulateWhisperPrewarmFailureForTesting(
            model: model,
            taskID: staleTaskID
        )

        #expect(fileManager.fileExists(atPath: modelFolderURL.path))
        #expect(fileManager.fileExists(atPath: markerURL.path))
        #expect(viewModel.modelManagementState.localModels == [model])
        #expect(viewModel.selectedModel == model)
        #expect(viewModel.modelManagementState.modelState == .prewarming)
        #expect(viewModel.modelManagementState.loadingProgressValue == 0.5)
        #expect(!viewModel.modelManagementState.hasModelLoadError)
        #expect(viewModel.modelManagementState.modelLoadError == nil)
        #expect(viewModel.modelManagementState.queuedDownloadModels.isEmpty)
        #expect(viewModel.pendingModelRepairForTesting == nil)
    }

    @Test("화자 모델 다운로드 중 catalog refresh는 진행 상태를 보존한다") @MainActor
    func testCatalogRefreshPreservesActiveSpeakerModelDownloadState() throws {
        let viewModel = ContentViewModel()
        let task = makeCancellableTask()
        viewModel.modelManagementState.beginSpeakerDiarizationModelDownload(path: "/tmp/staging")
        viewModel.setSpeakerDiarizationModelTaskForTesting(task)

        viewModel.refreshSpeakerDiarizationModelState()

        #expect(viewModel.modelManagementState.speakerDiarizationModelState == .downloading)
        #expect(viewModel.modelManagementState.speakerDiarizationModelPath == "/tmp/staging")
        viewModel.prepareForClose()
    }

    @Test("Cancelled waveform work cannot clear a replacement's loading state for the same audio") @MainActor
    func testCancelledWaveformPreservesNewerLoadingState() async {
        let viewModel = ContentViewModel()
        let audioURL = URL(fileURLWithPath: "/tmp/reimported-audio.wav")
        viewModel.audioState.importedAudioURL = audioURL
        viewModel.audioState.isWaveformProcessing = true
        viewModel.audioState.totalDuration = 10
        viewModel.audioState.waveformSamples = [0.2, 0.6]

        let cancelledTask = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await viewModel.processWaveform(for: audioURL)
        }
        await cancelledTask.value

        #expect(viewModel.audioState.isWaveformProcessing)
        #expect(viewModel.audioState.waveformSamples == [0.2, 0.6])
        #expect(viewModel.audioState.totalDuration == 10)
    }

    @Test("화면 종료 준비는 다운로드 worker 종료까지 취소 소유권을 유지한다") @MainActor
    func testPrepareForCloseRetainsDownloadOwnershipUntilWorkerExits() throws {
        let viewModel = ContentViewModel()
        let model = "openai_whisper-base"
        let task = makeCancellableTask()

        viewModel.setModelDownloadRuntimeForTesting(
            model: model,
            task: task,
            progress: Progress(totalUnitCount: 100),
            lastProgressCallbackTime: Date()
        )
        viewModel.modelManagementState.currentDownloadingModels.insert(model)
        viewModel.modelManagementState.cancellingModels.insert(model)
        viewModel.modelManagementState.queuedDownloadModels = ["openai_whisper-small"]
        viewModel.modelManagementState.downloadBatchModels = [model, "openai_whisper-small"]
        viewModel.modelManagementState.downloadProgress[model] = 0.4
        viewModel.modelManagementState.isDownloading = true
        viewModel.modelManagementState.catalogLoadState = .loadingRemote
        viewModel.modelManagementState.isRemoteModelSizeLoading = true

        viewModel.prepareForClose()

        #expect(viewModel.activeModelDownloadTaskCountForTesting == 1)
        #expect(viewModel.activeModelDownloadProgressObjectCountForTesting == 1)
        #expect(viewModel.activeModelDownloadProgressCallbackCountForTesting == 1)
        #expect(viewModel.modelManagementState.currentDownloadingModels.isEmpty)
        #expect(viewModel.modelManagementState.cancellingModels == [model])
        #expect(viewModel.modelManagementState.queuedDownloadModels.isEmpty)
        #expect(viewModel.modelManagementState.downloadBatchModels == [model])
        #expect(viewModel.modelManagementState.downloadProgress[model] == 0.4)
        #expect(viewModel.modelManagementState.isDownloading)
        #expect(viewModel.modelManagementState.catalogLoadState == .idle)
        #expect(!viewModel.modelManagementState.isRemoteModelSizeLoading)
        #expect(task.isCancelled)
    }

    @Test("화면 종료 준비는 모델 로딩 Task를 취소하고 종료까지 소유한다") @MainActor
    func testPrepareForCloseRetainsCancelledModelLoadUntilExit() throws {
        let viewModel = ContentViewModel()
        let task = makeCancellableTask()

        viewModel.setModelLoadTaskForTesting(task)
        #expect(viewModel.hasActiveModelLoadTaskForTesting)

        viewModel.prepareForClose()

        #expect(viewModel.hasActiveModelLoadTaskForTesting)
        #expect(task.isCancelled)
    }

    @Test("모델 로드 중 다른 선택은 현재 선택을 바꾸지 않는다") @MainActor
    func testSelectingModelWhileLoadingKeepsCurrentSelection() throws {
        let viewModel = ContentViewModel()
        let task = makeCancellableTask()
        viewModel.selectedModel = "openai_whisper-tiny"
        viewModel.modelManagementState.localModels = [
            "openai_whisper-tiny",
            "openai_whisper-base",
        ]
        viewModel.setModelLoadTaskForTesting(task)

        viewModel.selectModel("openai_whisper-base")

        #expect(viewModel.selectedModel == "openai_whisper-tiny")
        viewModel.prepareForClose()
    }

    @Test("취소 요청된 다운로드 세대는 성공 커밋할 수 없다") @MainActor
    func testCancellingDownloadCannotCommitSuccess() throws {
        let viewModel = ContentViewModel()
        let model = "openai_whisper-base"
        let task = makeCancellableTask()
        viewModel.setModelDownloadRuntimeForTesting(model: model, task: task)
        let operationID = try #require(
            viewModel.modelDownloadOperationIDForTesting(model: model)
        )

        #expect(viewModel.canCommitModelDownloadForTesting(
            model: model,
            operationID: operationID
        ))
        viewModel.modelManagementState.cancellingModels.insert(model)
        #expect(!viewModel.canCommitModelDownloadForTesting(
            model: model,
            operationID: operationID
        ))

        viewModel.prepareForClose()
    }

    @Test("오래된 모델 로드 완료는 현재 상태를 덮어쓰지 않는다") @MainActor
    func testStaleModelLoadCompletionDoesNotPublish() throws {
        let viewModel = ContentViewModel()
        let staleOperationID = viewModel.beginModelLoadOperationForTesting()
        let currentOperationID = viewModel.beginModelLoadOperationForTesting()

        viewModel.publishModelLoadCompletionForTesting(
            model: "openai_whisper-base",
            operationID: staleOperationID
        )
        #expect(viewModel.currentLoadedModel.isEmpty)

        viewModel.publishModelLoadCompletionForTesting(
            model: "openai_whisper-tiny",
            operationID: currentOperationID
        )
        #expect(viewModel.currentLoadedModel == "openai_whisper-tiny")
        #expect(viewModel.modelManagementState.modelState == .loaded)
    }

    @Test("화면 종료 준비는 오디오 파형과 정규화 Task도 취소한다") @MainActor
    func testPrepareForCloseCancelsAudioProcessingTasks() throws {
        let viewModel = ContentViewModel()
        let waveformTask = makeCancellableTask()
        let normalizationTask = makeCancellableTask()

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

    @Test("활성 다운로드 취소는 소유 Task를 중단하고 종료까지 소유한다") @MainActor
    func testActiveDownloadCancellationCancelsOwnedTask() throws {
        let viewModel = ContentViewModel()
        let model = "openai_whisper-base"
        let task = makeCancellableTask()

        viewModel.setModelDownloadRuntimeForTesting(model: model, task: task)
        viewModel.modelManagementState.currentDownloadingModels.insert(model)
        viewModel.modelManagementState.downloadBatchModels = [model]

        viewModel.cancelDownload(model)

        #expect(viewModel.modelManagementState.isCancelling(model: model))
        #expect(task.isCancelled)

        viewModel.prepareForClose()

        #expect(viewModel.modelManagementState.cancellingModels == [model])
        #expect(viewModel.activeModelDownloadTaskCountForTesting == 1)
    }
}

// MARK: - Speaker Diarization Tests

struct SpeakerDiarizationTests {
    @Test("화자 매핑 기본 전략은 자막 편집 세그먼트를 보존한다")
    func testSpeakerAssignmentMapperDefaultsToSegmentLevelMapping() throws {
        #expect(SpeakerAssignmentMapper.defaultGranularity == .segmentOverlap)
    }

    @Test("화자 매핑은 입력 자막 순서와 무관하게 원래 순서로 결과를 반환한다")
    func testSpeakerAssignmentMapperHandlesOutOfOrderSegments() throws {
        let transcriptionSegments = [
            TranscriptionSegment(start: 2, end: 3, text: "later"),
            TranscriptionSegment(start: 0, end: 1, text: "earlier"),
        ]
        let timelineSegments = [
            SpeakerTimelineSegment(speakerID: 0, start: 0, end: 1),
            SpeakerTimelineSegment(speakerID: 1, start: 2, end: 3),
        ]

        let assignments = SpeakerAssignmentMapper.assignments(
            for: transcriptionSegments,
            from: timelineSegments
        )

        #expect(assignments.map { $0?.speakerID } == [1, 0])
    }

    @Test("화자 매핑은 세그먼트 내부 화자 변경보다 편집 가능한 자막 경계를 우선한다")
    func testSegmentLevelMapperPreservesEditedCaptionBoundaries() throws {
        let transcriptionSegments = [
            TranscriptionSegment(start: 0, end: 10, text: "one edited caption"),
        ]
        let timelineSegments = [
            SpeakerTimelineSegment(speakerID: 0, start: 0, end: 4),
            SpeakerTimelineSegment(speakerID: 1, start: 4, end: 10),
        ]

        let assignments = SpeakerAssignmentMapper.assignments(
            for: transcriptionSegments,
            from: timelineSegments
        )

        #expect(assignments == [
            SpeakerSegmentAssignment(speakerID: 1),
        ])
    }

    @Test("화자분리 세그먼트 매핑 테스트")
    func testSpeakerAssignmentMapperLeavesUnmatchedSpeechUnassigned() throws {
        let transcriptionSegments = [
            TranscriptionSegment(start: 0, end: 2, text: "first"),
            TranscriptionSegment(start: 2, end: 4, text: "second"),
            TranscriptionSegment(start: 40, end: 41, text: "no matching speech"),
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
            nil,
        ])
    }

    @Test("화자분리 매핑은 시간 순서가 섞인 타임라인도 안정적으로 처리한다")
    func testSpeakerAssignmentMapperSortsTimelineBeforeLinearScan() throws {
        let transcriptionSegments = [
            TranscriptionSegment(start: 0, end: 1, text: "first"),
            TranscriptionSegment(start: 1, end: 2, text: "second"),
            TranscriptionSegment(start: 2, end: 3, text: "third"),
        ]
        let timelineSegments = [
            SpeakerTimelineSegment(speakerID: 2, start: 2, end: 3),
            SpeakerTimelineSegment(speakerID: 0, start: 0, end: 1),
            SpeakerTimelineSegment(speakerID: 1, start: 1, end: 2),
        ]

        let assignments = SpeakerAssignmentMapper.assignments(
            for: transcriptionSegments,
            from: timelineSegments
        )

        #expect(assignments == [
            SpeakerSegmentAssignment(speakerID: 0),
            SpeakerSegmentAssignment(speakerID: 1),
            SpeakerSegmentAssignment(speakerID: 2),
        ])
    }

    @Test("화자 배정 보존은 분할 여부와 무관하게 화자별 겹침 시간을 합산한다", arguments: [false, true])
    func testPreservedAssignmentsUsesCumulativeSpeakerOverlap(splitSource: Bool) {
        let speakerA = SpeakerSegmentAssignment(speakerID: 5)
        let speakerB = SpeakerSegmentAssignment(speakerID: 2)
        let sourceSegments = splitSource ? [
            TranscriptionSegment(start: 0, end: 2, text: "A first"),
            TranscriptionSegment(start: 2, end: 4, text: "A second"),
            TranscriptionSegment(start: 4, end: 7, text: "B"),
        ] : [
            TranscriptionSegment(start: 0, end: 4, text: "A"),
            TranscriptionSegment(start: 4, end: 7, text: "B"),
        ]
        let assignments: [SpeakerSegmentAssignment?] = splitSource
            ? [speakerA, speakerA, speakerB]
            : [speakerA, speakerB]

        let preserved = SpeakerAssignmentMapper.preservedAssignments(
            for: [TranscriptionSegment(start: 0, end: 7, text: "merged")],
            from: sourceSegments,
            assignments: assignments
        )

        #expect(preserved == [speakerA])
    }

    @Test("화자 배정 보존은 겹침이 없거나 경계만 닿으면 미배정으로 남긴다")
    func testPreservedAssignmentsLeavesZeroOverlapUnassigned() {
        let preserved = SpeakerAssignmentMapper.preservedAssignments(
            for: [
                TranscriptionSegment(start: -1, end: 0, text: "before"),
                TranscriptionSegment(start: 2, end: 4, text: "gap"),
                TranscriptionSegment(start: 7, end: 8, text: "after"),
                TranscriptionSegment(start: 1, end: 1, text: "zero duration"),
            ],
            from: [
                TranscriptionSegment(start: 0, end: 2, text: "A"),
                TranscriptionSegment(start: 4, end: 7, text: "B"),
            ],
            assignments: [
                SpeakerSegmentAssignment(speakerID: 5),
                SpeakerSegmentAssignment(speakerID: 2),
            ]
        )

        #expect(preserved == [nil, nil, nil, nil])
    }

    @Test("화자 배정 보존은 누적 겹침 시간이 같으면 낮은 화자 ID를 선택한다")
    func testPreservedAssignmentsBreaksCumulativeOverlapTieByLowerSpeakerID() {
        let higherID = SpeakerSegmentAssignment(speakerID: 5)
        let lowerID = SpeakerSegmentAssignment(speakerID: 2)
        let preserved = SpeakerAssignmentMapper.preservedAssignments(
            for: [TranscriptionSegment(start: 0, end: 4, text: "tie")],
            from: [
                TranscriptionSegment(start: 0, end: 2, text: "higher ID"),
                TranscriptionSegment(start: 2, end: 3, text: "lower ID first"),
                TranscriptionSegment(start: 3, end: 4, text: "lower ID second"),
            ],
            assignments: [higherID, lowerID, lowerID]
        )

        #expect(preserved == [lowerID])
    }

    @Test("화자 배정 보존은 시간 순서가 섞인 대상의 원래 순서를 유지한다")
    func testPreservedAssignmentsKeepsOutOfOrderTargetsInOriginalOrder() {
        let speakerA = SpeakerSegmentAssignment(speakerID: 5)
        let speakerB = SpeakerSegmentAssignment(speakerID: 2)
        let preserved = SpeakerAssignmentMapper.preservedAssignments(
            for: [
                TranscriptionSegment(start: 4, end: 7, text: "later"),
                TranscriptionSegment(start: 0, end: 7, text: "merged"),
                TranscriptionSegment(start: 0, end: 2, text: "earlier"),
            ],
            from: [
                TranscriptionSegment(start: 0, end: 2, text: "A first"),
                TranscriptionSegment(start: 2, end: 4, text: "A second"),
                TranscriptionSegment(start: 4, end: 7, text: "B"),
            ],
            assignments: [speakerA, speakerA, speakerB]
        )

        #expect(preserved == [speakerB, speakerA, speakerA])
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

// MARK: - CaptionMate Project Store Tests

struct CaptionMateProjectStoreTests {
    @Test("프로젝트는 저장, 목록 조회, 로드, 삭제가 가능하다")
    func testProjectStoreSavesLoadsListsAndDeletesProjects() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionMateProjectStore-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let store = CaptionMateProjectStore(rootURL: rootURL)
        let sidecar = CaptionMateSidecar(
            version: CaptionMateSidecar.currentVersion,
            audioFileName: "interview.wav",
            language: "en",
            segments: [
                .init(start: 0, end: 1.5, text: "Hello there", speakerID: 0),
                .init(start: 1.5, end: 3.0, text: "Nice to meet you", speakerID: 1),
            ],
            speakerNames: [
                "0": "Host",
                "1": "Guest",
            ],
            exportSettings: .init(
                selectedExportPreset: SubtitleExportPreset.finalCut.rawValue,
                frameRate: 29.97,
                includeSpeakerLabelsInExport: true,
                speakerDiarizationSpeakerCount: 2
            )
        )
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let updatedAt = createdAt.addingTimeInterval(120)
        let project = CaptionMateProject(
            id: "project-1",
            displayName: "Interview",
            createdAt: createdAt,
            updatedAt: updatedAt,
            sourceAudioPath: "/tmp/interview.wav",
            lastExportedAt: nil,
            sidecar: sidecar
        )

        let savedURL = try store.save(project)
        #expect(savedURL.lastPathComponent == "project-1.captionmateproject.json")

        let summaries = try store.listSummaries()
        #expect(summaries.count == 1)
        #expect(summaries[0].id == "project-1")
        #expect(summaries[0].displayName == "Interview")
        #expect(summaries[0].segmentCount == 2)
        #expect(summaries[0].speakerCount == 2)
        #expect(summaries[0].speakerDisplayNames == ["Host", "Guest"])
        #expect(summaries[0].sourceAudioFileName == "interview.wav")
        #expect(summaries[0].sourceAudioExists == false)

        let loaded = try store.load(id: "project-1")
        #expect(loaded == project)

        let renamed = try store.rename(
            id: "project-1",
            displayName: "  Client Review  ",
            now: updatedAt.addingTimeInterval(60)
        )
        #expect(renamed.displayName == "Client Review")
        #expect(renamed.createdAt == createdAt)
        #expect(renamed.updatedAt == updatedAt.addingTimeInterval(60))
        #expect(try store.load(id: "project-1").displayName == "Client Review")

        let reconnectedAudioURL = rootURL.appendingPathComponent("interview-reconnected.wav")
        try Data("reconnected-source-audio".utf8).write(to: reconnectedAudioURL)
        let relinked = try store.relinkSourceAudio(
            id: "project-1",
            sourceAudioURL: reconnectedAudioURL,
            bookmarkData: Data("reconnected-bookmark".utf8),
            now: updatedAt.addingTimeInterval(120)
        )
        #expect(relinked.sourceAudioPath == reconnectedAudioURL.path)
        #expect(relinked.sourceAudioBookmarkData == Data("reconnected-bookmark".utf8))
        #expect(relinked.updatedAt == updatedAt.addingTimeInterval(120))

        let duplicate = try store.duplicate(
            id: "project-1",
            displayName: "Client Review Copy",
            now: updatedAt.addingTimeInterval(180),
            newID: "project-1-copy"
        )
        #expect(duplicate.id == "project-1-copy")
        #expect(duplicate.displayName == "Client Review Copy")
        #expect(duplicate.createdAt == updatedAt.addingTimeInterval(180))
        #expect(duplicate.updatedAt == updatedAt.addingTimeInterval(180))
        #expect(duplicate.sourceAudioPath == reconnectedAudioURL.path)
        #expect(duplicate.sidecar == sidecar)
        #expect(try store.listSummaries().map(\.id) == ["project-1-copy", "project-1"])

        try store.delete(id: "project-1")
        #expect(try store.listSummaries().map(\.id) == ["project-1-copy"])
    }

    @Test("프로젝트 목록은 최근 수정 순으로 정렬된다")
    func testProjectStoreListsMostRecentlyUpdatedProjectFirst() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionMateProjectStoreSort-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let store = CaptionMateProjectStore(rootURL: rootURL)
        let baseSidecar = CaptionMateSidecar(
            version: CaptionMateSidecar.currentVersion,
            audioFileName: "clip.wav",
            language: "ko",
            segments: [.init(start: 0, end: 1, text: "안녕하세요", speakerID: nil)],
            speakerNames: [:],
            exportSettings: .init(
                selectedExportPreset: SubtitleExportPreset.general.rawValue,
                frameRate: 30,
                includeSpeakerLabelsInExport: false,
                speakerDiarizationSpeakerCount: 0
            )
        )

        try store.save(.init(
            id: "older",
            displayName: "Older",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20),
            sourceAudioPath: nil,
            lastExportedAt: nil,
            sidecar: baseSidecar
        ))
        try store.save(.init(
            id: "newer",
            displayName: "Newer",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 30),
            sourceAudioPath: nil,
            lastExportedAt: nil,
            sidecar: baseSidecar
        ))

        #expect(try store.listSummaries().map(\.id) == ["newer", "older"])
    }

    @Test("손상된 프로젝트 파일은 정상 프로젝트 목록을 가리지 않는다")
    func testProjectStoreSkipsCorruptFilesWhenListingSummaries() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionMateProjectStoreCorrupt-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let store = CaptionMateProjectStore(rootURL: rootURL)
        let sidecar = CaptionMateSidecar(
            version: CaptionMateSidecar.currentVersion,
            audioFileName: "valid.wav",
            language: "en",
            segments: [.init(start: 0, end: 1, text: "Valid", speakerID: nil)],
            speakerNames: [:],
            exportSettings: .init(
                selectedExportPreset: SubtitleExportPreset.general.rawValue,
                frameRate: 30,
                includeSpeakerLabelsInExport: false,
                speakerDiarizationSpeakerCount: 0
            )
        )
        try store.save(.init(
            id: "valid",
            displayName: "Valid",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20),
            sourceAudioPath: nil,
            lastExportedAt: nil,
            sidecar: sidecar
        ))

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try Data("{not-json".utf8).write(
            to: rootURL.appendingPathComponent("corrupt.captionmateproject.json")
        )

        #expect(try store.listSummaries().map(\.id) == ["valid"])
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
        let rawValues = allCases.map(\.rawValue)
        #expect(allCases.count == 6)
        #expect(allCases.contains(.srt))
        #expect(allCases.contains(.fcpxml))
        #expect(allCases.contains(.vtt))
        #expect(allCases.contains(.json))
        #expect(rawValues.contains("txt"))
        #expect(rawValues.contains("doc"))
    }

    @Test("SubtitleFileType UTType 변환 테스트")
    func testSubtitleFileTypeUTType() throws {
        // SRT - UTType 생성하여 비교
        let expectedSRT = UTType(filenameExtension: "srt")
        #expect(SubtitleFileType.srt.utType == expectedSRT || SubtitleFileType.srt
            .utType == .plainText)

        // JSON - 시스템 정의 UTType과 비교
        #expect(SubtitleFileType.json.utType == .json)

        // TXT - plain text UTType 확인
        #expect(SubtitleFileType.from(utType: .plainText)?.rawValue == "txt")

        // VTT - UTType 생성하여 비교
        let expectedVTT = UTType(filenameExtension: "vtt")
        #expect(SubtitleFileType.vtt.utType == expectedVTT || SubtitleFileType.vtt
            .utType == .plainText)

        // FCPXML - 커스텀 UTType 확인
        let fcpxmlType = SubtitleFileType.fcpxml.utType
        #expect(fcpxmlType == .fcpxml)

        // DOC - Word-compatible document UTType 확인
        let docType = UTType(filenameExtension: "doc") ?? .data
        #expect(SubtitleFileType.from(utType: docType)?.rawValue == "doc")
    }
}

// MARK: - Text Document Writer Tests

struct TextDocumentWriterTests {
    @Test("Plain text writer는 타임코드와 자막 텍스트를 txt 파일로 쓴다")
    func testPlainTextWriterWritesReadableTranscript() throws {
        let outputDirectory = try makeOutputDirectory()
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        let result = TranscriptionResult(
            text: "Hello World",
            segments: [
                TranscriptionSegment(start: 0, end: 1.5, text: "Hello"),
                TranscriptionSegment(start: 2, end: 3.25, text: "World"),
            ],
            language: "en",
            timings: TranscriptionTimings()
        )
        let writer = WritePlainText(outputDir: outputDirectory.path)

        switch writer.write(result: result, to: "plain_text_export", options: nil) {
        case .success:
            let outputURL = outputDirectory.appendingPathComponent("plain_text_export.txt")
            let text = try String(contentsOf: outputURL, encoding: .utf8)
            #expect(text.contains("CaptionMate Transcript"))
            #expect(text.contains("[00:00:00.00 - 00:00:01.50]"))
            #expect(text.contains("Hello"))
            #expect(text.contains("[00:00:02.00 - 00:00:03.25]"))
            #expect(text.contains("World"))
        case let .failure(error):
            throw error
        }
    }

    @Test("DOC writer는 Word-compatible HTML 문서를 doc 파일로 쓴다")
    func testDocWriterWritesWordCompatibleDocument() throws {
        let outputDirectory = try makeOutputDirectory()
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        let result = TranscriptionResult(
            text: "A&B",
            segments: [
                TranscriptionSegment(start: 0, end: 1, text: "A&B <caption>"),
            ],
            language: "en",
            timings: TranscriptionTimings()
        )
        let writer = WriteDOC(outputDir: outputDirectory.path)

        switch writer.write(result: result, to: "word_export", options: nil) {
        case .success:
            let outputURL = outputDirectory.appendingPathComponent("word_export.doc")
            let document = try String(contentsOf: outputURL, encoding: .utf8)
            #expect(document.contains("<html"))
            #expect(document.contains("CaptionMate Transcript"))
            #expect(document.contains("A&amp;B &lt;caption&gt;"))
            #expect(!document.contains("A&B <caption>"))
        case let .failure(error):
            throw error
        }
    }

    private func makeOutputDirectory() throws -> URL {
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionMateTextExport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        return outputDirectory
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

    @Test("화자분리 모델은 실제 진행률이 들어오기 전까지 결정형 0%로 표시하지 않는다") @MainActor
    func testSpeakerDiarizationProgressStaysIndeterminateUntilProgressAdvances() throws {
        let state = ModelManagementState()
        let progress = Progress(totalUnitCount: 100)

        state.beginSpeakerDiarizationModelDownload(path: "/tmp/speakerkit")

        #expect(state.speakerDiarizationModelState == .downloading)
        #expect(state.speakerDiarizationModelPath == "/tmp/speakerkit")
        state.applySpeakerDiarizationDownloadProgress(progress)

        #expect(state.speakerDiarizationModelProgress == nil)

        progress.completedUnitCount = 25
        state.applySpeakerDiarizationDownloadProgress(progress)

        #expect(state.speakerDiarizationModelProgress == 0.25)
    }

    @Test("화자 모델 업데이트 실패 시 기존 정상 캐시는 유지한다") @MainActor
    func testSpeakerModelUpdateFailurePreservesValidCache() throws {
        let state = ModelManagementState()
        state.speakerDiarizationModelState = .downloaded

        state.applySpeakerDiarizationDownloadFailure(
            message: "Network unavailable",
            modelIsValidAfterFailure: true,
            modelExists: true,
            updateIsRequired: true
        )

        #expect(state.speakerDiarizationModelError == "Network unavailable")
        #expect(state.speakerDiarizationModelNeedsRepair == false)
        #expect(state.speakerDiarizationModelNeedsUpdate == true)
        #expect(state.isSpeakerDiarizationModelReady)
        #expect(state.speakerDiarizationModelState == .downloaded)

        state.applySpeakerDiarizationDownloadFailure(
            message: "Corrupt download",
            modelIsValidAfterFailure: false,
            modelExists: true,
            updateIsRequired: true
        )

        #expect(state.speakerDiarizationModelNeedsRepair == true)
        #expect(state.speakerDiarizationModelNeedsUpdate == false)
        #expect(!state.isSpeakerDiarizationModelReady)
        #expect(state.speakerDiarizationModelState == .unloaded)
    }

    @Test("설치된 화자 모델도 업데이트가 필요하면 실행 버튼을 표시한다") @MainActor
    func testReadySpeakerModelShowsActionWhenUpdateIsAvailable() throws {
        let state = ModelManagementState()
        state.speakerDiarizationModelState = .downloaded
        state.speakerDiarizationModelProgress = 1

        #expect(!state.shouldShowSpeakerDiarizationModelAction)

        state.speakerDiarizationModelNeedsUpdate = true

        #expect(state.shouldShowSpeakerDiarizationModelAction)
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
        #expect(state.isSubtitleEditing == false)
    }
}

struct TranscriptionModeHeaderTests {
    @Test("마지막 자막을 삭제해도 편집 중에는 적용 헤더를 유지한다")
    func testEditingModeKeepsHeaderVisibleWithoutSegments() {
        #expect(
            TranscriptionModeHeader.shouldShow(
                isTranscribing: false,
                isEditing: true,
                hasSegments: false
            )
        )
    }
}

struct TranscriptionReadBlockTests {
    @Test("화자 정보가 없으면 연속 자막을 하나의 읽기 문단으로 합친다")
    func testGroupsSegmentsWithoutSpeakerAssignmentsIntoOneBlock() {
        let segments = [
            TranscriptionSegment(start: 0, end: 1, text: " First sentence. "),
            TranscriptionSegment(start: 1, end: 2, text: "Second sentence."),
            TranscriptionSegment(start: 2, end: 3, text: "Third sentence."),
        ]

        let blocks = TranscriptionReadBlock.grouped(
            segments: segments,
            speakerAssignments: []
        )

        #expect(blocks.count == 1)
        #expect(blocks.first?.start == 0)
        #expect(blocks.first?.end == 3)
        #expect(blocks.first?.text == "First sentence. Second sentence. Third sentence.")
        #expect(blocks.first?.speakerID == nil)
    }

    @Test("같은 화자의 연속 자막만 합치고 화자 변경 지점은 유지한다")
    func testGroupsAdjacentSegmentsBySpeakerTurn() {
        let segments = [
            TranscriptionSegment(start: 0, end: 1, text: "Opening."),
            TranscriptionSegment(start: 1, end: 2, text: "First reply."),
            TranscriptionSegment(start: 2, end: 3, text: "More detail."),
            TranscriptionSegment(start: 3, end: 4, text: "Closing."),
        ]
        let assignments = [
            SpeakerSegmentAssignment(speakerID: 0),
            SpeakerSegmentAssignment(speakerID: 1),
            SpeakerSegmentAssignment(speakerID: 1),
            SpeakerSegmentAssignment(speakerID: 0),
        ]

        let blocks = TranscriptionReadBlock.grouped(
            segments: segments,
            speakerAssignments: assignments
        )

        #expect(blocks.map(\.speakerID) == [0, 1, 0])
        #expect(blocks.map(\.text) == [
            "Opening.",
            "First reply. More detail.",
            "Closing.",
        ])
        #expect(blocks[1].start == 1)
        #expect(blocks[1].end == 3)
    }
}

// MARK: - Localization Catalog Tests

struct LocalizationCatalogTests {
    private let supportedLocales = [
        "de",
        "en",
        "en-GB",
        "ar",
        "es",
        "fr",
        "hi",
        "ja",
        "ko",
        "pt-BR",
        "zh-Hans",
    ]

    private let requiredStatusDetailKeys = [
        "Speaker model files need repair. Open Manage Models to repair them.",
        "All segments are empty.",
        "Cannot check disk space.",
        "Document directory not found.",
        "Download cancelled.",
        "No imported audio file.",
        "No speakers detected.",
        "No subtitles are ready.",
        "Open the listed segment to adjust it manually.",
        "Original audio is missing. You can still edit and export subtitles.",
        "Project name cannot be empty.",
        "Project subtitles restored.",
        "Speaker model is not ready.",
        "Speaker model is still preparing.",
        "This removes the saved subtitle project from CaptionMate. Your original audio file is not deleted.",
        "Your current project has unsaved subtitle changes.",
    ]

    private let requiredCriticalUIKeys = [
        "App Version: %@ (%@)",
        "Apply Changes",
        "Audio Encoder",
        "Audio",
        "Audio Missing",
        "Audio Relink Failed",
        "Audio Relinked",
        "Auto Language",
        "Choose a short name for this saved subtitle project.",
        "Compute Units",
        "Default offline model · %@",
        "Delete This Project?",
        "Delete Project",
        "Duplicate Project",
        "Download Model",
        "Downloading",
        "Drag and drop a file here",
        "Edit Subtitles",
        "Fix quality warnings before export.",
        "Import Files",
        "Import one file or a batch queue.",
        "Language Changed",
        "Later",
        "Load Model",
        "Manage Models",
        "Models",
        "More Project Actions",
        "No saved projects",
        "Nothing to Save",
        "Offline model is ready",
        "Open Without Saving",
        "Project Delete Failed",
        "Project Deleted",
        "Project Duplicate Failed",
        "Project Duplicated",
        "Project List Unavailable",
        "Project Name",
        "Project Open Failed",
        "Project Opened",
        "Project Rename Failed",
        "Project Renamed",
        "Project Save Failed",
        "Project Saved",
        "Projects",
        "Reconnect Audio",
        "Ready CaptionMate",
        "Recommended model",
        "Recommended model is local",
        "Refresh Projects",
        "Relink Audio",
        "Rename",
        "Rename Project",
        "Save and Open",
        "Save Changes Before Opening?",
        "Save Project",
        "Segments",
        "Settings",
        "Speakers",
        "Speaker diarization",
        "Select language",
        "Select model",
        "Source Language",
        "Start Transcription",
        "Subtitle review",
        "Text Decoder",
        "The language has been changed.",
        "Transcribe",
        "Translate",
        "Unsaved changes",
        "Unsaved transcript",
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
        "Download size",
        "Estimated size",
        "On disk",
        "Unknown",
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

// MARK: - Preservation Regression Tests

// Keep the large JSON fixtures and process-wide working-directory change sequential.
@Suite(.serialized)
struct CaptionMatePreservationRegressionTests {
    private func makeTemporaryDirectory(_ name: String) throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionMate\(name)-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }

    private func makeSidecar(text: String) -> CaptionMateSidecar {
        CaptionMateSidecar(
            version: CaptionMateSidecar.currentVersion,
            audioFileName: "clip.wav",
            language: "ko",
            segments: [.init(start: 0, end: 1, text: text, speakerID: nil)],
            speakerNames: [:],
            exportSettings: .init(
                selectedExportPreset: SubtitleExportPreset.general.rawValue,
                frameRate: 30,
                includeSpeakerLabelsInExport: false,
                speakerDiarizationSpeakerCount: 0
            )
        )
    }

    private func makeProject(text: String) -> CaptionMateProject {
        CaptionMateProject(
            id: "write-limit",
            displayName: "Readable project",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            sourceAudioPath: nil,
            lastExportedAt: nil,
            sidecar: makeSidecar(text: text)
        )
    }

    private func encodedByteCount<Value: Encodable>(_ value: Value) throws -> Int {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value).count
    }

    private func makeSidecar(encodedJSONBytes targetByteCount: Int) throws -> CaptionMateSidecar {
        let prefix = "한글 \"edited\" \\ %\n"
        let overhead = try encodedByteCount(makeSidecar(text: prefix))
        try #require(targetByteCount >= overhead)
        let sidecar = makeSidecar(text: prefix + String(repeating: "x", count: targetByteCount - overhead))
        try #require(try encodedByteCount(sidecar) == targetByteCount)
        return sidecar
    }

    private func makeProject(encodedJSONBytes targetByteCount: Int) throws -> CaptionMateProject {
        let prefix = "한글 \"edited\" \\ %\n"
        let overhead = try encodedByteCount(makeProject(text: prefix))
        try #require(targetByteCount >= overhead)
        let project = makeProject(text: prefix + String(repeating: "x", count: targetByteCount - overhead))
        try #require(try encodedByteCount(project) == targetByteCount)
        return project
    }

    @Test("Oversized project writes reject new files and preserve readable overwrites")
    func testProjectSaveRejectsOversizedNewFileAndPreservesReadableOverwrite() throws {
        let rootURL = try makeTemporaryDirectory("ProjectWriteLimit")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = CaptionMateProjectStore(rootURL: rootURL)
        let limit = CaptionMateProjectStore.maxReadableProjectBytes
        let oversized = try makeProject(encodedJSONBytes: Int(limit) + 1)
        let expectedError = CaptionMateProjectStoreError.fileTooLarge(byteCount: limit + 1, limit: limit)
        let expectedURL = rootURL.appendingPathComponent("write-limit.captionmateproject.json")
        #expect(oversized.sidecar.segments[0].text.utf8.count < Int(limit))

        #expect(throws: expectedError) { try store.save(oversized) }
        #expect(!FileManager.default.fileExists(atPath: expectedURL.path))

        let original = makeProject(text: "Readable original")
        let savedURL = try store.save(original)
        let originalBytes = try Data(contentsOf: savedURL)
        #expect(throws: expectedError) { try store.save(oversized) }
        #expect(try Data(contentsOf: savedURL) == originalBytes)
        #expect(try store.load(id: original.id) == original)
        #expect(try store.listSummaries().map(\.id) == [original.id])
    }

    @Test("Project writes remain readable at and just below the encoded JSON limit", arguments: [-1, 0])
    func testProjectSaveAcceptsEncodedJSONAtReadLimit(offset: Int) throws {
        let rootURL = try makeTemporaryDirectory("ProjectWriteBoundary")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = CaptionMateProjectStore(rootURL: rootURL)
        let byteCount = Int(CaptionMateProjectStore.maxReadableProjectBytes) + offset
        let project = try makeProject(encodedJSONBytes: byteCount)

        let savedURL = try store.save(project)
        #expect(try savedURL.resourceValues(forKeys: [.fileSizeKey]).fileSize == byteCount)
        #expect(try store.load(id: project.id) == project)
        #expect(try store.listSummaries().map(\.id) == [project.id])
    }

    @Test("Oversized sidecar writes reject new files and preserve readable overwrites")
    func testSidecarWriteRejectsOversizedNewFileAndPreservesReadableOverwrite() throws {
        let rootURL = try makeTemporaryDirectory("SidecarWriteLimit")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let mediaURL = rootURL.appendingPathComponent("clip.wav")
        let sidecarURL = CaptionMateSidecarService.sidecarURL(forMediaURL: mediaURL)
        let limit = CaptionMateSidecarService.maxReadableSidecarBytes
        let oversized = try makeSidecar(encodedJSONBytes: Int(limit) + 1)
        let original = makeSidecar(text: "Readable original")
        #expect(oversized.segments[0].text.utf8.count < Int(limit))

        for isOverwrite in [false, true] {
            var originalBytes: Data?
            if isOverwrite {
                try CaptionMateSidecarService.write(original, nextToMediaURL: mediaURL)
                originalBytes = try Data(contentsOf: sidecarURL)
            }
            do {
                try CaptionMateSidecarService.write(oversized, nextToMediaURL: mediaURL)
                Issue.record("An oversized sidecar write must throw fileTooLarge (overwrite: \(isOverwrite)).")
            } catch let error as CaptionMateSidecarError {
                guard case let .fileTooLarge(byteCount, actualLimit) = error else {
                    Issue.record("Expected fileTooLarge, got \(error).")
                    return
                }
                #expect(byteCount == limit + 1)
                #expect(actualLimit == limit)
            }
            if let originalBytes {
                #expect(try Data(contentsOf: sidecarURL) == originalBytes)
                #expect(try CaptionMateSidecarService.read(from: sidecarURL) == original)
                #expect(try CaptionMateSidecarService.readIfPresent(nextToMediaURL: mediaURL) == original)
            } else {
                #expect(!FileManager.default.fileExists(atPath: sidecarURL.path))
            }
        }
    }

    @Test("Sidecar writes remain readable at and just below the encoded JSON limit", arguments: [-1, 0])
    func testSidecarWriteAcceptsEncodedJSONAtReadLimit(offset: Int) throws {
        let rootURL = try makeTemporaryDirectory("SidecarWriteBoundary")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let mediaURL = rootURL.appendingPathComponent("clip.wav")
        let byteCount = Int(CaptionMateSidecarService.maxReadableSidecarBytes) + offset
        let sidecar = try makeSidecar(encodedJSONBytes: byteCount)

        let savedURL = try CaptionMateSidecarService.write(sidecar, nextToMediaURL: mediaURL)
        #expect(try savedURL.resourceValues(forKeys: [.fileSizeKey]).fileSize == byteCount)
        #expect(try CaptionMateSidecarService.read(from: savedURL) == sidecar)
        #expect(try CaptionMateSidecarService.readIfPresent(nextToMediaURL: mediaURL) == sidecar)
    }

    @Test("An oversized project save retains the active ID, dirty edits, and previous bytes") @MainActor
    func testOversizedProjectSaveKeepsActiveProjectAndUnsavedChanges() throws {
        let rootURL = try makeTemporaryDirectory("ViewModelWriteLimit")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = CaptionMateProjectStore(rootURL: rootURL)
        let viewModel = ContentViewModel(projectStore: store, speakerModelRootURL: nil)
        viewModel.audioState.audioFileName = "Readable original"
        viewModel.transcriptionState.confirmedSegments = [
            TranscriptionSegment(start: 0, end: 1, text: "Readable original"),
        ]
        let saved = try #require(viewModel.saveCurrentProject(showMessage: false))
        let savedURL = rootURL.appendingPathComponent(saved.id).appendingPathExtension(CaptionMateProjectStore.pathExtension)
        let originalBytes = try Data(contentsOf: savedURL)
        let originalProject = try store.load(id: saved.id)
        let originalSavedAt = viewModel.projectLibraryState.lastSavedAt
        #expect(!viewModel.hasUnsavedProjectChanges)

        // The text alone fits; the encoded project exceeds its read limit.
        let editedText = String(repeating: "한", count: Int(CaptionMateProjectStore.maxReadableProjectBytes) / 3)
        #expect(editedText.utf8.count <= Int(CaptionMateProjectStore.maxReadableProjectBytes))
        viewModel.updateTranscriptionSegmentText(at: 0, text: editedText)
        #expect(viewModel.hasUnsavedProjectChanges)

        #expect(viewModel.saveCurrentProject() == nil)
        #expect(viewModel.projectLibraryState.activeProjectID == saved.id)
        #expect(viewModel.projectLibraryState.lastSavedAt == originalSavedAt)
        #expect(viewModel.hasUnsavedProjectChanges)
        #expect(viewModel.transcriptionState.confirmedSegments.first?.text == editedText)
        #expect(!viewModel.projectLibraryState.isSaving)
        #expect(viewModel.projectLibraryState.errorMessage != nil)
        #expect(viewModel.uiState.userMessage?.title == "Project Save Failed")
        #expect(try Data(contentsOf: savedURL) == originalBytes)
        #expect(try store.load(id: saved.id) == originalProject)
    }

    @Test("Actual TXT, DOC, and FCPXML writer file URLs keep recovery sidecars beside the export", arguments: ["txt", "doc", "fcpxml"]) @MainActor
    func testActualWriterFileURLExportsKeepRecoverySidecarsBesideDocument(fileExtension: String) async throws {
        let rootURL = try makeTemporaryDirectory("WriterURLSidecar")
        let previousDirectory = FileManager.default.currentDirectoryPath
        defer { try? FileManager.default.removeItem(at: rootURL) }
        // Confine a misinterpreted relative file:// path to this disposable fixture.
        try #require(FileManager.default.changeCurrentDirectoryPath(rootURL.path))
        defer { _ = FileManager.default.changeCurrentDirectoryPath(previousDirectory) }
        let viewModel = ContentViewModel(
            projectStore: CaptionMateProjectStore(rootURL: rootURL.appendingPathComponent("Projects")),
            speakerModelRootURL: nil
        )
        let originalPreset = viewModel.selectedExportPreset
        let originalFrameRate = viewModel.frameRate
        let originalIncludeSpeakerLabels = viewModel.includeSpeakerLabelsInExport
        let originalSpeakerCount = viewModel.speakerDiarizationSpeakerCount
        defer {
            viewModel.selectedExportPreset = originalPreset
            viewModel.frameRate = originalFrameRate
            viewModel.includeSpeakerLabelsInExport = originalIncludeSpeakerLabels
            viewModel.speakerDiarizationSpeakerCount = originalSpeakerCount
        }
        viewModel.selectedExportPreset = .general
        viewModel.frameRate = 24
        viewModel.includeSpeakerLabelsInExport = false
        viewModel.speakerDiarizationSpeakerCount = 2
        // Literal %20 must remain literal after decoding the writer's file URL.
        let fileName = "회의 기록 100%20 완료"
        let exportURL = rootURL.appendingPathComponent(fileName).appendingPathExtension(fileExtension)
        let sidecarURL = rootURL.appendingPathComponent(fileName).appendingPathExtension(CaptionMateSidecarService.pathExtension)
        let segments = [
            TranscriptionSegment(start: 0, end: 1.5, text: "안녕하세요"),
            TranscriptionSegment(start: 2, end: 3.5, text: "회의를 시작합니다"),
        ]
        let result = TranscriptionResult(
            text: segments.map(\.text).joined(separator: " "),
            segments: segments,
            language: "ko",
            timings: TranscriptionTimings()
        )
        let assignments: [SpeakerSegmentAssignment?] = [
            SpeakerSegmentAssignment(speakerID: 0), SpeakerSegmentAssignment(speakerID: 1),
        ]
        let names = [0: "진행자", 1: "참석자"]
        viewModel.transcriptionResult = result
        viewModel.transcriptionState.confirmedSegments = segments
        viewModel.transcriptionState.speakerAssignments = assignments
        viewModel.transcriptionState.speakerNames = names
        viewModel.audioState.audioFileName = fileName
        let expectedSidecar = CaptionMateSidecar(
            result: result, audioFileName: fileName,
            speakerAssignments: assignments, speakerNames: names,
            selectedExportPreset: .general, frameRate: 24,
            includeSpeakerLabelsInExport: false, speakerDiarizationSpeakerCount: 2
        )
        var writerInvoked = false

        await viewModel.exportTranscription(skipQualityReview: true) { snapshot, name, frameRate in
            writerInvoked = true
            #expect(name == fileName)
            #expect(snapshot.segments.map(\.text) == segments.map(\.text))
            let writerResult: Result<String, Error>
            switch fileExtension {
            case "txt":
                writerResult = WritePlainText(outputDir: rootURL.path).write(result: snapshot, to: name)
            case "doc":
                writerResult = WriteDOC(outputDir: rootURL.path).write(result: snapshot, to: name)
            default:
                writerResult = WriteFCPXML(outputDir: rootURL.path, frameRate: frameRate).write(result: snapshot, to: name)
            }
            switch writerResult {
            case let .success(path):
                #expect(path == exportURL.absoluteString)
                #expect(URL(string: path)?.isFileURL == true)
                return .success(path: path)
            case let .failure(error):
                return .failure(error)
            }
        }

        #expect(writerInvoked)
        #expect(FileManager.default.fileExists(atPath: exportURL.path))
        #expect(FileManager.default.fileExists(atPath: sidecarURL.path))
        #expect(viewModel.uiState.userMessage?.title == "Export Complete")
        #expect(!FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("file:").path))
        #expect(try Set(FileManager.default.contentsOfDirectory(atPath: rootURL.path)) ==
            Set([exportURL.lastPathComponent, sidecarURL.lastPathComponent]))
        let exportedText = try String(contentsOf: exportURL, encoding: .utf8)
        #expect(segments.allSatisfy { exportedText.contains($0.text) })
        #expect(try CaptionMateSidecarService.read(from: sidecarURL) == expectedSidecar)
    }

    @MainActor
    private func makeRestorationSidecar(
        for viewModel: ContentViewModel,
        speakerNames: [String: String]
    ) -> CaptionMateSidecar {
        CaptionMateSidecar(
            version: CaptionMateSidecar.currentVersion,
            audioFileName: "aliases.wav",
            language: "ko",
            segments: [
                .init(start: 0, end: 1, text: "First", speakerID: 0),
                .init(start: 1, end: 2, text: "Second", speakerID: 1),
                .init(start: 2, end: 3, text: "Last valid ID", speakerID: 255),
                .init(start: 3, end: 4, text: "Unassigned", speakerID: nil),
                .init(start: 4, end: 5, text: "Negative", speakerID: -1),
                .init(start: 5, end: 6, text: "Out of range", speakerID: 256),
            ],
            speakerNames: speakerNames,
            exportSettings: .init(
                selectedExportPreset: viewModel.selectedExportPreset.rawValue,
                frameRate: viewModel.frameRate,
                includeSpeakerLabelsInExport: viewModel.includeSpeakerLabelsInExport,
                speakerDiarizationSpeakerCount: viewModel.speakerDiarizationSpeakerCount
            )
        )
    }

    @Test("Sidecar restoration prefers canonical decimal speaker keys without losing segments") @MainActor
    func testRestoreTranscriptionSidecarPrefersCanonicalSpeakerKeys() throws {
        let rootURL = try makeTemporaryDirectory("CanonicalSpeakerKeys")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let viewModel = ContentViewModel(
            projectStore: CaptionMateProjectStore(rootURL: rootURL), speakerModelRootURL: nil
        )
        let wasEnabled = viewModel.enableSpeakerDiarization
        defer { viewModel.enableSpeakerDiarization = wasEnabled }
        let fixture = makeRestorationSidecar(for: viewModel, speakerNames: [
            "0": "Canonical host", "00": "Leading-zero alias", "+0": "Signed alias",
            "1": "Canonical guest", "01": "Guest alias", "255": "Last speaker",
            "-1": "Negative", "256": "Out of range", "invalid": "Not an integer",
            "\(Int.max)": "Huge", "9223372036854775808": "Overflow",
        ])
        let sidecar = try JSONDecoder().decode(CaptionMateSidecar.self, from: JSONEncoder().encode(fixture))

        // The unpatched Dictionary(uniqueKeysWithValues:) traps on these integer aliases.
        viewModel.restoreTranscriptionSidecar(sidecar)

        #expect(viewModel.transcriptionState.speakerNames == [
            0: "Canonical host", 1: "Canonical guest", 255: "Last speaker",
        ])
        #expect(viewModel.transcriptionState.confirmedSegments.map(\.text) == sidecar.segments.map(\.text))
        #expect(viewModel.transcriptionState.confirmedSegments.map(\.start) == sidecar.segments.map(\.start))
        #expect(viewModel.transcriptionState.confirmedSegments.map(\.end) == sidecar.segments.map(\.end))
        #expect(viewModel.transcriptionState.speakerAssignments == [
            SpeakerSegmentAssignment(speakerID: 0), SpeakerSegmentAssignment(speakerID: 1),
            SpeakerSegmentAssignment(speakerID: 255), nil, nil, nil,
        ])
        #expect(viewModel.transcriptionResult?.segments.map(\.text) == sidecar.segments.map(\.text))
        #expect(viewModel.transcriptionResult?.language == "ko")
    }

    @Test("Alias-only speaker keys use the lexicographically first key consistently") @MainActor
    func testRestoreTranscriptionSidecarUsesLexicographicAliasFallback() throws {
        let rootURL = try makeTemporaryDirectory("AliasSpeakerKeys")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let viewModel = ContentViewModel(
            projectStore: CaptionMateProjectStore(rootURL: rootURL), speakerModelRootURL: nil
        )
        let wasEnabled = viewModel.enableSpeakerDiarization
        defer { viewModel.enableSpeakerDiarization = wasEnabled }
        let fixture = makeRestorationSidecar(for: viewModel, speakerNames: [
            "00": "Leading-zero host", "+0": "Signed host",
            "01": "Short guest alias", "001": "Long guest alias",
        ])
        let sidecar = try JSONDecoder().decode(CaptionMateSidecar.self, from: JSONEncoder().encode(fixture))

        viewModel.restoreTranscriptionSidecar(sidecar)

        #expect(viewModel.transcriptionState.speakerNames == [0: "Signed host", 1: "Long guest alias"])
        #expect(viewModel.transcriptionState.confirmedSegments.map(\.text) == sidecar.segments.map(\.text))
        #expect(viewModel.transcriptionState.speakerAssignments.first??.speakerID == 0)
    }
}

// MARK: - Release Gate Tests

struct ReleaseGateTests {
    @Test("Argmax SDK는 공식 argmax-oss-swift v1 패키지로 고정한다")
    func testArgmaxSDKUsesCanonicalV1Package() throws {
        let project = try Self.readRepositoryFile("CaptionMate/CaptionMate.xcodeproj/project.pbxproj")
        let resolved = try Self.readRepositoryFile(
            "CaptionMate/CaptionMate.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
        )

        #expect(project.contains("XCRemoteSwiftPackageReference \"argmax-oss-swift\""))
        #expect(project.contains("repositoryURL = \"https://github.com/argmaxinc/argmax-oss-swift.git\";"))
        #expect(project.contains("minimumVersion = 1.1.1;"))
        #expect(resolved.contains("\"identity\" : \"argmax-oss-swift\""))
        #expect(resolved.contains("\"location\" : \"https://github.com/argmaxinc/argmax-oss-swift.git\""))
        #expect(resolved.contains("\"version\" : \"1.1.1\""))
        #expect(resolved.contains("\"revision\" : \"1bbc57cb7fe6410248a685b1c5a3c6d56adc2ed4\""))
        #expect(!project.contains("https://github.com/argmaxinc/WhisperKit"))
        #expect(!resolved.contains("https://github.com/argmaxinc/WhisperKit"))
    }

    @Test("WhisperKit v1에서 제거된 prefill cache 옵션에 의존하지 않는다")
    func testWhisperKitV1MigrationAvoidsRemovedPrefillCacheOption() throws {
        let source = try Self.readRepositoryFile(
            "CaptionMate/CaptionMate/Source/Presentation/ViewModels/ContentViewModel.swift"
        )
        let settingsSource = try Self.readRepositoryFile(
            "CaptionMate/CaptionMate/Source/Presentation/Views/TranscriptionViews/SettingsView.swift"
        )

        #expect(!source.contains("usePrefillCache:"))
        #expect(!source.contains("prefillCompute"))
        #expect(!source.contains("enableCachePrefill"))
        #expect(!settingsSource.contains("Cache Prefill"))
        #expect(source.contains("let decodingCallback: TranscriptionCallback?"))
        #expect(!source.contains("Int(self.compressionCheckWindow)"))
    }

    @Test("다운로드 progress throttling은 Sendable callback에서 mutable capture를 만들지 않는다")
    func testDownloadProgressThrottleAvoidsMutableSendableCapture() throws {
        let source = try Self.readRepositoryFile(
            "CaptionMate/CaptionMate/Source/Presentation/ViewModels/ContentViewModel.swift"
        )

        #expect(!source.contains("var lastUpdateTime = Date()"))
        #expect(source.contains("private var modelDownloadLastProgressUIUpdateTime: [String: Date]"))
    }

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

    @Test("화자분리 모델 다운로드 Task는 ViewModel을 전체 작업 동안 강하게 보유하지 않는다")
    func testSpeakerModelDownloadTaskAvoidsLongLivedStrongSelfCapture() throws {
        let source = try Self.readRepositoryFile(
            "CaptionMate/CaptionMate/Source/Presentation/ViewModels/ContentViewModel.swift"
        )

        let longLivedCapturePattern =
            #"speakerDiarizationModelTask = Task\.detached\(priority: \.background\) \{ \[weak self\] in\s+guard let self else \{ return \}"#
        #expect(source.range(of: longLivedCapturePattern, options: .regularExpression) == nil)
    }

    @Test("모델 다운로드 Task는 ViewModel을 전체 작업 동안 강하게 보유하지 않는다")
    func testModelDownloadTaskAvoidsLongLivedStrongSelfCapture() throws {
        let source = try Self.readRepositoryFile(
            "CaptionMate/CaptionMate/Source/Presentation/ViewModels/ContentViewModel.swift"
        )

        let longLivedCapturePattern =
            #"let task = Task\.detached\(priority: \.background\) \{ \[weak self\] in\s+guard let self = self else \{ return \}"#
        #expect(source.range(of: longLivedCapturePattern, options: .regularExpression) == nil)
    }

    @Test("모델 다운로드 런타임 참조는 UI 상태 모델에 저장하지 않는다")
    func testModelDownloadRuntimeReferencesStayOutOfStateModel() throws {
        let stateSource = try Self.readRepositoryFile(
            "CaptionMate/CaptionMate/Source/Data/Models/StateModels.swift"
        )
        let viewModelSource = try Self.readRepositoryFile(
            "CaptionMate/CaptionMate/Source/Presentation/ViewModels/ContentViewModel.swift"
        )

        #expect(!stateSource.contains("downloadTasks: [String: Task<Void, Never>]"))
        #expect(!stateSource.contains("downloadProgressObjects: [String: Progress]"))
        #expect(!stateSource.contains("lastProgressCallbackTime: [String: Date]"))
        #expect(viewModelSource.contains("private var modelDownloadTasks: [String: Task<Void, Never>]"))
        #expect(viewModelSource.contains("private var modelDownloadProgressObjects: [String: Progress]"))
    }

    @Test("전사 Task는 UIState가 아니라 ViewModel이 소유한다")
    func testTranscriptionTaskIsOwnedByViewModel() throws {
        let stateSource = try Self.readRepositoryFile(
            "CaptionMate/CaptionMate/Source/Data/Models/StateModels.swift"
        )
        let viewModelSource = try Self.readRepositoryFile(
            "CaptionMate/CaptionMate/Source/Presentation/ViewModels/ContentViewModel.swift"
        )

        #expect(!stateSource.contains("Task<Void, Never>"))
        #expect(viewModelSource.contains("private var transcribeTask: Task<Void, Never>?"))
        #expect(viewModelSource.contains("func cancelTranscription()"))
    }

    @Test("화자분리가 꺼져 있으면 전사 오디오 샘플을 후속 분석으로 넘기지 않는다")
    func testTranscriptionSkipsDiarizationCallWhenDisabled() throws {
        let viewModelSource = try Self.readRepositoryFile(
            "CaptionMate/CaptionMate/Source/Presentation/ViewModels/ContentViewModel.swift"
        )

        #expect(viewModelSource.contains("let shouldRunSpeakerDiarization = enableSpeakerDiarization"))
        #expect(viewModelSource.contains(
            "if shouldRunSpeakerDiarization {\n            await runSpeakerDiarizationIfEnabled(audioSamples: audioFileSamples)\n        }"
        ))
        #expect(!viewModelSource.contains("""
        try Task.checkCancellation()
        await runSpeakerDiarizationIfEnabled(audioSamples: audioFileSamples)
        """))
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

actor RemoteSizeConcurrencyProbe {
    private var activeRequests = 0
    private var maxActiveRequests = 0

    func fetchSize(for _: String) async throws -> Int64 {
        activeRequests += 1
        maxActiveRequests = max(maxActiveRequests, activeRequests)
        try await Task.sleep(nanoseconds: 20_000_000)
        activeRequests -= 1
        return 1_000
    }

    func maxObservedActiveRequests() -> Int {
        maxActiveRequests
    }
}

actor RemoteSizeResultCollector {
    private var sizes: [String: Int64] = [:]

    func record(model: String, result: Result<Int64, Error>) {
        if case let .success(size) = result {
            sizes[model] = size
        }
    }

    func successfulSizes() -> [String: Int64] {
        sizes
    }
}
