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
//  ContentViewModel.swift
//  CaptionMate
//
//  Created by 조형구 on 3/3/25.
//

import AppKit
import AVFoundation
import Combine
import CoreML
import SpeakerKit
import SwiftUI
import WhisperKit

// MARK: - ContentViewModel

struct AppLanguageOption: Identifiable, Equatable, Sendable {
    let code: String
    let displayName: String

    var id: String { code }
}

private enum StorageCleanupPolicy {
    static let staleTemporaryAudioAge: TimeInterval = 60 * 60 * 24
    static let appScopedCoreMLCacheSubpaths = [
        "com.apple.e5rt.e5bundlecache",
        "com.apple.CoreML",
        "CoreML",
    ]
}

enum AppLanguageResolver {
    static let fallbackLanguageCode = "en-US"
    static let appLanguageDefaultsKey = "appLanguage"
    static let legacyAppleLanguagesDefaultsKey = "AppleLanguages"

    private static let legacyLanguageAliases = [
        "en": fallbackLanguageCode,
        "pt": "pt-BR",
        "zh": "zh-Hans",
    ]

    static func preferredAppLanguage(
        from preferredLanguages: [String],
        supportedLanguages: [AppLanguageOption]
    ) -> String {
        guard let primaryLanguage = preferredLanguages.first else {
            return fallbackLanguageCode
        }

        return normalizedSupportedLanguage(
            primaryLanguage,
            supportedLanguages: supportedLanguages
        ) ?? fallbackLanguageCode
    }

    static func normalizedSupportedLanguage(
        _ language: String,
        supportedLanguages: [AppLanguageOption]
    ) -> String? {
        let normalizedPrimaryLanguage = normalizeLanguageCode(language)
        let primaryBaseLanguage = normalizedPrimaryLanguage.split(separator: "-").first.map(String.init)
        let supportedCodesByNormalizedCode = Dictionary(
            supportedLanguages.map { (normalizeLanguageCode($0.code), $0.code) },
            uniquingKeysWith: { first, _ in first }
        )

        for supportedLanguage in supportedLanguages {
            let normalizedSupportedLanguage = normalizeLanguageCode(supportedLanguage.code)
            if normalizedPrimaryLanguage == normalizedSupportedLanguage ||
                normalizedPrimaryLanguage.hasPrefix("\(normalizedSupportedLanguage)-") {
                return supportedLanguage.code
            }

            if let primaryBaseLanguage,
               normalizedSupportedLanguage == primaryBaseLanguage {
                return supportedLanguage.code
            }
        }

        if let aliasedLanguage = legacyLanguageAliases[normalizedPrimaryLanguage],
           supportedCodesByNormalizedCode[normalizeLanguageCode(aliasedLanguage)] != nil {
            return aliasedLanguage
        }

        if let primaryBaseLanguage,
           let aliasedLanguage = legacyLanguageAliases[primaryBaseLanguage],
           supportedCodesByNormalizedCode[normalizeLanguageCode(aliasedLanguage)] != nil {
            return aliasedLanguage
        }

        return nil
    }

    private static func normalizeLanguageCode(_ code: String) -> String {
        code.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    static func clearLegacyAppleLanguagesOverride(in defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: legacyAppleLanguagesDefaultsKey) != nil else {
            return
        }

        defaults.removeObject(forKey: legacyAppleLanguagesDefaultsKey)
        defaults.synchronize()
    }
}

@MainActor
class ContentViewModel: ObservableObject {
    private static let supportedSpeakerIDRange = 0 ..< 8

    private var isLoadingModel = false
    private var activeTranscribeTaskID: UUID?
    private var activeSpeakerDiarizationTaskID: UUID?
    private var speakerDiarizationModelTask: Task<Void, Never>?
    private var speakerDiarizationTask: Task<Void, Never>?
    private var modelLoadTask: Task<Void, Never>?
    private var modelCatalogTask: Task<Void, Never>?
    private var remoteModelSizeTask: Task<Void, Never>?
    private var languageChangeNotificationTask: Task<Void, Never>?
    private var waveformProcessingTask: Task<Void, Never>?
    private var waveformProcessingTaskID: UUID?
    private var normalizationTask: Task<Void, Never>?
    private var normalizationTaskID: UUID?
    private var speakerDiarizationDownloadProgress: Progress?
    private var downloadCancellationMonitorTasks: [String: Task<Void, Never>] = [:]

#if DEBUG
    var activeDownloadCancellationMonitorCountForTesting: Int {
        downloadCancellationMonitorTasks.count
    }

    var hasActiveModelLoadTaskForTesting: Bool {
        modelLoadTask != nil
    }

    var hasActiveAudioProcessingTaskForTesting: Bool {
        waveformProcessingTask != nil || normalizationTask != nil
    }

    func setModelLoadTaskForTesting(_ task: Task<Void, Never>) {
        modelLoadTask = task
    }

    func setAudioProcessingTasksForTesting(
        waveformTask: Task<Void, Never>? = nil,
        normalizationTask: Task<Void, Never>? = nil
    ) {
        self.waveformProcessingTask = waveformTask
        waveformProcessingTaskID = waveformTask == nil ? nil : UUID()
        self.normalizationTask = normalizationTask
        normalizationTaskID = normalizationTask == nil ? nil : UUID()
    }
#endif

    // MARK: - Published Properties

    @Published var whisperKit: WhisperKit?

    // 현재 실제로 로드된 모델 추적
    @Published var currentLoadedModel: String = ""

    // Model 및 전사 관련 상태
    @Published var transcriptionState = TranscriptionState()
    let modelManagementState = ModelManagementState()
    @Published var audioState = AudioState()
    @Published var uiState = UIState()

    /// 전사 결과
    @Published var transcriptionResult: TranscriptionResult?

    /// Export 진행 여부
    @Published var isExporting: Bool = false
    @Published var batchQueue: [BatchImportItem] = []
    @Published var currentBatchIndex: Int?

    @Published var audioPlayer: AVAudioPlayer?
    @Published var normalizedVolumeFactor: Float = 1.0

    let audioPlaybackState = AudioPlaybackState()

    let playbackRates: [Float] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    @Published var currentPlaybackRateIndex: Int = 3

    @AppStorage("audioVolume") var audioVolume: Double = 1.0
    @AppStorage("stagingVolume") var stagingVolume: Double = 1.0
    @AppStorage("isMuted") var isMuted: Bool = false

    // Combine 관련
    private var playbackTimerCancellable: AnyCancellable?
    private var lastDecoderPreviewUpdate: Date = .distantPast

    // MARK: - AppStorage (사용자 설정, UserDefaults 기반)

    @AppStorage("selectedModel") var selectedModel: String = WhisperKit.recommendedModels().default
    @AppStorage("selectedTask") var selectedTask: String = "transcribe"
    @AppStorage("selectedLanguage") var selectedLanguage: String = "english"
    @AppStorage("repoName") var repoName: String = "argmaxinc/whisperkit-coreml"

    @AppStorage("enableTimestamps") var enableTimestamps: Bool = true
    @AppStorage("enablePromptPrefill") var enablePromptPrefill: Bool =
        true
    @AppStorage("enableCachePrefill") var enableCachePrefill: Bool = true
    @AppStorage("enableSpecialCharacters") var enableSpecialCharacters: Bool =
        false
    @AppStorage("enableWordTimestamp") var enableWordTimestamp: Bool =
        false
    @AppStorage("enableSpeakerDiarization") var enableSpeakerDiarization: Bool = false
    @AppStorage("speakerDiarizationSpeakerCount") var speakerDiarizationSpeakerCount: Int = 0
    @AppStorage("temperatureStart") var temperatureStart: Double = 0.0
    @AppStorage("fallbackCount") var fallbackCount: Double = 5.0
    @AppStorage("compressionCheckWindow") var compressionCheckWindow: Double =
        60.0
    @AppStorage("sampleLength") var sampleLength: Int = 224
    @AppStorage("concurrentWorkerCount") var concurrentWorkerCount: Double =
        4.0
    @AppStorage("chunkingStrategy") var chunkingStrategy: ChunkingStrategy =
        .vad

    // UI 전용 설정 - 전사 로직에 적용되지 않음
    @AppStorage("enableDecoderPreview") var enableDecoderPreview: Bool = true

    // Export 전용 설정
    @AppStorage("frameRate") var frameRate: Double = 30.0
    @AppStorage("includeSpeakerLabelsInExport") var includeSpeakerLabelsInExport: Bool = true
    @AppStorage("selectedExportPreset") private var selectedExportPresetRaw: String =
        SubtitleExportPreset.general.rawValue
    @AppStorage("hasSeenFirstRunGuide") var hasSeenFirstRunGuide: Bool = false
    @AppStorage("speakerDiarizationModelManifestVersion")
    private var speakerDiarizationModelManifestVersion: Int = 0

    // 기타 설정
    @AppStorage("encoderComputeUnits") var encoderComputeUnits: MLComputeUnits = .cpuAndNeuralEngine
    @AppStorage("decoderComputeUnits") var decoderComputeUnits: MLComputeUnits = .cpuAndNeuralEngine
    @AppStorage("isAutoLanguageEnable") var isAutoLanguageEnable: Bool = false
    @Published var appLanguage: String = AppLanguageResolver.fallbackLanguageCode {
        didSet {
            guard oldValue != appLanguage else { return }
            UserDefaults.standard.set(appLanguage, forKey: AppLanguageResolver.appLanguageDefaultsKey)
        }
    }
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.auto.rawValue

    /// 현재 선택된 테마
    var appTheme: AppTheme {
        get { AppTheme(rawValue: appThemeRaw) ?? .auto }
        set { appThemeRaw = newValue.rawValue }
    }

    var selectedExportPreset: SubtitleExportPreset {
        get { SubtitleExportPreset(rawValue: selectedExportPresetRaw) ?? .general }
        set { selectedExportPresetRaw = newValue.rawValue }
    }

    var batchProgressText: String {
        guard let currentBatchIndex,
              batchQueue.indices.contains(currentBatchIndex) else {
            return "\(batchQueue.count) files"
        }
        return "\(currentBatchIndex + 1) of \(batchQueue.count)"
    }

    var supportedAppLanguages: [AppLanguageOption] {
        Self.supportedAppLanguages
    }

    // MARK: - Initialization

    private static let supportedAppLanguages: [AppLanguageOption] = [
        .init(code: "en-US", displayName: "English (US)"),
        .init(code: "en-GB", displayName: "English (UK)"),
        .init(code: "ko", displayName: "한국어"),
        .init(code: "ja", displayName: "日本語"),
        .init(code: "es", displayName: "Español"),
        .init(code: "de", displayName: "Deutsch"),
        .init(code: "fr", displayName: "Français"),
        .init(code: "pt-BR", displayName: "Português (Brasil)"),
        .init(code: "hi", displayName: "हिन्दी"),
        .init(code: "zh-Hans", displayName: "简体中文"),
    ]

    private static let transcriptionLanguageCodes: [String: String] = [
        "afrikaans": "af",
        "arabic": "ar",
        "basque": "eu",
        "bengali": "bn",
        "cantonese": "yue",
        "catalan": "ca",
        "chinese": "zh",
        "czech": "cs",
        "danish": "da",
        "dutch": "nl",
        "english": "en",
        "finnish": "fi",
        "french": "fr",
        "galician": "gl",
        "german": "de",
        "greek": "el",
        "gujarati": "gu",
        "hebrew": "he",
        "hindi": "hi",
        "hungarian": "hu",
        "indonesian": "id",
        "italian": "it",
        "japanese": "ja",
        "kannada": "kn",
        "korean": "ko",
        "malay": "ms",
        "marathi": "mr",
        "norwegian": "no",
        "polish": "pl",
        "portuguese": "pt",
        "punjabi": "pa",
        "romanian": "ro",
        "russian": "ru",
        "spanish": "es",
        "swedish": "sv",
        "tamil": "ta",
        "telugu": "te",
        "thai": "th",
        "turkish": "tr",
        "ukrainian": "uk",
        "urdu": "ur",
        "vietnamese": "vi",
    ]

#if DEBUG
    private enum UITestArgument {
        static let resetDefaults = "-CaptionMateUITestResetDefaults"
        static let speakerFixture = "-CaptionMateUITestSpeakerFixture"
        static let disableModelDownloads = "-CaptionMateUITestDisableModelDownloads"
    }

    private static var launchArguments: [String] {
        ProcessInfo.processInfo.arguments
    }

    private static var isUITesting: Bool {
        launchArguments.contains(UITestArgument.resetDefaults) ||
            launchArguments.contains(UITestArgument.speakerFixture) ||
            launchArguments.contains(UITestArgument.disableModelDownloads)
    }

    var shouldSkipModelSelectorAutoActionsForUITesting: Bool {
        Self.isUITesting
    }
#endif

    init() {
#if DEBUG
        if Self.launchArguments.contains(UITestArgument.resetDefaults) {
            Self.resetPersistentDefaultsForUITesting()
            configureBaseDefaultsForUITesting()
        }
#endif

        AppLanguageResolver.clearLegacyAppleLanguagesOverride()

        // 첫 실행 시에만 시스템 언어로 설정
        if let storedLanguage = UserDefaults.standard.string(
            forKey: AppLanguageResolver.appLanguageDefaultsKey
        ) {
            appLanguage = storedLanguage
            normalizeStoredAppLanguageIfNeeded()
        } else {
            appLanguage = ContentViewModel.detectSystemLanguage()
        }

#if DEBUG
        if Self.launchArguments.contains(UITestArgument.speakerFixture) {
            configureSpeakerFixtureForUITesting()
        }
#endif
    }

#if DEBUG
    private static func resetPersistentDefaultsForUITesting() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        UserDefaults.standard.synchronize()
    }

    private func configureBaseDefaultsForUITesting() {
        appLanguage = "en-US"
        hasSeenFirstRunGuide = true
        enableSpeakerDiarization = false
        includeSpeakerLabelsInExport = true
        speakerDiarizationSpeakerCount = 0
        uiState.showFirstRunGuide = false
        uiState.showAdvancedOptions = false
        uiState.isModelmanagerViewPresented = false
    }

    private func configureSpeakerFixtureForUITesting() {
        hasSeenFirstRunGuide = true
        appLanguage = "en-US"
        enableSpeakerDiarization = true
        includeSpeakerLabelsInExport = true
        speakerDiarizationSpeakerCount = 2
        enableTimestamps = true
        modelManagementState.modelState = .loaded

        let segments = [
            TranscriptionSegment(start: 0, end: 1.8, text: "Welcome to CaptionMate."),
            TranscriptionSegment(start: 2.0, end: 3.8, text: "This segment already has a speaker."),
        ]
        transcriptionResult = TranscriptionResult(
            text: segments.map(\.text).joined(separator: " "),
            segments: segments,
            language: "en",
            timings: TranscriptionTimings()
        )
        transcriptionState.confirmedSegments = segments
        transcriptionState.speakerAssignments = [
            nil,
            SpeakerSegmentAssignment(speakerID: 0),
        ]
        transcriptionState.speakerNames = [:]
        transcriptionState.speakerDiarization = SpeakerDiarizationState(
            detectedSpeakerCount: 2
        )
        audioState.audioFileName = "UITest Speaker Fixture"
        audioState.importedAudioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionMateUITestSpeakerFixture.wav")
        audioState.totalDuration = 3.8
        uiState.isTranscribingView = true
        uiState.showFirstRunGuide = false
        uiState.isModelmanagerViewPresented = false
        refreshSubtitleQualityIssues()
    }

    func activateSpeakerFixtureNavigationForUITestingIfNeeded() {
        guard Self.launchArguments.contains(UITestArgument.speakerFixture) else { return }

        uiState.isTranscribingView = false
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.uiState.isTranscribingView = true
        }
    }
