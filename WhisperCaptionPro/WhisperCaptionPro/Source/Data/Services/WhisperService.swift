//
//  WhisperService.swift
//  WhisperCaptionPro
//
//  Created by 조형구 on 3/3/25.
//

import AVFoundation
import CoreML
import Foundation
import WhisperKit

/// WhisperKit 관련 기능을 캡슐화하는 서비스
class WhisperService {
    var whisperKit: WhisperKit?

    /// WhisperKit 인스턴스 초기화
    func initializeWhisper(with computeOptions: ModelComputeOptions) async throws -> WhisperKit {
        let config = WhisperKitConfig(
            computeOptions: computeOptions,
            verbose: true,
            logLevel: .debug,
            prewarm: false,
            load: false,
            download: false
        )
        let kit = try await WhisperKit(config)
        whisperKit = kit
        return kit
    }

    /// 모델 다운로드 또는 로드 후 초기화 및 전사 준비
    func loadModel(model: String,
                   localModels: [String],
                   localModelPath: String,
                   repoName: String,
                   computeOptions: ModelComputeOptions,
                   specializationProgressRatio: Float,
                   updateProgress: @escaping (Float, ModelState) -> Void) async throws
        -> WhisperKit {
        let kit = try await initializeWhisper(with: computeOptions)
        var folder: URL?

        // 로컬에 모델이 존재하면 로드, 없으면 다운로드
        if localModels.contains(model) {
            folder = URL(fileURLWithPath: localModelPath).appendingPathComponent(model)
        } else {
            folder = try await WhisperKit.download(
                variant: model,
                from: repoName,
                progressCallback: { progress in
                    DispatchQueue.main.async {
                        updateProgress(
                            Float(progress.fractionCompleted) * specializationProgressRatio,
                            .downloading
                        )
                    }
                }
            )
        }

        await MainActor.run {
            updateProgress(specializationProgressRatio, .downloaded)
        }

        if let modelFolder = folder {
            kit.modelFolder = modelFolder
            await MainActor.run {
                updateProgress(specializationProgressRatio, .prewarming)
            }
            try await kit.prewarmModels()
            await MainActor.run {
                updateProgress(
                    specializationProgressRatio + 0.9 * (1 - specializationProgressRatio),
                    .loading
                )
            }
            try await kit.loadModels()
        }

        return kit
    }

    /// 주어진 오디오 샘플 배열을 전사합니다.
    func transcribeAudioSamples(_ samples: [Float],
                                options: DecodingOptions,
                                decodingCallback: @escaping (TranscriptionProgress)
                                    -> Bool?) async throws -> TranscriptionResult? {
        guard let kit = whisperKit else { return nil }
        let results: [TranscriptionResult] = try await kit.transcribe(
            audioArray: samples,
            decodeOptions: options,
            callback: decodingCallback
        )
        return mergeTranscriptionResults(results)
    }

    // 추가적인 eager mode 전사 등 필요한 기능을 메서드로 구현 가능.
}
