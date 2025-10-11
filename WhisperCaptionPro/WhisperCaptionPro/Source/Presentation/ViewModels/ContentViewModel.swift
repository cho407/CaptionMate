//
//  ContentViewModel.swift
//  WhisperCaptionPro
//
//  Created by 조형구 on 3/3/25.
//

import AppKit
import AVFoundation
import Combine
import CoreML
import SwiftUI
import WhisperKit

// MARK: - ContentViewModel

@MainActor
class ContentViewModel: ObservableObject {
    private var isLoadingModel = false

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
        false // ✓ 적용됨 (skipSpecialTokens)
    @AppStorage("enableWordTimestamp") var enableWordTimestamp: Bool =
        false // ✓ 적용됨 (wordTimestamps)
    @AppStorage("temperatureStart") var temperatureStart: Double = 0.0
    @AppStorage("fallbackCount") var fallbackCount: Double = 5.0
    @AppStorage("compressionCheckWindow") var compressionCheckWindow: Double =
        60.0
    @AppStorage("sampleLength") var sampleLength: Int = 224 // ✓ 적용됨 (sampleLength)
    @AppStorage("concurrentWorkerCount") var concurrentWorkerCount: Double =
        4.0
    @AppStorage("chunkingStrategy") var chunkingStrategy: ChunkingStrategy =
        .vad

    // UI 전용 설정 - 전사 로직에 적용되지 않음
    @AppStorage("enableDecoderPreview") var enableDecoderPreview: Bool = true

    // Export 전용 설정
    @AppStorage("frameRate") var frameRate: Double = 30.0

    // 기타 설정
    @AppStorage("encoderComputeUnits") var encoderComputeUnits: MLComputeUnits = .cpuAndNeuralEngine
    @AppStorage("decoderComputeUnits") var decoderComputeUnits: MLComputeUnits = .cpuAndNeuralEngine
    @AppStorage("isAutoLanguageEnable") var isAutoLanguageEnable: Bool = false
    @AppStorage("appLanguage") var appLanguage: String = detectSystemLanguage()
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.auto.rawValue

    /// 현재 선택된 테마
    var appTheme: AppTheme {
        get { AppTheme(rawValue: appThemeRaw) ?? .auto }
        set { appThemeRaw = newValue.rawValue }
    }

    // MARK: - Initialization

    init() {
        // 첫 실행 시에만 시스템 언어로 설정 (이미 저장된 값이 있으면 유지)
        if UserDefaults.standard.object(forKey: "appLanguage") == nil {
            appLanguage = ContentViewModel.detectSystemLanguage()
        }
    }

    /// 시스템 언어 감지
    private static func detectSystemLanguage() -> String {
        let systemLanguage = Locale.preferredLanguages.first ?? "en"

        // 지원하는 언어 목록
        let supportedLanguages = ["ko"] // 현재는 한국어만 추가 지원

        // 시스템 언어가 지원 목록에 있는지 확인
        for supported in supportedLanguages {
            if systemLanguage.hasPrefix(supported) {
                return supported
            }
        }

        // 기본값 영어
        return "en"
    }

    // MARK: - Methods

    /// 앱 언어 변경
    func changeAppLanguage(to language: String) {
        appLanguage = language

        // Sheet들 닫기
        uiState.showAdvancedOptions = false // SettingsView
        uiState.isModelmanagerViewPresented = false // ModelManagerView

        // 시스템에 언어 변경 알림
        if let languageCode = getLanguageCode(for: language) {
            UserDefaults.standard.set([languageCode], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()

            print("App language changed to: \(language)")

            // 언어 변경 후 잠시 지연을 두고 Alert 표시
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.uiState.isLanguageChanged.toggle()
            }
        }
    }

    /// 언어 코드 변환
    private func getLanguageCode(for language: String) -> String? {
        switch language {
        case "en": return "en"
        case "ko": return "ko"
        default: return nil
        }
    }

    /// 현재 언어 표시명
    func getCurrentLanguageDisplayName() -> String {
        switch appLanguage {
        case "ko": return "한국어"
        case "en": return "English"
        default: return "English"
        }
    }

    /// 상태 초기화: 모든 상태 모델의 값을 초기값으로 재설정
    func resetState() {
        uiState.transcribeTask?.cancel()
        uiState.isTranscribingView = false
        audioState.isTranscribing = false
        whisperKit?.audioProcessor.stopRecording()

        // 임시 파일 정리
        cleanupPreviousAudioFile()

        transcriptionState.currentText = ""
        transcriptionState.currentChunks = [:]
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
        transcriptionResult = nil
    }

    /// Compute 옵션 생성 (설정 상태의 compute unit 값을 사용)
    func getComputeOptions() -> ModelComputeOptions {
        return ModelComputeOptions(
            audioEncoderCompute: encoderComputeUnits,
            textDecoderCompute: decoderComputeUnits
        )
    }

    // MARK: - Model Management

