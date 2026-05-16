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
//  StateModels.swift
//  CaptionMate
//
//  Created by 조형구 on 3/25/25.
//

import AVFoundation
import Combine
import CoreML
import SwiftUI
import WhisperKit

extension ModelState {
    var captionMateLocalizedKey: LocalizedStringKey {
        switch self {
        case .unloaded:
            return "Unloaded"
        case .loaded:
            return "Loaded"
        case .loading:
            return "Loading"
        case .prewarming:
            return "Specializing"
        case .unloading:
            return "Unloading"
        case .downloading:
            return "Downloading"
        case .downloaded:
            return "Downloaded"
        default:
            return LocalizedStringKey(description)
        }
    }
}

// MARK: - Transcription Models

struct TranscriptionState {
    var currentText: String = ""
    var currentChunks: [Int: (chunkText: [String], fallbacks: Int)] = [:]

    // 전사 결과 관련
    var tokensPerSecond: TimeInterval = 0
    var firstTokenTime: TimeInterval = 0
    var modelLoadingTime: TimeInterval = 0
    var pipelineStart: TimeInterval = 0
    var currentLag: TimeInterval = 0
    var currentFallbacks: Int = 0
    var currentEncodingLoops: Int = 0
    var currentDecodingLoops: Int = 0
    var lastConfirmedSegmentEndSeconds: Float = 0
    var confirmedSegments: [TranscriptionSegment] = []
    var speakerAssignments: [SpeakerSegmentAssignment?] = []
    var speakerNames: [Int: String] = [:]
    var speakerDiarization = SpeakerDiarizationState()

    // 전사 처리 시간 및 속도 관련
    var effectiveRealTimeFactor: TimeInterval = 0
    var effectiveSpeedFactor: TimeInterval = 0
    var totalInferenceTime: TimeInterval = 0
}

struct SpeakerSegmentAssignment: Equatable, Sendable {
    let speakerID: Int

    var displayName: String {
        "Speaker \(speakerID + 1)"
    }
}

struct SpeakerDiarizationState: Equatable, Sendable {
    var isRunning: Bool = false
    var progress: Double = 0
    var detectedSpeakerCount: Int = 0
    var errorMessage: String?
}

struct UserMessage: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case info
        case success
        case warning
        case error
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let detail: String?
}

enum SubtitleExportPreset: String, CaseIterable, Identifiable {
    case general
    case youtube
    case finalCut
    case premiereResolve
    case shorts

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .general:
            return "General"
        case .youtube:
            return "YouTube"
        case .finalCut:
            return "Final Cut Pro"
        case .premiereResolve:
            return "Premiere / Resolve"
        case .shorts:
            return "Shorts / Reels"
        }
    }

    var displayNameKey: LocalizedStringKey {
        switch self {
        case .general:
            return "preset.general"
        case .youtube:
            return "preset.youtube"
        case .finalCut:
            return "preset.final_cut"
        case .premiereResolve:
            return "preset.premiere_resolve"
        case .shorts:
            return "preset.shorts"
        }
    }

    var frameRate: Double {
        switch self {
        case .general, .youtube, .shorts:
            return 30.0
        case .finalCut:
            return 29.97
        case .premiereResolve:
            return 24.0
        }
    }

    var maxLineLength: Int {
        switch self {
        case .general, .youtube, .premiereResolve:
            return 42
        case .finalCut:
            return 40
        case .shorts:
            return 28
        }
    }

    var maxLines: Int {
        switch self {
        case .shorts:
            return 3
        default:
            return 2
        }
    }

    var summary: String {
        switch self {
        case .general:
            return "Balanced subtitle export defaults."
        case .youtube:
            return "30 fps timing for platform subtitle uploads."
        case .finalCut:
            return "29.97 fps timing for FCPXML handoff."
        case .premiereResolve:
            return "24 fps timing for editorial timelines."
        case .shorts:
            return "30 fps timing for short-form vertical edits."
        }
    }

    var summaryKey: LocalizedStringKey {
        switch self {
        case .general:
            return "preset.summary.general"
        case .youtube:
            return "preset.summary.youtube"
        case .finalCut:
            return "preset.summary.final_cut"
        case .premiereResolve:
            return "preset.summary.premiere_resolve"
        case .shorts:
            return "preset.summary.shorts"
        }
    }
}

