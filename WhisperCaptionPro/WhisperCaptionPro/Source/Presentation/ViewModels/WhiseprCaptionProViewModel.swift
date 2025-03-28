//
//  WhiseprCaptionProViewModel.swift
//  WhisperCaptionPro
//
//  Created by 조형구 on 3/3/25.
//

import AVFoundation
import Combine
import CoreML
import SwiftUI
import WhisperKit

// MARK: - ContentViewModel

@MainActor
class ContentViewModel: ObservableObject {
    // 각 기능별 상태 모델을 @Published 프로퍼티로 관리
    @Published var transcriptionState = TranscriptionState()
    @Published var modelManagementState = ModelManagementState()
    @Published var audioState = AudioState()
    @Published var uiState = UIState()
    @Published var settings = SettingsState()

    // WhisperKit 인스턴스
    @Published var whisperKit: WhisperKit?

    // MARK: - 메뉴 (Menu Items)

    struct MenuItem: Identifiable, Hashable {
        var id = UUID()
        var name: String
        var image: String
    }

    let menu: [MenuItem] = [
        MenuItem(name: "Transcribe", image: "book.pages"),
        MenuItem(name: "Stream", image: "waveform.badge.mic"),
    ]

    // MARK: - AppStorage 동기화

    @AppStorage("selectedAudioInput") var storedSelectedAudioInput: String = "No Audio Input" {
        didSet { settings.selectedAudioInput = storedSelectedAudioInput }
    }

    @AppStorage("selectedModel") var storedSelectedModel: String = WhisperKit.recommendedModels()
        .default {
        didSet { settings.selectedModel = storedSelectedModel }
    }

    @AppStorage("selectedTab") var storedSelectedTab: String = "Transcribe" {
        didSet { settings.selectedTab = storedSelectedTab }
    }

    @AppStorage("selectedTask") var storedSelectedTask: String = "transcribe" {
        didSet { settings.selectedTask = storedSelectedTask }
    }

    @AppStorage("selectedLanguage") var storedSelectedLanguage: String = "english" {
        didSet { settings.selectedLanguage = storedSelectedLanguage }
    }

    @AppStorage("repoName") var storedRepoName: String = "argmaxinc/whisperkit-coreml" {
        didSet { settings.repoName = storedRepoName }
    }

    @AppStorage("enableTimestamps") var storedEnableTimestamps: Bool = true {
        didSet { settings.enableTimestamps = storedEnableTimestamps }
    }

    @AppStorage("enablePromptPrefill") var storedEnablePromptPrefill: Bool = true {
        didSet { settings.enablePromptPrefill = storedEnablePromptPrefill }
    }

    @AppStorage("enableCachePrefill") var storedEnableCachePrefill: Bool = true {
        didSet { settings.enableCachePrefill = storedEnableCachePrefill }
    }

    @AppStorage("enableSpecialCharacters") var storedEnableSpecialCharacters: Bool = false {
        didSet { settings.enableSpecialCharacters = storedEnableSpecialCharacters }
    }

    @AppStorage("enableEagerDecoding") var storedEnableEagerDecoding: Bool = false {
        didSet { settings.enableEagerDecoding = storedEnableEagerDecoding }
    }

    @AppStorage("enableDecoderPreview") var storedEnableDecoderPreview: Bool = true {
        didSet { settings.enableDecoderPreview = storedEnableDecoderPreview }
    }

    @AppStorage("temperatureStart") var storedTemperatureStart: Double = 0 {
        didSet { settings.temperatureStart = storedTemperatureStart }
    }

    @AppStorage("fallbackCount") var storedFallbackCount: Double = 5 {
        didSet { settings.fallbackCount = storedFallbackCount }
    }

    @AppStorage("compressionCheckWindow") var storedCompressionCheckWindow: Double = 60 {
        didSet { settings.compressionCheckWindow = storedCompressionCheckWindow }
    }

    @AppStorage("sampleLength") var storedSampleLength: Double = 224 {
        didSet { settings.sampleLength = storedSampleLength }
    }