    /// 캐시 디렉토리 정리 함수
    func clearCoreMLRuntimeCache() {
        // 앱 캐시 디렉토리 경로 가져오기
        let fileManager = FileManager.default

        // 1. 앱의 캐시 디렉토리 찾기
        guard let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
            .first else {
            print("Cache directory not found.")
            return
        }

        // 2. 앱의 번들 ID 가져오기
        let bundleID = Bundle.main.bundleIdentifier ?? "com.WhisperCaptionPro"

        // 3. CoreML 캐시 디렉토리 찾기
        let possibleCacheDirs = [
            cachesDirectory.appendingPathComponent(bundleID)
                .appendingPathComponent("com.apple.e5rt.e5bundlecache"),
            cachesDirectory.appendingPathComponent(bundleID)
                .appendingPathComponent("com.apple.CoreML"),
            cachesDirectory.appendingPathComponent("com.apple.CoreML"),
            cachesDirectory.appendingPathComponent("CoreML"),
        ]

        // 4. 모든 가능한 캐시 디렉토리 정리
        var clearedAny = false
        for cacheDir in possibleCacheDirs {
            if fileManager.fileExists(atPath: cacheDir.path) {
                do {
                    // a. 디렉토리 내용 가져오기
                    let contents = try fileManager.contentsOfDirectory(
                        at: cacheDir,
                        includingPropertiesForKeys: nil
                    )

                    // b. 각 파일/폴더 삭제
                    for item in contents {
                        do {
                            try fileManager.removeItem(at: item)
                            print("Cache item deleted: \(item.lastPathComponent)")
                            clearedAny = true
                        } catch {
                            print(
                                "Failed to delete cache item: \(item.lastPathComponent) - \(error.localizedDescription)"
                            )
                        }
                    }

                    print("CoreML cache directory cleaned: \(cacheDir.path)")
                } catch {
                    print("Failed to access CoreML cache directory: \(error.localizedDescription)")
                }
            }
        }

        // 5. 임시 디렉토리 정리
        // tmpdir은 모든 앱이 공유하므로 관련 파일만 신중하게 삭제
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        do {
            let tempContents = try fileManager.contentsOfDirectory(
                at: tempDirectory,
                includingPropertiesForKeys: [.fileSizeKey, .creationDateKey]
            )

            // 앱 관련 임시 파일 필터링
            let appTempFiles = tempContents.filter { file in
                let fileName = file.lastPathComponent.lowercased()
                return fileName.contains("coreml") ||
                    fileName.contains("whisper") ||
                    fileName.contains(".bundle") ||
                    fileName.contains("model") ||
                    fileName.contains("mps") ||
                    fileName.contains("mlmodel") ||
                    fileName.contains(".wav") ||
                    fileName.contains(".mp3") ||
                    fileName.contains(".m4a") ||
                    fileName.contains(".aac") ||
                    fileName.contains(".flac") ||
                    fileName.hasPrefix("tmp") || // 시스템 임시 파일
                    fileName.contains("download") // 다운로드 관련
            }

            var totalClearedSize: Int64 = 0
            for tempFile in appTempFiles {
                do {
                    // 파일 크기 확인
                    let resourceValues = try tempFile.resourceValues(forKeys: [.fileSizeKey])
                    let fileSize = resourceValues.fileSize ?? 0

                    try fileManager.removeItem(at: tempFile)
                    totalClearedSize += Int64(fileSize)
                    print(
                        "Temporary file deleted: \(tempFile.lastPathComponent) (\(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)))"
                    )
                    clearedAny = true
                } catch {
                    print(
                        "Failed to delete temporary file: \(tempFile.lastPathComponent) - \(error.localizedDescription)"
                    )
                }
            }

            if totalClearedSize > 0 {
                print(
                    "Total temporary files cleaned: \(ByteCountFormatter.string(fromByteCount: totalClearedSize, countStyle: .file))"
                )
            }
        } catch {
            print("Failed to search temporary directory: \(error.localizedDescription)")
        }

        // 6. 결과 메시지 출력
        if clearedAny {
            print("CoreML cache files cleaned")
        } else {
            print("No CoreML cache files found to clean")
        }
    }

