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
    
    // Eager mode 관련
    var eagerResults: [TranscriptionResult?] = []
    var prevResult: TranscriptionResult? = nil
    var lastAgreedSeconds: Float = 0.0
    var prevWords: [WordTiming] = []
    var lastAgreedWords: [WordTiming] = []
    var confirmedWords: [WordTiming] = []
    var confirmedText: String = ""
    var hypothesisWords: [WordTiming] = []
    var hypothesisText: String = ""
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
    
    // 다운로드/로딩 진행률
    var loadingProgressValue: Float = 0.0
    var specializationProgressRatio: Float = 0.7
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
    
    // 다운로드 관리
    var maxConcurrentDownloads: Int = 2
    
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
    
    func canStartDownload(model: String) -> Bool {
        return !isDownloading(model: model) && !localModels.contains(model) && currentDownloadingModels.count < maxConcurrentDownloads
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
}