    @AppStorage("silenceThreshold") var storedSilenceThreshold: Double = 0.3 {
        didSet { settings.silenceThreshold = storedSilenceThreshold }
    }

    @AppStorage("realtimeDelayInterval") var storedRealtimeDelayInterval: Double = 1 {
        didSet { settings.realtimeDelayInterval = storedRealtimeDelayInterval }
    }

    @AppStorage("useVAD") var storedUseVAD: Bool = true {
        didSet { settings.useVAD = storedUseVAD }
    }

    @AppStorage("tokenConfirmationsNeeded") var storedTokenConfirmationsNeeded: Double = 2 {
        didSet { settings.tokenConfirmationsNeeded = storedTokenConfirmationsNeeded }
    }

    @AppStorage("concurrentWorkerCount") var storedConcurrentWorkerCount: Double = 4 {
        didSet { settings.concurrentWorkerCount = storedConcurrentWorkerCount }
    }

    @AppStorage("chunkingStrategy") var storedChunkingStrategy: ChunkingStrategy = .vad {
        didSet { settings.chunkingStrategy = storedChunkingStrategy }
    }

    @AppStorage("encoderComputeUnits") var storedEncoderComputeUnits: MLComputeUnits =
        .cpuAndNeuralEngine {
        didSet { settings.encoderComputeUnits = storedEncoderComputeUnits }
    }

    @AppStorage("decoderComputeUnits") var storedDecoderComputeUnits: MLComputeUnits =
        .cpuAndNeuralEngine {
        didSet { settings.decoderComputeUnits = storedDecoderComputeUnits }
    }

    @AppStorage("autoLanguage") var storedAutoLanguageOption: Bool =
        false {
        didSet { settings.isAutoLanguageEnable = storedAutoLanguageOption }
    }

    // MARK: - Methods

    /// 상태 초기화: 모든 상태 모델의 값을 초기값으로 재설정
    func resetState() {
        uiState.transcribeTask?.cancel()
        audioState.isRecording = false
        audioState.isTranscribing = false
        whisperKit?.audioProcessor.stopRecording()

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
        transcriptionState.lastBufferSize = 0
        transcriptionState.lastConfirmedSegmentEndSeconds = 0
        transcriptionState.bufferEnergy = []
        transcriptionState.bufferSeconds = 0
        transcriptionState.confirmedSegments = []
        transcriptionState.unconfirmedSegments = []

        transcriptionState.eagerResults = []
        transcriptionState.prevResult = nil
        transcriptionState.lastAgreedSeconds = 0.0
        transcriptionState.prevWords = []
        transcriptionState.lastAgreedWords = []
        transcriptionState.confirmedWords = []
        transcriptionState.confirmedText = ""
        transcriptionState.hypothesisWords = []
        transcriptionState.hypothesisText = ""
    }

    /// Compute 옵션 생성 (설정 상태의 compute unit 값을 사용)
    func getComputeOptions() -> ModelComputeOptions {
        return ModelComputeOptions(
            audioEncoderCompute: settings.encoderComputeUnits,
            textDecoderCompute: settings.decoderComputeUnits
        )
    }

    /// 로컬 및 원격 모델 목록 업데이트
    func fetchModels() {
        modelManagementState.availableModels = [settings.selectedModel]
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first {
            let modelPath = documents.appendingPathComponent(modelManagementState.modelStorage).path
            if FileManager.default.fileExists(atPath: modelPath) {
                modelManagementState.localModelPath = modelPath
                do {
                    let downloadedModels = try FileManager.default
                        .contentsOfDirectory(atPath: modelPath)
                    for model in downloadedModels
                        where !modelManagementState.localModels.contains(model) {
                        modelManagementState.localModels.append(model)
                    }
                } catch {
                    print("Error enumerating files at \(modelPath): \(error.localizedDescription)")
                }
            }
        }
        modelManagementState.localModels = WhisperKit
            .formatModelFiles(modelManagementState.localModels)
        for model in modelManagementState.localModels
            where !modelManagementState.availableModels.contains(model) {
            modelManagementState.availableModels.append(model)
        }

        print("Found locally: \(modelManagementState.localModels)")
        print("Previously selected model: \(settings.selectedModel)")

        Task {
            let remoteModelSupport = await WhisperKit.recommendedRemoteModels()
            await MainActor.run {
                for model in remoteModelSupport.supported {
                    if !modelManagementState.availableModels.contains(model) {
                        modelManagementState.availableModels.append(model)
                    }
                }
                for model in remoteModelSupport.disabled {
                    if !modelManagementState.disabledModels.contains(model) {
                        modelManagementState.disabledModels.append(model)
                    }
                }
            }
        }
    }

