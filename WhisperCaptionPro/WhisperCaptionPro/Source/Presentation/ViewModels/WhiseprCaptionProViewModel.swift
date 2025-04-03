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
    // WhisperKit 인스턴스
    @Published var whisperKit: WhisperKit?
    
    // model
    @Published var transcriptionState = TranscriptionState()
    @Published var modelManagementState = ModelManagementState()
    @Published var audioState = AudioState()
    @Published var uiState = UIState()
    
    // 자막 파일 타입
    @Published var transcriptionResult: TranscriptionResult? // 전사 결과
    @Published var isExporting: Bool = false
    
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
    // TODO: - userDefault로 획일화, decoding option 수정
    // MARK: - AppStorage
    @AppStorage("selectedAudioInput") var selectedAudioInput: String = "No Audio Input"
    @AppStorage("selectedModel") var selectedModel: String = WhisperKit.recommendedModels().default
    @AppStorage("selectedTab") var selectedTab: String = "Transcribe"
    @AppStorage("selectedTask") var selectedTask: String = "transcribe"
    @AppStorage("selectedLanguage") var selectedLanguage: String = "english"
    @AppStorage("repoName") var repoName: String = "argmaxinc/whisperkit-coreml"
    @AppStorage("enableTimestamps") var enableTimestamps: Bool = true
    @AppStorage("enablePromptPrefill") var enablePromptPrefill: Bool = true
    @AppStorage("enableCachePrefill") var enableCachePrefill: Bool = true
    @AppStorage("enableSpecialCharacters") var enableSpecialCharacters: Bool = false
    @AppStorage("enableEagerDecoding") var enableEagerDecoding: Bool = false
    @AppStorage("enableDecoderPreview") var enableDecoderPreview: Bool = true
    @AppStorage("temperatureStart") var temperatureStart: Double = 0
    @AppStorage("fallbackCount") var fallbackCount: Double = 5
    @AppStorage("compressionCheckWindow") var compressionCheckWindow: Double = 60
    @AppStorage("sampleLength") var sampleLength: Double = 224
    @AppStorage("silenceThreshold") var silenceThreshold: Double = 0.3
    @AppStorage("realtimeDelayInterval") var realtimeDelayInterval: Double = 1
    @AppStorage("useVAD") var useVAD: Bool = true
    @AppStorage("tokenConfirmationsNeeded") var tokenConfirmationsNeeded: Double = 2
    @AppStorage("concurrentWorkerCount") var concurrentWorkerCount: Double = 4
    @AppStorage("chunkingStrategy") var chunkingStrategy: ChunkingStrategy = .vad
    @AppStorage("encoderComputeUnits") var encoderComputeUnits: MLComputeUnits = .cpuAndNeuralEngine
    @AppStorage("decoderComputeUnits") var decoderComputeUnits: MLComputeUnits = .cpuAndNeuralEngine
    @AppStorage("isAutoLanguageEnable") var isAutoLanguageEnable: Bool = false
    @AppStorage("enableWordTimestamp") var enableWordTimestamp: Bool = false
    @AppStorage("frameRate") var frameRate: Double = 30.0
    
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
            audioEncoderCompute: encoderComputeUnits,
            textDecoderCompute: decoderComputeUnits
        )
    }
    
    /// 로컬 및 원격 모델 목록 업데이트
    func fetchModels() {
        modelManagementState.availableModels = [selectedModel]
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
        print("Previously selected model: \(selectedModel)")
        
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
                    from: repoName,
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
        if modelManagementState.localModels.contains(selectedModel) {
            let modelFolder = URL(fileURLWithPath: modelManagementState.localModelPath)
                .appendingPathComponent(selectedModel)
            do {
                try FileManager.default.removeItem(at: modelFolder)
                if let index = modelManagementState.localModels
                    .firstIndex(of: selectedModel) {
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
                    audioState.audioFileName = selectedFileURL.deletingPathExtension().lastPathComponent
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
                if selectedAudioInput != "No Audio Input",
                   let devices = audioState.audioDevices,
                   let device = devices
                    .first(where: { $0.name == selectedAudioInput }) {
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
        // 언어 자동 감지 기능을 위한 분기처리
        var options: DecodingOptions
        
        options = DecodingOptions(
            verbose: true,
            task: task,
            language: isAutoLanguageEnable ? nil : languageCode, // 자동 언어 감지 모드
            temperature: Float(temperatureStart),
            temperatureFallbackCount: Int(fallbackCount),
            sampleLength: Int(sampleLength),
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
                        if fallbacks == currentChunk.fallbacks &&
                            self.selectedTask == "transcribe" {
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
    
    /// 실시간 전사 루프
    func realtimeLoop() {
        uiState.transcriptionTask = Task {
            while audioState.isRecording && audioState.isTranscribing {
                do {
                    try await transcribeCurrentBuffer(delayInterval: Float(
                        realtimeDelayInterval))
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
        if useVAD {
            let voiceDetected = AudioProcessor.isVoiceDetected(
                in: whisperKit.audioProcessor.relativeEnergy,
                nextBufferInSeconds: nextBufferSeconds,
                silenceThreshold: Float(silenceThreshold)
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
        
        if selectedTask == "transcribe" && enableEagerDecoding {
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
            "Eager mode requires word timestamps, which are not supported by the current model: \(selectedModel)."
            return nil
        }
        let languageCode = Constants.languages[
            selectedLanguage,
            default: Constants.defaultLanguageCode
        ]
        let task: DecodingTask = selectedTask == "transcribe" ? .transcribe : .translate
        print(selectedLanguage)
        print(languageCode)
        let options = DecodingOptions(
            verbose: true,
            task: task,
            language: languageCode,
            temperature: Float(temperatureStart),
            temperatureFallbackCount: Int(fallbackCount),
            sampleLength: Int(sampleLength),
            usePrefillPrompt: enablePromptPrefill,
            usePrefillCache: enableCachePrefill,
            skipSpecialTokens: !enableSpecialCharacters,
            withoutTimestamps: !enableTimestamps,
            wordTimestamps: enableTimestamps,
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
                        if commonPrefix.count >= Int(self.tokenConfirmationsNeeded) {
                            self.transcriptionState
                                .lastAgreedWords = Array(commonPrefix
                                    .suffix(Int(self.tokenConfirmationsNeeded)))
                            self.transcriptionState.lastAgreedSeconds = self.transcriptionState
                                .lastAgreedWords.first!.start
                            Logging
                                .info(
                                    "[EagerMode] Found new last agreed word \"\(self.transcriptionState.lastAgreedWords.first!.word)\" at \(self.transcriptionState.lastAgreedSeconds) seconds"
                                )
                            self.transcriptionState.confirmedWords
                                .append(contentsOf: commonPrefix
                                    .prefix(commonPrefix
                                        .count - Int(self.tokenConfirmationsNeeded)))
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
    
    /// 파일 export 하는 함수
    // MARK: - Export Service 호출 (ViewModel 내)
    func exportTranscription() async {
        guard var result = transcriptionResult else {
            print("No transcription result available.")
            return
        }
        
        // 세그먼트와 단어 처리 - 참조가 아닌 구조체를 직접 변경하여 복사본 생성
        var cleanSegments: [TranscriptionSegment] = []
        
        for segment in result.segments {
            var cleanSegment = segment
            // 세그먼트 텍스트 앞뒤 공백 제거
            cleanSegment.text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // 단어 단위 타임스탬프가 있는 경우 각 단어도 처리
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
            
            // 빈 텍스트가 아닌 경우, 또는 유효한 단어가 있는 경우만 추가
            if !cleanSegment.text.isEmpty || (cleanSegment.words?.isEmpty == false) {
                cleanSegments.append(cleanSegment)
            }
        }
        
        // 시작 시간으로 세그먼트 정렬
        cleanSegments.sort { $0.start < $1.start }
        
        // 세그먼트 간 시간 겹침 처리
        for i in 0..<cleanSegments.count-1 {
            // 이전 세그먼트의 끝 시간이 다음 세그먼트의 시작 시간보다 뒤에 있으면 조정
            if cleanSegments[i].end > cleanSegments[i+1].start {
                // 다음 세그먼트 시작 시간에 맞춰 이전 세그먼트 끝 시간 조정
                cleanSegments[i].end = cleanSegments[i+1].start
            }
        }
        
        // 깨끗한 세그먼트로 결과 업데이트
        result.segments = cleanSegments
        
        // ExportService의 writer 분기 처리를 사용하여 파일 내보내기
        await ExportService.exportTranscriptionResult(result: result,
                                                      defaultFileName: audioState.audioFileName,
                                                      frameRate: frameRate)
    }
}
