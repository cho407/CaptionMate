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
    private var isLoadingModel = false
    // MARK: - Published Properties
    @Published var whisperKit: WhisperKit?
    
    // 현재 실제로 로드된 모델 추적 (selectedModel과 구분)
    @Published var currentLoadedModel: String = ""
    
    // Model 및 전사 관련 상태
    @Published var transcriptionState = TranscriptionState()
    @Published var modelManagementState = ModelManagementState()
    @Published var audioState = AudioState()
    @Published var uiState = UIState()
    
    /// 전사 결과 (전사 완료 후 업데이트)
    @Published var transcriptionResult: TranscriptionResult?
    
    /// Export 진행 여부
    @Published var isExporting: Bool = false
    
    @Published var audioPlayer: AVAudioPlayer?
    @Published var normalizedVolumeFactor: Float = 1.0  // 노멀라이제이션 계수 저장용
    @Published var currentPlayerTime: Double = 0.0  // currentTime publish 위한 트리거
    
    // 재생 속도 상태 추가
    let playbackRates: [Float] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75,2.0]
    @Published var currentPlaybackRateIndex: Int = 3 // 기본값은 1.0x (인덱스 3)
    
    // 볼륨 상태 (AppStorage로 관리)
    @AppStorage("audioVolume") var audioVolume: Double = 1.0  // 0.0 ~ 1.0
    @AppStorage("stagingVolume") var stagingVolume: Double = 1.0  // 음소거 전 볼륨 저장용
    @AppStorage("isMuted") var isMuted: Bool = false  // 음소거 상태
    
    // Combine 관련
    private var playbackTimerCancellable: AnyCancellable?
    
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
    
    /// 캐시 디렉토리 정리 함수를 추가합니다
    func clearCoreMLRuntimeCache() {
        // 앱 캐시 디렉토리 경로 가져오기
        let fileManager = FileManager.default
        
        // 1. 앱의 캐시 디렉토리 찾기
        guard let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            print("캐시 디렉토리를 찾을 수 없습니다.")
            return
        }
        
        // 2. 앱의 번들 ID 가져오기 (동적으로 현재 앱 번들 ID 사용)
        let bundleID = Bundle.main.bundleIdentifier ?? "com.WhisperCaptionPro"
        
        // 3. CoreML 캐시 디렉토리 찾기 - 여러 가능한 경로 확인
        let possibleCacheDirs = [
            cachesDirectory.appendingPathComponent(bundleID).appendingPathComponent("com.apple.e5rt.e5bundlecache"),
            cachesDirectory.appendingPathComponent(bundleID).appendingPathComponent("com.apple.CoreML"),
            cachesDirectory.appendingPathComponent("com.apple.CoreML"),
            cachesDirectory.appendingPathComponent("CoreML")
        ]
        
        // 4. 모든 가능한 캐시 디렉토리 정리
        var clearedAny = false
        for cacheDir in possibleCacheDirs {
            if fileManager.fileExists(atPath: cacheDir.path) {
                do {
                    // a. 디렉토리 내용 가져오기
                    let contents = try fileManager.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil)
                    
                    // b. 각 파일/폴더 삭제
                    for item in contents {
                        do {
                            try fileManager.removeItem(at: item)
                            print("캐시 아이템 삭제 완료: \(item.lastPathComponent)")
                            clearedAny = true
                        } catch {
                            print("캐시 아이템 삭제 실패: \(item.lastPathComponent) - \(error.localizedDescription)")
                        }
                    }
                    
                    print("CoreML 캐시 디렉토리 정리 완료: \(cacheDir.path)")
                } catch {
                    print("CoreML 캐시 디렉토리 접근 실패: \(error.localizedDescription)")
                }
            }
        }
        
        // 5. 임시 디렉토리 정리
        // tmpdir은 모든 앱이 공유하므로 CoreML/WhisperKit 관련 파일만 신중하게 삭제
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        do {
            let tempContents = try fileManager.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil)
            
            // WhisperKit 또는 CoreML 관련 파일만 필터링
            let coreMLTempFiles = tempContents.filter { file in
                let fileName = file.lastPathComponent.lowercased()
                return fileName.contains("coreml") || 
                       fileName.contains("whisper") || 
                       fileName.contains(".bundle") || 
                       fileName.contains("model") ||
                       fileName.contains("mps") ||
                       fileName.contains("mlmodel")
            }
            
            for tempFile in coreMLTempFiles {
                do {
                    try fileManager.removeItem(at: tempFile)
                    print("임시 파일 삭제 완료: \(tempFile.lastPathComponent)")
                    clearedAny = true
                } catch {
                    print("임시 파일 삭제 실패: \(tempFile.lastPathComponent) - \(error.localizedDescription)")
                }
            }
        } catch {
            print("임시 디렉토리 검색 실패: \(error.localizedDescription)")
        }
        
        // 6. 결과 메시지 출력
        if clearedAny {
            print("CoreML 캐시 파일 정리 완료")
        } else {
            print("정리할 CoreML 캐시 파일을 찾지 못했습니다")
        }
    }
    
    // 디스크 여유 공간 확인 함수를 추가합니다
    func checkDiskSpace() -> (available: Int64, required: Int64, isEnough: Bool) {
        let fileManager = FileManager.default
        guard let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return (available: 0, required: 0, isEnough: false)
        }
        
        do {
            let resourceValues = try cachesDirectory.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            guard let availableSpace = resourceValues.volumeAvailableCapacity else {
                return (available: 0, required: 0, isEnough: false)
            }
            
            // volumeAvailableCapacity는 Int 타입이므로 Int64로 변환
            let availableSpaceInt64 = Int64(availableSpace)
            
            // CoreML에 필요한 예상 캐싱 공간 (모델에 따라 다르지만 대략 500MB-1GB)
            let requiredSpace: Int64 = 3_000_000_000 // 1GB
            
            return (available: availableSpaceInt64, required: requiredSpace, isEnough: availableSpaceInt64 > requiredSpace)
        } catch {
            print("디스크 공간 확인 실패: \(error.localizedDescription)")
            return (available: 0, required: 0, isEnough: false)
        }
    }
    
    /// 모델 해제 (메모리에서 완전히 해제)
    func releaseModel() async {
        print("모델 해제 시작: \(selectedModel)")
        
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
            
            // 짧은 딜레이 후 최종 상태 설정 (진행률 표시 완료를 위해)
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            finalProgressTask.cancel()
            
            // 인스턴스 해제
            await MainActor.run {
                whisperKit = nil
                modelManagementState.modelState = .unloaded
                modelManagementState.loadingProgressValue = 0.0 // 마지막에 0으로 리셋
                currentLoadedModel = ""
                print("모델 해제 완료: \(selectedModel)")
            }
        } else {
            // WhisperKit 인스턴스가 없는 경우
            releaseProgressTask.cancel()
            
            // 짧은 딜레이 후 완료 상태 설정 (시각적 효과를 위해)
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
        
        // 다운로드 진행률 초기화 (모델에 대한 다운로드 진행률 별도 관리)
        if redownload || !modelManagementState.localModels.contains(model) {
            modelManagementState.downloadProgress[model] = 0.0
        }
        
        // 에러 상태 초기화
        modelManagementState.hasModelLoadError = false
        modelManagementState.modelLoadError = nil

        Task {
            // 로딩 단계별 진행률 비율 설정 (초기화/프리워밍/로딩)
            let initProgressRatio: Float = 0.9         // 초기화 단계 (0.0 ~ 0.2)
            let prewarmProgressRatio: Float = 0.7      // 프리워밍 단계 (0.2 ~ 0.7)
            let loadProgressRatio: Float = 1.0         // 로딩 단계 (0.7 ~ 1.0)
            
            // 1. 초기화 단계 진행률 표시 시작
            let initProgressTask = Task {
                await updateProgressBar(startProgress: 0.0, targetProgress: initProgressRatio, maxTime: 2.0)
            }
            
            // 디스크 공간 확인 및 캐시 정리
            let diskSpace = checkDiskSpace()
            if !diskSpace.isEnough {
                print("⚠️ 디스크 공간 부족: 사용 가능 \(diskSpace.available / 1_000_000) MB, 필요 \(diskSpace.required / 1_000_000) MB")
                clearCoreMLRuntimeCache()
            }
            
            // 기존 WhisperKit 인스턴스 해제
            if let kit = whisperKit {
                do {
                    await kit.unloadModels()
                    print("이전 WhisperKit 모델 해제 완료")
                } catch {
                    print("⚠️ 이전 모델 언로드 실패: \(error.localizedDescription)")
                }
                whisperKit = nil
            }
            
            // 초기화 진행률 업데이트 작업 완료
            initProgressTask.cancel()
            await MainActor.run {
                modelManagementState.loadingProgressValue = initProgressRatio
            }
            
            print("선택된 모델: \(model)")
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
                print("⚠️ WhisperKit 초기화 실패: \(error.localizedDescription)")
                await MainActor.run {
                    modelManagementState.modelState = .unloaded
                    modelManagementState.hasModelLoadError = true
                    modelManagementState.modelLoadError = "모델 초기화 실패: \(error.localizedDescription)"
                    modelManagementState.loadingProgressValue = 0.0
                    isLoadingModel = false
                }
                return
            }
            
            guard let whisperKit = whisperKit else {
                await MainActor.run {
                    modelManagementState.modelState = .unloaded
                    modelManagementState.hasModelLoadError = true
                    modelManagementState.modelLoadError = "WhisperKit 인스턴스 생성 실패"
                    modelManagementState.loadingProgressValue = 0.0
                    isLoadingModel = false
                }
                return
            }

            // 3. 모델 파일 설정 단계 (다운로드 또는 로컬 경로 설정)
            var folder: URL?
            do {
                if modelManagementState.localModels.contains(model) && !redownload {
                    // 로컬 모델 경로 가져오기 - 다운로드 없이 바로 로드
                    folder = URL(fileURLWithPath: modelManagementState.localModelPath).appendingPathComponent(model)
                    
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
                        await updateProgressBar(startProgress: 0.0, targetProgress: 0.99, maxTime: 20.0)
                    }
                    
                    // 모델 다운로드 (별도의 다운로드 진행률 업데이트)
                    folder = try await WhisperKit.download(variant: model, from: repoName, progressCallback: { progress in
                        Task { @MainActor in
                            // 다운로드 전용 진행률 업데이트 (0.0 ~ 1.0)
                            self.modelManagementState.downloadProgress[model] = Float(progress.fractionCompleted)
                        }
                    })
                    
                    
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
                print("⚠️ 모델 다운로드 실패: \(error.localizedDescription)")
                await MainActor.run {
                    modelManagementState.modelState = .unloaded
                    modelManagementState.hasModelLoadError = true
                    modelManagementState.modelLoadError = "모델 다운로드 실패: \(error.localizedDescription)"
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
                    print("⚠️ 모델 prewarm 실패: \(error.localizedDescription)")
                    prewarmProgressTask.cancel()
                    
                    // 재다운로드 시도 (한 번만)
                    if !redownload {
                        await MainActor.run {
                            modelManagementState.loadingProgressValue = 0.0
                            modelManagementState.hasModelLoadError = true
                            modelManagementState.modelLoadError = "모델 최적화 실패, 재시도 중..."
                        }
                        loadModel(model, redownload: true)
                        isLoadingModel = false
                        return
                    } else {
                        await MainActor.run {
                            modelManagementState.modelState = .unloaded
                            modelManagementState.hasModelLoadError = true
                            modelManagementState.modelLoadError = "모델 최적화 실패: \(error.localizedDescription)"
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
                    print("⚠️ 모델 로드 실패: \(error.localizedDescription)")
                    loadProgressTask.cancel()
                    
                    // MPSGraph 관련 에러인 경우 캐시 정리 후 한 번만 재시도
                    let errorString = error.localizedDescription
                    if errorString.contains("MPSGraph") || errorString.contains("MPSGraphExecutable") || errorString.contains("No space left on device") {
                        print("MPSGraph 관련 에러 또는 디스크 공간 부족 감지됨, 캐시 정리 후 재시도...")
                        clearCoreMLRuntimeCache()
                        
                        // 한 번 더 시도
                        do {
                            try await Task.sleep(nanoseconds: 500_000_000) // 500ms 대기
                            try await whisperKit.loadModels()
                        } catch {
                            await MainActor.run {
                                modelManagementState.modelState = .unloaded
                                modelManagementState.hasModelLoadError = true
                                modelManagementState.modelLoadError = "모델 로드 실패 (재시도 후): \(error.localizedDescription)"
                                modelManagementState.loadingProgressValue = 0.0
                                isLoadingModel = false
                            }
                            return
                        }
                    } else {
                        await MainActor.run {
                            modelManagementState.modelState = .unloaded
                            modelManagementState.hasModelLoadError = true
                            modelManagementState.modelLoadError = "모델 로드 실패: \(error.localizedDescription)"
                            modelManagementState.loadingProgressValue = 0.0
                            isLoadingModel = false
                        }
                        return
                    }
                }

                // 모델 로딩 성공
                await MainActor.run {
                    // 모델 정보 업데이트 및 완료 상태 설정
                    modelManagementState.availableLanguages = Constants.languages.map { $0.key }.sorted()
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
    func updateProgressBar(startProgress: Float = 0.0, targetProgress: Float, maxTime: TimeInterval) async {
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
    
    /// 모델 삭제 (선택 모델 또는 직접 지정)
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
                
                print("모델 삭제 완료: \(model)")
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
            print("최대 동시 다운로드 수에 도달했습니다")
            return
        }
        
        // 다운로드 시작 전 디스크 공간 확인
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("문서 디렉토리를 찾을 수 없습니다")
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
                let resourceValues = try documents.resourceValues(forKeys: [.volumeAvailableCapacityKey])
                guard let availableSpace = resourceValues.volumeAvailableCapacity else {
                    await MainActor.run {
                        self.modelManagementState.downloadErrors[model] = "디스크 공간을 확인할 수 없습니다"
                    }
                    return
                }
                
                // 모델 크기 예상치 계산 (안전 마진 20% 추가)
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
                    let errorMessage = String(format: "디스크 공간이 부족합니다. 필요: %.1f GB, 가용: %.1f GB", requiredGB, availableGB)
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
                        
                        // 작업이 취소되었는지 확인
                        if Task.isCancelled {
                            return
                        }
                        
                        // 진행률 업데이트 최적화 (너무 빈번한 업데이트 방지)
                        let currentTime = Date()
                        if currentTime.timeIntervalSince(lastUpdateTime) >= progressUpdateInterval {
                            Task { @MainActor in
                                self.modelManagementState.downloadProgress[model] = Float(progress.fractionCompleted)
                                
                                // 다운로드 중 디스크 공간 재확인 (50% 이상 다운로드된 경우에만)
                                if progress.fractionCompleted > 0.5 {
                                    if let resourceValues = try? documents.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
                                       let currentSpace = resourceValues.volumeAvailableCapacity,
                                       currentSpace < Int64(Double(estimatedSize) * (1.0 - progress.fractionCompleted)) {
                                        self.modelManagementState.downloadErrors[model] = "다운로드 중 디스크 공간이 부족해졌습니다"
                                        self.modelManagementState.currentDownloadingModels.remove(model)
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
                print("모델 다운로드 취소됨: \(model)")
                await cleanupPartialDownload(model)
            } catch {
                print("모델 다운로드 실패: \(error.localizedDescription)")
                await MainActor.run {
                    self.modelManagementState.downloadErrors[model] = "다운로드 실패: \(error.localizedDescription)"
                    self.modelManagementState.currentDownloadingModels.remove(model)
                    self.modelManagementState.downloadProgress[model] = nil
                    
                    if self.modelManagementState.currentDownloadingModels.isEmpty {
                        self.modelManagementState.isDownloading = false
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
        await MainActor.run { [weak self] in
            guard let self = self else { return }
            
            // 상태 업데이트
            self.modelManagementState.downloadProgress[model] = nil
            self.modelManagementState.currentDownloadingModels.remove(model)
            self.modelManagementState.downloadTasks[model] = nil
            
            // 모든 다운로드가 취소되었는지 확인
            if self.modelManagementState.currentDownloadingModels.isEmpty {
                self.modelManagementState.isDownloading = false
            }
        }
        
        // 부분적으로 다운로드된 파일 삭제
        let modelFolder = URL(fileURLWithPath: modelManagementState.localModelPath).appendingPathComponent(model)
        if FileManager.default.fileExists(atPath: modelFolder.path) {
            do {
                try FileManager.default.removeItem(at: modelFolder)
                print("부분 다운로드 파일 삭제 완료: \(model)")
            } catch {
                print("부분 다운로드 파일 삭제 실패: \(error.localizedDescription)")
            }
        }
    }
    
    /// 다운로드 취소
    func cancelDownload(_ model: String) {
        guard let task = modelManagementState.downloadTasks[model],
              modelManagementState.currentDownloadingModels.contains(model) else {
            return
        }
        
        print("다운로드 취소 요청: \(model)")
        
        // 작업 취소
        task.cancel()
        
        // UI 즉시 업데이트
        Task { @MainActor in
            modelManagementState.downloadProgress[model] = nil
            modelManagementState.currentDownloadingModels.remove(model)
            modelManagementState.downloadTasks[model] = nil
            
            // 모든 다운로드가 취소되었는지 확인
            if modelManagementState.currentDownloadingModels.isEmpty {
                modelManagementState.isDownloading = false
            }
        }
        
        // 부분 다운로드 파일 비동기 정리 시작
        Task {
            await cleanupPartialDownload(model)
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
            
            // 파일을 임포트한 후 바로 총 재생 시간을 확인하고 업데이트
            do {
                let audioAsset = AVURLAsset(url: selectedFileURL)
                let duration = try await audioAsset.load(.duration)
                let durationInSeconds = CMTimeGetSeconds(duration)
                
                // 재생 시간 업데이트 (재생 시작 전에 미리 설정)
                audioState.totalDuration = durationInSeconds
                audioPlayer?.currentTime = 0.0
                print("오디오 파일 재생 시간: \(durationInSeconds)초")
                
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
                print("오디오 파일 정보 읽기 오류: \(error.localizedDescription)")
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
        var peakLevel: Float = -160  // 초기값 (dB 단위)
        
        // 오디오 길이 기반 간격 계산
        let duration = player.duration
        let interval = duration / Double(sampleCount)
        
        // 전체 오디오 구간 분석 (무음 재생)
        player.volume = 0  // 소리 없이 분석
        player.play()
        
        for i in 0..<sampleCount {
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
        let estimatedLUFS = avgLevel + 10  // 간단한 변환식
        
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
        print("오디오 분석 - 평균 레벨: \(avgLevel) dB, 추정 LUFS: \(estimatedLUFS), 피크: \(peakLevel) dB")
        print("노멀라이제이션 계수: \(normalizedVolumeFactor)")
        
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
                guard let self = self, let player = self.audioPlayer else { return }
                
                self.currentPlayerTime = player.currentTime
                
                // 재생이 끝났는지 확인
                if !player.isPlaying && self.audioState.isPlaying {
                    self.audioState.isPlaying = false
                    // 재생이 끝났을 때만 처음 위치로 리셋
                    if player.currentTime >= player.duration - 0.1 {
                        player.currentTime = 0.0
                        self.currentPlayerTime = 0.0
                    }
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
        audioState.isPlaying = false
        
        // 타이머 정리
        audioState.playbackTimer?.invalidate()
        playbackTimerCancellable?.cancel()
    }
    
    /// 재생 위치 이동 (특정 시간으로 이동)
    func seekToPosition(_ position: Double) {
        guard let player = audioPlayer else { return }
        player.currentTime = position
        
        // 재생 중이었다면 계속 재생
        if audioState.isPlaying {
            player.play()
        }
        
        // 다음 UI 업데이트 사이클에서 모든 View에 변경 사항 알림
        objectWillChange.send()
    }
    
    /// 라인 내에서 특정 비율 위치로 이동 (WaveFormView에서 사용)
    func seekToPositionInLine(lineIndex: Int, secondsPerLine: Double, ratio: Double, totalDuration: Double) {
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
                print("파형 업데이트 완료: \(waveformSamples.count) 샘플, 총 시간: \(audioState.totalDuration)초")
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
    
    // MARK: - Drag and drop
    /// 파일 드래그 앤 드롭 메소드
    func handleDroppedFiles(providers: [NSItemProvider]) {
        // 첫 번째 파일만 처리
        guard let provider = providers.first else { return }
        
        // 드래그 앤 드롭 상태 해제
        DispatchQueue.main.async {
            self.uiState.isTargeted = false
        }
        
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] (item, error) in
            guard let self = self else { return }
            
            if let urlData = item as? Data,
               let url = URL(dataRepresentation: urlData, relativeTo: nil) {
                
                // 메인 스레드에서 파일 처리
                DispatchQueue.main.async {
                    // 파일 접근 권한 확보
                    let shouldStopAccessing = url.startAccessingSecurityScopedResource()
                    
                    // 기존 오디오 플레이어 정리
                    self.stopImportedAudio()
                    self.audioPlayer = nil
                    
                    // 파일 이름 저장
                    self.audioState.audioFileName = url.deletingPathExtension().lastPathComponent
                    
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
                            print("오디오 파일 로드 오류: \(error.localizedDescription)")
                        }
                    }
                    
                    // 파일 접근 권한 해제
                    if shouldStopAccessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
            } else {
                print("파일 드랍 처리 실패: \(error?.localizedDescription ?? "Unknown error")")
            }
        }
    }
    
    /// 로컬 및 원격 모델 목록 업데이트
    func fetchModels() {
        print("모델 목록 가져오기 시작...")
        
        // 상태 초기화
        modelManagementState.availableModels = []
        modelManagementState.modelSizes = [:] // 모델 크기 정보 초기화
        
        // 에러 상태 초기화
        modelManagementState.hasModelLoadError = false
        modelManagementState.modelLoadError = nil
        
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let modelPath = documents.appendingPathComponent(modelManagementState.modelStorage).path
            print("모델 경로 확인: \(modelPath)")
            
            // 디렉토리가 없으면 생성
            if !FileManager.default.fileExists(atPath: modelPath) {
                do {
                    try FileManager.default.createDirectory(at: URL(fileURLWithPath: modelPath), withIntermediateDirectories: true)
                    print("모델 디렉토리 생성: \(modelPath)")
                } catch {
                    print("모델 디렉토리 생성 실패: \(error.localizedDescription)")
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
                    let fullPath = URL(fileURLWithPath: modelPath).appendingPathComponent(fileName).path
                    var isDir: ObjCBool = false
                    if fileManager.fileExists(atPath: fullPath, isDirectory: &isDir) {
                        return isDir.boolValue
                    }
                    return false
                }
                print("로컬 모델 목록: \(downloadedModels)")
                
                // 로컬 모델 및 크기 정보 갱신
                for model in downloadedModels {
                    let modelFolderURL = URL(fileURLWithPath: modelPath).appendingPathComponent(model)
                    
                    // 모델 크기 계산
                    let totalSize = calculateFolderSize(url: modelFolderURL)
                    modelManagementState.modelSizes[model] = totalSize
                    
                    if !modelManagementState.localModels.contains(model) {
                        modelManagementState.localModels = downloadedModels
                    }
                }
            } catch {
                print("로컬 모델 목록 조회 실패: \(error.localizedDescription)")
            }
        }
        
        modelManagementState.localModels = WhisperKit.formatModelFiles(modelManagementState.localModels)
        for model in modelManagementState.localModels where !modelManagementState.availableModels.contains(model) {
            modelManagementState.availableModels.append(model)
        }
        
        print("로컬에서 찾은 모델: \(modelManagementState.localModels)")
        print("이전에 선택한 모델: \(selectedModel)")
        
        Task {
            // 원격 모델 목록 가져오기 시도
            var supportedModels: [String] = []
            var disabledModels: [String] = []
            
            let modelSupport = await WhisperKit.recommendedRemoteModels()
            supportedModels = modelSupport.supported
            disabledModels = modelSupport.disabled
            print("WhisperKit에서 모델 목록 가져옴: \(supportedModels.count)개")
            
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
                
                print("업데이트된 사용 가능 모델 수: \(modelManagementState.availableModels.count)")
                objectWillChange.send() // UI 갱신 강제
            }
        }
    }
    
    /// 폴더 크기 계산 함수
    private func calculateFolderSize(url: URL) -> Int64 {
        let fileManager = FileManager.default
        var folderSize: Int64 = 0
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            
            for fileURL in contents {
                let fileAttributes = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                
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