    // 디스크 여유 공간 확인 함수를 추가합니다
    func checkDiskSpace() -> (available: Int64, required: Int64, isEnough: Bool) {
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

            // volumeAvailableCapacity는 Int 타입이므로 Int64로 변환
            let availableSpaceInt64 = Int64(availableSpace)

            // CoreML에 필요한 예상 캐싱 공간
            let requiredSpace: Int64 = 3_000_000_000 // 1GB

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
        uiState.transcribeTask?.cancel()
        uiState.transcriptionTask?.cancel()
        uiState.isTranscribingView = false

        // 전사 관련 상태 초기화
        resetState()

        // CoreML 런타임 캐시 정리
        clearCoreMLRuntimeCache()

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

        Task {
            // 로딩 단계별 진행률 비율 설정 (초기화/프리워밍/로딩)
            let initProgressRatio: Float = 0.9 // 초기화 단계 (0.0 ~ 0.2)
            let prewarmProgressRatio: Float = 0.7 // 프리워밍 단계 (0.2 ~ 0.7)
            let loadProgressRatio: Float = 1.0 // 로딩 단계 (0.7 ~ 1.0)

            // 1. 초기화 단계 진행률 표시 시작
            let initProgressTask = Task {
                await updateProgressBar(
                    startProgress: 0.0,
                    targetProgress: initProgressRatio,
                    maxTime: 2.0
                )
            }

            // 디스크 공간 확인 및 캐시 정리
            let diskSpace = checkDiskSpace()
            if !diskSpace.isEnough {
                print(
                    "⚠️ Insufficient disk space: Available \(diskSpace.available / 1_000_000) MB, Required \(diskSpace.required / 1_000_000) MB"
                )
                clearCoreMLRuntimeCache()
            }

            // 기존 WhisperKit 인스턴스 해제
            if let kit = whisperKit {
                await kit.unloadModels()
                print("Previous WhisperKit model released")
                whisperKit = nil
            }

            // 초기화 진행률 업데이트 작업 완료
            initProgressTask.cancel()
            await MainActor.run {
                modelManagementState.loadingProgressValue = initProgressRatio
            }

            print("Selected model: \(model)")
            print("""
                연산 옵션:
                - Mel Spectrogram:  \(getComputeOptions().melCompute.description)
                - Audio Encoder:    \(getComputeOptions().audioEncoderCompute.description)
                - Text Decoder:     \(getComputeOptions().textDecoderCompute.description)
                - Prefill Data:     \(getComputeOptions().prefillCompute.description)
            """)

            // 2. WhisperKit 인스턴스 생성
            do {
                let config = WhisperKitConfig(computeOptions: getComputeOptions(),
                                              verbose: true,
                                              logLevel: .debug,
                                              prewarm: false,
                                              load: false,
                                              download: false)
                whisperKit = try await WhisperKit(config)
            } catch {
                print("⚠️ WhisperKit initialization failed: \(error.localizedDescription)")
                await MainActor.run {
                    modelManagementState.modelState = .unloaded
                    modelManagementState.hasModelLoadError = true
                    modelManagementState
                        .modelLoadError =
                        "Model initialization failed: \(error.localizedDescription)"
                    modelManagementState.loadingProgressValue = 0.0
                    isLoadingModel = false
                }
                return
            }

            guard let whisperKit = whisperKit else {
                await MainActor.run {
                    modelManagementState.modelState = .unloaded
                    modelManagementState.hasModelLoadError = true
                    modelManagementState.modelLoadError = "WhisperKit instance creation failed"
                    modelManagementState.loadingProgressValue = 0.0
                    isLoadingModel = false
                }
                return
            }

            // 3. 모델 파일 설정 단계
            var folder: URL?
            do {
                if modelManagementState.localModels.contains(model) && !redownload {
                    // 로컬 모델 경로 가져오기 - 다운로드 없이 바로 로드
                    folder = URL(fileURLWithPath: modelManagementState.localModelPath)
                        .appendingPathComponent(model)

                    // 로컬 모델은 다운로드 상태를 완료로 설정
                    if modelManagementState.downloadProgress[model] == nil {
                        modelManagementState.downloadProgress[model] = 1.0
                    }
                } else {
                    // 다운로드 시작 전 상태 업데이트
                    await MainActor.run {
                        modelManagementState.modelState = .downloading
                        modelManagementState.currentDownloadingModels.insert(model)
                        modelManagementState.isDownloading = true
                    }

                    let downloadTask = Task {
                        await updateProgressBar(
                            startProgress: 0.0,
                            targetProgress: 0.99,
                            maxTime: 20.0
                        )
                    }

                    // 모델 다운로드
                    folder = try await WhisperKit.download(
                        variant: model,
                        from: repoName,
                        progressCallback: { progress in
                            Task { @MainActor in
                                // 다운로드 전용 진행률 업데이트 (0.0 ~ 1.0)
                                self.modelManagementState
                                    .downloadProgress[model] = Float(progress.fractionCompleted)
                            }
                        }
                    )

                    // 다운로드 완료 후 상태 업데이트
                    downloadTask.cancel()
                    await MainActor.run {
                        modelManagementState.modelState = .downloaded
                        modelManagementState.downloadProgress[model] = 1.0
                        modelManagementState.currentDownloadingModels.remove(model)

                        // 다운로드 중인 모델이 더 없다면 다운로드 상태 해제
                        if modelManagementState.currentDownloadingModels.isEmpty {
                            modelManagementState.isDownloading = false
                        }

                        if !modelManagementState.localModels.contains(model) {
                            modelManagementState.localModels.append(model)
                        }
                    }
                }
            } catch {
                print("⚠️ Model download failed: \(error.localizedDescription)")
                await MainActor.run {
                    modelManagementState.modelState = .unloaded
                    modelManagementState.hasModelLoadError = true
                    modelManagementState
                        .modelLoadError = "Model download failed: \(error.localizedDescription)"
                    modelManagementState.loadingProgressValue = 0.0
                    modelManagementState.downloadProgress[model] = nil
                    modelManagementState.currentDownloadingModels.remove(model)

                    // 다운로드 중인 모델이 더 없다면 다운로드 상태 해제
                    if modelManagementState.currentDownloadingModels.isEmpty {
                        modelManagementState.isDownloading = false
                    }

                    isLoadingModel = false
                }
                return
            }

            if let modelFolder = folder {
                // 4. 모델 프리워밍 단계
                whisperKit.modelFolder = modelFolder

                // 프리워밍 시작
                await MainActor.run {
                    modelManagementState.modelState = .prewarming
                }

                // 프리워밍 진행률 업데이트 작업 시작
                let prewarmProgressTask = Task {
                    await updateProgressBar(startProgress: 0.0,
                                            targetProgress: prewarmProgressRatio,
                                            maxTime: 15) // 프리워밍은 보통 시간이 좀 더 걸림
                }

                // 모델 프리워밍
                do {
                    try await whisperKit.prewarmModels()
                    prewarmProgressTask.cancel()

                    // 프리워밍 완료 후 진행률 업데이트
                    await MainActor.run {
                        modelManagementState.loadingProgressValue = prewarmProgressRatio
                    }
                } catch {
                    print("⚠️ Model prewarm failed: \(error.localizedDescription)")
                    prewarmProgressTask.cancel()

                    // 재다운로드 시도
                    if !redownload {
                        await MainActor.run {
                            modelManagementState.loadingProgressValue = 0.0
                            modelManagementState.hasModelLoadError = true
                            modelManagementState
                                .modelLoadError = "Model optimization failed, retrying..."
                        }
                        loadModel(model, redownload: true)
                        isLoadingModel = false
                        return
                    } else {
                        await MainActor.run {
                            modelManagementState.modelState = .unloaded
                            modelManagementState.hasModelLoadError = true
                            modelManagementState
                                .modelLoadError =
                                "Model optimization failed: \(error.localizedDescription)"
                            modelManagementState.loadingProgressValue = 0.0
                            isLoadingModel = false
                        }
                        return
                    }
                }

                // 5. 모델 로딩 단계
                await MainActor.run {
                    modelManagementState.modelState = .loading
                }

                // 로딩 진행률 업데이트 작업 시작
                let loadProgressTask = Task {
                    await updateProgressBar(startProgress: prewarmProgressRatio,
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
                        clearCoreMLRuntimeCache()

                        // 한 번 더 시도
                        do {
                            try await Task.sleep(nanoseconds: 500_000_000) // 500ms 대기
                            try await whisperKit.loadModels()
                        } catch {
                            await MainActor.run {
                                modelManagementState.modelState = .unloaded
                                modelManagementState.hasModelLoadError = true
                                modelManagementState
                                    .modelLoadError =
                                    "Model load failed (after retry): \(error.localizedDescription)"
                                modelManagementState.loadingProgressValue = 0.0
                                isLoadingModel = false
                            }
                            return
                        }
                    } else {
                        await MainActor.run {
                            modelManagementState.modelState = .unloaded
                            modelManagementState.hasModelLoadError = true
                            modelManagementState
                                .modelLoadError = "Model load failed: \(error.localizedDescription)"
                            modelManagementState.loadingProgressValue = 0.0
                            isLoadingModel = false
                        }
                        return
                    }
                }

                // 모델 로딩 성공
                await MainActor.run {
                    // 모델 정보 업데이트 및 완료 상태 설정
                    modelManagementState.availableLanguages = Constants.languages.map { $0.key }
                        .sorted()
                    modelManagementState.loadingProgressValue = loadProgressRatio
                    modelManagementState.modelState = whisperKit.modelState
                    currentLoadedModel = model

                    // 에러 상태 초기화 (성공적으로 로드됨)
                    modelManagementState.hasModelLoadError = false
                    modelManagementState.modelLoadError = nil
                }
            }
            isLoadingModel = false
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
            let modelFolder = URL(fileURLWithPath: modelManagementState.localModelPath)
                .appendingPathComponent(model)
            do {
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
            } catch {
                print("Error deleting model: \(error)")
            }
        }
    }

