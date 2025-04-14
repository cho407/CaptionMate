//
//  AudioControlView.swift
//  WhisperCaptionPro
//
//  Created by 조형구 on 4/14/25.
//

import SwiftUI

struct AudioControlView: View {
    @ObservedObject var contentViewModel: ContentViewModel
    
    // 시간 포맷팅 함수
    private func formatTime(_ timeInSeconds: Double) -> String {
        let minutes = Int(timeInSeconds) / 60
        let seconds = Int(timeInSeconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var body: some View {
        ScrollView{
            // 오디오 파일 정보 및 컨트롤 섹션
            if contentViewModel.audioState.importedAudioURL != nil {
                VStack(spacing: 12) {
                    // 파일 이름 표시
                    HStack {
                        Image(systemName: "waveform")
                            .foregroundColor(.blue)
                        Text(contentViewModel.audioState.audioFileName)
                            .font(.headline)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal)
                    
                    // 오디오 파형 표시
                    if !contentViewModel.audioState.waveformSamples.isEmpty {
                        VStack(spacing: 0) {
                            // 재생 진행 상태 표시
                            HStack {
                                Text(formatTime(contentViewModel.audioState.currentPlaybackTime))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                WaveFormView(
                                    samples: contentViewModel.audioState.waveformSamples,
                                    currentTime: contentViewModel.audioState.currentPlaybackTime,
                                    totalDuration: contentViewModel.audioState.totalDuration,
                                    onSeek: { position in
                                        contentViewModel.seekToPosition(position)
                                    }
                                )
                                .frame(height: 60)
                                
                                Text(formatTime(contentViewModel.audioState.totalDuration))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                        }
                        .padding(.horizontal)
                    } else {
                        ProgressView()
                    }
                    
                    // 오디오 컨트롤
                    HStack(spacing: 16) {
                        // 재생/일시정지 버튼
                        Button {
                            if contentViewModel.audioState.isPlaying {
                                contentViewModel.pauseImportedAudio()
                            } else {
                                contentViewModel.playImportedAudio()
                            }
                        } label: {
                            Image(systemName: contentViewModel.audioState.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.blue)
                        }
                        
                        // 정지 버튼
                        Button {
                            contentViewModel.stopImportedAudio()
                        } label: {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.orange)
                        }
                        
                        // 파일 삭제 버튼
                        Button {
                            contentViewModel.deleteImportedAudio()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.red)
                        }
                        .help("앱에서 오디오 파일 제거")
                        
                        Spacer()
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)
            }
        }
    }
}

#Preview {
    AudioControlView(contentViewModel: ContentViewModel())
}