enum SubtitleIssueFilter: String, CaseIterable, Identifiable {
    case all
    case errors
    case warnings
    case notes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .errors:
            return "Errors"
        case .warnings:
            return "Warnings"
        case .notes:
            return "Notes"
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .all:
            return "All"
        case .errors:
            return "Errors"
        case .warnings:
            return "Warnings"
        case .notes:
            return "Notes"
        }
    }

    func matches(_ issue: SubtitleQualityIssue) -> Bool {
        switch self {
        case .all:
            return true
        case .errors:
            return issue.severity == .error
        case .warnings:
            return issue.severity == .warning
        case .notes:
            return issue.severity == .info
        }
    }
}

struct SubtitleQualityIssue: Identifiable, Equatable, Sendable {
    enum Severity: String, Equatable, Sendable {
        case error
        case warning
        case info
    }

    enum Kind: String, Equatable, Sendable {
        case emptyText
        case invalidTiming
        case overlappingTiming
        case shortDuration
        case longDuration
        case longLine
        case highReadingSpeed
        case missingSpeaker
        case defaultSpeakerName
    }

    let segmentIndex: Int
    let severity: Severity
    let kind: Kind
    let message: String
    let suggestion: String

    var id: String {
        "\(segmentIndex)-\(kind.rawValue)-\(severity.rawValue)"
    }
}

enum SubtitleQualityChecker {
    static let maxLineLength = 42
    static let maxTotalLength = 84
    static let minDuration: Float = 0.8
    static let maxDuration: Float = 7.0
    static let maxCharactersPerSecond: Float = 17.0

    static func check(segments: [TranscriptionSegment]) -> [SubtitleQualityIssue] {
        var issues: [SubtitleQualityIssue] = []

        for index in segments.indices {
            let segment = segments[index]
            let trimmedText = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let duration = segment.end - segment.start

            if trimmedText.isEmpty {
                issues.append(.init(
                    segmentIndex: index,
                    severity: .warning,
                    kind: .emptyText,
                    message: "Empty subtitle",
                    suggestion: "Delete it or add text before export."
                ))
            }

            if duration <= 0 {
                issues.append(.init(
                    segmentIndex: index,
                    severity: .error,
                    kind: .invalidTiming,
                    message: "Invalid timing",
                    suggestion: "Adjust the subtitle timing before export."
                ))
            } else {
                if duration < minDuration {
                    issues.append(.init(
                        segmentIndex: index,
                        severity: .warning,
                        kind: .shortDuration,
                        message: "Very short display time",
                        suggestion: "Merge it with a neighboring subtitle or extend the timing."
                    ))
                }

                if duration > maxDuration {
                    issues.append(.init(
                        segmentIndex: index,
                        severity: .info,
                        kind: .longDuration,
                        message: "Long display time",
                        suggestion: "Split it if the subtitle feels slow on screen."
                    ))
                }

                let readableCharacterCount = trimmedText.filter { !$0.isWhitespace }.count
                let charactersPerSecond = Float(readableCharacterCount) / duration
                if readableCharacterCount > 0, charactersPerSecond > maxCharactersPerSecond {
                    issues.append(.init(
                        segmentIndex: index,
                        severity: .warning,
                        kind: .highReadingSpeed,
                        message: "Fast reading speed",
                        suggestion: "Split the text or increase the display time."
                    ))
                }
            }

            if trimmedText.count > maxTotalLength ||
                trimmedText.split(whereSeparator: \.isNewline).contains(where: {
                    $0.count > maxLineLength
                }) {
                issues.append(.init(
                    segmentIndex: index,
                    severity: .warning,
                    kind: .longLine,
                    message: "Long subtitle line",
                    suggestion: "Split it into shorter subtitles."
                ))
            }

            if index < segments.index(before: segments.endIndex),
               segment.end > segments[index + 1].start {
                issues.append(.init(
                    segmentIndex: index,
                    severity: .warning,
                    kind: .overlappingTiming,
                    message: "Overlapping timing",
                    suggestion: "Merge neighboring subtitles or review timing before export."
                ))
            }
        }

        return issues
    }
}

