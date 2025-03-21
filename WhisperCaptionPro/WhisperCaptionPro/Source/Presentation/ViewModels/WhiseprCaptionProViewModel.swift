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

@MainActor
class ContentViewModel: ObservableObject {
    // MARK: - 뷰 상태 (원래 ContentView의 @State 변수들)

    @Published var whisperKit: WhisperKit?

    #if os(macOS)
        @Published var audioDevices: [AudioDevice]?
    #endif

    @Published var isRecording: Bool = false
    @Published var isTranscribing: Bool = false
    @Published var currentText: String = ""
    @Published var currentChunks: [Int: (chunkText: [String], fallbacks: Int)] = [:]

    // Model 관리 관련 상태
    @Published var modelStorage: String = "huggingface/models/argmaxinc/whisperkit-coreml"
    @Published var appStartTime: Date = .init()
    @Published var modelState: ModelState = .unloaded
    @Published var localModels: [String] = []
    @Published var localModelPath: String = ""
    @Published var availableModels: [String] = []
    @Published var availableLanguages: [String] = []
    @Published var disabledModels: [String] = WhisperKit.recommendedModels().disabled

    // Standard properties
    @Published var loadingProgressValue: Float = 0.0
    @Published var specializationProgressRatio: Float = 0.7
    @Published var isFilePickerPresented: Bool = false
    @Published var modelLoadingTime: TimeInterval = 0
    @Published var firstTokenTime: TimeInterval = 0
    @Published var pipelineStart: TimeInterval = 0
    @Published var effectiveRealTimeFactor: TimeInterval = 0
    @Published var effectiveSpeedFactor: TimeInterval = 0
    @Published var totalInferenceTime: TimeInterval = 0
    @Published var tokensPerSecond: TimeInterval = 0
    @Published var currentLag: TimeInterval = 0
    @Published var currentFallbacks: Int = 0
    @Published var currentEncodingLoops: Int = 0
    @Published var currentDecodingLoops: Int = 0
    @Published var lastBufferSize: Int = 0
    @Published var lastConfirmedSegmentEndSeconds: Float = 0
    @Published var requiredSegmentsForConfirmation: Int = 2
    @Published var bufferEnergy: [Float] = []
    @Published var bufferSeconds: Double = 0
    @Published var confirmedSegments: [TranscriptionSegment] = []
    @Published var unconfirmedSegments: [TranscriptionSegment] = []

    // Eager mode properties
    @Published var eagerResults: [TranscriptionResult?] = []
    @Published var prevResult: TranscriptionResult?
    @Published var lastAgreedSeconds: Float = 0.0
    @Published var prevWords: [WordTiming] = []
    @Published var lastAgreedWords: [WordTiming] = []
    @Published var confirmedWords: [WordTiming] = []
    @Published var confirmedText: String = ""
    @Published var hypothesisWords: [WordTiming] = []
    @Published var hypothesisText: String = ""

    // UI properties
    @Published var columnVisibility: NavigationSplitViewVisibility = .all
    @Published var showComputeUnits: Bool = true
    @Published var showAdvancedOptions: Bool = false
    @Published var transcriptionTask: Task<Void, Never>?
    @Published var selectedCategoryId: UUID?
    @Published var transcribeTask: Task<Void, Never>?

    // MARK: - 메뉴 (예: Transcribe, Stream)

    struct MenuItem: Identifiable, Hashable {
        var id = UUID()
        var name: String
        var image: String
    }

    let menu: [MenuItem] = [
        MenuItem(name: "Transcribe", image: "book.pages"),
        MenuItem(name: "Stream", image: "waveform.badge.mic"),
    ]

    // MARK: - AppStorage 변수 (PublishedAppStorage 커스텀 래퍼 사용도 고려 가능)