    /// 모델 로딩 (로컬/원격 모델 다운로드 및 초기화)
    func loadModel(_ model: String, redownload: Bool = false) {
        print("Selected Model: \(UserDefaults.standard.string(forKey: "selectedModel") ?? "nil")")
        print("""
            Computing Options:
            - Mel Spectrogram:  \(getComputeOptions().melCompute.description)
            - Audio Encoder:    \(getComputeOptions().audioEncoderCompute.description)
            - Text Decoder:     \(getComputeOptions().textDecoderCompute.description)
            - Prefill Data:     \(getComputeOptions().prefillCompute.description)
        """)

        whisperKit = nil
        Task {
            let config = WhisperKitConfig(computeOptions: getComputeOptions(),
                                          verbose: true,
                                          logLevel: .debug,
                                          prewarm: false,
                                          load: false,
                                          download: false)
            whisperKit = try await WhisperKit(config)
            guard let whisperKit = whisperKit else { return }

            var folder: URL?
            if modelManagementState.localModels.contains(model) && !redownload {
                folder = URL(fileURLWithPath: modelManagementState.localModelPath)
                    .appendingPathComponent(model)
            } else {
                folder = try await WhisperKit.download(
                    variant: model,
                    from: settings.repoName,
                    progressCallback: { progress in
                        DispatchQueue.main.async {
                            self.modelManagementState
                                .loadingProgressValue = Float(progress.fractionCompleted) * self
                                .modelManagementState.specializationProgressRatio
                            self.modelManagementState.modelState = .downloading
                        }
                    }
                )
            }

            await MainActor.run {
                modelManagementState.loadingProgressValue = modelManagementState
                    .specializationProgressRatio
                modelManagementState.modelState = .downloaded
            }

            if let modelFolder = folder {
                whisperKit.modelFolder = modelFolder
                await MainActor.run {
                    modelManagementState.loadingProgressValue = modelManagementState
                        .specializationProgressRatio
                    modelManagementState.modelState = .prewarming
                }

                let progressBarTask = Task {
                    await updateProgressBar(targetProgress: 0.9, maxTime: 240)
                }

                do {
                    try await whisperKit.prewarmModels()
                    progressBarTask.cancel()
                } catch {
                    print("Error prewarming models, retrying: \(error.localizedDescription)")
                    progressBarTask.cancel()
                    if !redownload {
                        loadModel(model, redownload: true)
                        return
                    } else {
                        modelManagementState.modelState = .unloaded
                        return
                    }
                }

                await MainActor.run {
                    modelManagementState.loadingProgressValue = modelManagementState
                        .specializationProgressRatio + 0.9 *
                        (1 - modelManagementState.specializationProgressRatio)
                    modelManagementState.modelState = .loading
                }

                try await whisperKit.loadModels()

                await MainActor.run {
                    if !modelManagementState.localModels.contains(model) {
                        modelManagementState.localModels.append(model)
                    }
                    modelManagementState.availableLanguages = Constants.languages.map { $0.key }
                        .sorted()
                    modelManagementState.loadingProgressValue = 1.0
                    modelManagementState.modelState = whisperKit.modelState
                }
            }
        }
    }

