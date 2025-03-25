//
//  AppStorageManager.swift
//  WhisperCaptionPro
//
//  Created by 조형구 on 3/25/25.
//
import AVFoundation
import Combine
import CoreML
import SwiftUI
import WhisperKit

// MARK: - UIState Models

/// 앱 설정(사용자 선택, AppStorage 관련)
struct SettingsState {
    var selectedAudioInput: String = "No Audio Input"
    var selectedModel: String = WhisperKit.recommendedModels().default
    var selectedTab: String = "Transcribe"
    var selectedTask: String = "transcribe"
    var selectedLanguage: String = "english"
    var repoName: String = "argmaxinc/whisperkit-coreml"
    var enableTimestamps: Bool = true
    var enablePromptPrefill: Bool = true
    var enableCachePrefill: Bool = true
    var enableSpecialCharacters: Bool = false
    var enableEagerDecoding: Bool = false
    var enableDecoderPreview: Bool = true
    var temperatureStart: Double = 0
    var fallbackCount: Double = 5
    var compressionCheckWindow: Double = 60
    var sampleLength: Double = 224
    var silenceThreshold: Double = 0.3
    var realtimeDelayInterval: Double = 1
    var useVAD: Bool = true
    var tokenConfirmationsNeeded: Double = 2
    var concurrentWorkerCount: Double = 4
    var chunkingStrategy: ChunkingStrategy = .vad
    var encoderComputeUnits: MLComputeUnits = .cpuAndNeuralEngine
    var decoderComputeUnits: MLComputeUnits = .cpuAndNeuralEngine
}