struct BatchImportItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let displayName: String
    let needsSecurityScopedAccess: Bool
}

// MARK: - Model Management State

enum ModelCatalogLoadState: Equatable {
    case idle
    case loadingLocal
    case loadingRemote
    case ready
    case failed(String)

    var isLoading: Bool {
        switch self {
        case .loadingLocal, .loadingRemote:
            return true
        case .idle, .ready, .failed:
            return false
        }
    }

    var statusText: String {
        switch self {
        case .idle:
            return "Ready"
        case .loadingLocal:
            return "Checking local models"
        case .loadingRemote:
            return "Loading model catalog"
        case .ready:
            return "Model catalog ready"
        case let .failed(message):
            return message
        }
    }
}

enum ModelSizeSource: String, Equatable {
    case local
    case remote
    case estimate
}

@MainActor
class ModelManagementState: ObservableObject {
    @Published var modelStorage: String = "huggingface/models/argmaxinc/whisperkit-coreml"
    @Published var appStartTime: Date = .init()
    @Published var modelState: ModelState = .unloaded
    @Published var localModels: [String] = []
    @Published var localModelPath: String = ""
    @Published var availableModels: [String] = []
    @Published var availableLanguages: [String] = []
    @Published var disabledModels: [String] = WhisperKit.recommendedModels().disabled
    @Published var catalogLoadState: ModelCatalogLoadState = .idle
    @Published var isRemoteModelSizeLoading: Bool = false

    // 에러 관련 상태
    @Published var modelLoadError: String? = nil
    @Published var hasModelLoadError: Bool = false

    // 다운로드/로딩 진행률 - 자주 업데이트되는 값들
    @Published var loadingProgressValue: Float = 0.0
    @Published var specializationProgressRatio: Float = 0.2
    @Published var downloadProgress: [String: Float] = [:]
    @Published var downloadTasks: [String: Task<Void, Never>] = [:]

    // 모델 크기 정보
    @Published var modelSizes: [String: Int64] = [:]
    @Published var modelSizeSources: [String: ModelSizeSource] = [:]
    @Published var totalDownloadSize: Int64 = 0
    @Published var downloadedSize: Int64 = 0

    // 다운로드 상태
    @Published var isDownloading: Bool = false
    @Published var currentDownloadingModels: Set<String> = []
    @Published var queuedDownloadModels: [String] = []
    @Published var downloadBatchModels: [String] = []
    @Published var downloadErrors: [String: String] = [:]
    @Published var cancellingModels: Set<String> = [] // 취소 중인 모델들
    @Published var lastProgressCallbackTime: [String: Date] = [:] // Progress 콜백 마지막 활동 시간
    @Published var downloadProgressObjects: [String: Progress] = [:] // NSProgress 객체 저장

    // 다운로드 관리
    @Published var maxConcurrentDownloads: Int = 2

    var availableDownloadSlotCount: Int {
        max(maxConcurrentDownloads - currentDownloadingModels.count, 0)
    }

    var hasAvailableDownloadSlot: Bool {
        availableDownloadSlotCount > 0
    }

    // 화자분리 모델 상태
    @Published var speakerDiarizationModelState: ModelState = .unloaded
    @Published var speakerDiarizationModelPath: String = ""
    @Published var speakerDiarizationModelSize: Int64 = SpeakerDiarizationModelStore.estimatedDownloadSize
    @Published var speakerDiarizationModelProgress: Float?
    @Published var speakerDiarizationModelError: String?
    @Published var speakerDiarizationModelNeedsRepair: Bool = false
    @Published var speakerDiarizationModelNeedsUpdate: Bool = false

    // UI 상태
    @Published var modelFilter: String = ""

