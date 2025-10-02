//
//  StateModels.swift
//  WhisperCaptionPro
//
//  Created by 조형구 on 3/25/25.
//

import AVFoundation
import Combine
import CoreML
import SwiftUI
import WhisperKit

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
    var lastBufferSize: Int = 0
    var lastConfirmedSegmentEndSeconds: Float = 0
    var bufferEnergy: [Float] = []
    var bufferSeconds: Double = 0
    var confirmedSegments: [TranscriptionSegment] = []
    var unconfirmedSegments: [TranscriptionSegment] = []
    
    // 전사 처리 시간 및 속도 관련
    var effectiveRealTimeFactor: TimeInterval = 0
    var effectiveSpeedFactor: TimeInterval = 0
    var totalInferenceTime: TimeInterval = 0

}

struct ModelManagementState {
    var modelStorage: String = "huggingface/models/argmaxinc/whisperkit-coreml"
    var appStartTime: Date = Date()
    var modelState: ModelState = .unloaded
    var localModels: [String] = []
    var localModelPath: String = ""
    var availableModels: [String] = []
    var availableLanguages: [String] = []
    var disabledModels: [String] = WhisperKit.recommendedModels().disabled
    
    // 에러 관련 상태
    var modelLoadError: String? = nil
    var hasModelLoadError: Bool = false
    
    // 다운로드/로딩 진행률
    var loadingProgressValue: Float = 0.0
    var specializationProgressRatio: Float = 0.2
    var downloadProgress: [String: Float] = [:]
    var downloadTasks: [String: Task<Void, Never>] = [:]
    
    // 모델 크기 정보
    var modelSizes: [String: Int64] = [:]
    var totalDownloadSize: Int64 = 0
    var downloadedSize: Int64 = 0
    
    // 다운로드 상태
    var isDownloading: Bool = false
    var currentDownloadingModels: Set<String> = []
    var downloadErrors: [String: String] = [:]
    var cancellingModels: Set<String> = [] // 취소 중인 모델들
    var lastProgressCallbackTime: [String: Date] = [:] // Progress 콜백 마지막 활동 시간
    var downloadProgressObjects: [String: Progress] = [:] // NSProgress 객체 저장
    
    // 다운로드 관리 - 제한 해제
    var maxConcurrentDownloads: Int = Int.max
    
    // UI 상태
    var modelFilter: String = ""
    
    var folder: URL?
    
    // 모델 정보 포맷 헬퍼 함수들
    func formattedModelSize(for model: String) -> String {
        guard let size = modelSizes[model] else { return "알 수 없음" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    func formattedDownloadProgress(for model: String) -> String {
        guard let progress = downloadProgress[model] else { return "0%" }
        return String(format: "%.1f%%", progress * 100)
    }
    
    func isDownloading(model: String) -> Bool {
        return currentDownloadingModels.contains(model)
    }
    
    func isCancelling(model: String) -> Bool {
        return cancellingModels.contains(model)
    }
    
    func canStartDownload(model: String) -> Bool {
        return !isDownloading(model: model) && !isCancelling(model: model) && !localModels.contains(model)
    }
    
    func displayName(for model: String) -> String {
        return model.components(separatedBy: "_").dropFirst().joined(separator: " ")
    }
}

struct AudioState {
    var isTranscribing: Bool = false
    var audioFileName: String = "Subtitle"
    var waveformSamples: [Float] = []
    
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
}