    /// 모델 삭제
    func deleteModel() {
        if modelManagementState.localModels.contains(settings.selectedModel) {
            let modelFolder = URL(fileURLWithPath: modelManagementState.localModelPath)
                .appendingPathComponent(settings.selectedModel)
            do {
                try FileManager.default.removeItem(at: modelFolder)
                if let index = modelManagementState.localModels
                    .firstIndex(of: settings.selectedModel) {
                    modelManagementState.localModels.remove(at: index)
                }
                modelManagementState.modelState = .unloaded
            } catch {
                print("Error deleting model: \(error)")
            }
        }
    }

    /// 진행률 업데이트
    func updateProgressBar(targetProgress: Float, maxTime: TimeInterval) async {
        let initialProgress = modelManagementState.loadingProgressValue
        let decayConstant = -log(1 - targetProgress) / Float(maxTime)
        let startTime = Date()

        while true {
            let elapsedTime = Date().timeIntervalSince(startTime)
            let decayFactor = exp(-decayConstant * Float(elapsedTime))
            let progressIncrement = (1 - initialProgress) * (1 - decayFactor)
            let currentProgress = initialProgress + progressIncrement

            await MainActor.run {
                modelManagementState.loadingProgressValue = currentProgress
            }

            if currentProgress >= targetProgress { break }

            do {
                try await Task.sleep(nanoseconds: 100_000_000)
            } catch {
                break
            }
        }
    }

    /// 파일 선택 (UI 관련)
    func selectFile() {
        uiState.isFilePickerPresented = true
    }