    @AppStorage("selectedAudioInput") var storedSelectedAudioInput: String = "No Audio Input"
    @AppStorage("selectedModel") var storedSelectedModel: String = WhisperKit.recommendedModels()
        .default
    @AppStorage("selectedTab") var storedSelectedTab: String = "Transcribe"
    @AppStorage("selectedTask") var storedSelectedTask: String = "transcribe"
    @AppStorage("selectedLanguage") var storedSelectedLanguage: String = "english"
    @AppStorage("repoName") var storedRepoName: String = "argmaxinc/whisperkit-coreml"
    @AppStorage("enableTimestamps") var storedEnableTimestamps: Bool = true
    @AppStorage("enablePromptPrefill") var storedEnablePromptPrefill: Bool = true
    @AppStorage("enableCachePrefill") var storedEnableCachePrefill: Bool = true
    @AppStorage("enableSpecialCharacters") var storedEnableSpecialCharacters: Bool = false
    @AppStorage("enableEagerDecoding") var storedEnableEagerDecoding: Bool = false
    @AppStorage("enableDecoderPreview") var storedEnableDecoderPreview: Bool = true
    @AppStorage("temperatureStart") var storedTemperatureStart: Double = 0
    @AppStorage("fallbackCount") var storedFallbackCount: Double = 5
    @AppStorage("compressionCheckWindow") var storedCompressionCheckWindow: Double = 60
    @AppStorage("sampleLength") var storedSampleLength: Double = 224
    @AppStorage("silenceThreshold") var storedSilenceThreshold: Double = 0.3
    @AppStorage("realtimeDelayInterval") var storedRealtimeDelayInterval: Double = 1
    @AppStorage("useVAD") var storedUseVAD: Bool = true
    @AppStorage("tokenConfirmationsNeeded") var storedTokenConfirmationsNeeded: Double = 2
    @AppStorage("concurrentWorkerCount") var storedConcurrentWorkerCount: Double = 4
    @AppStorage("chunkingStrategy") var storedChunkingStrategy: ChunkingStrategy = .vad
    @AppStorage("encoderComputeUnits") var storedEncoderComputeUnits: MLComputeUnits =
        .cpuAndNeuralEngine
    @AppStorage("decoderComputeUnits") var storedDecoderComputeUnits: MLComputeUnits =
        .cpuAndNeuralEngine

    // Published 값과 동기화
    @Published var selectedAudioInput: String = "No Audio Input" {
        didSet { storedSelectedAudioInput = selectedAudioInput }
    }

    @Published var selectedModel: String = WhisperKit.recommendedModels().default {
        didSet { storedSelectedModel = selectedModel }
    }

    @Published var selectedTab: String = "Transcribe" {
        didSet { storedSelectedTab = selectedTab }
    }

    @Published var selectedTask: String = "transcribe" {
        didSet { storedSelectedTask = selectedTask }
    }

    @Published var selectedLanguage: String = "english" {
        didSet { storedSelectedLanguage = selectedLanguage }
    }

    @Published var repoName: String = "argmaxinc/whisperkit-coreml" {
        didSet { storedRepoName = repoName }
    }

    @Published var enableTimestamps: Bool = true {
        didSet { storedEnableTimestamps = enableTimestamps }
    }

    @Published var enablePromptPrefill: Bool = true {
        didSet { storedEnablePromptPrefill = enablePromptPrefill }
    }

    @Published var enableCachePrefill: Bool = true {
        didSet { storedEnableCachePrefill = enableCachePrefill }
    }

    @Published var enableSpecialCharacters: Bool = false {
        didSet { storedEnableSpecialCharacters = enableSpecialCharacters }
    }

    @Published var enableEagerDecoding: Bool = false {
        didSet { storedEnableEagerDecoding = enableEagerDecoding }
    }

    @Published var enableDecoderPreview: Bool = true {
        didSet { storedEnableDecoderPreview = enableDecoderPreview }
    }

    @Published var temperatureStart: Double = 0 {
        didSet { storedTemperatureStart = temperatureStart }
    }

    @Published var fallbackCount: Double = 5 {
        didSet { storedFallbackCount = fallbackCount }
    }

    @Published var compressionCheckWindow: Double = 60 {
        didSet { storedCompressionCheckWindow = compressionCheckWindow }
    }

    @Published var sampleLength: Double = 224 {
        didSet { storedSampleLength = sampleLength }
    }

    @Published var silenceThreshold: Double = 0.3 {
        didSet { storedSilenceThreshold = silenceThreshold }
    }

    @Published var realtimeDelayInterval: Double = 1 {
        didSet { storedRealtimeDelayInterval = realtimeDelayInterval }
    }

    @Published var useVAD: Bool = true {
        didSet { storedUseVAD = useVAD }
    }

    @Published var tokenConfirmationsNeeded: Double = 2 {
        didSet { storedTokenConfirmationsNeeded = tokenConfirmationsNeeded }
    }

    @Published var concurrentWorkerCount: Double = 4 {
        didSet { storedConcurrentWorkerCount = concurrentWorkerCount }
    }

    @Published var chunkingStrategy: ChunkingStrategy = .vad {
        didSet { storedChunkingStrategy = chunkingStrategy }
    }

