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
    // MARK: - Published Properties
    @Published var whisperKit: WhisperKit?
    
    // Model 및 전사 관련 상태
    @Published var transcriptionState = TranscriptionState()
    @Published var modelManagementState = ModelManagementState()
    @Published var audioState = AudioState()
    @Published var uiState = UIState()
    
    /// 전사 결과 (전사 완료 후 업데이트)
    @Published var transcriptionResult: TranscriptionResult?

    /// Export 진행 여부
    @Published var isExporting: Bool = false
    
    var audioPlayer: AVAudioPlayer?

    // MARK: - AppStorage (사용자 설정, UserDefaults 기반)
    @AppStorage("selectedAudioInput") var selectedAudioInput: String = "No Audio Input"
    @AppStorage("selectedModel") var selectedModel: String = WhisperKit.recommendedModels().default
    @AppStorage("selectedTask") var selectedTask: String = "transcribe"
    @AppStorage("selectedLanguage") var selectedLanguage: String = "english"
    @AppStorage("repoName") var repoName: String = "argmaxinc/whisperkit-coreml"
    @AppStorage("enableTimestamps") var enableTimestamps: Bool = true
    @AppStorage("enablePromptPrefill") var enablePromptPrefill: Bool = true
    @AppStorage("enableCachePrefill") var enableCachePrefill: Bool = true
    @AppStorage("enableSpecialCharacters") var enableSpecialCharacters: Bool = false
    @AppStorage("enableEagerDecoding") var enableEagerDecoding: Bool = false
    @AppStorage("enableDecoderPreview") var enableDecoderPreview: Bool = true
    @AppStorage("temperatureStart") var temperatureStart: Double = 0.0
    @AppStorage("fallbackCount") var fallbackCount: Double = 5.0
    @AppStorage("compressionCheckWindow") var compressionCheckWindow: Double = 60.0
    @AppStorage("sampleLength") var sampleLength: Double = 224.0
    @AppStorage("silenceThreshold") var silenceThreshold: Double = 0.3
    @AppStorage("realtimeDelayInterval") var realtimeDelayInterval: Double = 1.0
    @AppStorage("useVAD") var useVAD: Bool = true
    @AppStorage("tokenConfirmationsNeeded") var tokenConfirmationsNeeded: Double = 2.0
    @AppStorage("concurrentWorkerCount") var concurrentWorkerCount: Double = 4.0
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
        uiState.isTranscribingView = false
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
    
    // MARK: - Model Management
    
    /// 로컬 및 원격 모델 목록 업데이트
    func fetchModels() {
        modelManagementState.availableModels = []
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let modelPath = documents.appendingPathComponent(modelManagementState.modelStorage).path
            if FileManager.default.fileExists(atPath: modelPath) {
                modelManagementState.localModelPath = modelPath
                do {
                    let downloadedModels = try FileManager.default.contentsOfDirectory(atPath: modelPath)
                    for model in downloadedModels where !modelManagementState.localModels.contains(model) {
                        modelManagementState.localModels.append(model)
                    }
                } catch {
                    print("Error enumerating files at \(modelPath): \(error.localizedDescription)")
                }
            }
        }
        modelManagementState.localModels = WhisperKit.formatModelFiles(modelManagementState.localModels)
        for model in modelManagementState.localModels where !modelManagementState.availableModels.contains(model) {
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
                            self.modelManagementState.loadingProgressValue = Float(progress.fractionCompleted) * self.modelManagementState.specializationProgressRatio
                            self.modelManagementState.modelState = .downloading
                        }
                    }
                )
            }
            
            await MainActor.run {
                modelManagementState.loadingProgressValue = modelManagementState.specializationProgressRatio
                modelManagementState.modelState = .downloaded
            }
            
            if let modelFolder = folder {
                whisperKit.modelFolder = modelFolder
                await MainActor.run {
                    modelManagementState.loadingProgressValue = modelManagementState.specializationProgressRatio
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
                    modelManagementState.loadingProgressValue = modelManagementState.specializationProgressRatio + 0.9 * (1 - modelManagementState.specializationProgressRatio)
                    modelManagementState.modelState = whisperKit.modelState
                }
                
                do {
                    try await whisperKit.loadModels()
                } catch {
                    print("Error loading models: \(error)")
                }
                
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
                if let index = modelManagementState.localModels.firstIndex(of: selectedModel) {
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
                do {
                    // 기존 오디오 플레이어 정리
                    stopImportedAudio()
                    audioPlayer = nil
                    
                    let audioFileData = try Data(contentsOf: selectedFileURL)
                    let uniqueFileName = UUID().uuidString + "." + selectedFileURL.pathExtension
                    let tempDirectoryURL = FileManager.default.temporaryDirectory
                    let localFileURL = tempDirectoryURL.appendingPathComponent(uniqueFileName)
                    try audioFileData.write(to: localFileURL)
                    print("File saved to temporary directory: \(localFileURL)")
                    audioState.audioFileName = selectedFileURL.deletingPathExtension().lastPathComponent
                    // 파일을 임포트한 후 바로 전사하지 않고 URL만 저장 (전사 버튼 호출 시 전사)
                    audioState.importedAudioURL = selectedFileURL
                    
                    // 파일 임포트 후 자동으로 파형 생성
                    Task {
                        await processWaveform()
                    }
                } catch {
                    print("File selection error: \(error.localizedDescription)")
                }
            }
        case let .failure(error):
            print("File selection error: \(error.localizedDescription)")
        }
    }
    
    /// 파일 전사 시작 (선택된 파일 URL로 전사 실행)
    func transcribeFile(path: String) {
        resetState()
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
            transcriptionState.currentEncodingLoops = Int(transcription?.timings.totalEncodingRuns ?? 0)
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
        let languageCode = Constants.languages[selectedLanguage, default: Constants.defaultLanguageCode]
        let task: DecodingTask = selectedTask == "transcribe" ? .transcribe : .translate
        let seekClip: [Float] = [transcriptionState.lastConfirmedSegmentEndSeconds]
        
        let options = DecodingOptions(
            verbose: true,
            task: task,
            language: isAutoLanguageEnable ? nil : languageCode, // 자동 언어 감지 옵션
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
                        if fallbacks == currentChunk.fallbacks && self.selectedTask == "transcribe" {
                            updatedChunk.chunkText = [(updatedChunk.chunkText.first ?? "") + progress.text]
                        } else {
                            updatedChunk.chunkText[currentChunk.chunkText.endIndex - 1] = progress.text
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
            // 항상 새로운 오디오 플레이어 생성
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioState.totalDuration = audioPlayer?.duration ?? 0.0
            
            audioPlayer?.play()
            audioState.isPlaying = true
            
            // 재생 시간 업데이트를 위한 타이머 설정
            audioState.playbackTimer?.invalidate()
            audioState.playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                
                // 메인 스레드에서 실행
                DispatchQueue.main.async {
                    guard let player = self.audioPlayer else { return }
                    self.audioState.currentPlaybackTime = player.currentTime
                    
                    // 재생이 끝났는지 확인
                    if !player.isPlaying && self.audioState.isPlaying {
                        self.audioState.isPlaying = false
                        self.audioState.currentPlaybackTime = 0.0
                    }
                }
            }
        } catch {
            print("Error playing audio: \(error.localizedDescription)")
        }
    }
    
    func pauseImportedAudio() {
        audioPlayer?.pause()
        audioState.isPlaying = false
        audioState.playbackTimer?.invalidate()
    }
    
    func stopImportedAudio() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        audioState.isPlaying = false
        audioState.currentPlaybackTime = 0.0
        audioState.playbackTimer?.invalidate()
    }
    
    func seekToPosition(_ position: Double) {
        guard let player = audioPlayer else { return }
        player.currentTime = position
        audioState.currentPlaybackTime = position
        
        // 재생 중이었다면 계속 재생
        if audioState.isPlaying {
            player.play()
        }
    }
    
    func deleteImportedAudio() {
        // 재생 중이면 먼저 정지
        stopImportedAudio()
        
        // 파일 삭제 대신 앱에서만 초기화
        audioState.importedAudioURL = nil
        audioState.audioFileName = ""
        audioState.waveformSamples = []
        print("Imported audio removed from app.")
    }
    
    /// 오디오 파일에서 파형 데이터를 생성 (RMS 기반 계산 예시)
    func processWaveform() async {
        guard let url = audioState.importedAudioURL else { return }
        do {
            let samples = try await Task {
                try autoreleasepool {
                    try AudioProcessor.loadAudioAsFloatArray(fromPath: url.path)
                }
            }.value
            let waveformSamples = computeWaveform(from: samples)
            await MainActor.run {
                audioState.waveformSamples = waveformSamples
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
            let chunk = samples[index..<min(index + chunkSize, samples.count)]
            let sumSquares = chunk.reduce(0) { $0 + $1 * $1 }
            let rms = sqrt(sumSquares / Float(chunk.count))
            rmsValues.append(rms)
            index += chunkSize
        }
        return rmsValues
    }
    
    // MARK: - Export Service 호출 (ViewModel 내)
    func exportTranscription() async {
        guard var result = transcriptionResult else {
            print("No transcription result available.")
            return
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
        for i in 0..<cleanSegments.count-1 {
            if cleanSegments[i].end > cleanSegments[i+1].start {
                cleanSegments[i].end = cleanSegments[i+1].start
            }
        }
        result.segments = cleanSegments
        
        // ExportService의 writer 분기 처리를 사용하여 파일 내보내기
        await ExportService.exportTranscriptionResult(result: result,
                                                      defaultFileName: audioState.audioFileName,
                                                      frameRate: frameRate)
    }
}