    /// 파일 선택 결과 처리
    func handleFilePicker(result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let selectedFileURL = urls.first else { return }
            if selectedFileURL.startAccessingSecurityScopedResource() {
                do {
                    let audioFileData = try Data(contentsOf: selectedFileURL)
                    let uniqueFileName = UUID().uuidString + "." + selectedFileURL.pathExtension
                    let tempDirectoryURL = FileManager.default.temporaryDirectory
                    let localFileURL = tempDirectoryURL.appendingPathComponent(uniqueFileName)
                    try audioFileData.write(to: localFileURL)
                    print("File saved to temporary directory: \(localFileURL)")
                    transcribeFile(path: selectedFileURL.path)
                } catch {
                    print("File selection error: \(error.localizedDescription)")
                }
            }
        case let .failure(error):
            print("File selection error: \(error.localizedDescription)")
        }
    }

    /// 파일 전사 시작
    func transcribeFile(path: String) {
        resetState()
        whisperKit?.audioProcessor = AudioProcessor()
        uiState.transcribeTask = Task {
            audioState.isTranscribing = true
            do {
                try await transcribeCurrentFile(path: path)
            } catch {
                print("File selection error: \(error.localizedDescription)")
            }
            audioState.isTranscribing = false
        }
    }

    /// 녹음/전사 토글
    func toggleRecording(shouldLoop: Bool) {
        audioState.isRecording.toggle()
        if audioState.isRecording {
            resetState()
            startRecording(shouldLoop)
        } else {
            stopRecording(shouldLoop)
        }
    }

    /// 녹음 시작
    func startRecording(_ loop: Bool) {
        if let audioProcessor = whisperKit?.audioProcessor {
            Task(priority: .userInitiated) {
                guard await AudioProcessor.requestRecordPermission() else {
                    print("Microphone access was not granted.")
                    return
                }
                var deviceId: DeviceID?
                #if os(macOS)
                    if settings.selectedAudioInput != "No Audio Input",
                       let devices = audioState.audioDevices,
                       let device = devices
                       .first(where: { $0.name == settings.selectedAudioInput }) {
                        deviceId = device.id
                    }
                    if deviceId == nil {
                        throw WhisperError.microphoneUnavailable()
                    }
                #endif
                try? audioProcessor.startRecordingLive(inputDeviceID: deviceId) { _ in
                    DispatchQueue.main.async {
                        // 전사 상태 업데이트
                        self.transcriptionState.bufferEnergy = self.whisperKit?.audioProcessor
                            .relativeEnergy ?? []
                        self.transcriptionState
                            .bufferSeconds = Double(self.whisperKit?.audioProcessor.audioSamples
                                .count ?? 0) / Double(WhisperKit.sampleRate)
                    }
                }
                audioState.isRecording = true
                audioState.isTranscribing = true
                if loop { realtimeLoop() }
            }
        }
    }

    /// 녹음 중지
    func stopRecording(_ loop: Bool) {
        audioState.isRecording = false
        stopRealtimeTranscription()
        if let audioProcessor = whisperKit?.audioProcessor {
            audioProcessor.stopRecording()
        }
        if !loop {
            uiState.transcribeTask = Task {
                audioState.isTranscribing = true
                do {
                    try await transcribeCurrentBuffer()
                } catch {
                    print("Error: \(error.localizedDescription)")
                }
                finalizeText()
                audioState.isTranscribing = false
            }
        }
        finalizeText()
    }

    /// 전사 텍스트 최종 확정
    func finalizeText() {
        Task {
            await MainActor.run {
                if transcriptionState.hypothesisText != "" {
                    transcriptionState.confirmedText += transcriptionState.hypothesisText
                    transcriptionState.hypothesisText = ""
                }
                if !transcriptionState.unconfirmedSegments.isEmpty {
                    transcriptionState.confirmedSegments
                        .append(contentsOf: transcriptionState.unconfirmedSegments)
                    transcriptionState.unconfirmedSegments = []
                }
            }
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
            settings.selectedLanguage,
            default: Constants.defaultLanguageCode
        ]
        let task: DecodingTask = settings.selectedTask == "transcribe" ? .transcribe : .translate
        let seekClip: [Float] = [transcriptionState.lastConfirmedSegmentEndSeconds]
        // 언어 자동 감지 기능을 위한 분기처리
        var options: DecodingOptions

        if (settings.isAutoLanguageEnable == true) && (whisperKit.modelVariant.isMultilingual == true) {
            options = DecodingOptions(
                verbose: true,
                task: task,
                language: nil, // 자동 언어 감지 모드
                temperature: Float(settings.temperatureStart),
                temperatureFallbackCount: Int(settings.fallbackCount),
                sampleLength: Int(settings.sampleLength),
                usePrefillPrompt: settings.enablePromptPrefill,
                usePrefillCache: settings.enableCachePrefill,
                detectLanguage: true,
                skipSpecialTokens: !settings.enableSpecialCharacters,
                withoutTimestamps: !settings.enableTimestamps,
                wordTimestamps: true,
                clipTimestamps: seekClip,
                concurrentWorkerCount: Int(settings.concurrentWorkerCount),
                chunkingStrategy: settings.chunkingStrategy
            )
        } else {
            options = DecodingOptions(
                verbose: true,
                task: task,
                language: languageCode,
                temperature: Float(settings.temperatureStart),
                temperatureFallbackCount: Int(settings.fallbackCount),
                sampleLength: Int(settings.sampleLength),
                usePrefillPrompt: settings.enablePromptPrefill,
                usePrefillCache: settings.enableCachePrefill,
                skipSpecialTokens: !settings.enableSpecialCharacters,
                withoutTimestamps: !settings.enableTimestamps,
                wordTimestamps: true,
                clipTimestamps: seekClip,
                concurrentWorkerCount: Int(settings.concurrentWorkerCount),
                chunkingStrategy: settings.chunkingStrategy
            )
        }

        let decodingCallback: ((TranscriptionProgress) -> Bool?) = { progress in
            DispatchQueue.main.async {
                let fallbacks = Int(progress.timings.totalDecodingFallbacks)
                let chunkId = self.settings.selectedTask == "transcribe" ? 0 : progress.windowId
                var updatedChunk = (chunkText: [progress.text], fallbacks: fallbacks)
                if var currentChunk = self.transcriptionState.currentChunks[chunkId],
                   let previousChunkText = currentChunk.chunkText.last {
                    if progress.text.count >= previousChunkText.count {
                        currentChunk.chunkText[currentChunk.chunkText.endIndex - 1] = progress.text
                        updatedChunk = currentChunk
                    } else {
                        if fallbacks == currentChunk.fallbacks && self.settings
                            .selectedTask == "transcribe" {
                            updatedChunk
                                .chunkText = [(updatedChunk.chunkText.first ?? "") + progress.text]
                        } else {
                            updatedChunk.chunkText[currentChunk.chunkText.endIndex - 1] = progress
                                .text
                            updatedChunk.fallbacks = fallbacks
                            print("Fallback occured: \(fallbacks)")
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
            let checkWindow = Int(self.settings.compressionCheckWindow)
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

    /// 실시간 전사 루프
    func realtimeLoop() {
        uiState.transcriptionTask = Task {
            while audioState.isRecording && audioState.isTranscribing {
                do {
                    try await transcribeCurrentBuffer(delayInterval: Float(settings
                            .realtimeDelayInterval))
                } catch {
                    print("Error: \(error.localizedDescription)")
                    break
                }
            }
        }
    }

    /// 실시간 전사 중지
    func stopRealtimeTranscription() {
        audioState.isTranscribing = false
        uiState.transcriptionTask?.cancel()
    }

    /// 현재 버퍼 전사
    func transcribeCurrentBuffer(delayInterval: Float = 1.0) async throws {
        guard let whisperKit = whisperKit else { return }
        let currentBuffer = whisperKit.audioProcessor.audioSamples
        let nextBufferSize = currentBuffer.count - transcriptionState.lastBufferSize
        let nextBufferSeconds = Float(nextBufferSize) / Float(WhisperKit.sampleRate)
        guard nextBufferSeconds > delayInterval else {
            await MainActor.run {
                if transcriptionState.currentText
                    .isEmpty { transcriptionState.currentText = "Waiting for speech..." }
            }
            try await Task.sleep(nanoseconds: 100_000_000)
            return
        }
        if settings.useVAD {
            let voiceDetected = AudioProcessor.isVoiceDetected(
                in: whisperKit.audioProcessor.relativeEnergy,
                nextBufferInSeconds: nextBufferSeconds,
                silenceThreshold: Float(settings.silenceThreshold)
            )
            guard voiceDetected else {
                await MainActor.run {
                    if transcriptionState.currentText
                        .isEmpty { transcriptionState.currentText = "Waiting for speech..." }
                }
                try await Task.sleep(nanoseconds: 100_000_000)
                return
            }
        }
        transcriptionState.lastBufferSize = currentBuffer.count

        if settings.selectedTask == "transcribe" && settings.enableEagerDecoding {
            let transcription = try await transcribeEagerMode(Array(currentBuffer))
            await MainActor.run {
                transcriptionState.currentText = ""
                transcriptionState.tokensPerSecond = transcription?.timings.tokensPerSecond ?? 0
                transcriptionState.firstTokenTime = transcription?.timings.firstTokenTime ?? 0
                transcriptionState.modelLoadingTime = transcription?.timings.modelLoading ?? 0
                transcriptionState.pipelineStart = transcription?.timings.pipelineStart ?? 0
                transcriptionState.currentLag = transcription?.timings.decodingLoop ?? 0
                transcriptionState
                    .currentEncodingLoops = Int(transcription?.timings.totalEncodingRuns ?? 0)
                let totalAudio = Double(currentBuffer.count) / Double(WhisperKit.sampleRate)
                transcriptionState.totalInferenceTime = transcription?.timings.fullPipeline ?? 0
                transcriptionState
                    .effectiveRealTimeFactor = Double(transcriptionState.totalInferenceTime) /
                    totalAudio
                transcriptionState
                    .effectiveSpeedFactor = totalAudio /
                    Double(transcriptionState.totalInferenceTime)
            }
        } else {
            let transcription = try await transcribeAudioSamples(Array(currentBuffer))
            await MainActor.run {
                transcriptionState.currentText = ""
                guard let segments = transcription?.segments else { return }
                transcriptionState.tokensPerSecond = transcription?.timings.tokensPerSecond ?? 0
                transcriptionState.firstTokenTime = transcription?.timings.firstTokenTime ?? 0
                transcriptionState.modelLoadingTime = transcription?.timings.modelLoading ?? 0
                transcriptionState.pipelineStart = transcription?.timings.pipelineStart ?? 0
                transcriptionState.currentLag = transcription?.timings.decodingLoop ?? 0
                transcriptionState
                    .currentEncodingLoops += Int(transcription?.timings.totalEncodingRuns ?? 0)
                let totalAudio = Double(currentBuffer.count) / Double(WhisperKit.sampleRate)
                transcriptionState.totalInferenceTime += transcription?.timings.fullPipeline ?? 0
                transcriptionState
                    .effectiveRealTimeFactor = Double(transcriptionState.totalInferenceTime) /
                    totalAudio
                transcriptionState
                    .effectiveSpeedFactor = totalAudio /
                    Double(transcriptionState.totalInferenceTime)

                if segments.count > transcriptionState.confirmedSegments.count {
                    let numberOfSegmentsToConfirm = segments.count - transcriptionState
                        .confirmedSegments.count
                    let confirmedSegmentsArray = Array(segments.prefix(numberOfSegmentsToConfirm))
                    let remainingSegments = Array(segments
                        .suffix(transcriptionState.confirmedSegments.count))
                    if let lastConfirmedSegment = confirmedSegmentsArray.last,
                       lastConfirmedSegment.end > transcriptionState
                       .lastConfirmedSegmentEndSeconds {
                        transcriptionState.lastConfirmedSegmentEndSeconds = lastConfirmedSegment.end
                        print(
                            "Last confirmed segment end: \(transcriptionState.lastConfirmedSegmentEndSeconds)"
                        )
                        for segment in confirmedSegmentsArray {
                            if !transcriptionState.confirmedSegments.contains(segment: segment) {
                                transcriptionState.confirmedSegments.append(segment)
                            }
                        }
                    }
                    transcriptionState.unconfirmedSegments = remainingSegments
                } else {
                    transcriptionState.unconfirmedSegments = segments
                }
            }
        }
    }

    /// Eager mode 전사
    func transcribeEagerMode(_ samples: [Float]) async throws -> TranscriptionResult? {
        guard let whisperKit = whisperKit else { return nil }
        guard whisperKit.textDecoder.supportsWordTimestamps else {
            transcriptionState
                .confirmedText =
                "Eager mode requires word timestamps, which are not supported by the current model: \(settings.selectedModel)."
            return nil
        }
        let languageCode = Constants.languages[
            settings.selectedLanguage,
            default: Constants.defaultLanguageCode
        ]
        let task: DecodingTask = settings.selectedTask == "transcribe" ? .transcribe : .translate
        print(settings.selectedLanguage)
        print(languageCode)
        let options = DecodingOptions(
            verbose: true,
            task: task,
            language: languageCode,
            temperature: Float(settings.temperatureStart),
            temperatureFallbackCount: Int(settings.fallbackCount),
            sampleLength: Int(settings.sampleLength),
            usePrefillPrompt: settings.enablePromptPrefill,
            usePrefillCache: settings.enableCachePrefill,
            skipSpecialTokens: !settings.enableSpecialCharacters,
            withoutTimestamps: !settings.enableTimestamps,
            wordTimestamps: true,
            firstTokenLogProbThreshold: -1.5,
            chunkingStrategy: ChunkingStrategy.none
        )

        let decodingCallback: ((TranscriptionProgress) -> Bool?) = { progress in
            DispatchQueue.main.async {
                let fallbacks = Int(progress.timings.totalDecodingFallbacks)
                if progress.text.count < self.transcriptionState.currentText.count {
                    if fallbacks == self.transcriptionState.currentFallbacks {
                        // no additional action
                    } else {
                        print("Fallback occured: \(fallbacks)")
                    }
                }
                self.transcriptionState.currentText = progress.text
                self.transcriptionState.currentFallbacks = fallbacks
                self.transcriptionState.currentDecodingLoops += 1
            }
            let currentTokens = progress.tokens
            let checkWindow = Int(self.settings.compressionCheckWindow)
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

        Logging
            .info(
                "[EagerMode] \(transcriptionState.lastAgreedSeconds)-\(Double(samples.count) / 16000.0) seconds"
            )
        let streamingAudio = samples
        var streamOptions = options
        streamOptions.clipTimestamps = [transcriptionState.lastAgreedSeconds]
        let lastAgreedTokens = transcriptionState.lastAgreedWords.flatMap { $0.tokens }
        streamOptions.prefixTokens = lastAgreedTokens
        do {
            let transcription: TranscriptionResult? = try await whisperKit.transcribe(
                audioArray: streamingAudio,
                decodeOptions: streamOptions,
                callback: decodingCallback
            ).first
            await MainActor.run {
                var skipAppend = false
                if let result = transcription {
                    self.transcriptionState.hypothesisWords = result.allWords
                        .filter { $0.start >= self.transcriptionState.lastAgreedSeconds }
                    if let prevResult = self.transcriptionState.prevResult {
                        self.transcriptionState.prevWords = prevResult.allWords
                            .filter { $0.start >= self.transcriptionState.lastAgreedSeconds }
                        let commonPrefix = findLongestCommonPrefix(
                            self.transcriptionState.prevWords,
                            self.transcriptionState.hypothesisWords
                        )
                        Logging
                            .info(
                                "[EagerMode] Prev \"\((self.transcriptionState.prevWords.map { $0.word }).joined())\""
                            )
                        Logging
                            .info(
                                "[EagerMode] Next \"\((self.transcriptionState.hypothesisWords.map { $0.word }).joined())\""
                            )
                        Logging
                            .info(
                                "[EagerMode] Found common prefix \"\((commonPrefix.map { $0.word }).joined())\""
                            )
                        if commonPrefix.count >= Int(self.settings.tokenConfirmationsNeeded) {
                            self.transcriptionState
                                .lastAgreedWords = Array(commonPrefix
                                    .suffix(Int(self.settings.tokenConfirmationsNeeded)))
                            self.transcriptionState.lastAgreedSeconds = self.transcriptionState
                                .lastAgreedWords.first!.start
                            Logging
                                .info(
                                    "[EagerMode] Found new last agreed word \"\(self.transcriptionState.lastAgreedWords.first!.word)\" at \(self.transcriptionState.lastAgreedSeconds) seconds"
                                )
                            self.transcriptionState.confirmedWords
                                .append(contentsOf: commonPrefix
                                    .prefix(commonPrefix
                                        .count - Int(self.settings.tokenConfirmationsNeeded)))
                            let currentWords = self.transcriptionState.confirmedWords
                                .map { $0.word }.joined()
                            Logging
                                .info(
                                    "[EagerMode] Current:  \(self.transcriptionState.lastAgreedSeconds) -> \(Double(samples.count) / 16000.0) \(currentWords)"
                                )
                        } else {
                            Logging
                                .info(
                                    "[EagerMode] Using same last agreed time \(self.transcriptionState.lastAgreedSeconds)"
                                )
                            skipAppend = true
                        }
                    }
                    self.transcriptionState.prevResult = result
                }
                if !skipAppend {
                    self.transcriptionState.eagerResults.append(transcription)
                }
            }

            await MainActor.run {
                let finalWords = self.transcriptionState.confirmedWords.map { $0.word }.joined()
                self.transcriptionState.confirmedText = finalWords
                let lastHypothesis = self.transcriptionState
                    .lastAgreedWords + findLongestDifferentSuffix(
                        self.transcriptionState.prevWords,
                        self.transcriptionState.hypothesisWords
                    )
                self.transcriptionState.hypothesisText = lastHypothesis.map { $0.word }.joined()
            }
        } catch {
            Logging.error("[EagerMode] Error: \(error)")
            finalizeText()
        }

        let mergedResult = mergeTranscriptionResults(
            transcriptionState.eagerResults,
            confirmedWords: transcriptionState.confirmedWords
        )
        return mergedResult
    }
}