    @Published var encoderComputeUnits: MLComputeUnits = .cpuAndNeuralEngine {
        didSet { storedEncoderComputeUnits = encoderComputeUnits }
    }

    @Published var decoderComputeUnits: MLComputeUnits = .cpuAndNeuralEngine {
        didSet { storedDecoderComputeUnits = decoderComputeUnits }
    }

    // MARK: - 로직 메서드들 (fetchModels, loadModel, transcribeFile, toggleRecording, start/stopRecording 등)

    // 기존 ContentView의 로직들을 적절히 옮깁니다.

    func resetState() {
        transcribeTask?.cancel()
        isRecording = false
        isTranscribing = false
        whisperKit?.audioProcessor.stopRecording()
        currentText = ""
        currentChunks = [:]

        pipelineStart = Double.greatestFiniteMagnitude
        firstTokenTime = Double.greatestFiniteMagnitude
        effectiveRealTimeFactor = 0
        effectiveSpeedFactor = 0
        totalInferenceTime = 0
        tokensPerSecond = 0
        currentLag = 0
        currentFallbacks = 0
        currentEncodingLoops = 0
        currentDecodingLoops = 0
        lastBufferSize = 0
        lastConfirmedSegmentEndSeconds = 0
        requiredSegmentsForConfirmation = 2
        bufferEnergy = []
        bufferSeconds = 0
        confirmedSegments = []
        unconfirmedSegments = []

        eagerResults = []
        prevResult = nil
        lastAgreedSeconds = 0.0
        prevWords = []
        lastAgreedWords = []
        confirmedWords = []
        confirmedText = ""
        hypothesisWords = []
        hypothesisText = ""
    }

    func getComputeOptions() -> ModelComputeOptions {
        return ModelComputeOptions(
            audioEncoderCompute: encoderComputeUnits,
            textDecoderCompute: decoderComputeUnits
        )
    }

    func fetchModels() {
        availableModels = [selectedModel]
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first {
            let modelPath = documents.appendingPathComponent(modelStorage).path
            if FileManager.default.fileExists(atPath: modelPath) {
                localModelPath = modelPath
                do {
                    let downloadedModels = try FileManager.default
                        .contentsOfDirectory(atPath: modelPath)
                    for model in downloadedModels where !localModels.contains(model) {
                        localModels.append(model)
                    }
                } catch {
                    print("Error enumerating files at \(modelPath): \(error.localizedDescription)")
                }
            }
        }
        localModels = WhisperKit.formatModelFiles(localModels)
        for model in localModels where !availableModels.contains(model) {
            availableModels.append(model)
        }

        print("Found locally: \(localModels)")
        print("Previously selected model: \(selectedModel)")

        Task {
            let remoteModelSupport = await WhisperKit.recommendedRemoteModels()
            await MainActor.run {
                for model in remoteModelSupport.supported {
                    if !availableModels.contains(model) {
                        availableModels.append(model)
                    }
                }
                for model in remoteModelSupport.disabled {
                    if !disabledModels.contains(model) {
                        disabledModels.append(model)
                    }
                }
            }
        }
    }

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

            if localModels.contains(model) && !redownload {
                folder = URL(fileURLWithPath: localModelPath).appendingPathComponent(model)
            } else {
                folder = try await WhisperKit.download(
                    variant: model,
                    from: repoName,
                    progressCallback: { progress in
                        DispatchQueue.main.async {
                            self.loadingProgressValue = Float(progress.fractionCompleted) * self
                                .specializationProgressRatio
                            self.modelState = .downloading
                        }
                    }
                )
            }

            await MainActor.run {
                loadingProgressValue = specializationProgressRatio
                modelState = .downloaded
            }

            if let modelFolder = folder {
                whisperKit.modelFolder = modelFolder
                await MainActor.run {
                    loadingProgressValue = specializationProgressRatio
                    modelState = .prewarming
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
                        modelState = .unloaded
                        return
                    }
                }

                await MainActor.run {
                    loadingProgressValue = specializationProgressRatio + 0.9 *
                        (1 - specializationProgressRatio)
                    modelState = .loading
                }

                try await whisperKit.loadModels()

