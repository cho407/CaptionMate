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
    // The manual count picker is limited to eight; automatic detection can find more.
    private static let supportedSpeakerIDRange = 0 ..< 256

    private var isLoadingModel = false
    private var activeTranscribeTaskID: UUID?
    private var transcribeTask: Task<Void, Never>?
    private var activeSpeakerDiarizationTaskID: UUID?
    private var activeSpeakerDiarizationModelTaskID: UUID?
    private var speakerDiarizationModelTask: Task<Void, Never>?
    private var speakerDiarizationTask: Task<Void, Never>?
    private var previousSpeakerDiarizationStatus: SpeakerDiarizationState?
    private var activeModelLoadTaskID: UUID?
    private var modelLoadTask: Task<Void, Never>?
    private var modelCatalogTask: Task<Void, Never>?
    private var remoteModelSizeTask: Task<Void, Never>?
    private var languageChangeNotificationTask: Task<Void, Never>?
    private var waveformProcessingTask: Task<Void, Never>?
    private var waveformProcessingTaskID: UUID?
    private var normalizationTask: Task<Void, Never>?
    private var normalizationTaskID: UUID?
    private var speakerDiarizationDownloadProgress: Progress?
    private var speakerModelIntegrityFailure: SpeakerDiarizationModelFailure?
    private var modelDownloadTasks: [String: Task<Void, Never>] = [:]
    private var modelDownloadOperationIDs: [String: UUID] = [:]
    private var modelDownloadCancellationErrors: [String: String] = [:]
    private var modelDownloadProgressObjects: [String: Progress] = [:]
    private var modelDownloadLastProgressCallbackTime: [String: Date] = [:]
    private var modelDownloadLastProgressUIUpdateTime: [String: Date] = [:]
    private var pendingModelLoadAfterDownload: String?
    private var pendingModelLoadIsRepair = false
    private var activeSourceAudioAccessURL: URL?
    private var activeAudioImportID: UUID?
    private var audioImportSnapshot: ProjectSnapshot?
    private var audioImportTask: Task<PreparedAudioImport, Error>?
    private let projectStore: CaptionMateProjectStore
    private let speakerModelRootURL: URL?
    typealias SpeakerAnalyzer = @Sendable (
        [Float], Int?, (@Sendable (Progress) -> Void)?
    ) async throws -> [SpeakerTimelineSegment]
    typealias AudioImportPreparer = @Sendable (URL, Bool) async throws -> PreparedAudioImport
    private let speakerAnalyzer: SpeakerAnalyzer?
    private let audioImportPreparer: AudioImportPreparer
    private var lastSavedProjectSnapshot: ProjectSnapshot?
    private var isConfirmingUnsavedChanges = false

    private struct ProjectSnapshot: Equatable {
        let sidecar: CaptionMateSidecar
        let sourceAudioPath: String?
        let sourceAudioBookmarkData: Data?
    }