    // MARK: - 모델 다운로드 관리

    /// 모델 다운로드
    func downloadModel(_ model: String) {
        // 현재 다운로드 중인 모델 수가 최대 동시 다운로드 수보다 작은지 확인
        guard modelManagementState.canStartDownload(model: model) else {
            print("Maximum concurrent downloads reached")
            return
        }

        // 다운로드 시작 전 디스크 공간 확인
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first else {
            print("Document directory not found")
            return
        }

        // 다운로드 상태 업데이트
        modelManagementState.currentDownloadingModels.insert(model)
        modelManagementState.isDownloading = true
        modelManagementState.downloadProgress[model] = 0.0
        modelManagementState.downloadErrors.removeValue(forKey: model)

        // 기존 다운로드 Task가 있다면 취소
        if let existingTask = modelManagementState.downloadTasks[model] {
            existingTask.cancel()
            modelManagementState.downloadTasks[model] = nil
        }

        // 백그라운드 작업 생성
        let task = Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }

            do {
                let resourceValues = try documents
                    .resourceValues(forKeys: [.volumeAvailableCapacityKey])
                guard let availableSpace = resourceValues.volumeAvailableCapacity else {
                    await MainActor.run {
                        self.modelManagementState.downloadErrors[model] = "Cannot check disk space"
                    }
                    return
                }

                // 모델 크기 예상치 계산
                let estimatedSize: Int64
                if model.contains("large") {
                    estimatedSize = 3_600_000_000 // 3GB + 20%
                } else if model.contains("medium") {
                    estimatedSize = 1_800_000_000 // 1.5GB + 20%
                } else if model.contains("small") {
                    estimatedSize = 600_000_000 // 500MB + 20%
                } else if model.contains("base") {
                    estimatedSize = 300_000_000 // 250MB + 20%
                } else {
                    estimatedSize = 180_000_000 // 150MB + 20%
                }

                if availableSpace < estimatedSize {
                    let availableGB = Double(availableSpace) / 1_000_000_000.0
                    let requiredGB = Double(estimatedSize) / 1_000_000_000.0
                    let errorMessage = String(
                        format: "Insufficient disk space. Required: %.1f GB, Available: %.1f GB",
                        requiredGB,
                        availableGB
                    )
                    await MainActor.run {
                        self.modelManagementState.downloadErrors[model] = errorMessage
                    }
                    return
                }

                // 다운로드 진행률 업데이트를 위한 타이머 설정
                let progressUpdateInterval: TimeInterval = 0.5 // 0.5초마다 업데이트
                var lastUpdateTime = Date()

                // 다운로드 시작
                let modelFolder = try await WhisperKit.download(
                    variant: model,
                    from: self.repoName,
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
                                Task {
                                    await self.cleanupPartialDownload(model)
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

                        // 취소 중인 상태인지 확인 - 즉시 중단
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
                                    Task {
                                        await self.cleanupPartialDownload(model)
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
                                        Int64(Double(estimatedSize) *
                                            (1.0 - progress.fractionCompleted)) {
                                        self.modelManagementState
                                            .downloadErrors[model] =
                                            "Disk space became insufficient during download"
                                        self.modelManagementState.currentDownloadingModels
                                            .remove(model)
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

                // 다운로드 완료 처리
                await MainActor.run {
                    self.modelManagementState.currentDownloadingModels.remove(model)
                    self.modelManagementState.downloadProgress[model] = 1.0

                    if !self.modelManagementState.localModels.contains(model) {
                        self.modelManagementState.localModels.append(model)
                    }

                    // 실제 다운로드된 모델의 크기 계산
                    let actualSize = self.calculateFolderSize(url: modelFolder)
                    self.modelManagementState.modelSizes[model] = actualSize

                    // 모든 다운로드가 완료되었는지 확인
                    if self.modelManagementState.currentDownloadingModels.isEmpty {
                        self.modelManagementState.isDownloading = false
                    }
                }

            } catch is CancellationError {
                print("Model download cancelled: \(model)")
                // 취소 중 상태가 아니라면 즉시 정리 (모니터링이 없는 경우)
                let isCancelling = await MainActor
                    .run { self.modelManagementState.cancellingModels.contains(model) }
                if !isCancelling {
                    await cleanupPartialDownload(model)
                }
            } catch {
                print("Model download failed: \(error.localizedDescription)")

                // DownloadError로 변환 (취소로 인한 파일 이동 에러는 nil 반환)
                let downloadError = DownloadError.from(error)

                await MainActor.run {
                    self.modelManagementState
                        .downloadErrors[model] = "Download failed: \(error.localizedDescription)"
                    self.modelManagementState.currentDownloadingModels.remove(model)
                    self.modelManagementState.downloadProgress[model] = nil
                    self.modelManagementState.cancellingModels.remove(model) // 에러 시 취소 상태도 해제
                    self.modelManagementState.lastProgressCallbackTime.removeValue(forKey: model)
                    self.modelManagementState.downloadProgressObjects.removeValue(forKey: model)

                    if self.modelManagementState.currentDownloadingModels.isEmpty {
                        self.modelManagementState.isDownloading = false
                    }

                    // 다운로드 실패 알림 표시 (취소로 인한 에러가 아닌 경우만)
                    if let downloadError = downloadError {
                        self.uiState.downloadError = downloadError
                        self.uiState.showDownloadErrorAlert = true
                    }
                }
                await cleanupPartialDownload(model)
            }
        }

        // 작업 참조 저장
        modelManagementState.downloadTasks[model] = task
    }

    /// 부분 다운로드 파일 정리 헬퍼 메서드
    private func cleanupPartialDownload(_ model: String) async {
        // 부분적으로 다운로드된 파일 삭제
        let modelFolder = URL(fileURLWithPath: modelManagementState.localModelPath)
            .appendingPathComponent(model)
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
        guard let task = modelManagementState.downloadTasks[model],
              modelManagementState.currentDownloadingModels.contains(model) else {
            return
        }

        print("Download cancellation requested: \(model)")

        // 1. 즉시 취소 중 상태로 변경
        modelManagementState.cancellingModels.insert(model)
        modelManagementState.currentDownloadingModels.remove(model)

        // 2. NSProgress 직접 취소 (다운로드 즉시 중단)
        if let progress = modelManagementState.downloadProgressObjects[model] {
            progress.cancel()
            print("NSProgress directly cancelled: \(model)")
        }

        // 3. Task 취소
        task.cancel()

        // 3. Progress 콜백이 완전히 멈출 때까지 모니터링 시작
        Task {
            await monitorProgressCompletion(model: model)
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
                break
            }
        }

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

            // 다운로드 관련 상태 정리
            self.modelManagementState.downloadProgress[model] = nil
            self.modelManagementState.downloadTasks[model] = nil

            // 모든 다운로드가 완료되었는지 확인
            if self.modelManagementState.currentDownloadingModels.isEmpty {
                self.modelManagementState.isDownloading = false
            }

            print("Progress completion confirmed - Cancelling UI released: \(model)")
        }

        // 부분 다운로드 파일 정리
        await cleanupPartialDownload(model)
    }