    @Published var folder: URL?

    // 모델 정보 포맷 헬퍼 함수들
    func formattedModelSize(for model: String) -> String {
        guard let size = modelSizes[model] else { return "알 수 없음" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    func formattedModelSizeWithSource(for model: String) -> String {
        let formattedSize = formattedModelSize(for: model)
        switch modelSizeSources[model] {
        case .local:
            return "\(formattedSize) on disk"
        case .remote:
            return "\(formattedSize) download"
        case .estimate:
            return "\(formattedSize) estimated"
        case nil:
            return formattedSize
        }
    }

    func formattedDownloadProgress(for model: String) -> String {
        String(format: "%.1f%%", downloadProgressValue(for: model) * 100)
    }

    func downloadProgressValue(for model: String) -> Float {
        Self.normalizedDownloadProgress(
            for: model,
            progressByModel: downloadProgress,
            queuedDownloadModels: queuedDownloadModels
        )
    }

    func downloadProgressPublisher(for model: String) -> AnyPublisher<Float, Never> {
        Publishers.CombineLatest($downloadProgress, $queuedDownloadModels)
            .map { progressByModel, queuedDownloadModels in
                Self.normalizedDownloadProgress(
                    for: model,
                    progressByModel: progressByModel,
                    queuedDownloadModels: queuedDownloadModels
                )
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    private static func normalizedDownloadProgress(
        for model: String,
        progressByModel: [String: Float],
        queuedDownloadModels: [String]
    ) -> Float {
        if queuedDownloadModels.contains(model) {
            return 0
        }

        let progress = progressByModel[model] ?? 0
        guard progress.isFinite else { return 0 }
        return min(max(progress, 0), 1)
    }

    func downloadDisplaySize(for model: String) -> Int64 {
        if let modelSize = modelSizes[model], modelSize > 0 {
            return modelSize
        }

        return ModelCatalogService.estimatedDownloadSize(for: model)
    }

    func totalDownloadByteCount(for models: [String]) -> Int64 {
        models.reduce(Int64(0)) { total, model in
            total + downloadDisplaySize(for: model)
        }
    }

    func downloadedByteCount(for models: [String]) -> Int64 {
        models.reduce(Int64(0)) { total, model in
            let modelSize = downloadDisplaySize(for: model)
            let progress = Double(downloadProgressValue(for: model))
            return total + Int64(Double(modelSize) * progress)
        }
    }

    func weightedDownloadProgress(for models: [String]) -> Double {
        let totalSize = totalDownloadByteCount(for: models)
        guard totalSize > 0 else { return 0 }
        return Double(downloadedByteCount(for: models)) / Double(totalSize)
    }

    var hasVisibleDownloadActivity: Bool {
        !currentDownloadingModels.isEmpty ||
            !queuedDownloadModels.isEmpty ||
            !cancellingModels.isEmpty
    }

    func beginDownloadBatchIfIdle() {
        guard !hasVisibleDownloadActivity else { return }
        downloadBatchModels.removeAll()
    }

    func trackDownloadRequest(_ model: String) {
        if !downloadBatchModels.contains(model) {
            downloadBatchModels.append(model)
        }
    }

    func untrackDownloadRequest(_ model: String) {
        downloadBatchModels.removeAll { $0 == model }
    }

    func clearDownloadBatchIfIdle() {
        guard !hasVisibleDownloadActivity else { return }
        downloadBatchModels.removeAll()
    }

    func trackedDownloadModels(orderedBy availableModels: [String]) -> [String] {
        let trackedModels = Set(downloadBatchModels)
            .union(currentDownloadingModels)
            .union(queuedDownloadModels)
            .union(cancellingModels)
        return orderedModels(trackedModels, orderedBy: availableModels)
    }

    func downloadActivityModels(orderedBy availableModels: [String]) -> [String] {
        orderedModels(downloadActivityModelSet, orderedBy: availableModels)
    }

    func downloadedSectionModels(orderedBy availableModels: [String]) -> [String] {
        availableModels.filter {
            localModels.contains($0) &&
                !downloadActivityModelSet.contains($0)
        }
    }

    func availableSectionModels(orderedBy availableModels: [String]) -> [String] {
        availableModels.filter {
            !localModels.contains($0) &&
                !downloadActivityModelSet.contains($0)
        }
    }

    private var downloadActivityModelSet: Set<String> {
        currentDownloadingModels
            .union(queuedDownloadModels)
            .union(cancellingModels)
    }

    private func orderedModels(
        _ models: Set<String>,
        orderedBy availableModels: [String]
    ) -> [String] {
        guard !models.isEmpty else { return [] }

        let orderedModels = availableModels.filter { models.contains($0) }
        let missingModels = models
            .subtracting(Set(orderedModels))
            .sorted()
        return orderedModels + missingModels
    }

    func isDownloading(model: String) -> Bool {
        return currentDownloadingModels.contains(model)
    }

    func isCancelling(model: String) -> Bool {
        return cancellingModels.contains(model)
    }

    func isQueued(model: String) -> Bool {
        return queuedDownloadModels.contains(model)
    }

    func canStartDownload(model: String) -> Bool {
        return !isDownloading(model: model) &&
            !isCancelling(model: model) &&
            !isQueued(model: model) &&
            !localModels.contains(model)
    }

    var isSpeakerDiarizationModelPreparing: Bool {
        speakerDiarizationModelState == .downloading ||
            speakerDiarizationModelState == .loading ||
            speakerDiarizationModelState == .prewarming
    }

    var isSpeakerDiarizationModelReady: Bool {
        speakerDiarizationModelState == .downloaded &&
            !speakerDiarizationModelNeedsRepair &&
            !speakerDiarizationModelNeedsUpdate
    }

    var formattedSpeakerDiarizationModelSize: String {
        ByteCountFormatter.string(fromByteCount: speakerDiarizationModelSize, countStyle: .file)
    }

    var formattedSpeakerDiarizationProgress: String {
        guard let progress = speakerDiarizationModelProgress else { return "0%" }
        return String(format: "%.1f%%", progress * 100)
    }

    func displayName(for model: String) -> String {
        return model.components(separatedBy: "_").dropFirst().joined(separator: " ")
            .replacingOccurrences(of: "-", with: " ")
    }
}

struct AudioState {
    var isTranscribing: Bool = false
    var audioFileName: String = "Subtitle"
    var waveformSamples: [Float] = []
    var isWaveformProcessing: Bool = false

    /// 파일 임포트 후 선택된 파일의 URL (미리듣기, 삭제, 파형 표시 등에 사용)
    var importedAudioURL: URL?
    var isPlaying: Bool = false
    var totalDuration: Double = 0.0
    var playbackTimer: Timer?

    /// 임시 디렉토리에 저장된 오디오 파일 URL (정리용)
    var temporaryAudioURL: URL?
}

struct UIState {
    var isFilePickerPresented: Bool = false
    var columnVisibility: NavigationSplitViewVisibility = .all
    var showComputeUnits: Bool = true
    var showAdvancedOptions: Bool = false
    var transcriptionTask: Task<Void, Never>? = nil
    var transcribeTask: Task<Void, Never>? = nil
    var isTranscribingView: Bool = false
    var isModelmanagerViewPresented: Bool = false
    var isTargeted: Bool = false
    var isLanguageChanged: Bool = false
    var showDownloadErrorAlert: Bool = false
    var downloadError: DownloadError? = nil
    var userMessage: UserMessage?
    var showFirstRunGuide: Bool = false
    var subtitleQualityIssues: [SubtitleQualityIssue] = []
    var showSubtitleReview: Bool = false
    var focusedSubtitleSegmentIndex: Int?
    var subtitleIssueFilter: SubtitleIssueFilter = .all
    var subtitleSearchText: String = ""
    var subtitleReplaceText: String = ""
}

// MARK: - Audio Playback State

@MainActor
class AudioPlaybackState: ObservableObject {
    @Published var currentPlayerTime: Double = 0.0
}