#if DEBUG
    var activeModelDownloadTaskCountForTesting: Int {
        modelDownloadTasks.count
    }

    var activeModelDownloadProgressObjectCountForTesting: Int {
        modelDownloadProgressObjects.count
    }

    var activeModelDownloadProgressCallbackCountForTesting: Int {
        modelDownloadLastProgressCallbackTime.count
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

    @discardableResult
    func setSpeakerDiarizationModelTaskForTesting(_ task: Task<Void, Never>) -> UUID {
        speakerDiarizationModelTask = task
        let operationID = UUID()
        activeSpeakerDiarizationModelTaskID = operationID
        return operationID
    }

    func installSpeakerModelForTesting(
        from stagedRoot: URL,
        to destinationRoot: URL,
        operationID: UUID,
        checksums: [String: String]
    ) throws {
        try commitSpeakerDiarizationModelDownload(
            stagedRootURL: stagedRoot,
            destinationRootURL: destinationRoot,
            operationID: operationID,
            expectedFileSHA256: checksums
        )
    }

    func ownsSpeakerModelDownloadForTesting(operationID: UUID) -> Bool {
        activeSpeakerDiarizationModelTaskID == operationID && speakerDiarizationModelTask != nil
    }

    func finishSpeakerModelDownloadForTesting(operationID: UUID, errorMessage: String?) {
        finishSpeakerDiarizationModelDownload(
            operationID: operationID,
            didInstallModel: false,
            errorMessage: errorMessage,
            showSuccessMessage: false
        )
    }

    func beginModelLoadOperationForTesting() -> UUID {
        let operationID = UUID()
        activeModelLoadTaskID = operationID
        return operationID
    }

    func publishModelLoadCompletionForTesting(model: String, operationID: UUID) {
        publishModelLoadCompletion(
            model: model,
            modelState: .loaded,
            operationID: operationID
        )
    }

    var pendingModelRepairForTesting: String? {
        pendingModelLoadIsRepair ? pendingModelLoadAfterDownload : nil
    }

    func simulateWhisperPrewarmFailureForTesting(model: String, taskID: UUID) async {
        await handleWhisperPrewarmFailure(
            model: model,
            error: NSError(
                domain: "ContentViewModelTests.WhisperPrewarm",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Simulated prewarm runtime failure"]
            ),
            redownload: false,
            taskID: taskID,
            failedKit: nil
        )
    }

    func setModelDownloadRuntimeForTesting(
        model: String,
        task: Task<Void, Never>? = nil,
        progress: Progress? = nil,
        lastProgressCallbackTime: Date? = nil
    ) {
        modelDownloadTasks[model] = task
        modelDownloadOperationIDs[model] = task == nil ? nil : UUID()
        modelDownloadProgressObjects[model] = progress
        modelDownloadLastProgressCallbackTime[model] = lastProgressCallbackTime
        modelDownloadLastProgressUIUpdateTime[model] = lastProgressCallbackTime
    }

    func modelDownloadOperationIDForTesting(model: String) -> UUID? {
        modelDownloadOperationIDs[model]
    }

    func canCommitModelDownloadForTesting(model: String, operationID: UUID) -> Bool {
        canCommitModelDownload(model, operationID: operationID)
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

    var transcriptionTaskForTesting: Task<Void, Never>? { transcribeTask }

    func setTranscriptionTaskForTesting(_ task: Task<Void, Never>) {
        cancelActiveTranscriptionTask()
        transcribeTask = task
        activeTranscribeTaskID = UUID()
    }

    func decodingCallbackForTesting() -> TranscriptionCallback {
        makeDecodingCallback(
            task: selectedTask == "transcribe" ? .transcribe : .translate,
            options: DecodingOptions()
        )
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
    @Published var projectLibraryState = ProjectLibraryState()

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

    var hasUnsavedProjectChanges: Bool {
        guard let currentProjectSnapshot = makeCurrentProjectSnapshot() else { return false }
        return currentProjectSnapshot != lastSavedProjectSnapshot
    }

    var canSaveCurrentProject: Bool {
        !audioState.isTranscribing &&
            (projectLibraryState.hasActiveProject || transcriptionResult != nil ||
                !transcriptionState.confirmedSegments.isEmpty)
    }

    enum UnsavedProjectDecision {
        case save, discard, cancel
    }

    func resolveUnsavedProjectChanges(_ decision: UnsavedProjectDecision) -> Bool {
        switch decision {
        case .save: return saveCurrentProject() != nil
        case .discard: return true
        case .cancel: return false
        }
    }

    func confirmDiscardingUnsavedChanges() -> Bool {
        guard !isConfirmingUnsavedChanges else { return false }
        guard hasUnsavedProjectChanges else { return true }
        isConfirmingUnsavedChanges = true
        defer { isConfirmingUnsavedChanges = false }
        let language = appLanguage == "en-US" ? "en" : appLanguage
        let bundle = Bundle.main.path(forResource: language, ofType: "lproj")
            .flatMap(Bundle.init(path:)) ?? .main
        func text(_ key: String) -> String {
            bundle.localizedString(forKey: key, value: key, table: "Localizable")
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = text("Save Changes?")
        alert.informativeText = text("Save your transcript before continuing.")
        alert.addButton(withTitle: text("Save Project"))
        alert.addButton(withTitle: text("Discard Changes"))
        alert.addButton(withTitle: text("Cancel")).keyEquivalent = "\u{1b}"
        switch alert.runModal() {
        case .alertFirstButtonReturn: return resolveUnsavedProjectChanges(.save)
        case .alertSecondButtonReturn: return resolveUnsavedProjectChanges(.discard)
        default: return resolveUnsavedProjectChanges(.cancel)
        }
    }

    var supportedAppLanguages: [AppLanguageOption] {
        Self.supportedAppLanguages
    }

    /// Model-dependent speaker analysis is available only after the local model passes validation.
    var isSpeakerDiarizationAvailable: Bool {
        modelManagementState.isSpeakerDiarizationModelReady
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
        .init(code: "ar", displayName: "العربية"),
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

    private static var shouldSimulateMissingSpeakerModelForUITesting: Bool {
        launchArguments.contains(UITestArgument.disableModelDownloads) &&
            !launchArguments.contains(UITestArgument.speakerFixture)
    }

    var shouldSkipModelSelectorAutoActionsForUITesting: Bool {
        Self.isUITesting
    }
#endif

    init(
        projectStore: CaptionMateProjectStore = .liveStore(),
        speakerAnalyzer: SpeakerAnalyzer? = nil,
        audioImportPreparer: AudioImportPreparer? = nil,
        speakerModelRootURL: URL? = SpeakerDiarizationModelStore.defaultRootURL()
    ) {
        self.projectStore = projectStore
        self.speakerModelRootURL = speakerModelRootURL
        self.speakerAnalyzer = speakerAnalyzer
        self.audioImportPreparer = audioImportPreparer ?? { url, scoped in
            try await Self.prepareAudioImport(from: url, needsSecurityScopedAccess: scoped)
        }
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
        modelManagementState.speakerDiarizationModelState = .downloaded
        modelManagementState.speakerDiarizationModelProgress = 1
        modelManagementState.speakerDiarizationModelNeedsRepair = false
        modelManagementState.speakerDiarizationModelNeedsUpdate = false

        let segments = [
            TranscriptionSegment(start: 0, end: 1.8, text: "Welcome to CaptionMate."),
            TranscriptionSegment(start: 2.0, end: 3.8, text: "This segment already has a speaker."),
            TranscriptionSegment(start: 4.0, end: 5.4, text: "The same speaker continues."),
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
            SpeakerSegmentAssignment(speakerID: 0),
        ]
        transcriptionState.speakerNames = [:]
        transcriptionState.speakerDiarization = SpeakerDiarizationState(
            detectedSpeakerCount: 2
        )
        audioState.audioFileName = "UITest Speaker Fixture"
        audioState.importedAudioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionMateUITestSpeakerFixture.wav")
        audioState.totalDuration = 5.4
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

    // MARK: - Project Library

    func refreshProjectLibrary() {
        do {
            projectLibraryState.summaries = try projectStore.listSummaries()
            projectLibraryState.errorMessage = nil
        } catch {
            projectLibraryState.errorMessage = error.localizedDescription
            showUserMessage(
                .warning,
                title: "Project List Unavailable",
                detail: error.localizedDescription
            )
        }
    }

    @discardableResult
    func saveCurrentProject(showMessage: Bool = true) -> CaptionMateProjectSummary? {
        guard let projectSnapshot = makeCurrentProjectSnapshot() else {
            if showMessage {
                showUserMessage(.warning, title: "Nothing to Save", detail: "No subtitles are ready.")
            }
            return nil
        }
        let sidecar = projectSnapshot.sidecar

        projectLibraryState.isSaving = true
        defer {
            projectLibraryState.isSaving = false
        }

        do {
            let now = Date()
            let existingProject = projectLibraryState.activeProjectID.flatMap {
                try? projectStore.load(id: $0)
            }
            let projectID = existingProject?.id ?? UUID().uuidString
            let displayName = projectDisplayName(from: sidecar)
            let project = CaptionMateProject(
                id: projectID,
                displayName: displayName,
                createdAt: existingProject?.createdAt ?? now,
                updatedAt: now,
                sourceAudioPath: projectSnapshot.sourceAudioPath,
                sourceAudioBookmarkData: projectSnapshot.sourceAudioBookmarkData,
                lastExportedAt: existingProject?.lastExportedAt,
                sidecar: sidecar
            )

            try projectStore.save(project)
            lastSavedProjectSnapshot = Self.snapshot(for: project)
            refreshProjectLibrary()
            projectLibraryState.activeProjectID = project.id
            projectLibraryState.activeProjectDisplayName = project.displayName
            projectLibraryState.lastSavedAt = project.updatedAt
            projectLibraryState.errorMessage = nil

            if showMessage {
                showUserMessage(.success, title: "Project Saved", detail: project.displayName)
            }

            return projectLibraryState.summaries.first { $0.id == project.id }
        } catch {
            projectLibraryState.errorMessage = error.localizedDescription
            if showMessage {
                showUserMessage(.error, title: "Project Save Failed", detail: error.localizedDescription)
            }
            return nil
        }
    }

    func shouldConfirmOpeningProject(id _: String) -> Bool {
        hasUnsavedProjectChanges
    }

    @discardableResult
    func openProjectSavingCurrentChangesFirst(id: String, showMessage: Bool = true) -> Bool {
        guard saveCurrentProject(showMessage: showMessage) != nil else {
            return false
        }
        openProject(id: id, showMessage: showMessage)
        return projectLibraryState.activeProjectID == id
    }

    func openProject(id: String, showMessage: Bool = true) {
        do {
            let project = try projectStore.load(id: id)
            resetState()
            restoreTranscriptionSidecar(project.sidecar)
            audioState.audioFileName = project.sidecar.audioFileName
            audioState.sourceAudioBookmarkData = project.sourceAudioBookmarkData
            // A source reference can remain valid even while its drive is offline.
            audioState.sourceAudioURL = project.sourceAudioPath.map { URL(fileURLWithPath: $0) }

            if let sourceAudioURL = resolveProjectAudioURL(project) {
                audioState.importedAudioURL = sourceAudioURL
                audioState.sourceAudioURL = sourceAudioURL
            }

            projectLibraryState.activeProjectID = project.id
            projectLibraryState.activeProjectDisplayName = project.displayName
            projectLibraryState.lastSavedAt = project.updatedAt
            lastSavedProjectSnapshot = Self.snapshot(for: project)
            projectLibraryState.errorMessage = nil
            refreshProjectLibrary()

            if showMessage {
                let audioDetail = audioState.importedAudioURL == nil ?
                    "Original audio is missing. You can still edit and export subtitles." :
                    "Project subtitles restored."
                showUserMessage(.success, title: "Project Opened", detail: audioDetail)
            }
        } catch {
            projectLibraryState.errorMessage = error.localizedDescription
            if showMessage {
                showUserMessage(.error, title: "Project Open Failed", detail: error.localizedDescription)
            }
        }
    }

    func deleteProject(id: String, showMessage: Bool = true) {
        do {
            let deletedActiveProject = projectLibraryState.activeProjectID == id
            try projectStore.delete(id: id)

            if deletedActiveProject {
                projectLibraryState.activeProjectID = nil
                projectLibraryState.activeProjectDisplayName = nil
                projectLibraryState.lastSavedAt = nil
                lastSavedProjectSnapshot = nil
            }

            refreshProjectLibrary()
            projectLibraryState.errorMessage = nil

            if showMessage {
                showUserMessage(.success, title: "Project Deleted")
            }
        } catch {
            projectLibraryState.errorMessage = error.localizedDescription
            if showMessage {
                showUserMessage(.error, title: "Project Delete Failed", detail: error.localizedDescription)
            }
        }
    }

    @discardableResult
    func renameProject(
        id: String,
        displayName: String,
        showMessage: Bool = true
    ) -> Bool {
        do {
            let renamedProject = try projectStore.rename(
                id: id,
                displayName: displayName
            )
            if projectLibraryState.activeProjectID == id {
                projectLibraryState.activeProjectDisplayName = renamedProject.displayName
                projectLibraryState.lastSavedAt = renamedProject.updatedAt
                lastSavedProjectSnapshot = Self.snapshot(for: renamedProject)
            }

            refreshProjectLibrary()
            projectLibraryState.errorMessage = nil

            if showMessage {
                showUserMessage(.success, title: "Project Renamed", detail: renamedProject.displayName)
            }
            return true
        } catch {
            projectLibraryState.errorMessage = error.localizedDescription
            if showMessage {
                showUserMessage(.error, title: "Project Rename Failed", detail: error.localizedDescription)
            }
            return false
        }
    }

    @discardableResult
    func duplicateProject(
        id: String,
        showMessage: Bool = true
    ) -> CaptionMateProjectSummary? {
        do {
            let sourceProject = try projectStore.load(id: id)
            let duplicateName = Self.duplicateDisplayName(for: sourceProject.displayName)
            let duplicatedProject = try projectStore.duplicate(
                id: id,
                displayName: duplicateName
            )

            refreshProjectLibrary()
            projectLibraryState.errorMessage = nil

            if showMessage {
                showUserMessage(.success, title: "Project Duplicated", detail: duplicatedProject.displayName)
            }
            return projectLibraryState.summaries.first { $0.id == duplicatedProject.id }
        } catch {
            projectLibraryState.errorMessage = error.localizedDescription
            if showMessage {
                showUserMessage(.error, title: "Project Duplicate Failed", detail: error.localizedDescription)
            }
            return nil
        }
    }

    @discardableResult
    func relinkProjectAudio(
        id: String,
        to sourceAudioURL: URL,
        needsSecurityScopedAccess: Bool,
        showMessage: Bool = true
    ) -> Bool {
        let didStartAccessing = needsSecurityScopedAccess ?
            sourceAudioURL.startAccessingSecurityScopedResource() : false
        var shouldKeepSecurityScopeOpen = false
        defer {
            if didStartAccessing && !shouldKeepSecurityScopeOpen {
                sourceAudioURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let bookmarkData = try? sourceAudioURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            let relinkedProject = try projectStore.relinkSourceAudio(
                id: id,
                sourceAudioURL: sourceAudioURL,
                bookmarkData: bookmarkData
            )

            if projectLibraryState.activeProjectID == id {
                stopImportedAudio()
                stopSourceAudioAccessIfNeeded()
                audioPlayer = nil
                audioState.sourceAudioURL = sourceAudioURL
                audioState.importedAudioURL = sourceAudioURL
                audioState.sourceAudioBookmarkData = bookmarkData
                audioState.totalDuration = 0
                audioPlaybackState.currentPlayerTime = 0
                projectLibraryState.lastSavedAt = relinkedProject.updatedAt
                lastSavedProjectSnapshot = Self.snapshot(for: relinkedProject)
                if didStartAccessing {
                    activeSourceAudioAccessURL = sourceAudioURL
                    shouldKeepSecurityScopeOpen = true
                }
            }

            refreshProjectLibrary()
            projectLibraryState.errorMessage = nil

            if showMessage {
                showUserMessage(
                    .success,
                    title: "Audio Relinked",
                    detail: sourceAudioURL.lastPathComponent
                )
            }
            return true
        } catch {
            projectLibraryState.errorMessage = error.localizedDescription
            if showMessage {
                showUserMessage(.error, title: "Audio Relink Failed", detail: error.localizedDescription)
            }
            return false
        }
    }

    private func resolveProjectAudioURL(_ project: CaptionMateProject) -> URL? {
        if let bookmarkData = project.sourceAudioBookmarkData {
            var isStale = false
            if let bookmarkedURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                let didStartAccessing = bookmarkedURL.startAccessingSecurityScopedResource()
                if FileManager.default.fileExists(atPath: bookmarkedURL.path) {
                    if didStartAccessing {
                        activeSourceAudioAccessURL = bookmarkedURL
                    }
                    return bookmarkedURL
                }
                if didStartAccessing {
                    bookmarkedURL.stopAccessingSecurityScopedResource()
                }
            }
        }

        guard let sourceAudioPath = project.sourceAudioPath,
              FileManager.default.fileExists(atPath: sourceAudioPath) else {
            return nil
        }
        return URL(fileURLWithPath: sourceAudioPath)
    }

    private func makeCurrentProjectSidecar() -> CaptionMateSidecar? {
        guard canSaveCurrentProject else { return nil }

        let language = transcriptionResult?.language ?? selectedLanguage
        let timings = transcriptionResult?.timings ?? TranscriptionTimings()
        let result = TranscriptionResult(
            text: transcriptionState.confirmedSegments.map(\.text).joined(separator: " "),
            segments: transcriptionState.confirmedSegments,
            language: language,
            timings: timings
        )
        return CaptionMateSidecar(
            result: result,
            audioFileName: audioState.audioFileName.isEmpty ? "Untitled Project" : audioState.audioFileName,
            speakerAssignments: transcriptionState.speakerAssignments,
            speakerNames: transcriptionState.speakerNames,
            selectedExportPreset: selectedExportPreset,
            frameRate: frameRate,
            includeSpeakerLabelsInExport: includeSpeakerLabelsInExport,
            speakerDiarizationSpeakerCount: speakerDiarizationSpeakerCount
        )
    }

    private func makeCurrentProjectSnapshot() -> ProjectSnapshot? {
        guard let sidecar = makeCurrentProjectSidecar() else { return nil }
        return ProjectSnapshot(
            sidecar: sidecar,
            sourceAudioPath: (audioState.sourceAudioURL ?? audioState.importedAudioURL)?.path,
            sourceAudioBookmarkData: audioState.sourceAudioBookmarkData
        )
    }

    private static func snapshot(for project: CaptionMateProject) -> ProjectSnapshot {
        ProjectSnapshot(
            sidecar: project.sidecar,
            sourceAudioPath: project.sourceAudioPath,
            sourceAudioBookmarkData: project.sourceAudioBookmarkData
        )
    }

    private func projectDisplayName(from sidecar: CaptionMateSidecar) -> String {
        let candidates = [
            projectLibraryState.activeProjectDisplayName ?? "",
            audioState.audioFileName,
            sidecar.audioFileName,
        ]
        return candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Untitled Project"
    }

    private static func duplicateDisplayName(for displayName: String) -> String {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmedName.isEmpty ? "Untitled Project" : trimmedName
        return "\(baseName) Copy"
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

    struct PreparedAudioImport: Sendable {
        let localURL: URL
        let sourceURL: URL
        let sourceBookmarkData: Data?
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
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let didStartAccessing = needsSecurityScopedAccess ?
                sourceURL.startAccessingSecurityScopedResource() : false
            defer {
                if didStartAccessing {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let localURL = try copyAudioFileToTemporaryDirectory(from: sourceURL)
            var prepared = false
            defer {
                if !prepared { try? FileManager.default.removeItem(at: localURL) }
            }
            try Task.checkCancellation()
            let sidecarResult = loadSidecarIfPresent(nextTo: sourceURL)
            let sourceBookmarkData = try? sourceURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            try Task.checkCancellation()
            prepared = true
            return PreparedAudioImport(
                localURL: localURL,
                sourceURL: sourceURL,
                sourceBookmarkData: sourceBookmarkData,
                displayName: sourceURL.deletingPathExtension().lastPathComponent,
                sidecar: sidecarResult.sidecar,
                sidecarURL: sidecarResult.url,
                sidecarRestoreError: sidecarResult.errorMessage
            )
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
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
        cancelAudioImport()
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
            audioState.sourceAudioURL = nil
            audioState.sourceAudioBookmarkData = nil
            audioState.audioFileName = "Subtitle"
            audioState.waveformSamples = []
            audioState.isWaveformProcessing = false
            audioState.totalDuration = 0
            audioPlaybackState.currentPlayerTime = 0
            audioPlayer = nil
            stopSourceAudioAccessIfNeeded()
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
        uiState.isSubtitleEditing = false
        projectLibraryState.activeProjectID = nil
        projectLibraryState.activeProjectDisplayName = nil
        projectLibraryState.lastSavedAt = nil
        lastSavedProjectSnapshot = nil
        transcriptionResult = nil
    }

    private func cancelActiveTranscriptionTask() {
        transcribeTask?.cancel()
        transcribeTask = nil
        activeTranscribeTaskID = nil
    }

    var isTranscriptionProgressVisible: Bool {
        guard let whisperKit,
              audioState.isTranscribing,
              let transcribeTask,
              !transcribeTask.isCancelled else {
            return false
        }
        return whisperKit.progress.fractionCompleted < 1
    }

    func cancelTranscription() {
        cancelActiveTranscriptionTask()
        resetState()
    }

    private func cancelActiveSpeakerDiarizationTask() {
        speakerDiarizationTask?.cancel()
        speakerDiarizationTask = nil
        activeSpeakerDiarizationTaskID = nil
        if let previousSpeakerDiarizationStatus {
            transcriptionState.speakerDiarization = previousSpeakerDiarizationStatus
        }
        previousSpeakerDiarizationStatus = nil
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
        cancelAudioImport()
        cancelActiveTranscriptionTask()
        cancelActiveSpeakerDiarizationTask()
        cancelAudioProcessingTasks()
        languageChangeNotificationTask?.cancel()
        languageChangeNotificationTask = nil

        let activeDownloadModels = Set(modelDownloadTasks.keys)
        for model in activeDownloadModels {
            modelDownloadCancellationErrors.removeValue(forKey: model)
            modelManagementState.currentDownloadingModels.remove(model)
            modelManagementState.cancellingModels.insert(model)
            modelDownloadProgressObjects[model]?.cancel()
            modelDownloadTasks[model]?.cancel()
        }
        modelManagementState.currentDownloadingModels.removeAll()
        modelManagementState.queuedDownloadModels.removeAll()
        modelManagementState.downloadBatchModels.removeAll {
            !activeDownloadModels.contains($0)
        }
        modelManagementState.downloadProgress = modelManagementState.downloadProgress.filter {
            activeDownloadModels.contains($0.key)
        }
        updateDownloadActivityState()
        modelCatalogTask?.cancel()
        modelCatalogTask = nil
        remoteModelSizeTask?.cancel()
        remoteModelSizeTask = nil
        if modelManagementState.catalogLoadState.isLoading {
            modelManagementState.catalogLoadState = .idle
        }
        modelManagementState.isRemoteModelSizeLoading = false
        if let speakerDiarizationModelTask {
            speakerDiarizationDownloadProgress?.cancel()
            speakerDiarizationModelTask.cancel()
            modelManagementState.speakerDiarizationModelState = .unloading
            modelManagementState.speakerDiarizationModelProgress = nil
        }
        modelLoadTask?.cancel()
        pendingModelLoadAfterDownload = nil
        pendingModelLoadIsRepair = false

        stopImportedAudio()
        stopSourceAudioAccessIfNeeded()
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

    func selectModel(_ model: String) {
        guard !isLoadingModel, modelLoadTask == nil else { return }

        if modelManagementState.localModels.contains(model) {
            selectedModel = model
            pendingModelLoadAfterDownload = nil
            pendingModelLoadIsRepair = false
            loadModel(model)
        } else {
            pendingModelLoadAfterDownload = model
            pendingModelLoadIsRepair = false
            if modelManagementState.isDownloading(model: model) ||
                modelManagementState.isQueued(model: model) {
                return
            }
            downloadModel(model)
        }
    }

    func loadModel(_ model: String, redownload: Bool = false) {
        if !modelManagementState.localModels.contains(model) {
            selectedModel = model
            pendingModelLoadAfterDownload = model
            pendingModelLoadIsRepair = redownload
            if !modelManagementState.isDownloading(model: model),
               !modelManagementState.isQueued(model: model) {
                downloadModel(model)
            }
            return
        }

        guard !isLoadingModel else { return }
        isLoadingModel = true
        modelLoadTask?.cancel()
        let taskID = UUID()
        activeModelLoadTaskID = taskID

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
                if self.activeModelLoadTaskID == taskID {
                    self.modelLoadTask = nil
                    self.activeModelLoadTaskID = nil
                    self.isLoadingModel = false
                }
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
                    maxTime: 2.0,
                    modelLoadOperationID: taskID
                )
            }
            defer { initProgressTask.cancel() }

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
                guard self.activeModelLoadTaskID == taskID else { return }
                print("Previous WhisperKit model released")
                self.whisperKit = nil
            }
            guard !Task.isCancelled,
                  self.activeModelLoadTaskID == taskID else {
                self.resetCancelledModelLoadState(operationID: taskID)
                return
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
            """)

            // 2. WhisperKit 인스턴스 생성
            do {
                let config = WhisperKitConfig(computeOptions: computeOptions,
                                              verbose: true,
                                              logLevel: .debug,
                                              prewarm: false,
                                              load: false,
                                              download: false)
                let initializedKit = try await WhisperKit(config)
                guard !Task.isCancelled,
                      self.activeModelLoadTaskID == taskID else {
                    await initializedKit.unloadModels()
                    self.resetCancelledModelLoadState(operationID: taskID)
                    return
                }
                self.whisperKit = initializedKit
            } catch is CancellationError {
                self.resetCancelledModelLoadState(operationID: taskID)
                return
            } catch {
                if Task.isCancelled {
                    self.resetCancelledModelLoadState(operationID: taskID)
                    return
                }
                guard self.activeModelLoadTaskID == taskID else { return }
                print("⚠️ WhisperKit initialization failed: \(error.localizedDescription)")
                await MainActor.run {
                    guard self.activeModelLoadTaskID == taskID else { return }
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
                    guard self.activeModelLoadTaskID == taskID else { return }
                    self.modelManagementState.modelState = .unloaded
                    self.modelManagementState.hasModelLoadError = true
                    self.modelManagementState.modelLoadError = "WhisperKit instance creation failed"
                    self.modelManagementState.loadingProgressValue = 0.0
                    self.isLoadingModel = false
                }
                return
            }

            // 3. 모델 파일 설정 단계
            let folder: URL
            do {
                folder = try ModelCatalogService.modelFolderURL(
                    for: model,
                    in: self.modelManagementState.localModelPath
                )
                if self.modelManagementState.downloadProgress[model] == nil {
                    self.modelManagementState.downloadProgress[model] = 1.0
                }
            } catch {
                guard self.activeModelLoadTaskID == taskID else { return }
                print("⚠️ Model files unavailable: \(error.localizedDescription)")
                await MainActor.run {
                    guard self.activeModelLoadTaskID == taskID else { return }
                    self.modelManagementState.modelState = .unloaded
                    self.modelManagementState.hasModelLoadError = true
                    self.modelManagementState
                        .modelLoadError = "Model files unavailable: \(error.localizedDescription)"
                    self.modelManagementState.loadingProgressValue = 0.0
                    self.isLoadingModel = false
                }
                return
            }

            let modelFolder = folder
                // 4. 모델 프리워밍 단계
                whisperKit.modelFolder = modelFolder

                // 프리워밍 시작
                await MainActor.run {
                    guard self.activeModelLoadTaskID == taskID else { return }
                    self.modelManagementState.modelState = .prewarming
                }
                guard !Task.isCancelled,
                      self.activeModelLoadTaskID == taskID else {
                    await whisperKit.unloadModels()
                    self.resetCancelledModelLoadState(operationID: taskID)
                    return
                }

                // 프리워밍 진행률 업데이트 작업 시작
                let prewarmProgressTask = Task {
                    await self.updateProgressBar(startProgress: 0.0,
                                                 targetProgress: prewarmProgressRatio,
                                                 maxTime: 15,
                                                 modelLoadOperationID: taskID) // 프리워밍은 보통 시간이 좀 더 걸림
                }
                defer { prewarmProgressTask.cancel() }

                // 모델 프리워밍
                do {
                    try await whisperKit.prewarmModels()
                    prewarmProgressTask.cancel()
                    guard !Task.isCancelled,
                          self.activeModelLoadTaskID == taskID else {
                        await whisperKit.unloadModels()
                        self.resetCancelledModelLoadState(operationID: taskID)
                        return
                    }

                    // 프리워밍 완료 후 진행률 업데이트
                    await MainActor.run {
                        guard self.activeModelLoadTaskID == taskID else { return }
                        self.modelManagementState.loadingProgressValue = prewarmProgressRatio
                    }
                } catch is CancellationError {
                    prewarmProgressTask.cancel()
                    await whisperKit.unloadModels()
                    self.resetCancelledModelLoadState(operationID: taskID)
                    return
                } catch {
                    if Task.isCancelled {
                        prewarmProgressTask.cancel()
                        await whisperKit.unloadModels()
                        self.resetCancelledModelLoadState(operationID: taskID)
                        return
                    }
                    guard self.activeModelLoadTaskID == taskID else { return }
                    prewarmProgressTask.cancel()
                    await self.handleWhisperPrewarmFailure(
                        model: model,
                        error: error,
                        redownload: redownload,
                        taskID: taskID,
                        failedKit: whisperKit
                    )
                    return
                }

                // 5. 모델 로딩 단계
                await MainActor.run {
                    guard self.activeModelLoadTaskID == taskID else { return }
                    self.modelManagementState.modelState = .loading
                }
                guard !Task.isCancelled,
                      self.activeModelLoadTaskID == taskID else {
                    await whisperKit.unloadModels()
                    self.resetCancelledModelLoadState(operationID: taskID)
                    return
                }

                // 로딩 진행률 업데이트 작업 시작
                let loadProgressTask = Task {
                    await self.updateProgressBar(startProgress: prewarmProgressRatio,
                                                 targetProgress: loadProgressRatio,
                                                 maxTime: 10,
                                                 modelLoadOperationID: taskID)
                }
                defer { loadProgressTask.cancel() }

                // 모델 로드 시도
                do {
                    try await whisperKit.loadModels()
                    loadProgressTask.cancel()
                    guard !Task.isCancelled,
                          self.activeModelLoadTaskID == taskID else {
                        await whisperKit.unloadModels()
                        self.resetCancelledModelLoadState(operationID: taskID)
                        return
                    }
                } catch is CancellationError {
                    loadProgressTask.cancel()
                    await whisperKit.unloadModels()
                    self.resetCancelledModelLoadState(operationID: taskID)
                    return
                } catch {
                    if Task.isCancelled {
                        loadProgressTask.cancel()
                        await whisperKit.unloadModels()
                        self.resetCancelledModelLoadState(operationID: taskID)
                        return
                    }
                    guard self.activeModelLoadTaskID == taskID else { return }
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
                            guard !Task.isCancelled,
                                  self.activeModelLoadTaskID == taskID else {
                                await whisperKit.unloadModels()
                                self.resetCancelledModelLoadState(operationID: taskID)
                                return
                            }
                        } catch is CancellationError {
                            await whisperKit.unloadModels()
                            self.resetCancelledModelLoadState(operationID: taskID)
                            return
                        } catch {
                            if Task.isCancelled {
                                await whisperKit.unloadModels()
                                self.resetCancelledModelLoadState(operationID: taskID)
                                return
                            }
                            guard self.activeModelLoadTaskID == taskID else { return }
                            await MainActor.run {
                                guard self.activeModelLoadTaskID == taskID else { return }
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
                            guard self.activeModelLoadTaskID == taskID else { return }
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
                    guard self.activeModelLoadTaskID == taskID,
                          !Task.isCancelled else { return }
                    self.publishModelLoadCompletion(
                        model: model,
                        modelState: whisperKit.modelState,
                        operationID: taskID
                    )
                }
        }
    }

    private func publishModelLoadCompletion(
        model: String,
        modelState: ModelState,
        operationID: UUID
    ) {
        guard activeModelLoadTaskID == operationID else { return }
        modelManagementState.availableLanguages = Constants.languages.map(\.key).sorted()
        modelManagementState.loadingProgressValue = 1
        modelManagementState.modelState = modelState
        currentLoadedModel = model
        modelManagementState.hasModelLoadError = false
        modelManagementState.modelLoadError = nil
        showUserMessage(
            .success,
            title: "Model Ready",
            detail: modelManagementState.displayName(for: model)
        )
    }

    private func resetCancelledModelLoadState(operationID: UUID) {
        guard activeModelLoadTaskID == operationID else { return }
        whisperKit = nil
        currentLoadedModel = ""
        modelManagementState.modelState = .unloaded
        modelManagementState.loadingProgressValue = 0
    }

    private func handleWhisperPrewarmFailure(
        model _: String,
        error: Error,
        redownload _: Bool,
        taskID: UUID,
        failedKit: WhisperKit?
    ) async {
        guard activeModelLoadTaskID == taskID,
              !Task.isCancelled else {
            if activeModelLoadTaskID == taskID {
                resetCancelledModelLoadState(operationID: taskID)
            }
            return
        }
        print("⚠️ Model prewarm failed: \(error.localizedDescription)")

        await failedKit?.unloadModels()
        guard activeModelLoadTaskID == taskID,
              !Task.isCancelled else {
            if activeModelLoadTaskID == taskID {
                resetCancelledModelLoadState(operationID: taskID)
            }
            return
        }

        whisperKit = nil
        modelManagementState.modelState = .unloaded
        modelManagementState.hasModelLoadError = true
        modelManagementState.modelLoadError =
            "Model optimization failed: \(error.localizedDescription)"
        modelManagementState.loadingProgressValue = 0.0
        isLoadingModel = false
    }

    /// 진행률 업데이트 - 시작 진행률부터 목표 진행률까지 자연스럽게 증가
    func updateProgressBar(
        startProgress: Float = 0.0,
        targetProgress: Float,
        maxTime: TimeInterval,
        modelLoadOperationID: UUID? = nil
    ) async {
        let progressRange = targetProgress - startProgress
        let decayConstant = -log(1 - 0.95) / Float(maxTime) // 95% 완료에 도달하는 시간 기준
        let startTime = Date()
        let updateInterval: TimeInterval = 0.2 // 업데이트 간격 (0.2초)

        // 업데이트 간격을 더 길게 설정하여 CPU 사용량 감소
        while !Task.isCancelled {
            if let modelLoadOperationID,
               activeModelLoadTaskID != modelLoadOperationID {
                break
            }
            let elapsedTime = Date().timeIntervalSince(startTime)
            // 자연스러운 곡선을 위해 지수 함수 사용
            let decayFactor = exp(-decayConstant * Float(elapsedTime))
            let progressIncrement = progressRange * (1 - decayFactor)
            let currentProgress = startProgress + progressIncrement

            // MainActor에서 한 번만 상태 업데이트
            await MainActor.run {
                guard modelLoadOperationID == nil ||
                        activeModelLoadTaskID == modelLoadOperationID else { return }
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
        if speakerDiarizationModelTask != nil,
           modelManagementState.isSpeakerDiarizationModelPreparing {
            return
        }

#if DEBUG
        if Self.shouldSimulateMissingSpeakerModelForUITesting {
            modelManagementState.speakerDiarizationModelState = .unloaded
            modelManagementState.speakerDiarizationModelPath = ""
            modelManagementState.speakerDiarizationModelProgress = nil
            modelManagementState.speakerDiarizationModelError = nil
            modelManagementState.speakerDiarizationModelNeedsRepair = false
            modelManagementState.speakerDiarizationModelNeedsUpdate = false
            modelManagementState.speakerDiarizationModelSize = SpeakerDiarizationModelStore
                .estimatedDownloadSize
            return
        }
#endif

        guard let modelRoot = speakerModelRootURL else {
            modelManagementState.speakerDiarizationModelState = .unloaded
            modelManagementState.speakerDiarizationModelPath = ""
            modelManagementState.speakerDiarizationModelError = "Document directory not found."
            modelManagementState.speakerDiarizationModelNeedsRepair = false
            modelManagementState.speakerDiarizationModelNeedsUpdate = false
            return
        }

        modelManagementState.speakerDiarizationModelPath = modelRoot.path

        if let failure = speakerModelIntegrityFailure {
            speakerModelIntegrityFailure = failure.rootURL == modelRoot ? failure.remainingFailure : nil
        }

        do {
            try SpeakerDiarizationModelStore.recoverBackupIfNeeded(for: modelRoot)
        } catch {
            modelManagementState.speakerDiarizationModelState = .unloaded
            modelManagementState.speakerDiarizationModelProgress = nil
            modelManagementState.speakerDiarizationModelError = error.localizedDescription
            modelManagementState.speakerDiarizationModelNeedsRepair = true
            modelManagementState.speakerDiarizationModelNeedsUpdate = false
            return
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: modelRoot.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            speakerModelIntegrityFailure = nil
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

        if report.isValid, speakerModelIntegrityFailure == nil {
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
                SpeakerDiarizationServiceError.repairMessage
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

        guard speakerDiarizationModelTask == nil,
              !modelManagementState.isSpeakerDiarizationModelPreparing else { return }

        refreshSpeakerDiarizationModelState()
        if !forceRepair,
           modelManagementState.isSpeakerDiarizationModelReady || speakerModelIntegrityFailure != nil {
            return
        }

        guard let modelRoot = speakerModelRootURL,
              let stagingDownloadBase = SpeakerDiarizationModelStore.stagingDownloadBaseURL() else {
            modelManagementState.speakerDiarizationModelError = "Document directory not found."
            return
        }

        speakerDiarizationDownloadProgress = nil
        modelManagementState.beginSpeakerDiarizationModelDownload(path: modelRoot.path)
        let operationID = UUID()
        activeSpeakerDiarizationModelTaskID = operationID

        speakerDiarizationModelTask = Task.detached(priority: .background) { [weak self] in
            let fileManager = FileManager.default
            var installedModel = false
            var downloadError: Error?

            do {
                if fileManager.fileExists(atPath: stagingDownloadBase.path) {
                    try fileManager.removeItem(at: stagingDownloadBase)
                }
                try Task.checkCancellation()
                let diskSpace = Self.diskSpaceStatus()
                if !diskSpace.isEnough {
                    Self.clearCoreMLRuntimeCacheContents()
                }

                let config = PyannoteConfig(
                    downloadBase: stagingDownloadBase.path,
                    modelRepo: SpeakerDiarizationModelStore.repoName,
                    download: true,
                    useBackgroundDownloadSession: false,
                    downloadRevision: SpeakerDiarizationModelStore.downloadRevision,
                    load: false,
                    verbose: false,
                    concurrentSegmenterWorkers: 1,
                    concurrentEmbedderWorkers: 1
                )
                let diarizer = SpeakerKitDiarizer.pyannote(config: config)
                let progressCallback: (Progress) -> Void = { [weak self] progress in
                    Task<Void, Never> { @MainActor [weak self] in
                        self?.updateSpeakerDiarizationDownloadProgress(
                            progress,
                            operationID: operationID
                        )
                    }
                }
                let resolvedModelPath = try await diarizer.loader.resolveModels(
                    downloader: diarizer.downloader,
                    progressCallback: progressCallback
                )
                try Task.checkCancellation()

                let stagedRoot = URL(fileURLWithPath: resolvedModelPath, isDirectory: true)
                    .standardizedFileURL
                let stagingPathPrefix = stagingDownloadBase.standardizedFileURL.path + "/"
                guard stagedRoot.path.hasPrefix(stagingPathPrefix) else {
                    throw CocoaError(.fileReadInvalidFileName)
                }

                let report = SpeakerDiarizationModelStore.validationReport(for: stagedRoot)
                guard report.isValid else {
                    throw CocoaError(.fileReadCorruptFile)
                }

                try await MainActor.run { [weak self] in
                    guard let self else { throw CancellationError() }
                    try self.commitSpeakerDiarizationModelDownload(
                        stagedRootURL: stagedRoot,
                        destinationRootURL: modelRoot,
                        operationID: operationID
                    )
                }
                installedModel = true
            } catch {
                downloadError = error
            }

            // The fixed staging directory belongs to this operation until cleanup returns.
            // Nothing may touch it after the MainActor releases the retry slot below.
            var downloadWasCancelled = !installedModel &&
                (downloadError is CancellationError || Task.isCancelled)
            do {
                if fileManager.fileExists(atPath: stagingDownloadBase.path) {
                    try fileManager.removeItem(at: stagingDownloadBase)
                }
            } catch {
                downloadError = error
                downloadWasCancelled = false
            }
            let didInstallModel = installedModel
            let errorMessage = downloadError.map {
                downloadWasCancelled ? "Download cancelled." : $0.localizedDescription
            }
            await MainActor.run { [weak self] in
                self?.finishSpeakerDiarizationModelDownload(
                    operationID: operationID,
                    didInstallModel: didInstallModel,
                    errorMessage: errorMessage,
                    showSuccessMessage: showSuccessMessage
                )
            }
        }
    }

    private func finishSpeakerDiarizationModelDownload(
        operationID: UUID,
        didInstallModel: Bool,
        errorMessage: String?,
        showSuccessMessage: Bool
    ) {
        guard activeSpeakerDiarizationModelTaskID == operationID else { return }
        if didInstallModel {
            speakerDiarizationModelManifestVersion = SpeakerDiarizationModelStore.manifestVersion
        }
        speakerDiarizationDownloadProgress = nil
        speakerDiarizationModelTask = nil
        activeSpeakerDiarizationModelTaskID = nil
        refreshSpeakerDiarizationModelState()
        if let errorMessage {
            modelManagementState.applySpeakerDiarizationDownloadFailure(
                message: errorMessage,
                modelIsValidAfterFailure: modelManagementState.isSpeakerDiarizationModelReady,
                modelExists: speakerModelRootURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false,
                updateIsRequired: speakerDiarizationModelManifestVersion < SpeakerDiarizationModelStore.manifestVersion
            )
        } else if showSuccessMessage {
            showUserMessage(
                .success,
                title: "Speaker Model Ready",
                detail: modelManagementState.formattedSpeakerDiarizationModelSize
            )
        }
    }

    private func commitSpeakerDiarizationModelDownload(
        stagedRootURL: URL,
        destinationRootURL: URL,
        operationID: UUID,
        expectedFileSHA256: [String: String] = SpeakerDiarizationModelStore.requiredFileSHA256
    ) throws {
        guard canCommitSpeakerDiarizationModelDownload(operationID: operationID) else {
            throw CancellationError()
        }

        try SpeakerDiarizationModelStore.installValidatedModel(
            from: stagedRootURL,
            to: destinationRootURL,
            expectedFileSHA256: expectedFileSHA256
        )
        speakerModelIntegrityFailure = nil
        modelManagementState.speakerDiarizationModelState = .loading
        modelManagementState.speakerDiarizationModelProgress = nil
    }

    private func canCommitSpeakerDiarizationModelDownload(operationID: UUID) -> Bool {
        guard activeSpeakerDiarizationModelTaskID == operationID,
              let task = speakerDiarizationModelTask,
              !task.isCancelled,
              modelManagementState.speakerDiarizationModelState != .unloading else {
            return false
        }
        return speakerDiarizationDownloadProgress?.isCancelled != true
    }

    func repairDefaultSpeakerDiarizationModel() {
        prepareDefaultSpeakerDiarizationModelIfNeeded(
            forceRepair: true,
            showSuccessMessage: true
        )
    }

    private func updateSpeakerDiarizationDownloadProgress(
        _ progress: Progress,
        operationID: UUID
    ) {
        guard activeSpeakerDiarizationModelTaskID == operationID,
              modelManagementState.speakerDiarizationModelState == .downloading else { return }
        speakerDiarizationDownloadProgress = progress
        modelManagementState.applySpeakerDiarizationDownloadProgress(progress)
    }

    func cancelDefaultSpeakerDiarizationModelDownload() {
        guard let task = speakerDiarizationModelTask else { return }
        speakerDiarizationDownloadProgress?.cancel()
        speakerDiarizationDownloadProgress = nil
        task.cancel()
        modelManagementState.speakerDiarizationModelState = .unloading
        modelManagementState.speakerDiarizationModelProgress = nil
        modelManagementState.speakerDiarizationModelError = "Cancelling download..."
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
        guard modelDownloadTasks[model] == nil,
              modelDownloadOperationIDs[model] == nil else { return }

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
        modelDownloadProgressObjects.removeValue(forKey: model)
        modelDownloadLastProgressCallbackTime.removeValue(forKey: model)
        modelDownloadLastProgressUIUpdateTime.removeValue(forKey: model)
        modelDownloadCancellationErrors.removeValue(forKey: model)

        let repoName = repoName
        let operationID = UUID()
        modelDownloadOperationIDs[model] = operationID
        let estimatedSize = estimatedDownloadSize(for: model)
        let requiredSpace = estimatedRequiredDownloadSpace(for: model)
        let reservedSpaceForOtherDownloads =
            estimatedRemainingDownloadSpaceForOtherActiveDownloads(excluding: model)
        let localModelPath = modelManagementState.localModelPath

        let task = Task.detached(priority: .background) { [weak self] in
            do {
                let resourceValues = try documents
                    .resourceValues(forKeys: [.volumeAvailableCapacityKey])
                guard let availableSpace = resourceValues.volumeAvailableCapacity else {
                    await MainActor.run { [weak self] in
                        self?.finishModelDownloadFailure(
                            model,
                            operationID: operationID,
                            message: "Cannot check disk space."
                        )
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
                    await MainActor.run { [weak self] in
                        self?.finishModelDownloadFailure(
                            model,
                            operationID: operationID,
                            message: errorMessage
                        )
                    }
                    return
                }

                let progressUpdateInterval: TimeInterval = 0.5

                let modelFolder = try await WhisperKit.download(
                    variant: model,
                    from: repoName,
                    progressCallback: { [weak self] progress in
                        // Progress 콜백 활동 기록 (모든 콜백에서 기록)
                        Task { @MainActor [weak self] in
                            guard let self,
                                  self.modelDownloadOperationIDs[model] == operationID else { return }
                            self.modelDownloadLastProgressCallbackTime[model] = Date()

                            // Progress 객체 저장 (처음 한 번만)
                            if self.modelDownloadProgressObjects[model] == nil {
                                self.modelDownloadProgressObjects[model] = progress
                                print("Progress object stored: \(model)")
                            }

                            // 진행률 업데이트 최적화
                            let currentTime = Date()
                            let lastUpdateTime = self.modelDownloadLastProgressUIUpdateTime[model]
                                ?? .distantPast
                            guard currentTime
                                .timeIntervalSince(lastUpdateTime) >= progressUpdateInterval else {
                                return
                            }
                            self.modelDownloadLastProgressUIUpdateTime[model] = currentTime

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
                                    self.requestModelDownloadCancellation(
                                        model,
                                        errorMessage: "Disk space became insufficient during download"
                                    )
                                    return
                                }
                            }
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
                try Task.checkCancellation()

                let didCommit = await MainActor.run { [weak self] in
                    guard let self,
                          self.canCommitModelDownload(model, operationID: operationID) else {
                        return false
                    }
                    self.modelManagementState.currentDownloadingModels.remove(model)
                    self.modelManagementState.cancellingModels.remove(model)
                    self.modelManagementState.downloadProgress[model] = 1.0
                    self.modelDownloadTasks[model] = nil
                    self.modelDownloadOperationIDs.removeValue(forKey: model)
                    self.modelDownloadCancellationErrors.removeValue(forKey: model)
                    self.modelDownloadProgressObjects.removeValue(forKey: model)
                    self.modelDownloadLastProgressCallbackTime.removeValue(forKey: model)
                    self.modelDownloadLastProgressUIUpdateTime.removeValue(forKey: model)

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
                    let shouldLoadModel = self.pendingModelLoadAfterDownload == model
                    let isRepairLoad = shouldLoadModel && self.pendingModelLoadIsRepair
                    if self.pendingModelLoadAfterDownload == model {
                        self.selectedModel = model
                        self.pendingModelLoadAfterDownload = nil
                        self.pendingModelLoadIsRepair = false
                    }
                    self.startNextQueuedDownloadIfPossible()
                    self.updateDownloadActivityState()
                    if shouldLoadModel {
                        self.loadModel(model, redownload: isRepairLoad)
                    }
                    return true
                }
                guard didCommit else { throw CancellationError() }

            } catch is CancellationError {
                print("Model download cancelled: \(model)")
                let ownsOperation = await MainActor.run { [weak self] in
                    self?.modelDownloadOperationIDs[model] == operationID
                }
                if ownsOperation {
                    Self.cleanupPartialDownload(model, localModelPath: localModelPath)
                }
                await MainActor.run { [weak self] in
                    self?.finishModelDownloadCancellation(model, operationID: operationID)
                }
            } catch {
                print("Model download failed: \(error.localizedDescription)")
                let ownsOperation = await MainActor.run { [weak self] in
                    self?.modelDownloadOperationIDs[model] == operationID
                }
                if ownsOperation {
                    Self.cleanupPartialDownload(model, localModelPath: localModelPath)
                }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if self.modelManagementState.cancellingModels.contains(model) {
                        self.finishModelDownloadCancellation(model, operationID: operationID)
                    } else {
                        self.finishModelDownloadFailure(
                            model,
                            operationID: operationID,
                            message: "Download failed: \(error.localizedDescription)",
                            downloadError: DownloadError.from(error)
                        )
                    }
                }
            }
        }

        modelDownloadTasks[model] = task
    }

    private func canCommitModelDownload(_ model: String, operationID: UUID) -> Bool {
        guard modelDownloadOperationIDs[model] == operationID,
              let task = modelDownloadTasks[model],
              !task.isCancelled,
              !modelManagementState.cancellingModels.contains(model) else {
            return false
        }
        return modelDownloadProgressObjects[model]?.isCancelled != true
    }

    private func clearModelDownloadRuntime(_ model: String, operationID: UUID) -> Bool {
        guard modelDownloadOperationIDs[model] == operationID else { return false }

        modelDownloadTasks.removeValue(forKey: model)
        modelDownloadOperationIDs.removeValue(forKey: model)
        modelDownloadProgressObjects.removeValue(forKey: model)
        modelDownloadLastProgressCallbackTime.removeValue(forKey: model)
        modelDownloadLastProgressUIUpdateTime.removeValue(forKey: model)
        modelManagementState.currentDownloadingModels.remove(model)
        modelManagementState.cancellingModels.remove(model)
        modelManagementState.downloadProgress[model] = nil
        modelManagementState.untrackDownloadRequest(model)
        return true
    }

    private func finishModelDownloadCancellation(_ model: String, operationID: UUID) {
        let errorMessage = modelDownloadCancellationErrors[model]
        guard clearModelDownloadRuntime(model, operationID: operationID) else { return }
        modelDownloadCancellationErrors.removeValue(forKey: model)

        if let errorMessage {
            modelManagementState.downloadErrors[model] = errorMessage
            showUserMessage(.error, title: "Download Failed", detail: errorMessage)
        } else {
            modelManagementState.downloadErrors.removeValue(forKey: model)
            showUserMessage(
                .info,
                title: "Download Cancelled",
                detail: modelManagementState.displayName(for: model)
            )
        }
        if pendingModelLoadAfterDownload == model {
            pendingModelLoadAfterDownload = nil
            pendingModelLoadIsRepair = false
        }
        startNextQueuedDownloadIfPossible()
        updateDownloadActivityState()
    }

    private func finishModelDownloadFailure(
        _ model: String,
        operationID: UUID,
        message: String,
        downloadError: DownloadError? = nil
    ) {
        guard clearModelDownloadRuntime(model, operationID: operationID) else { return }
        modelDownloadCancellationErrors.removeValue(forKey: model)
        modelManagementState.downloadErrors[model] = message
        if let downloadError {
            uiState.downloadError = downloadError
            uiState.showDownloadErrorAlert = true
        }
        if pendingModelLoadAfterDownload == model {
            pendingModelLoadAfterDownload = nil
            pendingModelLoadIsRepair = false
        }
        showUserMessage(.error, title: "Download Failed", detail: message)
        startNextQueuedDownloadIfPossible()
        updateDownloadActivityState()
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
            if pendingModelLoadAfterDownload == model {
                pendingModelLoadAfterDownload = nil
                pendingModelLoadIsRepair = false
            }
            updateDownloadActivityState()
            showUserMessage(
                .info,
                title: "Download Cancelled",
                detail: modelManagementState.displayName(for: model)
            )
            return
        }

        requestModelDownloadCancellation(model)
    }

    private func requestModelDownloadCancellation(
        _ model: String,
        errorMessage: String? = nil
    ) {
        guard let task = modelDownloadTasks[model],
              modelDownloadOperationIDs[model] != nil,
              !modelManagementState.cancellingModels.contains(model) else { return }

        if let errorMessage {
            modelDownloadCancellationErrors[model] = errorMessage
            modelManagementState.downloadErrors[model] = errorMessage
        }
        modelManagementState.cancellingModels.insert(model)
        modelManagementState.currentDownloadingModels.remove(model)
        modelManagementState.untrackDownloadRequest(model)
        updateDownloadActivityState()

        modelDownloadProgressObjects[model]?.cancel()
        task.cancel()
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
            guard !urls.isEmpty, confirmDiscardingUnsavedChanges() else { return }
            if urls.count > 1 {
                setBatchQueue(urls, needsSecurityScopedAccess: true)
            } else {
                clearBatchQueue()
            }

            guard let selectedFileURL = urls.first else { return }
            let operationID = beginAudioImportOperation()
            Task { [weak self] in
                guard let self else { return }
                if urls.count > 1 {
                    await self.processSelectedFile(
                        selectedFileURL, needsSecurityScopedAccess: true,
                        batchIndex: 0, operationID: operationID
                    )
                } else {
                    await self.processSelectedFile(
                        selectedFileURL,
                        needsSecurityScopedAccess: true,
                        operationID: operationID
                    )
                }
            }
        case let .failure(error):
            print("File selection error: \(error.localizedDescription)")
            showUserMessage(.error, title: "Import Failed", detail: error.localizedDescription)
        }
    }

    func setBatchQueue(_ urls: [URL], needsSecurityScopedAccess: Bool) {
        cancelAudioImport()
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
        cancelAudioImport()
        batchQueue = []
        currentBatchIndex = nil
    }

    func loadBatchItem(at index: Int, confirmingChanges: Bool = true) async {
        guard batchQueue.indices.contains(index) else { return }
        guard !confirmingChanges || confirmDiscardingUnsavedChanges() else { return }
        let item = batchQueue[index]
        await processSelectedFile(
            item.url,
            needsSecurityScopedAccess: item.needsSecurityScopedAccess,
            batchIndex: index
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
        cancelAudioImport()
        batchQueue.remove(at: index)

        if batchQueue.isEmpty {
            currentBatchIndex = nil
        } else if let currentBatchIndex {
            self.currentBatchIndex = min(currentBatchIndex, batchQueue.count - 1)
        }
    }

    private func cancelAudioImport() {
        audioImportTask?.cancel()
        audioImportTask = nil
        activeAudioImportID = nil
        audioImportSnapshot = nil
    }

    func beginAudioImportOperation() -> UUID {
        cancelAudioImport()
        let operationID = UUID()
        activeAudioImportID = operationID
        audioImportSnapshot = makeCurrentProjectSnapshot()
        return operationID
    }

    /// Prepare off-main and publish a complete import only while it still owns the document.
    @MainActor
    func processSelectedFile(
        _ selectedFileURL: URL,
        needsSecurityScopedAccess: Bool,
        batchIndex: Int? = nil,
        operationID requestedOperationID: UUID? = nil
    ) async {
        let operationID = requestedOperationID ?? beginAudioImportOperation()
        guard activeAudioImportID == operationID else { return }
        let originalSnapshot = audioImportSnapshot
        let prepare = audioImportPreparer
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try await prepare(selectedFileURL, needsSecurityScopedAccess)
        }
        audioImportTask = task
        defer {
            if activeAudioImportID == operationID {
                activeAudioImportID = nil
                audioImportTask = nil
                audioImportSnapshot = nil
            }
        }
        do {
            let importedAudio = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            var committed = false
            defer {
                if !committed { try? FileManager.default.removeItem(at: importedAudio.localURL) }
            }
            guard activeAudioImportID == operationID, !task.isCancelled, !Task.isCancelled else { return }
            let audioAsset = AVURLAsset(url: importedAudio.localURL)
            let duration = try? await audioAsset.load(.duration)
            guard activeAudioImportID == operationID, !task.isCancelled, !Task.isCancelled else { return }
            guard makeCurrentProjectSnapshot() == originalSnapshot else {
                showUserMessage(.warning, title: "Import Failed",
                                detail: "The transcript changed during import. Your current work was kept.")
                return
            }
            if let batchIndex {
                guard batchQueue.indices.contains(batchIndex),
                      batchQueue[batchIndex].url == selectedFileURL else { return }
            }

            activeAudioImportID = nil
            audioImportTask = nil
            resetState()
            committed = true
            if let batchIndex { currentBatchIndex = batchIndex }

            // 임시 파일 URL 저장 (나중에 정리용)
            audioState.temporaryAudioURL = importedAudio.localURL
            audioState.audioFileName = importedAudio.displayName
            audioState.waveformSamples = []
            audioState.isWaveformProcessing = true
            normalizedVolumeFactor = 1.0

            // 파일을 임포트한 후 바로 총 재생 시간을 확인하고 업데이트
            do {
                let durationInSeconds = duration.map(CMTimeGetSeconds) ?? 0

                // 재생 시간 업데이트 (재생 시작 전에 미리 설정)
                audioState.totalDuration = durationInSeconds.isFinite ? max(0, durationInSeconds) : 0
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
            audioState.sourceAudioURL = importedAudio.sourceURL
            audioState.sourceAudioBookmarkData = importedAudio.sourceBookmarkData

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
            guard activeAudioImportID == operationID,
                  !task.isCancelled, !Task.isCancelled, !(error is CancellationError) else { return }
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
        guard confirmDiscardingUnsavedChanges() else { return }
        resetState(preservingImportedAudio: true)
        stopImportedAudio()
        whisperKit?.audioProcessor = AudioProcessor()
        let taskID = UUID()
        activeTranscribeTaskID = taskID
        transcribeTask = Task { [weak self] in
            guard let self,
                  !Task.isCancelled,
                  self.activeTranscribeTaskID == taskID else { return }
            self.audioState.isTranscribing = true
            self.showUserMessage(.info, title: "Transcribing", detail: self.audioState.audioFileName)
            defer {
                if self.activeTranscribeTaskID == taskID {
                    self.audioState.isTranscribing = false
                    self.transcribeTask = nil
                    self.activeTranscribeTaskID = nil
                }
            }

            do {
                try await self.transcribeCurrentFile(path: path)
            } catch is CancellationError {
                guard self.activeTranscribeTaskID == taskID else { return }
                self.showUserMessage(.info, title: "Transcription Cancelled")
            } catch {
                guard self.activeTranscribeTaskID == taskID else { return }
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
        let audioFileSamples = try await CancellableAudioWork.run {
            try autoreleasepool {
                try AudioProcessor.loadAudioAsFloatArray(fromPath: path)
            }
        }
        try Task.checkCancellation()
        Logging.debug("Loaded audio file in \(Date().timeIntervalSince(loadingStart)) seconds")

        let transcription = try await transcribeAudioSamples(audioFileSamples)
        try Task.checkCancellation()
        let shouldRunSpeakerDiarization = enableSpeakerDiarization &&
            isSpeakerDiarizationAvailable &&
            (transcription?.segments.isEmpty == false)

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
            uiState.isSubtitleEditing = false
            refreshSubtitleQualityIssues()
            showUserMessage(
                .success,
                title: "Transcription Complete",
                detail: "\(segments.count) segments are ready to edit and export."
            )
            audioState.isTranscribing = false
        }

        try Task.checkCancellation()
        if shouldRunSpeakerDiarization {
            await runSpeakerDiarizationIfEnabled(audioSamples: audioFileSamples)
        }
    }

    private func runSpeakerDiarizationIfEnabled(audioSamples: [Float]) async {
        guard enableSpeakerDiarization,
              isSpeakerDiarizationAvailable,
              !transcriptionState.confirmedSegments.isEmpty else {
            return
        }

        guard let task = beginSpeakerDiarization(audioSamplesProvider: {
            audioSamples
        }) else { return }
        await task.value
    }

    @discardableResult
    func beginSpeakerDiarization(
        audioSamplesProvider: @escaping @Sendable () async throws -> [Float]
    ) -> Task<Void, Never>? {
        guard enableSpeakerDiarization,
              isSpeakerDiarizationAvailable,
              !transcriptionState.confirmedSegments.isEmpty else { return nil }

        cancelActiveSpeakerDiarizationTask()
        guard let modelRoot = speakerModelRootURL else { return nil }
        if speakerAnalyzer == nil { refreshSpeakerDiarizationModelState() }
        guard isSpeakerDiarizationAvailable else {
            showUserMessage(.warning, title: "Speaker Analysis Skipped", detail: "Speaker model is not ready.")
            return nil
        }

        let service = SpeakerDiarizationService(modelRootURL: modelRoot)
        let analyze: SpeakerAnalyzer = speakerAnalyzer ?? { samples, count, progress in
            try await service.diarize(audioSamples: samples, expectedSpeakerCount: count, progressHandler: progress)
        }
        let expectedSpeakerCount = speakerDiarizationExpectedSpeakerCount()
        let originalSnapshot = makeCurrentProjectSnapshot()
        let segments = transcriptionState.confirmedSegments
        let previousStatus = transcriptionState.speakerDiarization
        previousSpeakerDiarizationStatus = previousStatus
        let operationID = UUID()
        activeSpeakerDiarizationTaskID = operationID
        transcriptionState.speakerDiarization.isRunning = true
        transcriptionState.speakerDiarization.progress = 0
        transcriptionState.speakerDiarization.errorMessage = nil
        showUserMessage(.info, title: "Analyzing Speakers", detail: audioState.audioFileName)

        let task = Task { [weak self] in
            defer {
                if self?.activeSpeakerDiarizationTaskID == operationID {
                    self?.transcriptionState.speakerDiarization.isRunning = false
                    self?.speakerDiarizationTask = nil
                    self?.activeSpeakerDiarizationTaskID = nil
                    self?.previousSpeakerDiarizationStatus = nil
                }
            }

            do {
                let audioSamples = try await audioSamplesProvider()
                try Task.checkCancellation()
                let timeline = try await analyze(audioSamples, expectedSpeakerCount) { [weak self] progress in
                    let value = progress.fractionCompleted.isFinite ? progress.fractionCompleted : 0
                    Task { @MainActor [weak self] in
                        guard let self, self.activeSpeakerDiarizationTaskID == operationID else { return }
                        self.transcriptionState.speakerDiarization.progress = min(max(value, 0), 1)
                    }
                }
                try Task.checkCancellation()
                self?.publishSpeakerDiarizationResult(
                    timeline, segments: segments, originalSnapshot: originalSnapshot,
                    operationID: operationID, previousStatus: previousStatus
                )
            } catch is CancellationError {
                guard self?.activeSpeakerDiarizationTaskID == operationID else { return }
                self?.transcriptionState.speakerDiarization = previousStatus
            } catch {
                guard let self, self.activeSpeakerDiarizationTaskID == operationID else { return }
                self.transcriptionState.speakerDiarization = previousStatus
                guard !Task.isCancelled else { return }
                var detail: String? = error.localizedDescription
                if case let .modelUnavailable(failure) = error as? SpeakerDiarizationServiceError {
                    if failure.rootURL == modelRoot, let remainingFailure = failure.remainingFailure {
                        self.speakerModelIntegrityFailure = remainingFailure
                        self.refreshSpeakerDiarizationModelState()
                    } else {
                        detail = nil
                    }
                }
                self.transcriptionState.speakerDiarization.errorMessage = detail
                self.showUserMessage(
                    .warning,
                    title: "Speaker Analysis Failed",
                    detail: detail
                )
            }
        }
        speakerDiarizationTask = task
        return task
    }

    private func publishSpeakerDiarizationResult(
        _ timelineSegments: [SpeakerTimelineSegment],
        segments: [TranscriptionSegment],
        originalSnapshot: ProjectSnapshot?,
        operationID: UUID,
        previousStatus: SpeakerDiarizationState
    ) {
        guard activeSpeakerDiarizationTaskID == operationID,
              enableSpeakerDiarization else { return }
        guard makeCurrentProjectSnapshot() == originalSnapshot else {
            let detail = "The transcript changed during speaker analysis. Previous speaker labels were kept."
            transcriptionState.speakerDiarization = previousStatus
            transcriptionState.speakerDiarization.errorMessage = detail
            showUserMessage(.warning, title: "Speaker Analysis Skipped", detail: detail)
            return
        }
        guard !timelineSegments.isEmpty,
              timelineSegments.allSatisfy({ Self.normalizedSpeakerID($0.speakerID) != nil }) else {
            let detail = timelineSegments.isEmpty ? "No speakers detected." :
                "Too many speakers detected. Previous speaker labels were kept."
            transcriptionState.speakerDiarization = previousStatus
            transcriptionState.speakerDiarization.errorMessage = detail
            showUserMessage(.warning, title: "Speaker Analysis Skipped", detail: detail)
            return
        }

        let assignments = SpeakerAssignmentMapper.assignments(
            for: segments,
            from: timelineSegments
        )
        let names = SpeakerAssignmentMapper.reconciledNames(
            from: transcriptionState.speakerAssignments,
            names: transcriptionState.speakerNames,
            to: assignments
        )
        let namesNeedReview = names.count < transcriptionState.speakerNames.count
        let speakerCount = Set(timelineSegments.map(\.speakerID)).count
        transcriptionState.speakerAssignments = assignments
        transcriptionState.speakerNames = names
        transcriptionState.speakerDiarization = SpeakerDiarizationState(
            isRunning: false,
            progress: 1,
            detectedSpeakerCount: speakerCount,
            errorMessage: namesNeedReview ? "Speaker names need review after reanalysis." : nil
        )
        refreshSubtitleQualityIssues()

        let assignedCount = assignments.compactMap { $0 }.count
        showUserMessage(
            speakerCount > 0 ? .success : .warning,
            title: speakerCount > 0 ? "Speakers Ready" : "No Speakers Detected",
            detail: speakerCount > 0
                ? "\(speakerCount) speaker(s), \(assignedCount) labeled segment(s)."
                : nil
        )
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

    func beginSubtitleEditing() {
        guard !transcriptionState.confirmedSegments.isEmpty else { return }
        uiState.isSubtitleEditing = true
        uiState.focusedSubtitleSegmentIndex = nil
    }

    func applySubtitleEdits() {
        transcriptionResult?.text = transcriptionState.confirmedSegments
            .map(\.text)
            .joined(separator: " ")
        refreshSubtitleQualityIssues()
        uiState.isSubtitleEditing = false
        uiState.focusedSubtitleSegmentIndex = nil
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
        cancelActiveSpeakerDiarizationTask()
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
        uiState.isSubtitleEditing = false
        transcriptionState.speakerAssignments = sidecar.segments.map { segment in
            Self.normalizedSpeakerID(segment.speakerID).map(SpeakerSegmentAssignment.init)
        }
        var restoredSpeakerNames: [Int: String] = [:]
        for (key, value) in sidecar.speakerNames.sorted(by: { $0.key < $1.key }) {
            guard let speakerID = Self.normalizedSpeakerID(Int(key)) else { continue }
            if restoredSpeakerNames[speakerID] == nil || key == String(speakerID) {
                restoredSpeakerNames[speakerID] = value
            }
        }
        transcriptionState.speakerNames = restoredSpeakerNames

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
        guard Self.normalizedSpeakerID(speakerID) != nil else { return }
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
        guard speakerID == nil || Self.normalizedSpeakerID(speakerID) != nil else { return }
        normalizeSpeakerAssignmentCount()
        transcriptionState.speakerAssignments[index] = speakerID.map(SpeakerSegmentAssignment.init)
        refreshSubtitleQualityIssues()
    }

    func setSpeakerDiarizationEnabled(_ enabled: Bool) {
        if enabled {
            guard isSpeakerDiarizationAvailable else {
                enableSpeakerDiarization = false
                let detail = modelManagementState.isSpeakerDiarizationModelPreparing
                    ? "Speaker model is still preparing."
                    : (modelManagementState.speakerDiarizationModelError ??
                        "Speaker model is not ready.")
                showUserMessage(
                    .warning,
                    title: "Speaker Analysis Unavailable",
                    detail: detail
                )
                refreshSubtitleQualityIssues()
                return
            }

            enableSpeakerDiarization = true
        } else {
            enableSpeakerDiarization = false
            cancelActiveSpeakerDiarizationTask()
            transcriptionState.speakerDiarization = SpeakerDiarizationState()
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

        guard isSpeakerDiarizationAvailable else {
            let detail = modelManagementState.isSpeakerDiarizationModelPreparing
                ? "Speaker model is still preparing."
                : (modelManagementState.speakerDiarizationModelError ??
                    "Speaker model is not ready.")
            showUserMessage(.warning, title: "Speaker Analysis Unavailable", detail: detail)
            return
        }

        enableSpeakerDiarization = true

        beginSpeakerDiarization {
            try await CancellableAudioWork.run {
                try autoreleasepool {
                    try AudioProcessor.loadAudioAsFloatArray(fromPath: audioURL.path)
                }
            }
        }
    }

    func cancelSpeakerDiarization() {
        cancelActiveSpeakerDiarizationTask()
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
        uiState.isSubtitleEditing = true
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
            detectLanguage: isAutoLanguageEnable,
            skipSpecialTokens: !enableSpecialCharacters,
            withoutTimestamps: !enableTimestamps,
            wordTimestamps: enableWordTimestamp,
            clipTimestamps: seekClip,
            concurrentWorkerCount: Int(concurrentWorkerCount),
            chunkingStrategy: chunkingStrategy
        )
        let decodingCallback: TranscriptionCallback? = makeDecodingCallback(task: task, options: options)
        let transcriptionResults: [TranscriptionResult] = try await whisperKit.transcribe(
            audioArray: samples,
            decodeOptions: options,
            callback: decodingCallback
        )
        return TranscriptionUtilities.mergeTranscriptionResults(
            transcriptionResults,
            confirmedWords: []
        )
    }

    private func makeDecodingCallback(
        task: DecodingTask,
        options: DecodingOptions
    ) -> TranscriptionCallback {
        let operationID = activeTranscribeTaskID
        let compressionCheckWindow = Int(compressionCheckWindow)
        let compressionRatioThreshold = options.compressionRatioThreshold
        let logProbThreshold = options.logProbThreshold

        return { [weak self] progress in
            guard let self else { return false }

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let operationID,
                      self.activeTranscribeTaskID == operationID,
                      self.transcribeTask?.isCancelled == false else { return }
                let now = Date()
                guard now.timeIntervalSince(self.lastDecoderPreviewUpdate) >= 0.12 else {
                    return
                }
                self.lastDecoderPreviewUpdate = now

                let fallbacks = Int(progress.timings.totalDecodingFallbacks)
                let chunkId = task == .transcribe ? 0 : progress.windowId
                var updatedChunk = (chunkText: [progress.text], fallbacks: fallbacks)
                if var currentChunk = self.transcriptionState.currentChunks[chunkId],
                   let previousChunkText = currentChunk.chunkText.last {
                    if progress.text.count >= previousChunkText.count {
                        currentChunk.chunkText[currentChunk.chunkText.endIndex - 1] = progress.text
                        updatedChunk = currentChunk
                    } else {
                        if fallbacks == currentChunk.fallbacks && task == .transcribe {
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
            if currentTokens.count > compressionCheckWindow {
                let checkTokens: [Int] = Array(currentTokens.suffix(compressionCheckWindow))
                let compressionRatio = TextUtilities.compressionRatio(of: checkTokens)
                if let compressionRatioThreshold,
                   compressionRatio > compressionRatioThreshold {
                    Logging.debug("Early stopping due to compression threshold")
                    return false
                }
            }
            if let avgLogprob = progress.avgLogprob,
               let logProbThreshold,
               avgLogprob < logProbThreshold {
                Logging.debug("Early stopping due to logprob threshold")
                return false
            }
            return nil
        }
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
        cancelAudioImport()
        cancelActiveSpeakerDiarizationTask()
        // 재생 중이면 먼저 정지
        stopImportedAudio()
        cancelAudioProcessingTasks()

        // 임시 파일 정리
        cleanupPreviousAudioFile()

        // 파일 삭제 대신 앱에서만 초기화
        audioState.importedAudioURL = nil
        audioState.sourceAudioURL = nil
        audioState.sourceAudioBookmarkData = nil
        audioState.audioFileName = ""
        audioState.waveformSamples = []
        audioState.isWaveformProcessing = false
        audioState.totalDuration = 0
        audioPlaybackState.currentPlayerTime = 0
        stopSourceAudioAccessIfNeeded()
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

    private func stopSourceAudioAccessIfNeeded() {
        activeSourceAudioAccessURL?.stopAccessingSecurityScopedResource()
        activeSourceAudioAccessURL = nil
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
                audioState.waveformSamples = []
            }

            // 오디오 파일 정보 업데이트 (임포트 직후에도 실행)
            if audioState.totalDuration == 0 {
                let audioAsset = AVURLAsset(url: url)
                let duration = try await audioAsset.load(.duration)
                let durationInSeconds = CMTimeGetSeconds(duration)
                try Task.checkCancellation()
                guard audioState.importedAudioURL == url else { return }
                audioState.totalDuration = durationInSeconds
            }

            // 파형은 작은 버퍼 단위로 읽어 전체 오디오 샘플 배열을 추가로 만들지 않는다.
            let waveformSamples = try await CancellableAudioWork.run {
                try autoreleasepool {
                    try Self.computeWaveform(fromAudioURL: url)
                }
            }
            try Task.checkCancellation()

            guard audioState.importedAudioURL == url else { return }
            audioState.waveformSamples = waveformSamples
            audioState.isWaveformProcessing = false
            print(
                "Waveform update completed: \(waveformSamples.count) samples, total duration: \(audioState.totalDuration) seconds"
            )
        } catch is CancellationError {
            // Reset or the replacement worker owns the current loading state.
        } catch {
            guard !Task.isCancelled, audioState.importedAudioURL == url else { return }
            audioState.isWaveformProcessing = false
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

    func exportTranscription(
        skipQualityReview: Bool = false,
        exporter: (TranscriptionResult, String, Double) async -> ExportOutcome = { result, name, rate in
            await ExportService.exportTranscriptionResult(result: result, defaultFileName: name, frameRate: rate)
        }
    ) async {
        guard !isExporting, !audioState.isTranscribing else { return }
        guard !transcriptionState.speakerDiarization.isRunning else {
            showUserMessage(.info, title: "Analyzing Speakers")
            return
        }
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
        for (index, segment) in transcriptionState.confirmedSegments.enumerated() {
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
        // The exporter can suspend while the user opens or edits another document.
        let sidecar = makeCurrentProjectSidecar()
        let outcome = await exporter(exportResult, audioState.audioFileName, frameRate)

        switch outcome {
        case let .success(path):
            do {
                let exportURL: URL
                if let fileURL = URL(string: path), fileURL.isFileURL {
                    exportURL = fileURL
                } else {
                    exportURL = URL(fileURLWithPath: path)
                }
                let sidecarURL = try sidecar.map {
                    try CaptionMateSidecarService.write($0, nextToMediaURL: exportURL)
                }
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

    // MARK: - Drag and drop

    /// 파일 드래그 앤 드롭 메소드
    func handleDroppedFiles(providers: [NSItemProvider]) {
        // 첫 번째 파일만 처리
        guard let provider = providers.first, confirmDiscardingUnsavedChanges() else { return }
        clearBatchQueue()
        let operationID = beginAudioImportOperation()

        // 드래그 앤 드롭 상태 해제
        uiState.isTargeted = false

        provider
            .loadItem(forTypeIdentifier: UTType.fileURL.identifier,
                      options: nil) { [weak self] item, error in
                if let urlData = item as? Data,
                   let url = URL(dataRepresentation: urlData, relativeTo: nil) {
                    Task { @MainActor [weak self] in
                        guard let self, self.activeAudioImportID == operationID else { return }
                        await self.processSelectedFile(
                            url,
                            needsSecurityScopedAccess: true,
                            operationID: operationID
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
            await ModelCatalogService.fetchRemoteFolderSizes(
                repoName: repoName,
                models: modelsNeedingRemoteSize,
                maxConcurrentRequests: 3
            ) { [weak self] model, result in
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    switch result {
                    case let .success(size) where size > 0:
                        self.modelManagementState.modelSizes[model] = size
                        self.modelManagementState.modelSizeSources[model] = .remote
                    default:
                        if self.modelManagementState.modelSizes[model] == nil {
                            self.modelManagementState.modelSizes[model] = ModelCatalogService
                                .estimatedDownloadSize(for: model)
                            self.modelManagementState.modelSizeSources[model] = .estimate
                        }
                    }
                }
            }

            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                guard let self else { return }
                var cachedSizes = ModelCatalogService.cachedRemoteSizes(repoName: repoName)
                for model in modelsNeedingRemoteSize
                    where self.modelManagementState.modelSizeSources[model] == .remote {
                    cachedSizes[model] = self.modelManagementState.modelSizes[model]
                }
                ModelCatalogService.saveCachedRemoteSizes(cachedSizes, repoName: repoName)
                self.modelManagementState.isRemoteModelSizeLoading = false
                self.remoteModelSizeTask = nil
            }
        }
    }

    private func mergedModelList(localModels: [String], remoteModels: [String]) -> [String] {
        var seenModels: Set<String> = []
        return (localModels + remoteModels).filter { model in
            seenModels.insert(model).inserted
        }
    }
}