#endif

    func dismissUserMessage() {
        uiState.userMessage = nil
    }

    private func showUserMessage(
        _ kind: UserMessage.Kind,
        title: String,
        detail: String? = nil,
        autoDismissAfter delay: TimeInterval? = 4.0
    ) {
        let message = UserMessage(kind: kind, title: title, detail: detail)
        uiState.userMessage = message

        guard let delay else { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await MainActor.run {
                if self?.uiState.userMessage?.id == message.id {
                    self?.uiState.userMessage = nil
                }
            }
        }
    }

    func presentFirstRunGuideIfNeeded() {
        guard !hasSeenFirstRunGuide else { return }
        uiState.showFirstRunGuide = true
    }

    func dismissFirstRunGuide() {
        hasSeenFirstRunGuide = true
        uiState.showFirstRunGuide = false
    }

    func prepareRecommendedModelFromGuide() {
        let recommendedModel = WhisperKit.recommendedModels().default
        selectedModel = recommendedModel
        dismissFirstRunGuide()
        prepareDefaultSpeakerDiarizationModelIfNeeded()

        if modelManagementState.localModels.contains(recommendedModel) {
            loadModel(recommendedModel)
        } else {
            downloadModel(recommendedModel)
            showUserMessage(
                .info,
                title: "Downloading Recommended Model",
                detail: modelManagementState.displayName(for: recommendedModel)
            )
        }
    }

    func applySelectedExportPreset(showMessage: Bool = true) {
        frameRate = selectedExportPreset.frameRate
        guard showMessage else { return }
        showUserMessage(
            .success,
            title: "Export Preset Applied",
            detail: "\(selectedExportPreset.displayName) · \(String(format: "%.2f fps", frameRate))"
        )
    }

    func applyRecommendedPerformanceSettings(showMessage: Bool = true) {
        let activeCores = max(1, ProcessInfo.processInfo.activeProcessorCount)
        let memoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        let memoryAdjustedLimit = memoryGB >= 32 ? 8 : (memoryGB >= 16 ? 6 : 4)
        let recommendedWorkers = min(max(2, activeCores / 2), memoryAdjustedLimit)

        concurrentWorkerCount = Double(recommendedWorkers)
        chunkingStrategy = .vad

        guard showMessage else { return }
        showUserMessage(
            .success,
            title: "Performance Tuned",
            detail: "\(recommendedWorkers) workers · VAD chunking"
        )
    }

    private struct PreparedAudioImport {
        let localURL: URL
        let displayName: String
        let sidecar: CaptionMateSidecar?
        let sidecarURL: URL?
        let sidecarRestoreError: String?
    }

    nonisolated private static func appTemporaryAudioDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionMateAudio", isDirectory: true)
    }

    nonisolated private static func prepareAudioImport(
        from sourceURL: URL,
        needsSecurityScopedAccess: Bool
    ) async throws -> PreparedAudioImport {
        try await Task.detached(priority: .userInitiated) {
            let didStartAccessing = needsSecurityScopedAccess ?
                sourceURL.startAccessingSecurityScopedResource() : false
            defer {
                if didStartAccessing {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let localURL = try copyAudioFileToTemporaryDirectory(from: sourceURL)
            let sidecarResult = loadSidecarIfPresent(nextTo: sourceURL)

            return PreparedAudioImport(
                localURL: localURL,
                displayName: sourceURL.deletingPathExtension().lastPathComponent,
                sidecar: sidecarResult.sidecar,
                sidecarURL: sidecarResult.url,
                sidecarRestoreError: sidecarResult.errorMessage
            )
        }.value
    }

    nonisolated private static func loadSidecarIfPresent(
        nextTo mediaURL: URL
    ) -> (sidecar: CaptionMateSidecar?, url: URL?, errorMessage: String?) {
        let sidecarURL = CaptionMateSidecarService.sidecarURL(forMediaURL: mediaURL)
        guard FileManager.default.fileExists(atPath: sidecarURL.path) else {
            return (nil, nil, nil)
        }

        do {
            return (try CaptionMateSidecarService.read(from: sidecarURL), sidecarURL, nil)
        } catch {
            return (nil, sidecarURL, error.localizedDescription)
        }
    }

    nonisolated private static func copyAudioFileToTemporaryDirectory(
        from sourceURL: URL
    ) throws -> URL {
        let fileManager = FileManager.default
        let tempDirectoryURL = appTemporaryAudioDirectoryURL()
        try fileManager.createDirectory(
            at: tempDirectoryURL,
            withIntermediateDirectories: true
        )

        let fileExtension = sourceURL.pathExtension
        let uniqueFileName = fileExtension.isEmpty ?
            UUID().uuidString : "\(UUID().uuidString).\(fileExtension)"
        let localFileURL = tempDirectoryURL.appendingPathComponent(uniqueFileName)

        try fileManager.copyItem(at: sourceURL, to: localFileURL)
        return localFileURL
    }

    nonisolated private static func normalizationFactor(for audioURL: URL) -> Float {
        do {
            let player = try AVAudioPlayer(contentsOf: audioURL)
            player.isMeteringEnabled = true

            let sampleCount = 50
            guard player.duration.isFinite, player.duration > 0 else { return 1.0 }

            var totalLevel: Float = 0
            var peakLevel: Float = -160
            let interval = player.duration / Double(sampleCount)

            player.volume = 0
            player.play()
            defer {
                player.stop()
                player.currentTime = 0
            }

            for i in 0 ..< sampleCount {
                if Task.isCancelled { return 1.0 }
                player.currentTime = Double(i) * interval
                Thread.sleep(forTimeInterval: 0.01)
                player.updateMeters()

                let avgPower = player.averagePower(forChannel: 0)
                let peakPower = player.peakPower(forChannel: 0)
                totalLevel += avgPower
                peakLevel = max(peakLevel, peakPower)
            }

            let avgLevel = totalLevel / Float(sampleCount)
            let estimatedLUFS = avgLevel + 10
            let targetLUFS: Float = -14.0
            let gainNeeded = targetLUFS - estimatedLUFS
            let factor = gainNeeded < 0 ? pow(10.0, gainNeeded / 20.0) : 1.0

            print(
                "Audio analysis - Average level: \(avgLevel) dB, Estimated LUFS: \(estimatedLUFS), Peak: \(peakLevel) dB"
            )
            print("Normalization factor: \(factor)")
            return factor
        } catch {
            print("Audio normalization analysis failed: \(error.localizedDescription)")
            return 1.0
        }
    }

    /// 시스템 언어 감지
    private static func detectSystemLanguage() -> String {
        AppLanguageResolver.preferredAppLanguage(
            from: Locale.preferredLanguages,
            supportedLanguages: supportedAppLanguages
        )
    }

    private func normalizeStoredAppLanguageIfNeeded() {
        guard let normalizedLanguage = AppLanguageResolver.normalizedSupportedLanguage(
            appLanguage,
            supportedLanguages: Self.supportedAppLanguages
        ) else {
            appLanguage = AppLanguageResolver.fallbackLanguageCode
            return
        }

        if normalizedLanguage != appLanguage {
            appLanguage = normalizedLanguage
        }
    }

    // MARK: - Methods

    /// 앱 언어 변경
    func changeAppLanguage(to language: String) {
        guard let languageCode = getLanguageCode(for: language) else {
            return
        }

        AppLanguageResolver.clearLegacyAppleLanguagesOverride()
        appLanguage = languageCode

        print("App language changed to: \(languageCode)")

        scheduleLanguageChangeNotification()
    }

    private func scheduleLanguageChangeNotification() {
        languageChangeNotificationTask?.cancel()
        languageChangeNotificationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard !Task.isCancelled else { return }
                self?.uiState.isLanguageChanged.toggle()
                self?.languageChangeNotificationTask = nil
            }
        }
    }

    /// 언어 코드 변환
    private func getLanguageCode(for language: String) -> String? {
        AppLanguageResolver.normalizedSupportedLanguage(
            language,
            supportedLanguages: Self.supportedAppLanguages
        )
    }

    /// 현재 언어 표시명
    func getCurrentLanguageDisplayName() -> String {
        Self.supportedAppLanguages.first { $0.code == appLanguage }?.displayName ?? "English"
    }

    func transcriptionLanguageTitle(for language: String) -> String {
        let normalizedLanguage = language
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()

        if let languageCode = Self.transcriptionLanguageCodes[normalizedLanguage],
           let localizedName = Locale(identifier: appLanguage)
            .localizedString(forLanguageCode: languageCode) {
            return localizedName
        }

        if normalizedLanguage.count <= 8,
           let localizedName = Locale(identifier: appLanguage)
            .localizedString(forLanguageCode: normalizedLanguage) {
            return localizedName
        }

        return language.capitalized
    }

    /// 상태 초기화: 모든 상태 모델의 값을 초기값으로 재설정
    func resetState(preservingImportedAudio: Bool = false) {
        cancelActiveTranscriptionTask()
        cancelActiveSpeakerDiarizationTask()
        stopImportedAudio()
        uiState.isTranscribingView = false
        audioState.isTranscribing = false
        whisperKit?.audioProcessor.stopRecording()

        // 임시 파일 정리
        if !preservingImportedAudio {
            cancelAudioProcessingTasks()
            cleanupPreviousAudioFile()
            audioState.importedAudioURL = nil
            audioState.audioFileName = "Subtitle"
            audioState.waveformSamples = []
            audioState.isWaveformProcessing = false
            audioState.totalDuration = 0
            audioPlaybackState.currentPlayerTime = 0
            audioPlayer = nil
        }

        transcriptionState.currentText = ""
        transcriptionState.currentChunks = [:]
        lastDecoderPreviewUpdate = .distantPast
        transcriptionState.pipelineStart = Double.greatestFiniteMagnitude
        transcriptionState.firstTokenTime = Double.greatestFiniteMagnitude
        transcriptionState.effectiveRealTimeFactor = 0
        transcriptionState.effectiveSpeedFactor = 0
        transcriptionState.totalInferenceTime = 0
        transcriptionState.tokensPerSecond = 0
        transcriptionState.currentLag = 0
        transcriptionState.currentFallbacks = 0
        transcriptionState.currentEncodingLoops = 0
        transcriptionState.currentDecodingLoops = 0
        transcriptionState.lastConfirmedSegmentEndSeconds = 0
        transcriptionState.confirmedSegments = []
        transcriptionState.speakerAssignments = []
        transcriptionState.speakerNames = [:]
        transcriptionState.speakerDiarization = SpeakerDiarizationState()
        uiState.subtitleQualityIssues = []
        uiState.showSubtitleReview = false
        uiState.focusedSubtitleSegmentIndex = nil
        uiState.subtitleIssueFilter = .all
        uiState.subtitleSearchText = ""
        uiState.subtitleReplaceText = ""
        transcriptionResult = nil
    }

    private func cancelActiveTranscriptionTask() {
        uiState.transcribeTask?.cancel()
        uiState.transcribeTask = nil
        activeTranscribeTaskID = nil
    }

    private func cancelActiveSpeakerDiarizationTask() {
        speakerDiarizationTask?.cancel()
        speakerDiarizationTask = nil
        activeSpeakerDiarizationTaskID = nil
        transcriptionState.speakerDiarization.isRunning = false
    }

    private func cancelAudioProcessingTasks() {
        waveformProcessingTask?.cancel()
        waveformProcessingTask = nil
        waveformProcessingTaskID = nil
        normalizationTask?.cancel()
        normalizationTask = nil
        normalizationTaskID = nil
    }

    func prepareForClose() {
        cancelActiveTranscriptionTask()
        cancelActiveSpeakerDiarizationTask()
        cancelAudioProcessingTasks()
        uiState.transcriptionTask?.cancel()
        uiState.transcriptionTask = nil
        languageChangeNotificationTask?.cancel()
        languageChangeNotificationTask = nil

        for task in modelManagementState.downloadTasks.values {
            task.cancel()
        }
        for progress in modelManagementState.downloadProgressObjects.values {
            progress.cancel()
        }
        for task in downloadCancellationMonitorTasks.values {
            task.cancel()
        }
        downloadCancellationMonitorTasks.removeAll()
        modelManagementState.downloadTasks.removeAll()
        modelManagementState.downloadProgressObjects.removeAll()
        modelManagementState.lastProgressCallbackTime.removeAll()
        modelManagementState.currentDownloadingModels.removeAll()
        modelManagementState.cancellingModels.removeAll()
        modelManagementState.queuedDownloadModels.removeAll()
        modelManagementState.downloadBatchModels.removeAll()
        modelManagementState.downloadProgress.removeAll()
        modelManagementState.isDownloading = false
        modelCatalogTask?.cancel()
        modelCatalogTask = nil
        remoteModelSizeTask?.cancel()
        remoteModelSizeTask = nil
        if modelManagementState.catalogLoadState.isLoading {
            modelManagementState.catalogLoadState = .idle
        }
        modelManagementState.isRemoteModelSizeLoading = false
        speakerDiarizationModelTask?.cancel()
        speakerDiarizationModelTask = nil
        modelLoadTask?.cancel()
        modelLoadTask = nil
        isLoadingModel = false
        speakerDiarizationDownloadProgress?.cancel()
        speakerDiarizationDownloadProgress = nil

        stopImportedAudio()
    }

    /// Compute 옵션 생성
    func getComputeOptions() -> ModelComputeOptions {
        return ModelComputeOptions(
            audioEncoderCompute: encoderComputeUnits,
            textDecoderCompute: decoderComputeUnits
        )
    }

    // MARK: - Model Management

    /// 앱 소유 CoreML 런타임 캐시만 정리한다.
    nonisolated func clearCoreMLRuntimeCache() {
        Self.clearCoreMLRuntimeCacheContents()
    }

    private nonisolated static func clearCoreMLRuntimeCacheContents() {
        let fileManager = FileManager.default

        guard let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
            .first else {
            print("Cache directory not found.")
            return
        }

        let bundleID = Bundle.main.bundleIdentifier ?? "com.CaptionMate"
        let appCacheDirectory = cachesDirectory.appendingPathComponent(bundleID, isDirectory: true)
        let cacheDirectories = StorageCleanupPolicy.appScopedCoreMLCacheSubpaths.map {
            appCacheDirectory.appendingPathComponent($0, isDirectory: true)
        }

        var removedItemCount = 0
        var removedBytes: Int64 = 0

        for cacheDirectory in cacheDirectories {
            do {
                let report = try StorageCleanupService.cleanupContents(
                    in: cacheDirectory,
                    fileManager: fileManager
                )
                removedItemCount += report.removedItemCount
                removedBytes += report.removedBytes
            } catch {
                print("Failed to clean CaptionMate runtime cache: \(error.localizedDescription)")
            }
        }

        guard removedItemCount > 0 else {
            print("No CaptionMate runtime cache files found to clean")
            return
        }

        let formattedSize = ByteCountFormatter.string(fromByteCount: removedBytes, countStyle: .file)
        print("CaptionMate runtime cache cleaned: \(removedItemCount) items, \(formattedSize)")
    }

    /// 디스크 여유 공간 확인 함수
    nonisolated func checkDiskSpace() -> (available: Int64, required: Int64, isEnough: Bool) {
        Self.diskSpaceStatus()
    }

    private nonisolated static func diskSpaceStatus() -> (
        available: Int64,
        required: Int64,
        isEnough: Bool
    ) {
        let fileManager = FileManager.default
        guard let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
            .first else {
            return (available: 0, required: 0, isEnough: false)
        }

        do {
            let resourceValues = try cachesDirectory
                .resourceValues(forKeys: [.volumeAvailableCapacityKey])
            guard let availableSpace = resourceValues.volumeAvailableCapacity else {
                return (available: 0, required: 0, isEnough: false)
            }

            let availableSpaceInt64 = Int64(availableSpace)

            // CoreML에 필요한 예상 캐싱 공간
            let requiredSpace: Int64 = 3_000_000_000

            return (
                available: availableSpaceInt64,
                required: requiredSpace,
                isEnough: availableSpaceInt64 > requiredSpace
            )
        } catch {
            print("Failed to check disk space: \(error.localizedDescription)")
            return (available: 0, required: 0, isEnough: false)
        }
    }

    /// 모델 해제
    func releaseModel() async {
        print("Starting model release: \(selectedModel)")

        // 해제 프로세스 시작 상태 설정
        await MainActor.run {
            modelManagementState.modelState = .unloading
            modelManagementState.loadingProgressValue = 0.0

            // 에러 상태 초기화
            modelManagementState.hasModelLoadError = false
            modelManagementState.modelLoadError = nil
        }

        // 점진적인 진행률 업데이트를 위한 Task 시작
        let releaseProgressTask = Task {
            await updateProgressBar(startProgress: 0.0, targetProgress: 0.5, maxTime: 2.0)
        }

        // 백그라운드 작업 취소
        cancelActiveTranscriptionTask()
        uiState.transcriptionTask?.cancel()
        uiState.transcriptionTask = nil
        uiState.isTranscribingView = false

        // 전사 관련 상태 초기화
        resetState()

        // WhisperKit 인스턴스 해제
        if let kit = whisperKit {
            // 모델 언로드 호출로 내부 리소스 정리
            releaseProgressTask.cancel() // 진행 작업 취소

            // 모델 언로드 작업에 대한 새로운 진행률 표시 시작
            let unloadProgressTask = Task {
                await updateProgressBar(startProgress: 0.5, targetProgress: 0.9, maxTime: 2.0)
            }

            await kit.unloadModels()
            unloadProgressTask.cancel()

            // 인스턴스 해제 및 완료 진행률 표시
            let finalProgressTask = Task {
                await updateProgressBar(startProgress: 0.9, targetProgress: 1.0, maxTime: 0.5)
            }

            // 짧은 딜레이 후 최종 상태 설정
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            finalProgressTask.cancel()

            // 인스턴스 해제
            await MainActor.run {
                whisperKit = nil
                modelManagementState.modelState = .unloaded
                modelManagementState.loadingProgressValue = 0.0 // 마지막에 0으로 리셋
                currentLoadedModel = ""
                print("Model release completed: \(selectedModel)")
            }
        } else {
            // WhisperKit 인스턴스가 없는 경우
            releaseProgressTask.cancel()

            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

            await MainActor.run {
                modelManagementState.modelState = .unloaded
                modelManagementState.loadingProgressValue = 0.0
                currentLoadedModel = ""
            }
        }
    }

    func loadModel(_ model: String, redownload: Bool = false) {
        guard !isLoadingModel else { return }
        isLoadingModel = true
        modelLoadTask?.cancel()

        // 상태 초기화
        modelManagementState.modelState = .unloading
        modelManagementState.loadingProgressValue = 0.0

        // 다운로드 진행률 초기화
        if redownload || !modelManagementState.localModels.contains(model) {
            modelManagementState.downloadProgress[model] = 0.0
        }

        // 에러 상태 초기화
        modelManagementState.hasModelLoadError = false
        modelManagementState.modelLoadError = nil

        modelLoadTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.modelLoadTask = nil
                self.isLoadingModel = false
            }
            // 로딩 단계별 진행률 비율 설정 (초기화/프리워밍/로딩)
            let initProgressRatio: Float = 0.9 // 초기화 단계
            let prewarmProgressRatio: Float = 0.7 // 프리워밍 단계
            let loadProgressRatio: Float = 1.0 // 로딩 단계

            // 1. 초기화 단계 진행률 표시 시작
            let initProgressTask = Task {
                await self.updateProgressBar(
                    startProgress: 0.0,
                    targetProgress: initProgressRatio,
                    maxTime: 2.0
                )
            }

            // 디스크 공간 확인 및 캐시 정리
            let diskSpace = self.checkDiskSpace()
            if !diskSpace.isEnough {
                print(
                    "⚠️ Insufficient disk space: Available \(diskSpace.available / 1_000_000) MB, Required \(diskSpace.required / 1_000_000) MB"
                )
                self.clearCoreMLRuntimeCache()
            }

            // 기존 WhisperKit 인스턴스 해제
            if let kit = self.whisperKit {
                await kit.unloadModels()
                print("Previous WhisperKit model released")
                self.whisperKit = nil
            }

            // 초기화 진행률 업데이트 작업 완료
            initProgressTask.cancel()
            await MainActor.run {
                self.modelManagementState.loadingProgressValue = initProgressRatio
            }

            print("Selected model: \(model)")
            let computeOptions = self.getComputeOptions()
            print("""
                연산 옵션:
                - Mel Spectrogram:  \(computeOptions.melCompute.description)
                - Audio Encoder:    \(computeOptions.audioEncoderCompute.description)
                - Text Decoder:     \(computeOptions.textDecoderCompute.description)
                - Prefill Data:     \(computeOptions.prefillCompute.description)
            """)

            // 2. WhisperKit 인스턴스 생성
            do {
                let config = WhisperKitConfig(computeOptions: computeOptions,
                                              verbose: true,
                                              logLevel: .debug,
                                              prewarm: false,
                                              load: false,
                                              download: false)
                self.whisperKit = try await WhisperKit(config)
            } catch {
                print("⚠️ WhisperKit initialization failed: \(error.localizedDescription)")
                await MainActor.run {
                    self.modelManagementState.modelState = .unloaded
                    self.modelManagementState.hasModelLoadError = true
                    self.modelManagementState
                        .modelLoadError =
                        "Model initialization failed: \(error.localizedDescription)"
                    self.modelManagementState.loadingProgressValue = 0.0
                    self.isLoadingModel = false
                }
                return
            }

            guard let whisperKit = self.whisperKit else {
                await MainActor.run {
                    self.modelManagementState.modelState = .unloaded
                    self.modelManagementState.hasModelLoadError = true
                    self.modelManagementState.modelLoadError = "WhisperKit instance creation failed"
                    self.modelManagementState.loadingProgressValue = 0.0
                    self.isLoadingModel = false
                }
                return
            }

            // 3. 모델 파일 설정 단계
            var folder: URL?
            do {
                if self.modelManagementState.localModels.contains(model) && !redownload {
                    // 로컬 모델 경로 가져오기 - 다운로드 없이 바로 로드
                    folder = try ModelCatalogService.modelFolderURL(
                        for: model,
                        in: self.modelManagementState.localModelPath
                    )

                    // 로컬 모델은 다운로드 상태를 완료로 설정
                    if self.modelManagementState.downloadProgress[model] == nil {
                        self.modelManagementState.downloadProgress[model] = 1.0
                    }
                } else {
                    // 다운로드 시작 전 상태 업데이트
                    await MainActor.run {
                        self.modelManagementState.beginDownloadBatchIfIdle()
                        self.modelManagementState.trackDownloadRequest(model)
                        self.modelManagementState.modelState = .downloading
                        self.modelManagementState.currentDownloadingModels.insert(model)
                        self.modelManagementState.isDownloading = true
                    }

                    let downloadTask = Task {
                        await self.updateProgressBar(
                            startProgress: 0.0,
                            targetProgress: 0.99,
                            maxTime: 20.0
                        )
                    }

                    // 모델 다운로드
                    folder = try await WhisperKit.download(
                        variant: model,
                        from: self.repoName,
                        progressCallback: { progress in
                            Task { [weak self] in
                                await MainActor.run { [weak self] in
                                    guard let self else { return }
                                    // 다운로드 전용 진행률 업데이트
                                    self.modelManagementState
                                        .downloadProgress[model] = Float(progress.fractionCompleted)
                                }
                            }
                        }
                    )

                    // 다운로드 완료 후 상태 업데이트
                    downloadTask.cancel()
                    await MainActor.run {
                        self.modelManagementState.modelState = .downloaded
                        self.modelManagementState.downloadProgress[model] = 1.0
                        self.modelManagementState.currentDownloadingModels.remove(model)

                        self.updateDownloadActivityState()

                        if !self.modelManagementState.localModels.contains(model) {
                            self.modelManagementState.localModels.append(model)
                        }
                    }
                }
            } catch {
                print("⚠️ Model download failed: \(error.localizedDescription)")
                await MainActor.run {
                    self.modelManagementState.modelState = .unloaded
                    self.modelManagementState.hasModelLoadError = true
                    self.modelManagementState
                        .modelLoadError = "Model download failed: \(error.localizedDescription)"
                    self.modelManagementState.loadingProgressValue = 0.0
                    self.modelManagementState.downloadProgress[model] = nil
                    self.modelManagementState.currentDownloadingModels.remove(model)
                    self.modelManagementState.untrackDownloadRequest(model)

                    self.updateDownloadActivityState()

                    self.isLoadingModel = false
                }
                return
            }

            if let modelFolder = folder {
                // 4. 모델 프리워밍 단계
                whisperKit.modelFolder = modelFolder

                // 프리워밍 시작
                await MainActor.run {
                    self.modelManagementState.modelState = .prewarming
                }

                // 프리워밍 진행률 업데이트 작업 시작
                let prewarmProgressTask = Task {
                    await self.updateProgressBar(startProgress: 0.0,
                                                 targetProgress: prewarmProgressRatio,
                                                 maxTime: 15) // 프리워밍은 보통 시간이 좀 더 걸림
                }

                // 모델 프리워밍
                do {
                    try await whisperKit.prewarmModels()
                    prewarmProgressTask.cancel()

                    // 프리워밍 완료 후 진행률 업데이트
                    await MainActor.run {
                        self.modelManagementState.loadingProgressValue = prewarmProgressRatio
                    }
                } catch {
                    print("⚠️ Model prewarm failed: \(error.localizedDescription)")
                    prewarmProgressTask.cancel()

                    // 재다운로드 시도
                    if !redownload {
                        await MainActor.run {
                            self.modelManagementState.loadingProgressValue = 0.0
                            self.modelManagementState.hasModelLoadError = true
                            self.modelManagementState
                                .modelLoadError = "Model optimization failed, retrying..."
                            self.isLoadingModel = false
                        }
                        self.loadModel(model, redownload: true)
                        return
                    } else {
                        await MainActor.run {
                            self.modelManagementState.modelState = .unloaded
                            self.modelManagementState.hasModelLoadError = true
                            self.modelManagementState
                                .modelLoadError =
                                "Model optimization failed: \(error.localizedDescription)"
                            self.modelManagementState.loadingProgressValue = 0.0
                            self.isLoadingModel = false
                        }
                        return
                    }
                }

                // 5. 모델 로딩 단계
                await MainActor.run {
                    self.modelManagementState.modelState = .loading
                }

                // 로딩 진행률 업데이트 작업 시작
                let loadProgressTask = Task {
                    await self.updateProgressBar(startProgress: prewarmProgressRatio,
                                                 targetProgress: loadProgressRatio,
                                                 maxTime: 10)
                }

                // 모델 로드 시도
                do {
                    try await whisperKit.loadModels()
                    loadProgressTask.cancel()
                } catch {
                    print("⚠️ Model load failed: \(error.localizedDescription)")
                    loadProgressTask.cancel()

                    // MPSGraph 관련 에러인 경우 캐시 정리 후 한 번만 재시도
                    let errorString = error.localizedDescription
                    if errorString.contains("MPSGraph") || errorString
                        .contains("MPSGraphExecutable") || errorString
                        .contains("No space left on device") {
                        print(
                            "MPSGraph error or disk space shortage detected, retrying after cache cleanup..."
                        )
                        self.clearCoreMLRuntimeCache()

                        // 한 번 더 시도
                        do {
                            try await Task.sleep(nanoseconds: 500_000_000) // 500ms 대기
                            try await whisperKit.loadModels()
                        } catch {
                            await MainActor.run {
                                self.modelManagementState.modelState = .unloaded
                                self.modelManagementState.hasModelLoadError = true
                                self.modelManagementState
                                    .modelLoadError =
                                    "Model load failed (after retry): \(error.localizedDescription)"
                                self.modelManagementState.loadingProgressValue = 0.0
                                self.isLoadingModel = false
                            }
                            return
                        }
                    } else {
                        await MainActor.run {
                            self.modelManagementState.modelState = .unloaded
                            self.modelManagementState.hasModelLoadError = true
                            self.modelManagementState
                                .modelLoadError = "Model load failed: \(error.localizedDescription)"
                            self.modelManagementState.loadingProgressValue = 0.0
                            self.isLoadingModel = false
                        }
                        return
                    }
                }

                // 모델 로딩 성공
                await MainActor.run {
                    // 모델 정보 업데이트 및 완료 상태 설정
                    self.modelManagementState.availableLanguages = Constants.languages.map { $0.key }
                        .sorted()
                    self.modelManagementState.loadingProgressValue = loadProgressRatio
                    self.modelManagementState.modelState = whisperKit.modelState
                    self.currentLoadedModel = model

                    // 에러 상태 초기화 (성공적으로 로드됨)
                    self.modelManagementState.hasModelLoadError = false
                    self.modelManagementState.modelLoadError = nil
                    self.showUserMessage(
                        .success,
                        title: "Model Ready",
                        detail: self.modelManagementState.displayName(for: model)
                    )
                    self.modelLoadTask = nil
                }
            }
        }
    }

    /// 진행률 업데이트 - 시작 진행률부터 목표 진행률까지 자연스럽게 증가
    func updateProgressBar(
        startProgress: Float = 0.0,
        targetProgress: Float,
        maxTime: TimeInterval
    ) async {
        let progressRange = targetProgress - startProgress
        let decayConstant = -log(1 - 0.95) / Float(maxTime) // 95% 완료에 도달하는 시간 기준
        let startTime = Date()
        let updateInterval: TimeInterval = 0.2 // 업데이트 간격 (0.2초)

        // 업데이트 간격을 더 길게 설정하여 CPU 사용량 감소
        while !Task.isCancelled {
            let elapsedTime = Date().timeIntervalSince(startTime)
            // 자연스러운 곡선을 위해 지수 함수 사용
            let decayFactor = exp(-decayConstant * Float(elapsedTime))
            let progressIncrement = progressRange * (1 - decayFactor)
            let currentProgress = startProgress + progressIncrement

            // MainActor에서 한 번만 상태 업데이트
            await MainActor.run {
                modelManagementState.loadingProgressValue = min(currentProgress, targetProgress)
            }

            if currentProgress >= targetProgress { break }

            do {
                try await Task.sleep(nanoseconds: UInt64(updateInterval * 1_000_000_000))
            } catch {
                break
            }
        }
    }

    /// 모델 삭제
    func deleteModel(_ model: String) {
        if modelManagementState.localModels.contains(model) {
            do {
                let modelFolder = try ModelCatalogService.modelFolderURL(
                    for: model,
                    in: modelManagementState.localModelPath
                )

                // 모델 크기 정보 백업
                let modelSize = modelManagementState.modelSizes[model]

                try FileManager.default.removeItem(at: modelFolder)
                if let index = modelManagementState.localModels.firstIndex(of: model) {
                    modelManagementState.localModels.remove(at: index)
                }

                // 선택된 모델이 삭제된 경우 모델 상태 업데이트
                if selectedModel == model {
                    modelManagementState.modelState = .unloaded
                }

                // 모델 크기 정보 유지
                if let size = modelSize {
                    modelManagementState.modelSizes[model] = size
                }

                print("Model deleted: \(model)")
                showUserMessage(
                    .success,
                    title: "Model Deleted",
                    detail: modelManagementState.displayName(for: model)
                )
            } catch {
                print("Error deleting model: \(error)")
                showUserMessage(.error, title: "Delete Failed", detail: error.localizedDescription)
            }
        }
    }

    func refreshSpeakerDiarizationModelState() {
        guard let modelRoot = SpeakerDiarizationModelStore.defaultRootURL() else {
            modelManagementState.speakerDiarizationModelState = .unloaded
            modelManagementState.speakerDiarizationModelPath = ""
            modelManagementState.speakerDiarizationModelError = "Document directory not found."
            modelManagementState.speakerDiarizationModelNeedsRepair = false
            modelManagementState.speakerDiarizationModelNeedsUpdate = false
            return
        }

        modelManagementState.speakerDiarizationModelPath = modelRoot.path

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: modelRoot.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            modelManagementState.speakerDiarizationModelState = .unloaded
            modelManagementState.speakerDiarizationModelProgress = nil
            modelManagementState.speakerDiarizationModelError = nil
            modelManagementState.speakerDiarizationModelNeedsRepair = false
            modelManagementState.speakerDiarizationModelNeedsUpdate = false
            modelManagementState.speakerDiarizationModelSize = SpeakerDiarizationModelStore
                .estimatedDownloadSize
            return
        }

        let report = SpeakerDiarizationModelStore.validationReport(for: modelRoot)
        let folderSize = ModelCatalogService.folderSize(url: modelRoot)
        modelManagementState.speakerDiarizationModelSize = max(
            folderSize,
            SpeakerDiarizationModelStore.estimatedDownloadSize
        )

        if report.isValid {
            let needsUpdate = speakerDiarizationModelManifestVersion <
                SpeakerDiarizationModelStore.manifestVersion
            modelManagementState.speakerDiarizationModelState = .downloaded
            modelManagementState.speakerDiarizationModelProgress = 1.0
            modelManagementState.speakerDiarizationModelError = needsUpdate ? "Update available" : nil
            modelManagementState.speakerDiarizationModelNeedsRepair = false
            modelManagementState.speakerDiarizationModelNeedsUpdate = needsUpdate
        } else {
            modelManagementState.speakerDiarizationModelState = .unloaded
            modelManagementState.speakerDiarizationModelProgress = nil
            modelManagementState.speakerDiarizationModelError =
                "Missing files: \(report.missingRelativePaths.prefix(3).joined(separator: ", "))"
            modelManagementState.speakerDiarizationModelNeedsRepair = true
            modelManagementState.speakerDiarizationModelNeedsUpdate = false
        }
    }

    func prepareDefaultSpeakerDiarizationModelIfNeeded(
        forceRepair: Bool = false,
        showSuccessMessage: Bool = false
    ) {
#if DEBUG
        guard !Self.isUITesting else {
            refreshSpeakerDiarizationModelState()
            return
        }
#endif

        guard !modelManagementState.isSpeakerDiarizationModelPreparing else { return }

        refreshSpeakerDiarizationModelState()
        if !forceRepair, modelManagementState.isSpeakerDiarizationModelReady {
            return
        }

        guard let modelRoot = SpeakerDiarizationModelStore.defaultRootURL() else {
            modelManagementState.speakerDiarizationModelError = "Document directory not found."
            return
        }

        let shouldResetLocalCache = forceRepair ||
            modelManagementState.speakerDiarizationModelNeedsRepair ||
            modelManagementState.speakerDiarizationModelNeedsUpdate

        speakerDiarizationModelTask?.cancel()
        speakerDiarizationDownloadProgress = nil
        modelManagementState.speakerDiarizationModelState = .downloading
        modelManagementState.speakerDiarizationModelProgress = 0.0
        modelManagementState.speakerDiarizationModelError = nil
        modelManagementState.speakerDiarizationModelNeedsRepair = false
        modelManagementState.speakerDiarizationModelNeedsUpdate = false
        modelManagementState.speakerDiarizationModelPath = modelRoot.path

        speakerDiarizationModelTask = Task.detached(priority: .background) { [weak self] in
            do {
                if shouldResetLocalCache {
                    try? FileManager.default.removeItem(at: modelRoot)
                }

                let diskSpace = Self.diskSpaceStatus()
                if !diskSpace.isEnough {
                    Self.clearCoreMLRuntimeCacheContents()
                }

                let config = PyannoteConfig(
                    modelRepo: SpeakerDiarizationModelStore.repoName,
                    download: true,
                    useBackgroundDownloadSession: false,
                    load: false,
                    verbose: false,
                    concurrentSegmenterWorkers: 1,
                    concurrentEmbedderWorkers: 1
                )
                let diarizer = SpeakerKitDiarizer.pyannote(config: config)
                let progressCallback: (Progress) -> Void = { [weak self] progress in
                    Task<Void, Never> { @MainActor [weak self] in
                        self?.updateSpeakerDiarizationDownloadProgress(progress)
                    }
                }
                _ = try await diarizer.loader.resolveModels(
                    downloader: diarizer.downloader,
                    progressCallback: progressCallback
                )
                try Task.checkCancellation()

                let report = SpeakerDiarizationModelStore.validationReport(for: modelRoot)
                guard report.isValid else {
                    throw CocoaError(.fileReadCorruptFile)
                }

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.modelManagementState.speakerDiarizationModelProgress = 1.0
                    self.refreshSpeakerDiarizationModelState()
                    self.speakerDiarizationModelManifestVersion = SpeakerDiarizationModelStore
                        .manifestVersion
                    self.refreshSpeakerDiarizationModelState()
                    self.speakerDiarizationDownloadProgress = nil
                    self.speakerDiarizationModelTask = nil

                    if showSuccessMessage {
                        self.showUserMessage(
                            .success,
                            title: "Speaker Model Ready",
                            detail: self.modelManagementState.formattedSpeakerDiarizationModelSize
                        )
                    }
                }
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: modelRoot)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.modelManagementState.speakerDiarizationModelState = .unloaded
                    self.modelManagementState.speakerDiarizationModelProgress = nil
                    self.modelManagementState.speakerDiarizationModelError = "Download cancelled."
                    self.speakerDiarizationDownloadProgress = nil
                    self.speakerDiarizationModelTask = nil
                }
            } catch {
                let modelExists = FileManager.default.fileExists(atPath: modelRoot.path)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.modelManagementState.speakerDiarizationModelState = .unloaded
                    self.modelManagementState.speakerDiarizationModelProgress = nil
                    self.modelManagementState.speakerDiarizationModelError = error.localizedDescription
                    self.modelManagementState.speakerDiarizationModelNeedsRepair = modelExists
                    self.speakerDiarizationDownloadProgress = nil
                    self.speakerDiarizationModelTask = nil
                }
            }
        }
    }

    func repairDefaultSpeakerDiarizationModel() {
        prepareDefaultSpeakerDiarizationModelIfNeeded(
            forceRepair: true,
            showSuccessMessage: true
        )
    }

    private func updateSpeakerDiarizationDownloadProgress(_ progress: Progress) {
        speakerDiarizationDownloadProgress = progress
        let fraction = progress.fractionCompleted
        guard fraction.isFinite else { return }
        modelManagementState.speakerDiarizationModelProgress =
            Float(min(max(fraction, 0), 1))
    }

    func cancelDefaultSpeakerDiarizationModelDownload() {
        guard modelManagementState.isSpeakerDiarizationModelPreparing else { return }
        speakerDiarizationDownloadProgress?.cancel()
        speakerDiarizationDownloadProgress = nil
        speakerDiarizationModelTask?.cancel()
        speakerDiarizationModelTask = nil
        modelManagementState.speakerDiarizationModelState = .unloaded
        modelManagementState.speakerDiarizationModelProgress = nil
        modelManagementState.speakerDiarizationModelError = "Download cancelled."

        if let modelRoot = SpeakerDiarizationModelStore.defaultRootURL() {
            Task(priority: .utility) {
                try? FileManager.default.removeItem(at: modelRoot)
            }
        }
    }

    // MARK: - 모델 다운로드 관리

    /// 모델 다운로드
    func downloadModel(_ model: String) {
        guard modelManagementState.canStartDownload(model: model) else {
            showUserMessage(.warning, title: "Download Unavailable")
            return
        }

        modelManagementState.beginDownloadBatchIfIdle()
        modelManagementState.trackDownloadRequest(model)

        if !modelManagementState.hasAvailableDownloadSlot {
            modelManagementState.queuedDownloadModels.append(model)
            modelManagementState.downloadProgress[model] = 0.0
            modelManagementState.downloadErrors.removeValue(forKey: model)
            showUserMessage(
                .info,
                title: "Download Queued",
                detail: modelManagementState.displayName(for: model)
            )
            return
        }

        startModelDownload(model)
    }

    private func startNextQueuedDownloadIfPossible() {
        while modelManagementState.hasAvailableDownloadSlot,
              !modelManagementState.queuedDownloadModels.isEmpty {
            let nextModel = modelManagementState.queuedDownloadModels.removeFirst()
            startModelDownload(nextModel)
        }
    }

    private func updateDownloadActivityState() {
        modelManagementState.isDownloading = modelManagementState.hasVisibleDownloadActivity
        modelManagementState.clearDownloadBatchIfIdle()
    }

    private func estimatedDownloadSize(for model: String) -> Int64 {
        max(
            modelManagementState.downloadDisplaySize(for: model),
            ModelCatalogService.estimatedDownloadSize(for: model)
        )
    }

    private func estimatedRequiredDownloadSpace(for model: String) -> Int64 {
        Int64(Double(estimatedDownloadSize(for: model)) * 1.2)
    }

    private func estimatedRemainingDownloadSpaceForOtherActiveDownloads(
        excluding model: String
    ) -> Int64 {
        modelManagementState.currentDownloadingModels
            .filter { $0 != model }
            .reduce(Int64(0)) { total, activeModel in
                let remainingProgress = 1.0 - Double(
                    modelManagementState.downloadProgressValue(for: activeModel)
                )
                let remainingSize = Double(estimatedDownloadSize(for: activeModel)) *
                    max(remainingProgress, 0)
                return total + Int64(remainingSize * 1.2)
            }
    }

    private func startModelDownload(_ model: String) {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first else {
            print("Document directory not found")
            modelManagementState.untrackDownloadRequest(model)
            updateDownloadActivityState()
            showUserMessage(.error, title: "Download Failed", detail: "Document directory not found.")
            return
        }

        // 다운로드 상태 업데이트
        modelManagementState.trackDownloadRequest(model)
        modelManagementState.currentDownloadingModels.insert(model)
        modelManagementState.isDownloading = true
        modelManagementState.downloadProgress[model] = 0.0
        modelManagementState.downloadErrors.removeValue(forKey: model)

        // 기존 다운로드 Task가 있다면 취소
        if let existingTask = modelManagementState.downloadTasks[model] {
            existingTask.cancel()
            modelManagementState.downloadTasks[model] = nil
        }

        let repoName = repoName
        let estimatedSize = estimatedDownloadSize(for: model)
        let requiredSpace = estimatedRequiredDownloadSpace(for: model)
        let reservedSpaceForOtherDownloads =
            estimatedRemainingDownloadSpaceForOtherActiveDownloads(excluding: model)
        let localModelPath = modelManagementState.localModelPath

        let task = Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }

            do {
                let resourceValues = try documents
                    .resourceValues(forKeys: [.volumeAvailableCapacityKey])
                guard let availableSpace = resourceValues.volumeAvailableCapacity else {
                    await MainActor.run {
                        self.modelManagementState.downloadErrors[model] = "Cannot check disk space."
                        self.modelManagementState.currentDownloadingModels.remove(model)
                        self.modelManagementState.downloadProgress[model] = nil
                        self.modelManagementState.downloadTasks[model] = nil
                        self.modelManagementState.untrackDownloadRequest(model)
                        self.showUserMessage(
                            .error,
                            title: "Download Failed",
                            detail: "Cannot check disk space."
                        )
                        self.startNextQueuedDownloadIfPossible()
                        self.updateDownloadActivityState()
                    }
                    return
                }

                let totalRequiredSpace = requiredSpace + reservedSpaceForOtherDownloads

                if availableSpace < totalRequiredSpace {
                    let availableGB = Double(availableSpace) / 1_000_000_000.0
                    let requiredGB = Double(totalRequiredSpace) / 1_000_000_000.0
                    let errorMessage = String(
                        format: "Insufficient disk space. Required: %.1f GB, Available: %.1f GB",
                        requiredGB,
                        availableGB
                    )
                    await MainActor.run {
                        self.modelManagementState.downloadErrors[model] = errorMessage
                        self.modelManagementState.currentDownloadingModels.remove(model)
                        self.modelManagementState.downloadProgress[model] = nil
                        self.modelManagementState.downloadTasks[model] = nil
                        self.modelManagementState.untrackDownloadRequest(model)
                        self.showUserMessage(.error, title: "Download Failed", detail: errorMessage)
                        self.startNextQueuedDownloadIfPossible()
                        self.updateDownloadActivityState()
                    }
                    return
                }

                let progressUpdateInterval: TimeInterval = 0.5
                var lastUpdateTime = Date()

                let modelFolder = try await WhisperKit.download(
                    variant: model,
                    from: repoName,
                    progressCallback: { [weak self] progress in
                        guard let self = self else { return }

                        // Progress 콜백 활동 기록 (모든 콜백에서 기록)
                        Task { @MainActor in
                            self.modelManagementState.lastProgressCallbackTime[model] = Date()

                            // Progress 객체 저장 (처음 한 번만)
                            if self.modelManagementState.downloadProgressObjects[model] == nil {
                                self.modelManagementState.downloadProgressObjects[model] = progress
                                print("Progress object stored: \(model)")
                            }

                            // Progress 완료 감지 (1.0 도달 시 cancelling 상태 해제)
                            if self.modelManagementState.cancellingModels.contains(model) &&
                                progress.fractionCompleted >= 1.0 {
                                print(
                                    "Progress completion detected (fractionCompleted: \(progress.fractionCompleted)) - Cancelling state released: \(model)"
                                )
                                self.modelManagementState.cancellingModels.remove(model)
                                self.modelManagementState.lastProgressCallbackTime
                                    .removeValue(forKey: model)
                                self.modelManagementState.downloadProgressObjects
                                    .removeValue(forKey: model)

                                // 부분 다운로드 파일 정리 (비동기)
                                Task.detached {
                                    Self.cleanupPartialDownload(
                                        model,
                                        localModelPath: localModelPath
                                    )
                                }
                            }
                        }

                        // 작업이 취소되었는지 확인
                        if Task.isCancelled {
                            print(
                                "Task cancellation detected - terminating from progress callback: \(model)"
                            )
                            return
                        }

                        // 취소 중인 상태인지 확인
                        let isCancelling = Task { @MainActor in
                            self.modelManagementState.cancellingModels.contains(model)
                        }

                        Task {
                            if await isCancelling.value || progress.isCancelled {
                                print(
                                    "Cancellation detected - immediate download stop: \(model) (progress: \(String(format: "%.1f", progress.fractionCompleted * 100))%)"
                                )

                                // Progress가 취소되었으면 즉시 파일 삭제
                                if progress.isCancelled {
                                    print(
                                        "NSProgress cancellation detected - starting immediate file deletion: \(model)"
                                    )

                                    // 즉시 부분 다운로드 파일 정리
                                    Task.detached {
                                        Self.cleanupPartialDownload(
                                            model,
                                            localModelPath: localModelPath
                                        )
                                    }

                                    // 마지막 취소 완료 콜백까지 기다리기 위해 타임스탬프만 업데이트
                                    await MainActor.run {
                                        self.modelManagementState
                                            .lastProgressCallbackTime[model] = Date()
                                    }
                                }

                                // Progress 콜백에서 즉시 return하여 더 이상 진행하지 않음
                                return
                            }
                        }

                        // 진행률 업데이트 최적화
                        let currentTime = Date()
                        if currentTime.timeIntervalSince(lastUpdateTime) >= progressUpdateInterval {
                            Task { @MainActor in
                                // 취소 중인 상태라면 UI 업데이트 건너뛰기
                                if self.modelManagementState.cancellingModels.contains(model) {
                                    print("Cancelling - skipping UI update: \(model)")
                                    return
                                }

                                // 다운로드 중이 아니면 종료
                                guard self.modelManagementState.currentDownloadingModels
                                    .contains(model) else {
                                    return
                                }

                                self.modelManagementState
                                    .downloadProgress[model] = Float(progress.fractionCompleted)

                                // 다운로드 중 디스크 공간 재확인 (50% 이상 다운로드된 경우에만)
                                if progress.fractionCompleted > 0.5 {
                                    if let resourceValues = try? documents
                                        .resourceValues(forKeys: [.volumeAvailableCapacityKey]),
                                        let currentSpace = resourceValues.volumeAvailableCapacity,
                                        currentSpace <
                                        Int64(
                                            Double(estimatedSize) *
                                                max(1.0 - progress.fractionCompleted, 0) *
                                                1.2
                                        ) +
                                        self.estimatedRemainingDownloadSpaceForOtherActiveDownloads(
                                            excluding: model
                                        ) {
                                        progress.cancel()
                                        self.modelManagementState
                                            .downloadErrors[model] =
                                            "Disk space became insufficient during download"
                                        self.modelManagementState.currentDownloadingModels
                                            .remove(model)
                                        self.modelManagementState.untrackDownloadRequest(model)
                                        self.updateDownloadActivityState()
                                        return
                                    }
                                }
                            }
                            lastUpdateTime = currentTime
                        }
                    }
                )

                // 작업이 취소되었는지 확인
                if Task.isCancelled {
                    throw CancellationError()
                }

                let actualSize = await Task.detached {
                    ModelCatalogService.folderSize(url: modelFolder)
                }.value

                await MainActor.run {
                    self.modelManagementState.currentDownloadingModels.remove(model)
                    self.modelManagementState.downloadProgress[model] = 1.0
                    self.modelManagementState.downloadTasks[model] = nil
                    self.modelManagementState.downloadProgressObjects.removeValue(forKey: model)
                    self.modelManagementState.lastProgressCallbackTime.removeValue(forKey: model)

                    if !self.modelManagementState.localModels.contains(model) {
                        self.modelManagementState.localModels.append(model)
                    }

                    self.modelManagementState.modelSizes[model] = actualSize
                    self.modelManagementState.modelSizeSources[model] = .local

                    self.showUserMessage(
                        .success,
                        title: "Model Downloaded",
                        detail: self.modelManagementState.displayName(for: model)
                    )
                    self.startNextQueuedDownloadIfPossible()
                    self.updateDownloadActivityState()
                }

            } catch is CancellationError {
                print("Model download cancelled: \(model)")
                let isCancelling = await MainActor
                    .run { self.modelManagementState.cancellingModels.contains(model) }
                if !isCancelling {
                    Self.cleanupPartialDownload(model, localModelPath: localModelPath)
                    await MainActor.run {
                        self.modelManagementState.currentDownloadingModels.remove(model)
                        self.modelManagementState.downloadProgress[model] = nil
                        self.modelManagementState.downloadTasks[model] = nil
                        self.modelManagementState.downloadProgressObjects.removeValue(forKey: model)
                        self.modelManagementState.lastProgressCallbackTime.removeValue(forKey: model)
                        self.modelManagementState.untrackDownloadRequest(model)
                        self.startNextQueuedDownloadIfPossible()
                        self.updateDownloadActivityState()
                    }
                }
            } catch {
                print("Model download failed: \(error.localizedDescription)")

                let downloadError = DownloadError.from(error)

                await MainActor.run {
                    self.modelManagementState
                        .downloadErrors[model] = "Download failed: \(error.localizedDescription)"
                    self.modelManagementState.currentDownloadingModels.remove(model)
                    self.modelManagementState.downloadProgress[model] = nil
                    self.modelManagementState.downloadTasks[model] = nil
                    self.modelManagementState.cancellingModels.remove(model) // 에러 시 취소 상태도 해제
                    self.modelManagementState.lastProgressCallbackTime.removeValue(forKey: model)
                    self.modelManagementState.downloadProgressObjects.removeValue(forKey: model)
                    self.modelManagementState.untrackDownloadRequest(model)

                    // 다운로드 실패 알림 표시 (취소로 인한 에러가 아닌 경우만)
                    if let downloadError = downloadError {
                        self.uiState.downloadError = downloadError
                        self.uiState.showDownloadErrorAlert = true
                    }
                    self.showUserMessage(
                        .error,
                        title: "Download Failed",
                        detail: error.localizedDescription
                    )
                    self.startNextQueuedDownloadIfPossible()
                    self.updateDownloadActivityState()
                }
                Self.cleanupPartialDownload(model, localModelPath: localModelPath)
            }
        }

        modelManagementState.downloadTasks[model] = task
    }

    /// 부분 다운로드 파일 정리 헬퍼 메서드
    private func cleanupPartialDownload(_ model: String) async {
        Self.cleanupPartialDownload(model, localModelPath: modelManagementState.localModelPath)
    }

    private nonisolated static func cleanupPartialDownload(
        _ model: String,
        localModelPath: String
    ) {
        // 부분적으로 다운로드된 파일 삭제
        guard let modelFolder = try? ModelCatalogService.modelFolderURL(
            for: model,
            in: localModelPath
        ) else {
            print("Skipped partial download cleanup for unsafe model name: \(model)")
            return
        }

        if FileManager.default.fileExists(atPath: modelFolder.path) {
            do {
                try FileManager.default.removeItem(at: modelFolder)
                print("Partial download file deleted: \(model)")
            } catch {
                print("Failed to delete partial download file: \(error.localizedDescription)")
            }
        }
    }

    /// 다운로드 취소
    func cancelDownload(_ model: String) {
        if let queuedIndex = modelManagementState.queuedDownloadModels.firstIndex(of: model) {
            modelManagementState.queuedDownloadModels.remove(at: queuedIndex)
            modelManagementState.downloadProgress[model] = nil
            modelManagementState.downloadErrors.removeValue(forKey: model)
            modelManagementState.untrackDownloadRequest(model)
            updateDownloadActivityState()
            showUserMessage(
                .info,
                title: "Download Cancelled",
                detail: modelManagementState.displayName(for: model)
            )
            return
        }

        guard let task = modelManagementState.downloadTasks[model],
              modelManagementState.currentDownloadingModels.contains(model) else {
            return
        }

        print("Download cancellation requested: \(model)")

        // 1. 즉시 취소 중 상태로 변경
        modelManagementState.cancellingModels.insert(model)
        modelManagementState.currentDownloadingModels.remove(model)
        modelManagementState.untrackDownloadRequest(model)
        updateDownloadActivityState()

        // 2. NSProgress 직접 취소 (다운로드 즉시 중단)
        if let progress = modelManagementState.downloadProgressObjects[model] {
            progress.cancel()
            print("NSProgress directly cancelled: \(model)")
        }

        // 3. Task 취소
        task.cancel()

        // 3. Progress 콜백이 완전히 멈출 때까지 모니터링 시작
        downloadCancellationMonitorTasks[model]?.cancel()
        downloadCancellationMonitorTasks[model] = Task { [weak self] in
            await self?.monitorProgressCompletion(model: model)
        }

        print(
            "Download cancellation processing completed - Progress completion monitoring started: \(model)"
        )
    }

    /// 마지막 취소 완료 콜백 감지 모니터링
    private func monitorProgressCompletion(model: String) async {
        let maxWaitTime: TimeInterval = 30.0 // 최대 30초 대기
        let checkInterval: TimeInterval = 0.5 // 0.5초마다 확인
        let inactivityThreshold: TimeInterval = 3.0 // 3초간 비활성 시 마지막 콜백으로 간주

        let startTime = Date()
        print("Cancellation completion callback monitoring started: \(model)")

        while await MainActor
            .run(body: { self.modelManagementState.cancellingModels.contains(model) }) {
            // 최대 대기 시간 초과 확인
            if Date().timeIntervalSince(startTime) > maxWaitTime {
                print(
                    "Cancellation completion monitoring timeout (30s) - forced termination: \(model)"
                )
                break
            }

            // 마지막 Progress 콜백 활동 확인
            let lastActivity = await MainActor.run {
                self.modelManagementState.lastProgressCallbackTime[model]
            }

            if let lastActivity = lastActivity {
                let timeSinceLastActivity = Date().timeIntervalSince(lastActivity)

                // 3초간 비활성이면 마지막 취소 완료 콜백으로 간주
                if timeSinceLastActivity > inactivityThreshold {
                    print(
                        "Last cancellation completion callback detected (\(String(format: "%.1f", timeSinceLastActivity))s inactive) - Cancelling UI released: \(model)"
                    )
                    break
                }
            }

            // 대기
            do {
                try await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
            } catch {
                return
            }
        }

        guard !Task.isCancelled else { return }

        // 최종 정리 (마지막 콜백 완료 후)
        await finalizeProgressCompletion(model: model)
    }

    /// Progress 완료 후 최종 상태 정리
    private func finalizeProgressCompletion(model: String) async {
        await MainActor.run {
            // 취소 중 상태 해제
            self.modelManagementState.cancellingModels.remove(model)
            self.modelManagementState.lastProgressCallbackTime.removeValue(forKey: model)
            self.modelManagementState.downloadProgressObjects.removeValue(forKey: model)
            self.modelManagementState.currentDownloadingModels.remove(model)

            // 다운로드 관련 상태 정리
            self.modelManagementState.downloadProgress[model] = nil
            self.modelManagementState.downloadTasks[model] = nil
            self.modelManagementState.untrackDownloadRequest(model)
            self.downloadCancellationMonitorTasks.removeValue(forKey: model)

            // 모든 다운로드가 완료되었는지 확인
            print("Progress completion confirmed - Cancelling UI released: \(model)")
            self.startNextQueuedDownloadIfPossible()
            self.updateDownloadActivityState()
        }

        // 부분 다운로드 파일 정리
        await cleanupPartialDownload(model)
    }

    // MARK: - 파일 선택 및 처리

    /// 파일 선택
    func selectFile() {
        uiState.isFilePickerPresented = true
    }

    /// 파일 선택 결과 처리 (파일 임포트 후 URL 저장 및 전사 호출)
    func handleFilePicker(result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard !urls.isEmpty else { return }
            if urls.count > 1 {
                setBatchQueue(urls, needsSecurityScopedAccess: true)
            }

            guard let selectedFileURL = urls.first else { return }
            Task {
                if urls.count > 1 {
                    await loadBatchItem(at: 0)
                } else {
                    clearBatchQueue()
                    await processSelectedFile(
                        selectedFileURL,
                        needsSecurityScopedAccess: true
                    )
                }
            }
        case let .failure(error):
            print("File selection error: \(error.localizedDescription)")
            showUserMessage(.error, title: "Import Failed", detail: error.localizedDescription)
        }
    }

    func setBatchQueue(_ urls: [URL], needsSecurityScopedAccess: Bool) {
        batchQueue = urls.map { url in
            BatchImportItem(
                url: url,
                displayName: url.deletingPathExtension().lastPathComponent,
                needsSecurityScopedAccess: needsSecurityScopedAccess
            )
        }
        currentBatchIndex = batchQueue.isEmpty ? nil : 0
        showUserMessage(
            .success,
            title: "Batch Queue Ready",
            detail: "\(batchQueue.count) files added."
        )
    }

    func clearBatchQueue() {
        batchQueue = []
        currentBatchIndex = nil
    }

    func loadBatchItem(at index: Int) async {
        guard batchQueue.indices.contains(index) else { return }
        currentBatchIndex = index
        let item = batchQueue[index]
        await processSelectedFile(
            item.url,
            needsSecurityScopedAccess: item.needsSecurityScopedAccess
        )
    }

    func loadNextBatchItem() {
        guard let currentBatchIndex,
              batchQueue.indices.contains(currentBatchIndex + 1) else {
            showUserMessage(.info, title: "End of Batch")
            return
        }

        Task {
            await loadBatchItem(at: currentBatchIndex + 1)
        }
    }

    func loadPreviousBatchItem() {
        guard let currentBatchIndex,
              batchQueue.indices.contains(currentBatchIndex - 1) else {
            showUserMessage(.info, title: "Start of Batch")
            return
        }

        Task {
            await loadBatchItem(at: currentBatchIndex - 1)
        }
    }

    func removeBatchItem(at index: Int) {
        guard batchQueue.indices.contains(index) else { return }
        batchQueue.remove(at: index)

        if batchQueue.isEmpty {
            currentBatchIndex = nil
        } else if let currentBatchIndex {
            self.currentBatchIndex = min(currentBatchIndex, batchQueue.count - 1)
        }
    }

    /// 선택된 파일 처리 (비동기 작업)
    @MainActor
    private func processSelectedFile(
        _ selectedFileURL: URL,
        needsSecurityScopedAccess: Bool
    ) async {
        do {
            let importedAudio = try await Self.prepareAudioImport(
                from: selectedFileURL,
                needsSecurityScopedAccess: needsSecurityScopedAccess
            )

            resetState()

            // 임시 파일 URL 저장 (나중에 정리용)
            audioState.temporaryAudioURL = importedAudio.localURL
            audioState.audioFileName = importedAudio.displayName
            audioState.waveformSamples = []
            audioState.isWaveformProcessing = true
            normalizedVolumeFactor = 1.0

            // 파일을 임포트한 후 바로 총 재생 시간을 확인하고 업데이트
            do {
                let audioAsset = AVURLAsset(url: importedAudio.localURL)
                let duration = try await audioAsset.load(.duration)
                let durationInSeconds = CMTimeGetSeconds(duration)

                // 재생 시간 업데이트 (재생 시작 전에 미리 설정)
                audioState.totalDuration = durationInSeconds
                audioPlayer?.currentTime = 0.0
                print("Audio file duration: \(durationInSeconds) seconds")

                // 미리 AVAudioPlayer 생성하여 정보 준비
                let player = try AVAudioPlayer(contentsOf: importedAudio.localURL)
                audioPlayer = player
                audioPlayer?.prepareToPlay() // 버퍼링 미리 수행
                applyVolume()

                // 정확한 재생 시간 재확인
                if audioState.totalDuration == 0 {
                    audioState.totalDuration = player.duration
                }
            } catch {
                print("Audio file info reading error: \(error.localizedDescription)")
            }

            // 파일 URL 저장
            audioState.importedAudioURL = importedAudio.localURL

            if let sidecar = importedAudio.sidecar {
                restoreTranscriptionSidecar(sidecar, sourceURL: importedAudio.sidecarURL)
                let sidecarName = importedAudio.sidecarURL?.lastPathComponent ?? "sidecar"
                showUserMessage(
                    .success,
                    title: "Saved Subtitles Restored",
                    detail: "\(sidecar.segments.count) segment(s) restored from \(sidecarName). " +
                        "Review or transcribe again if the audio changed.",
                    autoDismissAfter: 6.0
                )
            } else if let sidecarRestoreError = importedAudio.sidecarRestoreError {
                showUserMessage(
                    .warning,
                    title: "Sidecar Restore Failed",
                    detail: sidecarRestoreError
                )
            } else {
                showUserMessage(
                    .success,
                    title: "Audio Ready",
                    detail: "\(importedAudio.displayName) is ready to transcribe."
                )
            }

            updateNormalizationFactor(for: importedAudio.localURL)
            startWaveformProcessing(for: importedAudio.localURL)
        } catch {
            print("File selection error: \(error.localizedDescription)")
            showUserMessage(.error, title: "Import Failed", detail: error.localizedDescription)
        }
    }

    private func updateNormalizationFactor(for audioURL: URL) {
        normalizationTask?.cancel()
        let taskID = UUID()
        normalizationTaskID = taskID
        normalizationTask = Task { [weak self] in
            let calculationTask = Task.detached(priority: .utility) {
                Self.normalizationFactor(for: audioURL)
            }
            let normalizationFactor = await withTaskCancellationHandler(operation: {
                await calculationTask.value
            }, onCancel: {
                calculationTask.cancel()
            })

            guard let self,
                  !Task.isCancelled,
                  self.normalizationTaskID == taskID,
                  self.audioState.importedAudioURL == audioURL else { return }

            self.normalizedVolumeFactor = normalizationFactor
            self.applyVolume()
            self.clearNormalizationTaskIfCurrent(taskID)
        }
    }

    private func startWaveformProcessing(for url: URL) {
        waveformProcessingTask?.cancel()
        let taskID = UUID()
        waveformProcessingTaskID = taskID
        waveformProcessingTask = Task { [weak self] in
            await self?.processWaveform(for: url)
            await MainActor.run { [weak self] in
                self?.clearWaveformProcessingTaskIfCurrent(taskID)
            }
        }
    }

    private func clearWaveformProcessingTaskIfCurrent(_ taskID: UUID) {
        guard waveformProcessingTaskID == taskID else { return }
        waveformProcessingTask = nil
        waveformProcessingTaskID = nil
    }

    private func clearNormalizationTaskIfCurrent(_ taskID: UUID) {
        guard normalizationTaskID == taskID else { return }
        normalizationTask = nil
        normalizationTaskID = nil
    }

    /// 볼륨 적용 함수
    private func applyVolume() {
        guard let player = audioPlayer else { return }

        // 음소거 상태인 경우
        if isMuted {
            player.volume = 0.0
            return
        }

        // 노멀라이제이션 계수와 사용자 볼륨 설정을 곱해서 적용
        player.volume = normalizedVolumeFactor * Float(audioVolume)
    }

    /// 파일 전사 시작
    func transcribeFile(path: String) {
        resetState(preservingImportedAudio: true)
        stopImportedAudio()
        whisperKit?.audioProcessor = AudioProcessor()
        let taskID = UUID()
        activeTranscribeTaskID = taskID
        uiState.transcribeTask = Task { [weak self] in
            guard let self else { return }
            self.audioState.isTranscribing = true
            self.showUserMessage(.info, title: "Transcribing", detail: self.audioState.audioFileName)
            defer {
                self.audioState.isTranscribing = false
                if self.activeTranscribeTaskID == taskID {
                    self.uiState.transcribeTask = nil
                    self.activeTranscribeTaskID = nil
                }
            }

            do {
                try await self.transcribeCurrentFile(path: path)
            } catch is CancellationError {
                self.showUserMessage(.info, title: "Transcription Cancelled")
            } catch {
                print("Transcription error: \(error.localizedDescription)")
                self.showUserMessage(
                    .error,
                    title: "Transcription Failed",
                    detail: error.localizedDescription
                )
            }
        }
    }

    /// 오디오 파일 전사 진행
    func transcribeCurrentFile(path: String) async throws {
        Logging.debug("Loading audio file: \(path)")
        let loadingStart = Date()
        let audioFileSamples = try await Task.detached(priority: .userInitiated) {
            try autoreleasepool {
                try AudioProcessor.loadAudioAsFloatArray(fromPath: path)
            }
        }.value
        Logging.debug("Loaded audio file in \(Date().timeIntervalSince(loadingStart)) seconds")

        let transcription = try await transcribeAudioSamples(audioFileSamples)

        await MainActor.run {
            transcriptionState.currentText = ""
            transcriptionResult = transcription

            guard let segments = transcription?.segments else { return }
            transcriptionState.tokensPerSecond = transcription?.timings.tokensPerSecond ?? 0
            transcriptionState.effectiveRealTimeFactor = transcription?.timings.realTimeFactor ?? 0
            transcriptionState.effectiveSpeedFactor = transcription?.timings.speedFactor ?? 0
            transcriptionState
                .currentEncodingLoops = Int(transcription?.timings.totalEncodingRuns ?? 0)
            transcriptionState.firstTokenTime = transcription?.timings.firstTokenTime ?? 0
            transcriptionState.modelLoadingTime = transcription?.timings.modelLoading ?? 0
            transcriptionState.pipelineStart = transcription?.timings.pipelineStart ?? 0
            transcriptionState.currentLag = transcription?.timings.decodingLoop ?? 0
            transcriptionState.confirmedSegments = segments
            transcriptionState.speakerAssignments = Array(repeating: nil, count: segments.count)
            transcriptionState.speakerNames = [:]
            transcriptionState.speakerDiarization = SpeakerDiarizationState()
            refreshSubtitleQualityIssues()
            showUserMessage(
                .success,
                title: "Transcription Complete",
                detail: "\(segments.count) segments are ready to edit and export."
            )
            audioState.isTranscribing = false
        }

        try Task.checkCancellation()
        await runSpeakerDiarizationIfEnabled(audioSamples: audioFileSamples)
    }

    private func runSpeakerDiarizationIfEnabled(audioSamples: [Float]) async {
        guard enableSpeakerDiarization,
              !transcriptionState.confirmedSegments.isEmpty else {
            return
        }

        guard let modelRoot = SpeakerDiarizationModelStore.defaultRootURL() else {
            transcriptionState.speakerDiarization = SpeakerDiarizationState(
                errorMessage: "Document directory not found."
            )
            showUserMessage(.warning, title: "Speaker Analysis Skipped", detail: "Document directory not found.")
            return
        }

        refreshSpeakerDiarizationModelState()
        guard modelManagementState.isSpeakerDiarizationModelReady else {
            let detail = modelManagementState.isSpeakerDiarizationModelPreparing
                ? "Speaker model is still preparing."
                : (modelManagementState.speakerDiarizationModelError ?? "Speaker model is not ready.")
            transcriptionState.speakerDiarization = SpeakerDiarizationState(errorMessage: detail)
            showUserMessage(.warning, title: "Speaker Analysis Skipped", detail: detail)
            return
        }

        transcriptionState.speakerDiarization = SpeakerDiarizationState(isRunning: true)
        showUserMessage(.info, title: "Analyzing Speakers", detail: audioState.audioFileName)

        let service = SpeakerDiarizationService(modelRootURL: modelRoot)
        let expectedSpeakerCount = speakerDiarizationExpectedSpeakerCount()
        do {
            let timelineSegments = try await service.diarize(
                audioSamples: audioSamples,
                expectedSpeakerCount: expectedSpeakerCount
            ) { [weak self] progress in
                let progressValue = progress.fractionCompleted.isFinite ? progress.fractionCompleted : 0
                Task { @MainActor [weak self] in
                    guard let self,
                          self.transcriptionState.speakerDiarization.isRunning else {
                        return
                    }
                    self.transcriptionState.speakerDiarization.progress = min(max(progressValue, 0), 1)
                }
            }
            try Task.checkCancellation()

            let assignments = SpeakerAssignmentMapper.assignments(
                for: transcriptionState.confirmedSegments,
                from: timelineSegments
            )
            let speakerCount = Set(timelineSegments.map(\.speakerID)).count
            transcriptionState.speakerAssignments = assignments
            transcriptionState.speakerDiarization = SpeakerDiarizationState(
                isRunning: false,
                progress: 1,
                detectedSpeakerCount: speakerCount,
                errorMessage: speakerCount == 0 ? "No speakers detected." : nil
            )

            let assignedCount = assignments.compactMap { $0 }.count
            showUserMessage(
                speakerCount > 0 ? .success : .warning,
                title: speakerCount > 0 ? "Speakers Ready" : "No Speakers Detected",
                detail: speakerCount > 0
                    ? "\(speakerCount) speaker(s), \(assignedCount) labeled segment(s)."
                    : nil
            )
        } catch is CancellationError {
            transcriptionState.speakerDiarization.isRunning = false
        } catch {
            transcriptionState.speakerDiarization = SpeakerDiarizationState(
                errorMessage: error.localizedDescription
            )
            showUserMessage(
                .warning,
                title: "Speaker Analysis Failed",
                detail: error.localizedDescription
            )
        }
    }

    func updateTranscriptionSegmentText(at index: Int, text: String) {
        guard transcriptionState.confirmedSegments.indices.contains(index) else { return }

        transcriptionState.confirmedSegments[index].text = text
        transcriptionState.confirmedSegments[index].words = nil

        guard let result = transcriptionResult,
              result.segments.indices.contains(index) else { return }

        result.segments[index].text = text
        result.segments[index].words = nil
        refreshSubtitleQualityIssues()
    }

    @discardableResult
    func refreshSubtitleQualityIssues() -> [SubtitleQualityIssue] {
        var issues = SubtitleQualityChecker.check(segments: transcriptionState.confirmedSegments)
        issues.append(contentsOf: speakerLabelReviewIssues())
        uiState.subtitleQualityIssues = issues
        return issues
    }

    private func speakerLabelReviewIssues() -> [SubtitleQualityIssue] {
        guard enableSpeakerDiarization,
              includeSpeakerLabelsInExport,
              !transcriptionState.confirmedSegments.isEmpty,
              !availableSpeakerIDs().isEmpty else {
            return []
        }

        var issues: [SubtitleQualityIssue] = []
        var defaultNameSpeakerIDs: Set<Int> = []

        for index in transcriptionState.confirmedSegments.indices {
            let segment = transcriptionState.confirmedSegments[index]
            let trimmedText = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else { continue }

            guard let assignment = speakerAssignment(forSegmentAt: index) else {
                issues.append(.init(
                    segmentIndex: index,
                    severity: .warning,
                    kind: .missingSpeaker,
                    message: "Missing speaker label",
                    suggestion: "Assign a speaker or turn off speaker labels before export."
                ))
                continue
            }

            let customName = speakerName(for: assignment.speakerID)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if customName.isEmpty,
               !defaultNameSpeakerIDs.contains(assignment.speakerID) {
                defaultNameSpeakerIDs.insert(assignment.speakerID)
                issues.append(.init(
                    segmentIndex: index,
                    severity: .info,
                    kind: .defaultSpeakerName,
                    message: "\(defaultSpeakerName(for: assignment.speakerID)) uses a default name",
                    suggestion: "Rename this speaker if the exported file needs real names."
                ))
            }
        }

        return issues
    }

    func qualityIssues(forSegmentAt index: Int) -> [SubtitleQualityIssue] {
        uiState.subtitleQualityIssues.filter { $0.segmentIndex == index }
    }

    func speakerAssignment(forSegmentAt index: Int) -> SpeakerSegmentAssignment? {
        guard transcriptionState.speakerAssignments.indices.contains(index) else { return nil }
        return transcriptionState.speakerAssignments[index]
    }

    func speakerDiarizationExpectedSpeakerCount() -> Int? {
        let clampedCount = min(max(speakerDiarizationSpeakerCount, 0), 8)
        return clampedCount > 0 ? clampedCount : nil
    }

    func speakerCountOptionTitle(for count: Int) -> String {
        count == 0 ? "Auto" : "\(count)"
    }

    func speakerCountOptionTitleKey(for count: Int) -> LocalizedStringKey {
        guard count == 0 else { return LocalizedStringKey(String(count)) }
        return "Auto"
    }

    func availableSpeakerIDs() -> [Int] {
        let detectedSpeakerCount = min(
            max(transcriptionState.speakerDiarization.detectedSpeakerCount, 0),
            Self.supportedSpeakerIDRange.count
        )
        let detectedIDs = Array(0 ..< detectedSpeakerCount)
        let configuredIDs = Array(0 ..< (speakerDiarizationExpectedSpeakerCount() ?? 0))
        let assignedIDs = transcriptionState.speakerAssignments
            .compactMap { Self.normalizedSpeakerID($0?.speakerID) }
        return Array(Set(detectedIDs + configuredIDs + assignedIDs)).sorted()
    }

    func defaultSpeakerName(for speakerID: Int) -> String {
        "Speaker \(speakerID + 1)"
    }

    func speakerName(for speakerID: Int) -> String {
        transcriptionState.speakerNames[speakerID] ?? ""
    }

    func speakerDisplayName(for speakerID: Int) -> String {
        let customName = transcriptionState.speakerNames[speakerID]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (customName?.isEmpty == false ? customName : nil) ??
            defaultSpeakerName(for: speakerID)
    }

    func speakerDisplayName(for assignment: SpeakerSegmentAssignment?) -> String? {
        assignment.map { speakerDisplayName(for: $0.speakerID) }
    }

    func restoreTranscriptionSidecar(
        _ sidecar: CaptionMateSidecar,
        sourceURL _: URL? = nil
    ) {
        let restoredSegments = sidecar.segments.map { segment in
            TranscriptionSegment(
                start: segment.start,
                end: segment.end,
                text: segment.text
            )
        }
        let language = sidecar.language.isEmpty ? selectedLanguage : sidecar.language

        transcriptionResult = TranscriptionResult(
            text: restoredSegments.map(\.text).joined(separator: " "),
            segments: restoredSegments,
            language: language,
            timings: TranscriptionTimings()
        )
        transcriptionState.currentText = ""
        transcriptionState.confirmedSegments = restoredSegments
        transcriptionState.speakerAssignments = sidecar.segments.map { segment in
            Self.normalizedSpeakerID(segment.speakerID).map(SpeakerSegmentAssignment.init)
        }
        transcriptionState.speakerNames = Dictionary(
            uniqueKeysWithValues: sidecar.speakerNames.compactMap { key, value in
                guard let speakerID = Self.normalizedSpeakerID(Int(key)) else { return nil }
                return (speakerID, value)
            }
        )

        let preset = SubtitleExportPreset(rawValue: sidecar.exportSettings.selectedExportPreset)
        if let preset {
            selectedExportPreset = preset
        }
        frameRate = sidecar.exportSettings.frameRate
        includeSpeakerLabelsInExport = sidecar.exportSettings.includeSpeakerLabelsInExport

        let restoredSpeakerCount = min(max(sidecar.exportSettings.speakerDiarizationSpeakerCount, 0), 8)
        speakerDiarizationSpeakerCount = restoredSpeakerCount
        let restoredSpeakerIDs = Set(
            transcriptionState.speakerAssignments.compactMap { $0?.speakerID } +
                Array(transcriptionState.speakerNames.keys)
        )
        let highestRestoredSpeakerID = restoredSpeakerIDs.max() ?? -1
        let detectedCount = min(
            Self.supportedSpeakerIDRange.count,
            max(restoredSpeakerCount, highestRestoredSpeakerID + 1)
        )
        transcriptionState.speakerDiarization = SpeakerDiarizationState(
            detectedSpeakerCount: detectedCount
        )
        if detectedCount > 0 {
            enableSpeakerDiarization = true
        }

        uiState.isTranscribingView = !restoredSegments.isEmpty
        refreshSubtitleQualityIssues()
    }

    private static func normalizedSpeakerID(_ speakerID: Int?) -> Int? {
        guard let speakerID,
              supportedSpeakerIDRange.contains(speakerID) else {
            return nil
        }
        return speakerID
    }

    func setSpeakerName(_ name: String, for speakerID: Int) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            transcriptionState.speakerNames.removeValue(forKey: speakerID)
        } else {
            transcriptionState.speakerNames[speakerID] = trimmedName
        }
        refreshSubtitleQualityIssues()
    }

    func setSpeakerAssignment(at index: Int, speakerID: Int?) {
        guard transcriptionState.confirmedSegments.indices.contains(index) else { return }
        normalizeSpeakerAssignmentCount()
        transcriptionState.speakerAssignments[index] = speakerID.map(SpeakerSegmentAssignment.init)
        refreshSubtitleQualityIssues()
    }

    func setSpeakerDiarizationEnabled(_ enabled: Bool) {
        enableSpeakerDiarization = enabled
        if enabled {
            prepareDefaultSpeakerDiarizationModelIfNeeded()
        } else {
            cancelActiveSpeakerDiarizationTask()
            transcriptionState.speakerDiarization = SpeakerDiarizationState()
            transcriptionState.speakerAssignments = Array(
                repeating: nil,
                count: transcriptionState.confirmedSegments.count
            )
            transcriptionState.speakerNames = [:]
        }
        refreshSubtitleQualityIssues()
    }

    func reanalyzeSpeakersForCurrentAudio() {
        guard !transcriptionState.confirmedSegments.isEmpty else {
            showUserMessage(.warning, title: "Speaker Analysis Unavailable", detail: "No subtitles are ready.")
            return
        }

        guard let audioURL = audioState.importedAudioURL else {
            showUserMessage(.warning, title: "Speaker Analysis Unavailable", detail: "No imported audio file.")
            return
        }

        guard !transcriptionState.speakerDiarization.isRunning else { return }

        enableSpeakerDiarization = true
        prepareDefaultSpeakerDiarizationModelIfNeeded()

        let taskID = UUID()
        activeSpeakerDiarizationTaskID = taskID
        speakerDiarizationTask?.cancel()
        speakerDiarizationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.activeSpeakerDiarizationTaskID == taskID {
                    self.speakerDiarizationTask = nil
                    self.activeSpeakerDiarizationTaskID = nil
                }
            }

            do {
                let audioSamples = try await Task.detached(priority: .userInitiated) {
                    try autoreleasepool {
                        try AudioProcessor.loadAudioAsFloatArray(fromPath: audioURL.path)
                    }
                }.value
                try Task.checkCancellation()
                await self.runSpeakerDiarizationIfEnabled(audioSamples: audioSamples)
            } catch is CancellationError {
                self.transcriptionState.speakerDiarization.isRunning = false
            } catch {
                self.transcriptionState.speakerDiarization = SpeakerDiarizationState(
                    errorMessage: error.localizedDescription
                )
                self.showUserMessage(
                    .warning,
                    title: "Speaker Analysis Failed",
                    detail: error.localizedDescription
                )
            }
        }
    }

    func subtitleSearchMatchCount() -> Int {
        let query = uiState.subtitleSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return 0 }

        return transcriptionState.confirmedSegments.reduce(0) { count, segment in
            segment.text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) == nil
                ? count
                : count + 1
        }
    }

    func focusNextSubtitleSearchMatch() {
        let query = uiState.subtitleSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty,
              !transcriptionState.confirmedSegments.isEmpty else {
            showUserMessage(.warning, title: "Search Unavailable")
            return
        }

        let startIndex = (uiState.focusedSubtitleSegmentIndex ?? -1) + 1
        let orderedIndices = Array(transcriptionState.confirmedSegments.indices[startIndex...]) +
            Array(transcriptionState.confirmedSegments.indices[..<min(
                startIndex,
                transcriptionState.confirmedSegments.count
            )])

        guard let matchIndex = orderedIndices.first(where: { index in
            transcriptionState.confirmedSegments[index].text.range(
                of: query,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) != nil
        }) else {
            showUserMessage(.info, title: "No Matches")
            return
        }

        uiState.focusedSubtitleSegmentIndex = matchIndex
    }

    func replaceNextSubtitleMatch() {
        let query = uiState.subtitleSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            showUserMessage(.warning, title: "Search Text Required")
            return
        }

        let startIndex = uiState.focusedSubtitleSegmentIndex ?? 0
        let orderedIndices = Array(transcriptionState.confirmedSegments.indices[startIndex...]) +
            Array(transcriptionState.confirmedSegments.indices[..<startIndex])

        guard let matchIndex = orderedIndices.first(where: { index in
            transcriptionState.confirmedSegments[index].text.range(
                of: query,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) != nil
        }) else {
            showUserMessage(.info, title: "No Matches")
            return
        }

        guard let updatedText = Self.replacingFirstMatch(
            in: transcriptionState.confirmedSegments[matchIndex].text,
            searchText: query,
            replacementText: uiState.subtitleReplaceText
        ) else { return }

        updateTranscriptionSegmentText(at: matchIndex, text: updatedText)
        uiState.focusedSubtitleSegmentIndex = matchIndex
    }

    func replaceAllSubtitleMatches() {
        let query = uiState.subtitleSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            showUserMessage(.warning, title: "Search Text Required")
            return
        }

        var segments = transcriptionState.confirmedSegments
        var replacementCount = 0
        for index in segments.indices {
            let originalText = segments[index].text
            let updatedText = originalText.replacingOccurrences(
                of: query,
                with: uiState.subtitleReplaceText,
                options: [.caseInsensitive, .diacriticInsensitive]
            )
            guard updatedText != originalText else { continue }

            segments[index].text = updatedText
            segments[index].words = nil
            replacementCount += 1
        }

        if replacementCount > 0 {
            replaceTranscriptionSegments(segments)
        }

        showUserMessage(
            replacementCount > 0 ? .success : .info,
            title: replacementCount > 0 ? "Replace Complete" : "No Matches",
            detail: replacementCount > 0 ? "\(replacementCount) segment(s) updated." : nil
        )
    }

    func focusSubtitleIssue(_ issue: SubtitleQualityIssue) {
        uiState.showSubtitleReview = false
        uiState.focusedSubtitleSegmentIndex = issue.segmentIndex
    }

    func applySubtitleReviewQuickFixes() {
        let fixedCount = applySubtitleQualityQuickFixes()
        if fixedCount > 0 {
            showUserMessage(
                .success,
                title: "Subtitle Fixes Applied",
                detail: "\(fixedCount) quick fix(es) applied. Review the remaining issues before export."
            )
        } else {
            showUserMessage(
                .info,
                title: "No Quick Fixes Available",
                detail: "Open the listed segment to adjust it manually."
            )
        }
    }

    @discardableResult
    func applySubtitleQualityQuickFixes() -> Int {
        refreshSubtitleQualityIssues()
        guard !transcriptionState.confirmedSegments.isEmpty else { return 0 }

        var segments = transcriptionState.confirmedSegments
        var assignments = Self.normalizedSpeakerAssignments(
            transcriptionState.speakerAssignments,
            count: segments.count
        )
        var fixedCount = 0

        fixedCount += Self.trimAndRemoveEmptySegments(
            segments: &segments,
            assignments: &assignments
        )
        fixedCount += Self.normalizeSubtitleTimings(segments: &segments)
        fixedCount += Self.splitReadableLongSegments(
            segments: &segments,
            assignments: &assignments
        )
        fixedCount += fillMissingSpeakerAssignments(assignments: &assignments)

        guard fixedCount > 0 else {
            refreshSubtitleQualityIssues()
            return 0
        }

        transcriptionState.confirmedSegments = segments
        transcriptionState.speakerAssignments = Self.normalizedSpeakerAssignments(
            assignments,
            count: segments.count
        )
        transcriptionResult?.segments = segments
        transcriptionResult?.text = segments.map(\.text).joined(separator: " ")
        refreshSubtitleQualityIssues()
        return fixedCount
    }

    private static func trimAndRemoveEmptySegments(
        segments: inout [TranscriptionSegment],
        assignments: inout [SpeakerSegmentAssignment?]
    ) -> Int {
        var fixedCount = 0
        var keptSegments: [TranscriptionSegment] = []
        var keptAssignments: [SpeakerSegmentAssignment?] = []
        keptSegments.reserveCapacity(segments.count)
        keptAssignments.reserveCapacity(assignments.count)

        for index in segments.indices {
            var segment = segments[index]
            let trimmedText = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedText != segment.text {
                segment.text = trimmedText
                segment.words = nil
                fixedCount += 1
            }

            if trimmedText.isEmpty {
                fixedCount += 1
                continue
            }

            keptSegments.append(segment)
            keptAssignments.append(assignments.indices.contains(index) ? assignments[index] : nil)
        }

        segments = keptSegments
        assignments = keptAssignments
        return fixedCount
    }

    private static func normalizeSubtitleTimings(segments: inout [TranscriptionSegment]) -> Int {
        guard !segments.isEmpty else { return 0 }

        var fixedCount = 0
        for index in segments.indices {
            var segment = segments[index]
            if segment.end <= segment.start {
                let targetEnd = segment.start + SubtitleQualityChecker.minDuration
                if index < segments.index(before: segments.endIndex),
                   segments[index + 1].start > segment.start {
                    segment.end = min(targetEnd, segments[index + 1].start)
                } else {
                    segment.end = targetEnd
                }
                segment.words = nil
                fixedCount += 1
            }

            if index < segments.index(before: segments.endIndex),
               segment.end > segments[index + 1].start,
               segments[index + 1].start > segment.start {
                segment.end = segments[index + 1].start
                segment.words = nil
                fixedCount += 1
            }

            segments[index] = segment
        }

        return fixedCount
    }

    private static func splitReadableLongSegments(
        segments: inout [TranscriptionSegment],
        assignments: inout [SpeakerSegmentAssignment?]
    ) -> Int {
        var fixedCount = 0
        var index = segments.startIndex

        while index < segments.endIndex {
            let segment = segments[index]
            let duration = segment.end - segment.start
            let trimmedText = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let readableCharacterCount = trimmedText.filter { !$0.isWhitespace }.count
            let charactersPerSecond = duration > 0 ?
                Float(readableCharacterCount) / duration : 0
            let needsSplit = duration > SubtitleQualityChecker.maxDuration ||
                trimmedText.count > SubtitleQualityChecker.maxTotalLength ||
                trimmedText.split(whereSeparator: \.isNewline).contains {
                    $0.count > SubtitleQualityChecker.maxLineLength
                } ||
                charactersPerSecond > SubtitleQualityChecker.maxCharactersPerSecond

            guard needsSplit,
                  duration >= SubtitleQualityChecker.minDuration * 2,
                  let splitText = splitSubtitleText(trimmedText) else {
                index += 1
                continue
            }

            let midpoint = segment.start + duration / 2
            let firstSegment = TranscriptionSegment(
                start: segment.start,
                end: midpoint,
                text: splitText.first
            )
            let secondSegment = TranscriptionSegment(
                start: midpoint,
                end: segment.end,
                text: splitText.second
            )
            let assignment = assignments.indices.contains(index) ? assignments[index] : nil

            segments.replaceSubrange(index ... index, with: [firstSegment, secondSegment])
            assignments.replaceSubrange(index ... index, with: [assignment, assignment])
            fixedCount += 1
            index += 2
        }

        return fixedCount
    }

    private func fillMissingSpeakerAssignments(
        assignments: inout [SpeakerSegmentAssignment?]
    ) -> Int {
        guard enableSpeakerDiarization,
              includeSpeakerLabelsInExport,
              !assignments.isEmpty else {
            return 0
        }

        let detectedIDs = Array(0 ..< transcriptionState.speakerDiarization.detectedSpeakerCount)
        let configuredIDs = Array(0 ..< (speakerDiarizationExpectedSpeakerCount() ?? 0))
        let namedIDs = Array(transcriptionState.speakerNames.keys)
        let assignedIDs = assignments.compactMap { $0?.speakerID }
        let availableIDs = Array(Set(detectedIDs + configuredIDs + namedIDs + assignedIDs)).sorted()
        guard let fallbackID = availableIDs.first else { return 0 }

        var fixedCount = 0
        var previousAssignment: SpeakerSegmentAssignment?
        for index in assignments.indices {
            if let assignment = assignments[index] {
                previousAssignment = assignment
                continue
            }

            let nextAssignment = assignments[(index + 1)...].compactMap { $0 }.first
            let replacement = previousAssignment ??
                nextAssignment ??
                SpeakerSegmentAssignment(speakerID: fallbackID)
            assignments[index] = replacement
            previousAssignment = replacement
            fixedCount += 1
        }

        return fixedCount
    }

    func splitTranscriptionSegment(at index: Int) {
        guard transcriptionState.confirmedSegments.indices.contains(index) else { return }
        let segment = transcriptionState.confirmedSegments[index]
        let duration = segment.end - segment.start
        guard duration > 0,
              let splitText = Self.splitSubtitleText(segment.text) else {
            showUserMessage(.warning, title: "Split Unavailable")
            return
        }

        let midpoint = segment.start + duration / 2
        let firstSegment = TranscriptionSegment(
            start: segment.start,
            end: midpoint,
            text: splitText.first
        )
        let secondSegment = TranscriptionSegment(
            start: midpoint,
            end: segment.end,
            text: splitText.second
        )

        var segments = transcriptionState.confirmedSegments
        segments.replaceSubrange(index ... index, with: [firstSegment, secondSegment])
        replaceTranscriptionSegments(segments)
    }

    func mergeTranscriptionSegment(at index: Int, withNext: Bool) {
        let neighborIndex = withNext ? index + 1 : index - 1
        guard transcriptionState.confirmedSegments.indices.contains(index),
              transcriptionState.confirmedSegments.indices.contains(neighborIndex) else {
            showUserMessage(.warning, title: "Merge Unavailable")
            return
        }

        let firstIndex = min(index, neighborIndex)
        let secondIndex = max(index, neighborIndex)
        let first = transcriptionState.confirmedSegments[firstIndex]
        let second = transcriptionState.confirmedSegments[secondIndex]
        let mergedText = [first.text, second.text]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let mergedSegment = TranscriptionSegment(
            start: min(first.start, second.start),
            end: max(first.end, second.end),
            text: mergedText
        )

        var segments = transcriptionState.confirmedSegments
        segments.replaceSubrange(firstIndex ... secondIndex, with: [mergedSegment])
        replaceTranscriptionSegments(segments)
    }

    func nudgeTranscriptionSegment(at index: Int, by seconds: Float) {
        guard transcriptionState.confirmedSegments.indices.contains(index) else { return }

        var segments = transcriptionState.confirmedSegments
        var segment = segments[index]
        let duration = max(0.1, segment.end - segment.start)
        let lowerBound = index == 0 ? Float(0) : segments[index - 1].end
        let upperBound = index < segments.count - 1 ?
            max(lowerBound, segments[index + 1].start - duration) :
            Float.greatestFiniteMagnitude
        let newStart = min(max(segment.start + seconds, lowerBound), upperBound)

        segment.start = newStart
        segment.end = newStart + duration
        segment.words = nil
        segments[index] = segment
        replaceTranscriptionSegments(segments)
    }

    func adjustTranscriptionSegmentStart(at index: Int, by seconds: Float) {
        guard transcriptionState.confirmedSegments.indices.contains(index) else { return }

        var segments = transcriptionState.confirmedSegments
        var segment = segments[index]
        let lowerBound = index == 0 ? Float(0) : segments[index - 1].end
        let upperBound = segment.end - 0.1
        segment.start = min(max(segment.start + seconds, lowerBound), upperBound)
        segment.words = nil
        segments[index] = segment
        replaceTranscriptionSegments(segments)
    }

    func adjustTranscriptionSegmentEnd(at index: Int, by seconds: Float) {
        guard transcriptionState.confirmedSegments.indices.contains(index) else { return }

        var segments = transcriptionState.confirmedSegments
        var segment = segments[index]
        let lowerBound = segment.start + 0.1
        let upperBound = index < segments.count - 1 ?
            segments[index + 1].start :
            Float.greatestFiniteMagnitude
        segment.end = min(max(segment.end + seconds, lowerBound), upperBound)
        segment.words = nil
        segments[index] = segment
        replaceTranscriptionSegments(segments)
    }

    func setTranscriptionSegmentStart(at index: Int, to seconds: Float) {
        guard transcriptionState.confirmedSegments.indices.contains(index) else { return }

        var segments = transcriptionState.confirmedSegments
        var segment = segments[index]
        let lowerBound = index == 0 ? Float(0) : segments[index - 1].end
        let upperBound = segment.end - 0.1
        segment.start = min(max(seconds, lowerBound), upperBound)
        segment.words = nil
        segments[index] = segment
        replaceTranscriptionSegments(segments)
    }

    func setTranscriptionSegmentEnd(at index: Int, to seconds: Float) {
        guard transcriptionState.confirmedSegments.indices.contains(index) else { return }

        var segments = transcriptionState.confirmedSegments
        var segment = segments[index]
        let lowerBound = segment.start + 0.1
        let upperBound = index < segments.count - 1 ?
            segments[index + 1].start :
            Float.greatestFiniteMagnitude
        segment.end = min(max(seconds, lowerBound), upperBound)
        segment.words = nil
        segments[index] = segment
        replaceTranscriptionSegments(segments)
    }

    func deleteTranscriptionSegment(at index: Int) {
        guard transcriptionState.confirmedSegments.indices.contains(index) else { return }

        var segments = transcriptionState.confirmedSegments
        segments.remove(at: index)
        replaceTranscriptionSegments(segments)
    }

    private func replaceTranscriptionSegments(_ segments: [TranscriptionSegment]) {
        let previousSegments = transcriptionState.confirmedSegments
        let previousAssignments = transcriptionState.speakerAssignments
        transcriptionState.confirmedSegments = segments
        if previousAssignments.allSatisfy({ $0 == nil }) {
            transcriptionState.speakerAssignments = Array(repeating: nil, count: segments.count)
        } else if Self.segmentTimingsMatch(previousSegments, segments) {
            transcriptionState.speakerAssignments = Self.normalizedSpeakerAssignments(
                previousAssignments,
                count: segments.count
            )
        } else {
            transcriptionState.speakerAssignments = SpeakerAssignmentMapper.preservedAssignments(
                for: segments,
                from: previousSegments,
                assignments: previousAssignments
            )
        }
        transcriptionResult?.segments = segments
        refreshSubtitleQualityIssues()
    }

    private func normalizeSpeakerAssignmentCount() {
        let segmentCount = transcriptionState.confirmedSegments.count
        if transcriptionState.speakerAssignments.count == segmentCount {
            return
        }

        if transcriptionState.speakerAssignments.count > segmentCount {
            transcriptionState.speakerAssignments = Array(
                transcriptionState.speakerAssignments.prefix(segmentCount)
            )
        } else {
            transcriptionState.speakerAssignments.append(
                contentsOf: Array(
                    repeating: nil,
                    count: segmentCount - transcriptionState.speakerAssignments.count
                )
            )
        }
    }

    private static func normalizedSpeakerAssignments(
        _ assignments: [SpeakerSegmentAssignment?],
        count: Int
    ) -> [SpeakerSegmentAssignment?] {
        if assignments.count >= count {
            return Array(assignments.prefix(count))
        }
        return assignments + Array(repeating: nil, count: count - assignments.count)
    }

    private static func segmentTimingsMatch(
        _ lhs: [TranscriptionSegment],
        _ rhs: [TranscriptionSegment]
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for index in lhs.indices where lhs[index].start != rhs[index].start || lhs[index].end != rhs[index].end {
            return false
        }
        return true
    }

    private static func splitSubtitleText(_ text: String) -> (first: String, second: String)? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.count > 1 else { return nil }

        let midpointOffset = trimmedText.count / 2
        let midpoint = trimmedText.index(trimmedText.startIndex, offsetBy: midpointOffset)

        let splitIndex = trimmedText[midpoint...].firstIndex(where: \.isWhitespace) ??
            trimmedText[..<midpoint].lastIndex(where: \.isWhitespace) ??
            midpoint

        let secondStart = trimmedText[splitIndex].isWhitespace ?
            trimmedText.index(after: splitIndex) : splitIndex
        let first = String(trimmedText[..<splitIndex])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let second = String(trimmedText[secondStart...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !first.isEmpty, !second.isEmpty else { return nil }
        return (first, second)
    }

    private static func replacingFirstMatch(
        in text: String,
        searchText: String,
        replacementText: String
    ) -> String? {
        guard let range = text.range(
            of: searchText,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) else { return nil }

        var updatedText = text
        updatedText.replaceSubrange(range, with: replacementText)
        return updatedText
    }

    static func wrappedSubtitleText(
        _ text: String,
        maxLineLength: Int,
        maxLines: Int
    ) -> String {
        let words = text
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !words.isEmpty else { return "" }

        var lines: [String] = []
        var currentLine = ""

        for word in words {
            if currentLine.isEmpty {
                currentLine = word
            } else if currentLine.count + 1 + word.count <= maxLineLength {
                currentLine += " \(word)"
            } else {
                lines.append(currentLine)
                currentLine = word
            }
        }

        if !currentLine.isEmpty {
            lines.append(currentLine)
        }

        guard lines.count > maxLines, maxLines > 0 else {
            return lines.joined(separator: "\n")
        }

        let visibleLines = Array(lines.prefix(maxLines - 1))
        let remainingText = lines.dropFirst(maxLines - 1).joined(separator: " ")
        return (visibleLines + [remainingText]).joined(separator: "\n")
    }

    /// 오디오 샘플 전사
    func transcribeAudioSamples(_ samples: [Float]) async throws -> TranscriptionResult? {
        guard let whisperKit = whisperKit else { return nil }
        let languageCode = Constants.languages[
            selectedLanguage,
            default: Constants.defaultLanguageCode
        ]
        let task: DecodingTask = selectedTask == "transcribe" ? .transcribe : .translate
        let seekClip: [Float] = [transcriptionState.lastConfirmedSegmentEndSeconds]

        let options = DecodingOptions(
            verbose: true,
            task: task,
            language: isAutoLanguageEnable ? nil : languageCode,
            temperature: Float(temperatureStart),
            temperatureFallbackCount: Int(fallbackCount),
            sampleLength: sampleLength,
            usePrefillPrompt: enablePromptPrefill,
            usePrefillCache: enableCachePrefill,
            detectLanguage: isAutoLanguageEnable,
            skipSpecialTokens: !enableSpecialCharacters,
            withoutTimestamps: !enableTimestamps,
            wordTimestamps: enableWordTimestamp,
            clipTimestamps: seekClip,
            concurrentWorkerCount: Int(concurrentWorkerCount),
            chunkingStrategy: chunkingStrategy
        )

        let decodingCallback: ((TranscriptionProgress) -> Bool?) = { [weak self] progress in
            guard let self else { return false }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let now = Date()
                guard now.timeIntervalSince(self.lastDecoderPreviewUpdate) >= 0.12 else {
                    return
                }
                self.lastDecoderPreviewUpdate = now

                let fallbacks = Int(progress.timings.totalDecodingFallbacks)
                let chunkId = self.selectedTask == "transcribe" ? 0 : progress.windowId
                var updatedChunk = (chunkText: [progress.text], fallbacks: fallbacks)
                if var currentChunk = self.transcriptionState.currentChunks[chunkId],
                   let previousChunkText = currentChunk.chunkText.last {
                    if progress.text.count >= previousChunkText.count {
                        currentChunk.chunkText[currentChunk.chunkText.endIndex - 1] = progress.text
                        updatedChunk = currentChunk
                    } else {
                        if fallbacks == currentChunk.fallbacks && self
                            .selectedTask == "transcribe" {
                            updatedChunk
                                .chunkText = [(updatedChunk.chunkText.first ?? "") + progress.text]
                        } else {
                            updatedChunk.chunkText[currentChunk.chunkText.endIndex - 1] = progress
                                .text
                            updatedChunk.fallbacks = fallbacks
                            print("Fallback occurred: \(fallbacks)")
                        }
                    }
                }
                self.transcriptionState.currentChunks[chunkId] = updatedChunk
                let joinedChunks = self.transcriptionState.currentChunks.sorted { $0.key < $1.key }
                    .flatMap { $0.value.chunkText }
                    .joined(separator: "\n")
                self.transcriptionState.currentText = joinedChunks
                self.transcriptionState.currentFallbacks = fallbacks
                self.transcriptionState.currentDecodingLoops += 1
            }

            let currentTokens = progress.tokens
            let checkWindow = Int(self.compressionCheckWindow)
            if currentTokens.count > checkWindow {
                let checkTokens: [Int] = Array(currentTokens.suffix(checkWindow))
                let compressionRatio = TextUtilities.compressionRatio(of: checkTokens)
                if compressionRatio > options.compressionRatioThreshold! {
                    Logging.debug("Early stopping due to compression threshold")
                    return false
                }
            }
            if progress.avgLogprob! < options.logProbThreshold! {
                Logging.debug("Early stopping due to logprob threshold")
                return false
            }
            return nil
        }

        let transcriptionResults: [TranscriptionResult] = try await whisperKit.transcribe(
            audioArray: samples,
            decodeOptions: options,
            callback: decodingCallback
        )
        let mergedResults = TranscriptionUtilities.mergeTranscriptionResults(
            transcriptionResults,
            confirmedWords: []
        )
        return mergedResults
    }

    // MARK: - Audio Preview & Deletion

    /// 오디오 미리듣기
    func playImportedAudio() {
        guard let url = audioState.importedAudioURL else { return }
        do {
            // 플레이어가 없거나 새로운 파일을 재생할 때만 새로 생성
            if audioPlayer == nil {
                audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer?.prepareToPlay()

                // 총 재생 시간 업데이트 (이미 설정되어 있으면 변경하지 않음)
                if audioState.totalDuration == 0 {
                    audioState.totalDuration = audioPlayer?.duration ?? 0.0
                }
            }

            // 재생 속도 설정
            audioPlayer?.enableRate = true
            audioPlayer?.rate = playbackRates[currentPlaybackRateIndex]

            // 볼륨 적용 (노멀라이제이션된 값 기준)
            applyVolume()

            audioPlayer?.play()
            audioState.isPlaying = true

            setupPlaybackTimeUpdater()
        } catch {
            print("Error playing audio: \(error.localizedDescription)")
        }
    }

    // 재생 시간 업데이트를 위한 Combine 타이머 설정
    private func setupPlaybackTimeUpdater() {
        invalidatePlaybackTimer()

        // Combine 타이머 설정
        playbackTimerCancellable = Timer.publish(every: 0.05, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, let player = self.audioPlayer else {
                    self?.invalidatePlaybackTimer()
                    return
                }

                // 재생 중일 때만 업데이트
                if self.audioState.isPlaying {
                    self.audioPlaybackState.currentPlayerTime = player.currentTime
                }

                // 재생이 끝났는지 확인
                if !player.isPlaying && self.audioState.isPlaying {
                    self.audioState.isPlaying = false
                    // 재생이 끝났을 때만 처음 위치로 리셋
                    if player.currentTime >= player.duration - 0.1 {
                        player.currentTime = 0.0
                        self.audioPlaybackState.currentPlayerTime = 0.0
                    }
                    self.invalidatePlaybackTimer()
                }
            }
    }

    private func invalidatePlaybackTimer() {
        audioState.playbackTimer?.invalidate()
        audioState.playbackTimer = nil
        playbackTimerCancellable?.cancel()
        playbackTimerCancellable = nil
    }

    /// 선택된 배속으로 재생
    func changePlaybackRate(faster: Bool) {
        if faster {
            currentPlaybackRateIndex = min(currentPlaybackRateIndex + 1, playbackRates.count - 1)
        } else {
            currentPlaybackRateIndex = max(currentPlaybackRateIndex - 1, 0)
        }

        // 현재 재생 중이면 속도 변경
        if let player = audioPlayer, audioState.isPlaying {
            player.enableRate = true
            player.rate = playbackRates[currentPlaybackRateIndex]
        }
    }

    /// 현재 재생 속도 텍스트 반환
    func currentPlaybackRateText() -> String {
        let rate = playbackRates[currentPlaybackRateIndex]
        return String(format: "%.2fx", rate)
    }

    /// 앞으로 이동 (5초)
    func skipForward() {
        guard let player = audioPlayer else { return }
        let newTime = min(player.duration, player.currentTime + 5.0)
        player.currentTime = newTime
    }

    /// 뒤로 이동 (5초)
    func skipBackward() {
        guard let player = audioPlayer else { return }
        let newTime = max(0, player.currentTime - 5.0)
        player.currentTime = newTime
    }

    func pauseImportedAudio() {
        audioPlayer?.pause()
        audioState.isPlaying = false
        invalidatePlaybackTimer()
    }

    func stopImportedAudio() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        audioPlaybackState.currentPlayerTime = 0
        audioState.isPlaying = false
        invalidatePlaybackTimer()
    }

    /// 재생 위치 이동
    func seekToPosition(_ position: Double) {
        guard let player = audioPlayer else { return }
        player.currentTime = position

        // currentPlayerTime 즉시 업데이트
        audioPlaybackState.currentPlayerTime = position

        // 재생 중이었다면 계속 재생
        if audioState.isPlaying {
            player.play()
        }
    }

    /// 라인 내에서 특정 비율 위치로 이동 (WaveFormView에서 사용)
    func seekToPositionInLine(lineIndex: Int, secondsPerLine: Double, ratio: Double,
                              totalDuration: Double) {
        let startTime = Double(lineIndex) * secondsPerLine
        let endTime = min(startTime + secondsPerLine, totalDuration)
        let seekTime = startTime + (endTime - startTime) * ratio

        // 범위 내 안전한 값으로 조정
        let safePosition = max(0, min(seekTime, totalDuration))

        // 기존 메소드 호출
        seekToPosition(safePosition)
    }

    /// 볼륨 조절 메서드
    func setVolume(_ volume: Double) {
        audioVolume = volume

        // 볼륨이 0이면 음소거 상태로 변경
        if volume == 0.0 {
            isMuted = true
        } else if isMuted {
            // 음소거 상태에서 볼륨을 올리면 음소거 해제
            isMuted = false
            stagingVolume = volume
        } else {
            stagingVolume = volume
        }

        // 간소화된 볼륨 적용
        applyVolume()
    }

    /// 음소거 토글
    func toggleMute() {
        if isMuted {
            // 음소거 해제 - 이전 볼륨으로 복원
            isMuted = false
            audioVolume = stagingVolume > 0.0 ? stagingVolume : 1.0
        } else {
            // 음소거 적용 - 현재 볼륨 저장
            isMuted = true
            stagingVolume = audioVolume
            audioVolume = 0.0
        }

        // 간소화된 볼륨 적용
        applyVolume()
    }

    func deleteImportedAudio() {
        // 재생 중이면 먼저 정지
        stopImportedAudio()
        cancelAudioProcessingTasks()

        // 임시 파일 정리
        cleanupPreviousAudioFile()

        // 파일 삭제 대신 앱에서만 초기화
        audioState.importedAudioURL = nil
        audioState.audioFileName = ""
        audioState.waveformSamples = []
        audioState.isWaveformProcessing = false
        audioState.totalDuration = 0
        audioPlaybackState.currentPlayerTime = 0
        print("Imported audio removed from app.")
    }

    /// 이전 오디오 임시 파일 정리
    private func cleanupPreviousAudioFile() {
        if let tempURL = audioState.temporaryAudioURL {
            do {
                if FileManager.default.fileExists(atPath: tempURL.path) {
                    try FileManager.default.removeItem(at: tempURL)
                    print("Previous temporary audio file deleted: \(tempURL.lastPathComponent)")
                }
            } catch {
                print(
                    "Failed to delete previous temporary audio file: \(error.localizedDescription)"
                )
            }
            audioState.temporaryAudioURL = nil
        }
    }

    /// 앱이 직접 만든 오래된 임시 오디오 파일만 정리
    private func cleanupStaleTemporaryAudioFiles() {
        let tempDirectoryURL = Self.appTemporaryAudioDirectoryURL()
        let preservedURLs = audioState.temporaryAudioURL.map { Set([$0]) } ?? []

        do {
            let report = try StorageCleanupService.cleanupStaleItems(
                in: tempDirectoryURL,
                olderThan: StorageCleanupPolicy.staleTemporaryAudioAge,
                preserving: preservedURLs
            )

            if !report.isEmpty {
                print(
                    "CaptionMate temporary audio cleaned: \(ByteCountFormatter.string(fromByteCount: report.removedBytes, countStyle: .file))"
                )
            }
        } catch {
            print("Failed to clean CaptionMate temporary audio: \(error.localizedDescription)")
        }
    }

    /// 앱 시작 시 이전 세션의 오래된 임시 파일 정리
    func performStartupCleanup() async {
        print("Starting startup cleanup...")

        // 1. 현재 세션의 오디오 임시 파일 정리
        cleanupPreviousAudioFile()
        cleanupStaleTemporaryAudioFiles()

        print("Startup cleanup completed")
    }

    /// 오디오 파일에서 파형 데이터를 생성 (RMS 기반 계산 예시)
    func processWaveform(for url: URL) async {
        guard audioState.importedAudioURL == url else { return }
        do {
            try Task.checkCancellation()
            // 현재 파형 샘플이 비어있지 않으면 초기화 (새 파일용)
            if !audioState.waveformSamples.isEmpty {
                await MainActor.run {
                    audioState.waveformSamples = []
                }
            }

            // 오디오 파일 정보 업데이트 (임포트 직후에도 실행)
            if audioState.totalDuration == 0 {
                let audioAsset = AVURLAsset(url: url)
                let duration = try await audioAsset.load(.duration)
                let durationInSeconds = CMTimeGetSeconds(duration)

                await MainActor.run {
                    audioState.totalDuration = durationInSeconds
                }
            }

            // 파형은 작은 버퍼 단위로 읽어 전체 오디오 샘플 배열을 추가로 만들지 않는다.
            let waveformSamples = try await Task.detached(priority: .userInitiated) {
                try autoreleasepool {
                    try Self.computeWaveform(fromAudioURL: url)
                }
            }.value
            try Task.checkCancellation()

            // 파형 상태 업데이트
            await MainActor.run {
                guard audioState.importedAudioURL == url else { return }

                // 모든 정보 업데이트 (동시에 한 번에 갱신)
                audioState.waveformSamples = waveformSamples
                audioState.isWaveformProcessing = false

                // 디버그 로그
                print(
                    "Waveform update completed: \(waveformSamples.count) samples, total duration: \(audioState.totalDuration) seconds"
                )
            }
        } catch is CancellationError {
            if audioState.importedAudioURL == url {
                audioState.isWaveformProcessing = false
            }
        } catch {
            if audioState.importedAudioURL == url {
                audioState.isWaveformProcessing = false
            }
            print("Error processing waveform: \(error.localizedDescription)")
        }
    }

    private enum WaveformProcessingError: LocalizedError {
        case unsupportedAudioFormat

        var errorDescription: String? {
            switch self {
            case .unsupportedAudioFormat:
                return "The audio file could not be read as floating point PCM."
            }
        }
    }

    private nonisolated static let waveformReferenceSampleRate: Double = 16_000
    private nonisolated static let waveformReferenceChunkSize = 1024

    nonisolated static func computeWaveform(from samples: [Float]) -> [Float] {
        let chunkSize = waveformReferenceChunkSize
        var rmsValues = [Float]()
        rmsValues.reserveCapacity(samples.count / chunkSize + 1)
        var index = 0
        while index < samples.count {
            let endIndex = min(index + chunkSize, samples.count)
            var sumSquares: Float = 0
            var sampleIndex = index
            while sampleIndex < endIndex {
                let sample = samples[sampleIndex]
                sumSquares += sample * sample
                sampleIndex += 1
            }
            let rms = sqrt(sumSquares / Float(endIndex - index))
            rmsValues.append(rms)
            index += chunkSize
        }
        return rmsValues
    }

    nonisolated static func computeWaveform(fromAudioURL audioURL: URL) throws -> [Float] {
        let audioFile = try AVAudioFile(
            forReading: audioURL,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let format = audioFile.processingFormat
        let channelCount = Int(format.channelCount)
        guard channelCount > 0 else {
            throw WaveformProcessingError.unsupportedAudioFormat
        }

        let sampleRate = format.sampleRate > 0 ? format.sampleRate : waveformReferenceSampleRate
        let framesPerWaveformSample = max(
            1,
            Int((sampleRate / waveformReferenceSampleRate) * Double(waveformReferenceChunkSize))
        )
        let readFrameCapacity = AVAudioFrameCount(
            min(max(framesPerWaveformSample * 16, 4096), 65_536)
        )
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: readFrameCapacity
        ) else {
            throw WaveformProcessingError.unsupportedAudioFormat
        }

        var rmsValues = [Float]()
        if audioFile.length > 0 {
            rmsValues.reserveCapacity(
                Int(ceil(Double(audioFile.length) / Double(framesPerWaveformSample)))
            )
        }

        var sumSquares: Double = 0
        var sampleCountInChunk = 0

        while audioFile.framePosition < audioFile.length {
            try Task.checkCancellation()
            let remainingFrames = audioFile.length - audioFile.framePosition
            let framesToRead = AVAudioFrameCount(min(Int64(readFrameCapacity), remainingFrames))
            try audioFile.read(into: buffer, frameCount: framesToRead)

            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { break }
            guard let channelData = buffer.floatChannelData else {
                throw WaveformProcessingError.unsupportedAudioFormat
            }

            for frameIndex in 0 ..< frameLength {
                var mixedSample: Float = 0
                for channelIndex in 0 ..< channelCount {
                    mixedSample += channelData[channelIndex][frameIndex]
                }
                let sample = mixedSample / Float(channelCount)
                sumSquares += Double(sample * sample)
                sampleCountInChunk += 1

                if sampleCountInChunk == framesPerWaveformSample {
                    rmsValues.append(Float(sqrt(sumSquares / Double(sampleCountInChunk))))
                    sumSquares = 0
                    sampleCountInChunk = 0
                }
            }
        }

        if sampleCountInChunk > 0 {
            rmsValues.append(Float(sqrt(sumSquares / Double(sampleCountInChunk))))
        }

        return rmsValues
    }

    // MARK: - Export Service 호출

    func exportTranscription(skipQualityReview: Bool = false) async {
        guard let result = transcriptionResult else {
            print("No transcription result available.")
            showUserMessage(.warning, title: "Nothing to Export")
            return
        }

        let qualityIssues = refreshSubtitleQualityIssues()
        let hasBlockingIssues = qualityIssues.contains { $0.severity == .error }
        if hasBlockingIssues || (!skipQualityReview && !qualityIssues.isEmpty) {
            uiState.showSubtitleReview = true
            showUserMessage(
                hasBlockingIssues ? .error : .warning,
                title: hasBlockingIssues ? "Fix Required Before Export" : "Review Subtitles Before Export",
                detail: "\(qualityIssues.count) subtitle quality issue(s) found."
            )
            return
        }

        // Export 시작 (언어 메뉴 비활성화)
        isExporting = true
        defer {
            // Export 완료 후 항상 실행
            isExporting = false
        }

        // 세그먼트와 단어 처리: 앞뒤 공백 제거 후 빈 세그먼트 제거 등
        var cleanSegments: [TranscriptionSegment] = []
        let exportPreset = selectedExportPreset
        for (index, segment) in result.segments.enumerated() {
            var cleanSegment = segment
            let speakerAssignment = speakerAssignment(forSegmentAt: index)
            cleanSegment.text = SpeakerLabelFormatter.prefixedText(
                segment.text,
                assignment: speakerAssignment,
                speakerName: speakerDisplayName(for: speakerAssignment),
                includeSpeakerLabel: includeSpeakerLabelsInExport
            )
            cleanSegment.text = Self.wrappedSubtitleText(
                cleanSegment.text,
                maxLineLength: exportPreset.maxLineLength,
                maxLines: exportPreset.maxLines
            )
            if let words = segment.words {
                var cleanWords: [WordTiming] = []
                for word in words {
                    var cleanWord = word
                    cleanWord.word = word.word.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleanWord.word.isEmpty {
                        cleanWords.append(cleanWord)
                    }
                }
                cleanSegment.words = cleanWords.isEmpty ? nil : cleanWords
            }
            if !cleanSegment.text.isEmpty || (cleanSegment.words?.isEmpty == false) {
                cleanSegments.append(cleanSegment)
            }
        }
        cleanSegments.sort { $0.start < $1.start }
        guard !cleanSegments.isEmpty else {
            showUserMessage(.warning, title: "Nothing to Export", detail: "All segments are empty.")
            return
        }

        // 세그먼트 간 겹침 조정
        if cleanSegments.count > 1 {
            for i in 0 ..< (cleanSegments.count - 1) {
                if cleanSegments[i].end > cleanSegments[i + 1].start {
                    cleanSegments[i].end = cleanSegments[i + 1].start
                }
            }
        }

        // ExportService의 writer 분기 처리를 사용하여 파일 내보내기
        let exportResult = TranscriptionResult(
            text: cleanSegments.map(\.text).joined(separator: " "),
            segments: cleanSegments,
            language: result.language,
            timings: result.timings,
            seekTime: result.seekTime
        )
        let outcome = await ExportService.exportTranscriptionResult(
            result: exportResult,
            defaultFileName: audioState.audioFileName,
            frameRate: frameRate
        )

        switch outcome {
        case let .success(path):
            do {
                let sidecarURL = try writeCurrentSidecar(
                    nextToExportedPath: path,
                    language: result.language,
                    timings: result.timings
                )
                let detail = sidecarURL.map { "\(path)\nSidecar: \($0.path)" } ?? path
                showUserMessage(.success, title: "Export Complete", detail: detail)
            } catch {
                showUserMessage(
                    .warning,
                    title: "Export Complete, Sidecar Failed",
                    detail: error.localizedDescription
                )
            }
        case .cancelled:
            showUserMessage(.info, title: "Export Cancelled")
        case let .failure(error):
            showUserMessage(.error, title: "Export Failed", detail: error.localizedDescription)
        }
    }

    private func writeCurrentSidecar(
        nextToExportedPath path: String,
        language: String,
        timings: TranscriptionTimings
    ) throws -> URL? {
        guard !transcriptionState.confirmedSegments.isEmpty else {
            return nil
        }

        let sidecarResult = TranscriptionResult(
            text: transcriptionState.confirmedSegments.map(\.text).joined(separator: " "),
            segments: transcriptionState.confirmedSegments,
            language: language,
            timings: timings
        )
        let sidecar = CaptionMateSidecar(
            result: sidecarResult,
            audioFileName: audioState.audioFileName,
            speakerAssignments: transcriptionState.speakerAssignments,
            speakerNames: transcriptionState.speakerNames,
            selectedExportPreset: selectedExportPreset,
            frameRate: frameRate,
            includeSpeakerLabelsInExport: includeSpeakerLabelsInExport,
            speakerDiarizationSpeakerCount: speakerDiarizationSpeakerCount
        )
        return try CaptionMateSidecarService.write(
            sidecar,
            nextToMediaURL: URL(fileURLWithPath: path)
        )
    }

    // MARK: - Drag and drop

    /// 파일 드래그 앤 드롭 메소드
    func handleDroppedFiles(providers: [NSItemProvider]) {
        // 첫 번째 파일만 처리
        guard let provider = providers.first else { return }

        // 드래그 앤 드롭 상태 해제
        DispatchQueue.main.async {
            self.uiState.isTargeted = false
        }

        provider
            .loadItem(forTypeIdentifier: UTType.fileURL.identifier,
                      options: nil) { [weak self] item, error in
                guard let self = self else { return }

                if let urlData = item as? Data,
                   let url = URL(dataRepresentation: urlData, relativeTo: nil) {
                    Task { @MainActor in
                        await self.processSelectedFile(
                            url,
                            needsSecurityScopedAccess: true
                        )
                    }
                } else {
                    print(
                        "File drop processing failed: \(error?.localizedDescription ?? "Unknown error")"
                    )
                }
            }
    }

    /// 로컬 및 원격 모델 목록 업데이트
    func fetchModels(forceRefresh: Bool = false) {
        if modelManagementState.catalogLoadState.isLoading, !forceRefresh {
            return
        }

        modelCatalogTask?.cancel()
        modelManagementState.catalogLoadState = .loadingLocal
        modelManagementState.hasModelLoadError = false
        modelManagementState.modelLoadError = nil

        let modelStorage = modelManagementState.modelStorage
        let activeRepoName = repoName

        modelCatalogTask = Task { [weak self] in
            guard let self else { return }

            do {
                let localSnapshot = try await Task.detached {
                    try ModelCatalogService.loadLocalModelFolders(modelStorage: modelStorage)
                }.value

                guard !Task.isCancelled else { return }

                let localFolders = ModelCatalogService.orderedLocalModelFolders(
                    localSnapshot.folders,
                    formattingNamesWith: ModelUtilities.formatModelFiles
                )
                let localNames = localFolders.map(\.name)
                self.modelManagementState.localModelPath = localSnapshot.directoryURL.path
                self.modelManagementState.localModels = localNames

                for folder in localFolders {
                    self.modelManagementState.modelSizes[folder.name] = folder.size
                    self.modelManagementState.modelSizeSources[folder.name] = .local
                }

                self.modelManagementState.availableModels = self.mergedModelList(
                    localModels: localNames,
                    remoteModels: self.modelManagementState.availableModels
                )
                self.refreshSpeakerDiarizationModelState()
            } catch {
                self.modelManagementState.catalogLoadState = .failed(error.localizedDescription)
                self.modelManagementState.hasModelLoadError = true
                self.modelManagementState.modelLoadError = error.localizedDescription
                return
            }

#if DEBUG
            guard !Self.isUITesting else {
                self.modelManagementState.catalogLoadState = .ready
                return
            }
#endif

            self.modelManagementState.catalogLoadState = .loadingRemote
            let cachedSizes = forceRefresh ? [:] :
                ModelCatalogService.cachedRemoteSizes(repoName: activeRepoName)

            let modelSupport = await WhisperKit.recommendedRemoteModels()
            guard !Task.isCancelled else { return }

            self.modelManagementState.disabledModels = modelSupport.disabled
            self.applyRemoteModels(
                modelSupport.supported,
                cachedSizes: cachedSizes,
                forceRemoteSizeRefresh: forceRefresh
            )
            self.modelManagementState.catalogLoadState = .ready
            self.refreshRemoteModelSizes(for: modelSupport.supported, repoName: activeRepoName)
        }
    }

    private func applyRemoteModels(
        _ remoteModels: [String],
        cachedSizes: [String: Int64],
        forceRemoteSizeRefresh: Bool
    ) {
        modelManagementState.availableModels = mergedModelList(
            localModels: modelManagementState.localModels,
            remoteModels: remoteModels
        )

        for model in remoteModels where !modelManagementState.localModels.contains(model) {
            if !forceRemoteSizeRefresh,
               let cachedSize = cachedSizes[model],
               cachedSize > 0 {
                modelManagementState.modelSizes[model] = cachedSize
                modelManagementState.modelSizeSources[model] = .remote
            } else if forceRemoteSizeRefresh || modelManagementState.modelSizes[model] == nil {
                modelManagementState.modelSizes[model] = ModelCatalogService
                    .estimatedDownloadSize(for: model)
                modelManagementState.modelSizeSources[model] = .estimate
            }
        }
    }

    private func refreshRemoteModelSizes(for remoteModels: [String], repoName: String) {
        remoteModelSizeTask?.cancel()

        let modelsNeedingRemoteSize = remoteModels.filter { model in
            !modelManagementState.localModels.contains(model) &&
                modelManagementState.modelSizeSources[model] != .remote
        }

        guard !modelsNeedingRemoteSize.isEmpty else {
            modelManagementState.isRemoteModelSizeLoading = false
            return
        }

        modelManagementState.isRemoteModelSizeLoading = true
        remoteModelSizeTask = Task { [weak self] in
            guard let self else { return }
            var cachedSizes = ModelCatalogService.cachedRemoteSizes(repoName: repoName)

            for model in modelsNeedingRemoteSize {
                guard !Task.isCancelled else { break }
                do {
                    let size = try await ModelCatalogService.remoteFolderSize(
                        repoName: repoName,
                        model: model
                    )
                    guard size > 0 else { continue }
                    cachedSizes[model] = size
                    self.modelManagementState.modelSizes[model] = size
                    self.modelManagementState.modelSizeSources[model] = .remote
                } catch {
                    if self.modelManagementState.modelSizes[model] == nil {
                        self.modelManagementState.modelSizes[model] = ModelCatalogService
                            .estimatedDownloadSize(for: model)
                        self.modelManagementState.modelSizeSources[model] = .estimate
                    }
                }
            }

            if !Task.isCancelled {
                ModelCatalogService.saveCachedRemoteSizes(cachedSizes, repoName: repoName)
            }
            self.modelManagementState.isRemoteModelSizeLoading = false
            self.remoteModelSizeTask = nil
        }
    }

    private func mergedModelList(localModels: [String], remoteModels: [String]) -> [String] {
        var seenModels: Set<String> = []
        return (localModels + remoteModels).filter { model in
            seenModels.insert(model).inserted
        }
    }
}