    // MARK: - 파일 선택 및 처리

    /// 파일 선택 (UI 관련)
    func selectFile() {
        uiState.isFilePickerPresented = true
    }

    /// 파일 선택 결과 처리 (파일 임포트 후 URL 저장 및 전사 호출)
    func handleFilePicker(result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let selectedFileURL = urls.first else { return }
            if selectedFileURL.startAccessingSecurityScopedResource() {
                // 비동기 처리를 위한 Task 생성
                Task {
                    await processSelectedFile(selectedFileURL)
                }
            }
        case let .failure(error):
            print("File selection error: \(error.localizedDescription)")
        }
    }

    /// 선택된 파일 처리 (비동기 작업)
    @MainActor
    private func processSelectedFile(_ selectedFileURL: URL) async {
        do {
            // 기존 오디오 플레이어 및 임시 파일 정리
            cleanupPreviousAudioFile()
            stopImportedAudio()
            audioPlayer = nil

            let audioFileData = try Data(contentsOf: selectedFileURL)
            let uniqueFileName = UUID().uuidString + "." + selectedFileURL.pathExtension
            let tempDirectoryURL = FileManager.default.temporaryDirectory
            let localFileURL = tempDirectoryURL.appendingPathComponent(uniqueFileName)
            try audioFileData.write(to: localFileURL)
            print("File saved to temporary directory: \(localFileURL)")

            // 임시 파일 URL 저장 (나중에 정리용)
            audioState.temporaryAudioURL = localFileURL
            audioState.audioFileName = selectedFileURL.deletingPathExtension().lastPathComponent

            // 파일을 임포트한 후 바로 총 재생 시간을 확인하고 업데이트
            do {
                let audioAsset = AVURLAsset(url: selectedFileURL)
                let duration = try await audioAsset.load(.duration)
                let durationInSeconds = CMTimeGetSeconds(duration)

                // 재생 시간 업데이트 (재생 시작 전에 미리 설정)
                audioState.totalDuration = durationInSeconds
                audioPlayer?.currentTime = 0.0
                print("Audio file duration: \(durationInSeconds) seconds")

                // 미리 AVAudioPlayer 생성하여 정보 준비
                let player = try AVAudioPlayer(contentsOf: selectedFileURL)
                audioPlayer = player
                audioPlayer?.prepareToPlay() // 버퍼링 미리 수행

                // 오디오 파일 분석 - 평균 음량 및 피크값 확인 및 노멀라이제이션 계수 계산
                calculateNormalizationFactor(player)

                // 정확한 재생 시간 재확인
                if audioState.totalDuration == 0 {
                    audioState.totalDuration = player.duration
                }
            } catch {
                print("Audio file info reading error: \(error.localizedDescription)")
            }

            // 파일 URL 저장
            audioState.importedAudioURL = selectedFileURL

            // 파일 임포트 후 백그라운드에서 파형 생성
            await processWaveform()
        } catch {
            print("File selection error: \(error.localizedDescription)")
        }
    }

    // 오디오 레벨 분석 및 노멀라이제이션 계수 계산 함수
    private func calculateNormalizationFactor(_ player: AVAudioPlayer) {
        // 오디오 미터링 활성화
        player.isMeteringEnabled = true

        // 전체 파일을 여러 구간으로 나누어 샘플링
        let sampleCount = 50
        var totalLevel: Float = 0
        var peakLevel: Float = -160 // 초기값 (dB 단위)

        // 오디오 길이 기반 간격 계산
        let duration = player.duration
        let interval = duration / Double(sampleCount)

        // 전체 오디오 구간 분석 (무음 재생)
        player.volume = 0 // 소리 없이 분석
        player.play()

        for i in 0 ..< sampleCount {
            // 특정 지점으로 이동
            player.currentTime = Double(i) * interval

            // 약간 대기하여 미터가 업데이트되도록 함
            Thread.sleep(forTimeInterval: 0.01)

            // 미터 업데이트
            player.updateMeters()

            // 평균 및 피크 레벨 (dB 단위) 측정
            let avgPower = player.averagePower(forChannel: 0)
            let peakPower = player.peakPower(forChannel: 0)

            totalLevel += avgPower
            peakLevel = max(peakLevel, peakPower)
        }

        // 분석 후 정지
        player.stop()
        player.currentTime = 0

        // 평균 레벨 계산 (dB 단위)
        let avgLevel = totalLevel / Float(sampleCount)

        // dB 값을 LUFS로 변환 (대략적인 추정)
        let estimatedLUFS = avgLevel + 10 // 간단한 변환식

        // 타겟 LUFS (-14 LUFS)
        let targetLUFS: Float = -14.0

        // 정규화 계산 (LUFS 기준)
        let gainNeeded = targetLUFS - estimatedLUFS

        // 감쇠만 적용 (유튜브 스타일)
        // 오디오가 타겟보다 클 경우만 줄이고, 작을 경우는 그대로 둠
        if gainNeeded < 0 {
            // dB를 선형 스케일로 변환 (감쇠 적용)
            normalizedVolumeFactor = pow(10.0, gainNeeded / 20.0)
        } else {
            // 타겟보다 작으므로 그대로 유지
            normalizedVolumeFactor = 1.0
        }

        // 디버그 로그
        print(
            "Audio analysis - Average level: \(avgLevel) dB, Estimated LUFS: \(estimatedLUFS), Peak: \(peakLevel) dB"
        )
        print("Normalization factor: \(normalizedVolumeFactor)")

        // 초기 볼륨 적용
        applyVolume()
    }

    /// 볼륨 적용 함수 (간소화된 버전)
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

    /// 파일 전사 시작 (선택된 파일 URL로 전사 실행)
    func transcribeFile(path: String) {
        resetState()
        stopImportedAudio()
        whisperKit?.audioProcessor = AudioProcessor()
        uiState.transcribeTask = Task {
            audioState.isTranscribing = true
            do {
                try await transcribeCurrentFile(path: path)
            } catch {
                print("Transcription error: \(error.localizedDescription)")
            }
            audioState.isTranscribing = false
        }
    }

    /// 오디오 파일 전사 진행
    func transcribeCurrentFile(path: String) async throws {
        Logging.debug("Loading audio file: \(path)")
        let loadingStart = Date()
        let audioFileSamples = try await Task {
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
        }
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
            language: isAutoLanguageEnable ? nil : languageCode, // 자동 언어 감지 옵션
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

        let decodingCallback: ((TranscriptionProgress) -> Bool?) = { progress in
            DispatchQueue.main.async {
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
                let compressionRatio = compressionRatio(of: checkTokens)
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
        let mergedResults = mergeTranscriptionResults(transcriptionResults)
        return mergedResults
    }

    // MARK: - Audio Preview & Deletion

    /// 오디오 미리듣기 (AVAudioPlayer를 활용)
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

                // 새 플레이어를 만든 경우 노멀라이제이션 계수 계산
                calculateNormalizationFactor(audioPlayer!)
            }

            // 재생 속도 설정
            audioPlayer?.enableRate = true
            audioPlayer?.rate = playbackRates[currentPlaybackRateIndex]

            // 볼륨 적용 (노멀라이제이션된 값 기준)
            applyVolume()

            audioPlayer?.play()
            audioState.isPlaying = true

            // Combine 타이머로 교체하여 업데이트 성능 향상
            setupPlaybackTimeUpdater()
        } catch {
            print("Error playing audio: \(error.localizedDescription)")
        }
    }

    // 재생 시간 업데이트를 위한 Combine 타이머 설정
    private func setupPlaybackTimeUpdater() {
        // 이전 타이머 취소
        audioState.playbackTimer?.invalidate()
        playbackTimerCancellable?.cancel()

        // Combine 타이머 설정 - 30fps로 부드러운 업데이트
        playbackTimerCancellable = Timer.publish(every: 0.033, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, let player = self.audioPlayer else {
                    // 플레이어가 없으면 타이머 정리
                    self?.playbackTimerCancellable?.cancel()
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
                    // 재생이 멈췄으므로 타이머 정리
                    self.playbackTimerCancellable?.cancel()
                }
            }
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

        // 타이머 정리
        audioState.playbackTimer?.invalidate()
        playbackTimerCancellable?.cancel()
    }

    func stopImportedAudio() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        audioPlaybackState.currentPlayerTime = 0
        audioState.isPlaying = false

        // 타이머 정리
        audioState.playbackTimer?.invalidate()
        playbackTimerCancellable?.cancel()
    }

    /// 재생 위치 이동 (특정 시간으로 이동)
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

        // 임시 파일 정리
        cleanupPreviousAudioFile()

        // 파일 삭제 대신 앱에서만 초기화
        audioState.importedAudioURL = nil
        audioState.audioFileName = ""
        audioState.waveformSamples = []
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

    /// 앱 시작 시 통합 정리 (이전 세션의 모든 임시 파일)
    func performStartupCleanup() async {
        print("🧹 Starting comprehensive cleanup on app launch...")

        // 1. 현재 세션의 오디오 임시 파일 정리
        cleanupPreviousAudioFile()

        // 2. 백그라운드에서 전체 임시 파일 정리
        await Task.detached(priority: .background) {
            await MainActor.run {
                self.clearCoreMLRuntimeCache()
            }
        }.value

        print("✅ Startup cleanup completed")
    }

    /// 오디오 파일에서 파형 데이터를 생성 (RMS 기반 계산 예시)
    func processWaveform() async {
        guard let url = audioState.importedAudioURL else { return }
        do {
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

            // 오디오 샘플 로드 및 파형 계산
            let samples = try await Task {
                try autoreleasepool {
                    try AudioProcessor.loadAudioAsFloatArray(fromPath: url.path)
                }
            }.value

            // 파형 계산 및 상태 업데이트
            let waveformSamples = computeWaveform(from: samples)
            await MainActor.run {
                // 모든 정보 업데이트 (동시에 한 번에 갱신)
                audioState.waveformSamples = waveformSamples

                // 디버그 로그
                print(
                    "Waveform update completed: \(waveformSamples.count) samples, total duration: \(audioState.totalDuration) seconds"
                )
            }
        } catch {
            print("Error processing waveform: \(error.localizedDescription)")
        }
    }

    private func computeWaveform(from samples: [Float]) -> [Float] {
        let chunkSize = 1024
        var rmsValues = [Float]()
        var index = 0
        while index < samples.count {
            let chunk = samples[index ..< min(index + chunkSize, samples.count)]
            let sumSquares = chunk.reduce(0) { $0 + $1 * $1 }
            let rms = sqrt(sumSquares / Float(chunk.count))
            rmsValues.append(rms)
            index += chunkSize
        }
        return rmsValues
    }

    // MARK: - Export Service 호출

    func exportTranscription() async {
        guard var result = transcriptionResult else {
            print("No transcription result available.")
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
        for segment in result.segments {
            var cleanSegment = segment
            cleanSegment.text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
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
        // 세그먼트 간 겹침 조정
        for i in 0 ..< cleanSegments.count - 1 {
            if cleanSegments[i].end > cleanSegments[i + 1].start {
                cleanSegments[i].end = cleanSegments[i + 1].start
            }
        }
        result.segments = cleanSegments

        // ExportService의 writer 분기 처리를 사용하여 파일 내보내기
        await ExportService.exportTranscriptionResult(result: result,
                                                      defaultFileName: audioState.audioFileName,
                                                      frameRate: frameRate)
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
                    // 메인 스레드에서 파일 처리
                    DispatchQueue.main.async {
                        // 파일 접근 권한 확보
                        let shouldStopAccessing = url.startAccessingSecurityScopedResource()

                        // 기존 오디오 플레이어 및 임시 파일 정리
                        self.cleanupPreviousAudioFile()
                        self.stopImportedAudio()
                        self.audioPlayer = nil

                        // 파일 이름 저장
                        self.audioState.audioFileName = url.deletingPathExtension()
                            .lastPathComponent

                        // 파일 URL 저장
                        self.audioState.importedAudioURL = url

                        // 비동기 처리를 위한 Task 생성 - 파일 정보 읽기 및 파형 생성
                        Task { @MainActor in
                            do {
                                // 오디오 파일 재생 시간 설정
                                let audioAsset = AVURLAsset(url: url)
                                let duration = try await audioAsset.load(.duration)
                                let durationInSeconds = CMTimeGetSeconds(duration)

                                // 재생 시간 업데이트
                                self.audioState.totalDuration = durationInSeconds
                                self.audioPlayer?.currentTime = 0.0

                                // 오디오 플레이어 초기화
                                let player = try AVAudioPlayer(contentsOf: url)
                                self.audioPlayer = player

                                // 노멀라이제이션 계수 계산 (파일 로드 시 1회)
                                self.calculateNormalizationFactor(player)

                                self.audioPlayer?.prepareToPlay()

                                // 파형 생성 처리
                                await self.processWaveform()
                            } catch {
                                print("Audio file load error: \(error.localizedDescription)")
                            }
                        }

                        // 파일 접근 권한 해제
                        if shouldStopAccessing {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                } else {
                    print(
                        "File drop processing failed: \(error?.localizedDescription ?? "Unknown error")"
                    )
                }
            }
    }

    /// 로컬 및 원격 모델 목록 업데이트
    func fetchModels() {
        print("Starting to fetch model list...")

        // 상태 초기화
        modelManagementState.availableModels = []
        modelManagementState.modelSizes = [:] // 모델 크기 정보 초기화

        // 에러 상태 초기화
        modelManagementState.hasModelLoadError = false
        modelManagementState.modelLoadError = nil

        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first {
            let modelPath = documents.appendingPathComponent(modelManagementState.modelStorage).path
            print("Model path verification: \(modelPath)")

            // 디렉토리가 없으면 생성
            if !FileManager.default.fileExists(atPath: modelPath) {
                do {
                    try FileManager.default.createDirectory(
                        at: URL(fileURLWithPath: modelPath),
                        withIntermediateDirectories: true
                    )
                    print("Model directory created: \(modelPath)")
                } catch {
                    print("Failed to create model directory: \(error.localizedDescription)")
                }
            }

            modelManagementState.localModelPath = modelPath

            do {
                let allFiles = try FileManager.default.contentsOfDirectory(atPath: modelPath)
                // .DS_Store 및 기타 시스템 파일 필터링 + 디렉토리만 포함
                let fileManager = FileManager.default
                let downloadedModels = allFiles.filter { fileName in
                    // 숨겨진 파일 제외
                    if fileName.hasPrefix(".") {
                        return false
                    }

                    // 디렉토리인지 확인
                    let fullPath = URL(fileURLWithPath: modelPath).appendingPathComponent(fileName)
                        .path
                    var isDir: ObjCBool = false
                    if fileManager.fileExists(atPath: fullPath, isDirectory: &isDir) {
                        return isDir.boolValue
                    }
                    return false
                }
                print("Local model list: \(downloadedModels)")

                // 로컬 모델 및 크기 정보 갱신
                for model in downloadedModels {
                    let modelFolderURL = URL(fileURLWithPath: modelPath)
                        .appendingPathComponent(model)

                    // 모델 크기 계산
                    let totalSize = calculateFolderSize(url: modelFolderURL)
                    modelManagementState.modelSizes[model] = totalSize

                    if !modelManagementState.localModels.contains(model) {
                        modelManagementState.localModels = downloadedModels
                    }
                }
            } catch {
                print("Failed to fetch local model list: \(error.localizedDescription)")
            }
        }

        modelManagementState.localModels = WhisperKit
            .formatModelFiles(modelManagementState.localModels)
        for model in modelManagementState.localModels
            where !modelManagementState.availableModels.contains(model) {
            modelManagementState.availableModels.append(model)
        }

        print("Models found locally: \(modelManagementState.localModels)")
        print("Previously selected model: \(selectedModel)")

        Task {
            // 원격 모델 목록 가져오기 시도
            var supportedModels: [String] = []
            var disabledModels: [String] = []

            let modelSupport = await WhisperKit.recommendedRemoteModels()
            supportedModels = modelSupport.supported
            disabledModels = modelSupport.disabled
            print("Fetched model list from WhisperKit: \(supportedModels.count) models")

            // 메인 스레드에서 UI 업데이트
            await MainActor.run {
                for model in supportedModels {
                    if !modelManagementState.availableModels.contains(model) {
                        modelManagementState.availableModels.append(model)

                        // 원격 모델 예상 크기 - 실제 크기를 알 수 없으므로 예상치 설정
                        if !modelManagementState.modelSizes.keys.contains(model) {
                            // 모델 이름에 따라 예상 크기 설정 (MB 단위)
                            let estimatedSize: Int64
                            if model.contains("large") {
                                estimatedSize = 3_000_000_000 // 약 3GB
                            } else if model.contains("medium") {
                                estimatedSize = 1_500_000_000 // 약 1.5GB
                            } else if model.contains("small") {
                                estimatedSize = 500_000_000 // 약 500MB
                            } else if model.contains("base") {
                                estimatedSize = 250_000_000 // 약 250MB
                            } else {
                                estimatedSize = 150_000_000 // 약 150MB (기본값)
                            }
                            modelManagementState.modelSizes[model] = estimatedSize
                        }
                    }
                }

                for model in disabledModels {
                    if !modelManagementState.disabledModels.contains(model) {
                        modelManagementState.disabledModels.append(model)
                    }
                }

                print(
                    "Updated available model count: \(modelManagementState.availableModels.count)"
                )
                objectWillChange.send() // UI 갱신 강제
            }
        }
    }

    /// 폴더 크기 계산 함수
    private func calculateFolderSize(url: URL) -> Int64 {
        let fileManager = FileManager.default
        var folderSize: Int64 = 0

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil
            )

            for fileURL in contents {
                let fileAttributes = try fileURL.resourceValues(forKeys: [
                    .isDirectoryKey,
                    .fileSizeKey,
                ])

                if let isDirectory = fileAttributes.isDirectory, isDirectory {
                    // 하위 폴더면 재귀적으로 계산
                    folderSize += calculateFolderSize(url: fileURL)
                } else if let fileSize = fileAttributes.fileSize {
                    // 파일이면 크기 추가
                    folderSize += Int64(fileSize)
                }
            }
        } catch {
            print("Error calculating folder size: \(error)")
        }

        return folderSize
    }
}