                await MainActor.run {
                    if !localModels.contains(model) {
                        localModels.append(model)
                    }
                    availableLanguages = Constants.languages.map { $0.key }.sorted()
                    loadingProgressValue = 1.0
                    modelState = whisperKit.modelState
                }
            }
        }
    }

    func deleteModel() {
        if localModels.contains(selectedModel) {
            let modelFolder = URL(fileURLWithPath: localModelPath)
                .appendingPathComponent(selectedModel)
            do {
                try FileManager.default.removeItem(at: modelFolder)
                if let index = localModels.firstIndex(of: selectedModel) {
                    localModels.remove(at: index)
                }
                modelState = .unloaded
            } catch {
                print("Error deleting model: \(error)")
            }
        }
    }

    func updateProgressBar(targetProgress: Float, maxTime: TimeInterval) async {
        let initialProgress = loadingProgressValue
        let decayConstant = -log(1 - targetProgress) / Float(maxTime)
        let startTime = Date()

        while true {
            let elapsedTime = Date().timeIntervalSince(startTime)
            let decayFactor = exp(-decayConstant * Float(elapsedTime))
            let progressIncrement = (1 - initialProgress) * (1 - decayFactor)
            let currentProgress = initialProgress + progressIncrement

            await MainActor.run {
                loadingProgressValue = currentProgress
            }

            if currentProgress >= targetProgress { break }

            do {
                try await Task.sleep(nanoseconds: 100_000_000)
            } catch {
                break
            }
        }
    }

    func selectFile() {
        isFilePickerPresented = true
    }

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

    func transcribeFile(path: String) {
        resetState()
        whisperKit?.audioProcessor = AudioProcessor()
        transcribeTask = Task {
            isTranscribing = true
            do {
                try await transcribeCurrentFile(path: path)
            } catch {
                print("File selection error: \(error.localizedDescription)")
            }
            isTranscribing = false
        }
    }

    func toggleRecording(shouldLoop: Bool) {
        isRecording.toggle()
        if isRecording {
            resetState()
            startRecording(shouldLoop)
        } else {
            stopRecording(shouldLoop)
        }
    }

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
                       let devices = audioDevices,
                       let device = devices.first(where: { $0.name == selectedAudioInput }) {
                        deviceId = device.id
                    }
                    if deviceId == nil {
                        throw WhisperError.microphoneUnavailable()
                    }
                #endif
                try? audioProcessor.startRecordingLive(inputDeviceID: deviceId) { _ in
                    DispatchQueue.main.async {
                        self.bufferEnergy = self.whisperKit?.audioProcessor.relativeEnergy ?? []
                        self
                            .bufferSeconds = Double(self.whisperKit?.audioProcessor.audioSamples
                                .count ?? 0) / Double(WhisperKit.sampleRate)
                    }
                }
                isRecording = true
                isTranscribing = true
                if loop { realtimeLoop() }
            }
        }
    }

    func stopRecording(_ loop: Bool) {
        isRecording = false
        stopRealtimeTranscription()
        if let audioProcessor = whisperKit?.audioProcessor {
            audioProcessor.stopRecording()
        }
        if !loop {
            transcribeTask = Task {
                isTranscribing = true
                do {
                    try await transcribeCurrentBuffer()
                } catch {
                    print("Error: \(error.localizedDescription)")
                }
                finalizeText()
                isTranscribing = false
            }
        }
        finalizeText()
    }

    func finalizeText() {
        Task {
            await MainActor.run {
                if hypothesisText != "" {
                    confirmedText += hypothesisText
                    hypothesisText = ""
                }
                if !unconfirmedSegments.isEmpty {
                    confirmedSegments.append(contentsOf: unconfirmedSegments)
                    unconfirmedSegments = []
                }
            }
        }
    }

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
            currentText = ""
            guard let segments = transcription?.segments else { return }
            tokensPerSecond = transcription?.timings.tokensPerSecond ?? 0
            effectiveRealTimeFactor = transcription?.timings.realTimeFactor ?? 0
            effectiveSpeedFactor = transcription?.timings.speedFactor ?? 0
            currentEncodingLoops = Int(transcription?.timings.totalEncodingRuns ?? 0)
            firstTokenTime = transcription?.timings.firstTokenTime ?? 0
            modelLoadingTime = transcription?.timings.modelLoading ?? 0
            pipelineStart = transcription?.timings.pipelineStart ?? 0
            currentLag = transcription?.timings.decodingLoop ?? 0
            confirmedSegments = segments
        }
    }

    func transcribeAudioSamples(_ samples: [Float]) async throws -> TranscriptionResult? {
        guard let whisperKit = whisperKit else { return nil }
        let languageCode = Constants.languages[
            selectedLanguage,
            default: Constants.defaultLanguageCode
        ]
        let task: DecodingTask = selectedTask == "transcribe" ? .transcribe : .translate
        let seekClip: [Float] = [lastConfirmedSegmentEndSeconds]
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
            wordTimestamps: true,
            clipTimestamps: seekClip,
            concurrentWorkerCount: Int(concurrentWorkerCount),
            chunkingStrategy: chunkingStrategy
        )

        let decodingCallback: ((TranscriptionProgress) -> Bool?) = { progress in
            DispatchQueue.main.async {
                let fallbacks = Int(progress.timings.totalDecodingFallbacks)
                let chunkId = self.selectedTask == "transcribe" ? 0 : progress.windowId
                var updatedChunk = (chunkText: [progress.text], fallbacks: fallbacks)
                if var currentChunk = self.currentChunks[chunkId],
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
                            print("Fallback occured: \(fallbacks)")
                        }
                    }
                }
                self.currentChunks[chunkId] = updatedChunk
                let joinedChunks = self.currentChunks.sorted { $0.key < $1.key }
                    .flatMap { $0.value.chunkText }.joined(separator: "\n")
                self.currentText = joinedChunks
                self.currentFallbacks = fallbacks
                self.currentDecodingLoops += 1
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

    func realtimeLoop() {
        transcriptionTask = Task {
            while isRecording && isTranscribing {
                do {
                    try await transcribeCurrentBuffer(delayInterval: Float(realtimeDelayInterval))
                } catch {
                    print("Error: \(error.localizedDescription)")
                    break
                }
            }
        }
    }

    func stopRealtimeTranscription() {
        isTranscribing = false
        transcriptionTask?.cancel()
    }

    func transcribeCurrentBuffer(delayInterval: Float = 1.0) async throws {
        guard let whisperKit = whisperKit else { return }
        let currentBuffer = whisperKit.audioProcessor.audioSamples
        let nextBufferSize = currentBuffer.count - lastBufferSize
        let nextBufferSeconds = Float(nextBufferSize) / Float(WhisperKit.sampleRate)
        guard nextBufferSeconds > delayInterval else {
            await MainActor.run {
                if currentText == "" { currentText = "Waiting for speech..." }
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
                    if currentText == "" { currentText = "Waiting for speech..." }
                }
                try await Task.sleep(nanoseconds: 100_000_000)
                return
            }
        }
        lastBufferSize = currentBuffer.count

        if enableEagerDecoding && selectedTask == "transcribe" {
            let transcription = try await transcribeEagerMode(Array(currentBuffer))
            await MainActor.run {
                currentText = ""
                tokensPerSecond = transcription?.timings.tokensPerSecond ?? 0
                firstTokenTime = transcription?.timings.firstTokenTime ?? 0
                modelLoadingTime = transcription?.timings.modelLoading ?? 0
                pipelineStart = transcription?.timings.pipelineStart ?? 0
                currentLag = transcription?.timings.decodingLoop ?? 0
                currentEncodingLoops = Int(transcription?.timings.totalEncodingRuns ?? 0)
                let totalAudio = Double(currentBuffer.count) / Double(WhisperKit.sampleRate)
                totalInferenceTime = transcription?.timings.fullPipeline ?? 0
                effectiveRealTimeFactor = Double(totalInferenceTime) / totalAudio
                effectiveSpeedFactor = totalAudio / Double(totalInferenceTime)
            }
        } else {
            let transcription = try await transcribeAudioSamples(Array(currentBuffer))
            await MainActor.run {
                currentText = ""
                guard let segments = transcription?.segments else { return }
                tokensPerSecond = transcription?.timings.tokensPerSecond ?? 0
                firstTokenTime = transcription?.timings.firstTokenTime ?? 0
                modelLoadingTime = transcription?.timings.modelLoading ?? 0
                pipelineStart = transcription?.timings.pipelineStart ?? 0
                currentLag = transcription?.timings.decodingLoop ?? 0
                currentEncodingLoops += Int(transcription?.timings.totalEncodingRuns ?? 0)
                let totalAudio = Double(currentBuffer.count) / Double(WhisperKit.sampleRate)
                totalInferenceTime += transcription?.timings.fullPipeline ?? 0
                effectiveRealTimeFactor = Double(totalInferenceTime) / totalAudio
                effectiveSpeedFactor = totalAudio / Double(totalInferenceTime)

                if segments.count > requiredSegmentsForConfirmation {
                    let numberOfSegmentsToConfirm = segments.count - requiredSegmentsForConfirmation
                    let confirmedSegmentsArray = Array(segments.prefix(numberOfSegmentsToConfirm))
                    let remainingSegments = Array(segments.suffix(requiredSegmentsForConfirmation))
                    if let lastConfirmedSegment = confirmedSegmentsArray.last,
                       lastConfirmedSegment.end > lastConfirmedSegmentEndSeconds {
                        lastConfirmedSegmentEndSeconds = lastConfirmedSegment.end
                        print("Last confirmed segment end: \(lastConfirmedSegmentEndSeconds)")
                        for segment in confirmedSegmentsArray {
                            if !confirmedSegments.contains(segment: segment) {
                                confirmedSegments.append(segment)
                            }
                        }
                    }
                    unconfirmedSegments = remainingSegments
                } else {
                    unconfirmedSegments = segments
                }
            }
        }
    }

    func transcribeEagerMode(_ samples: [Float]) async throws -> TranscriptionResult? {
        guard let whisperKit = whisperKit else { return nil }
        guard whisperKit.textDecoder.supportsWordTimestamps else {
            confirmedText =
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
            wordTimestamps: true,
            firstTokenLogProbThreshold: -1.5,
            chunkingStrategy: ChunkingStrategy.none
        )

        let decodingCallback: ((TranscriptionProgress) -> Bool?) = { progress in
            DispatchQueue.main.async {
                let fallbacks = Int(progress.timings.totalDecodingFallbacks)
                if progress.text.count < self.currentText.count {
                    if fallbacks == self.currentFallbacks {
                        // no additional action
                    } else {
                        print("Fallback occured: \(fallbacks)")
                    }
                }
                self.currentText = progress.text
                self.currentFallbacks = fallbacks
                self.currentDecodingLoops += 1
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

        Logging.info("[EagerMode] \(lastAgreedSeconds)-\(Double(samples.count) / 16000.0) seconds")
        let streamingAudio = samples
        var streamOptions = options
        streamOptions.clipTimestamps = [lastAgreedSeconds]
        let lastAgreedTokens = lastAgreedWords.flatMap { $0.tokens }
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
                    hypothesisWords = result.allWords.filter { $0.start >= lastAgreedSeconds }
                    if let prevResult = prevResult {
                        prevWords = prevResult.allWords.filter { $0.start >= lastAgreedSeconds }
                        let commonPrefix = findLongestCommonPrefix(prevWords, hypothesisWords)
                        Logging.info("[EagerMode] Prev \"\((prevWords.map { $0.word }).joined())\"")
                        Logging
                            .info(
                                "[EagerMode] Next \"\((hypothesisWords.map { $0.word }).joined())\""
                            )
                        Logging
                            .info(
                                "[EagerMode] Found common prefix \"\((commonPrefix.map { $0.word }).joined())\""
                            )
                        if commonPrefix.count >= Int(tokenConfirmationsNeeded) {
                            lastAgreedWords = Array(commonPrefix
                                .suffix(Int(tokenConfirmationsNeeded)))
                            lastAgreedSeconds = lastAgreedWords.first!.start
                            Logging
                                .info(
                                    "[EagerMode] Found new last agreed word \"\(lastAgreedWords.first!.word)\" at \(lastAgreedSeconds) seconds"
                                )
                            confirmedWords
                                .append(contentsOf: commonPrefix
                                    .prefix(commonPrefix.count - Int(tokenConfirmationsNeeded)))
                            let currentWords = confirmedWords.map { $0.word }.joined()
                            Logging
                                .info(
                                    "[EagerMode] Current:  \(lastAgreedSeconds) -> \(Double(samples.count) / 16000.0) \(currentWords)"
                                )
                        } else {
                            Logging
                                .info(
                                    "[EagerMode] Using same last agreed time \(lastAgreedSeconds)"
                                )
                            skipAppend = true
                        }
                    }
                    prevResult = result
                }
                if !skipAppend {
                    eagerResults.append(transcription)
                }
            }

            await MainActor.run {
                let finalWords = confirmedWords.map { $0.word }.joined()
                confirmedText = finalWords
                let lastHypothesis = lastAgreedWords + findLongestDifferentSuffix(
                    prevWords,
                    hypothesisWords
                )
                hypothesisText = lastHypothesis.map { $0.word }.joined()
            }
        } catch {
            Logging.error("[EagerMode] Error: \(error)")
            finalizeText()
        }

        let mergedResult = mergeTranscriptionResults(eagerResults, confirmedWords: confirmedWords)
        return mergedResult
    }
}
