//
//  AudioControlView.swift
//  WhisperCaptionPro
//
//  Created by 조형구 on 4/14/25.
//

import SwiftUI

struct AudioControlView: View {
    @ObservedObject var contentViewModel: ContentViewModel
    @State private var isViewActive: Bool = true
    
    // 시간 포맷팅 함수 (소수점 둘째자리까지 포함)
    private func formatTimeDetailed(_ timeInSeconds: Double) -> String {
        let hours = Int(timeInSeconds) / 3600
        let minutes = (Int(timeInSeconds) % 3600) / 60
        let seconds = Int(timeInSeconds) % 60
        let milliseconds = Int((timeInSeconds - Double(Int(timeInSeconds))) * 100)
        
        return String(format: "%02d:%02d:%02d.%02d", hours, minutes, seconds, milliseconds)
    }
    
    // 간단한 시간 포맷팅 함수
    private func formatTime(_ timeInSeconds: Double) -> String {
        let minutes = Int(timeInSeconds) / 60
        let seconds = Int(timeInSeconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 오디오 파일 정보 및 컨트롤 섹션
            if contentViewModel.audioState.importedAudioURL != nil {
                VStack(spacing: 0) {
                    // 파일 이름 표시 (라이트 모드 스타일)
                    HStack {
                        Image(systemName: "waveform")
                            .foregroundColor(.blue)
                        Text(contentViewModel.audioState.audioFileName)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.95, green: 0.95, blue: 0.97))
                    
                    // 오디오 파형 표시
                    if !contentViewModel.audioState.waveformSamples.isEmpty {
                        VStack(spacing: 0) {
                            // 재생 진행 상태 표시 (파형 + 시간 표시)
                            ZStack(alignment: .top) {
                                VStack(spacing: 0) {
                                    // 파형 영역 (시간 표시 없음)
                                    WaveFormView(
                                        viewModel: contentViewModel,
                                        samples: contentViewModel.audioState.waveformSamples,
                                        currentTime: contentViewModel.audioState.currentPlaybackTime,
                                        totalDuration: contentViewModel.audioState.totalDuration,
                                        onSeek: { position in
                                            contentViewModel.seekToPosition(position)
                                        }
                                    )

                                    
                                    // 트랜스포트 컨트롤 바 (라이트 모드 스타일)
                                    HStack(spacing: 0) {
                                        Spacer()
                                        
                                        // 뒤로 감기 버튼
                                        Button {
                                            contentViewModel.skipBackward()
                                        } label: {
                                            Image(systemName: "gobackward.5")
                                                .font(.system(size: 16))
                                                .foregroundColor(.primary)
                                                .frame(width: 32, height: 32)
                                        }
                                        .buttonStyle(LightModeButtonStyle())
                                        .keyboardShortcut(.leftArrow, modifiers: [])
                                        
                                        Spacer(minLength: 8)
                                        
                                        // 느리게 재생 버튼 
                                        Button {
                                            contentViewModel.changePlaybackRate(faster: false)
                                        } label: {
                                            Image(systemName: "tortoise.fill")
                                                .font(.system(size: 16))
                                                .foregroundColor(.primary)
                                                .frame(width: 32, height: 32)
                                        }
                                        .buttonStyle(LightModeButtonStyle())
                                        .keyboardShortcut(.downArrow, modifiers: [])
                                        
                                        Spacer(minLength: 8)
                                        
                                        // 재생 버튼
                                        Button {
                                            if contentViewModel.audioState.isPlaying {
                                                contentViewModel.pauseImportedAudio()
                                            } else {
                                                contentViewModel.playImportedAudio()
                                            }
                                        } label: {
                                            Image(systemName: contentViewModel.audioState.isPlaying ? "pause.fill" : "play.fill")
                                                .font(.system(size: 16))
                                                .foregroundColor(.primary)
                                                .frame(width: 32, height: 32)
                                        }
                                        .buttonStyle(LightModeButtonStyle())
                                        .keyboardShortcut(.space, modifiers: [])
                                        
                                        // 시간 표시 (HH:MM:SS.ss / HH:MM:SS.ss 형식)
                                        Text("**\(formatTimeDetailed(contentViewModel.audioState.currentPlaybackTime))** / \(formatTimeDetailed(contentViewModel.audioState.totalDuration))")
                                            .font(.system(size: 20, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .frame(minWidth: 150)
                                            .padding(.horizontal, 8)
                                        
                                        // 정지 버튼
                                        Button {
                                            contentViewModel.stopImportedAudio()
                                        } label: {
                                            Image(systemName: "stop.fill")
                                                .font(.system(size: 16))
                                                .foregroundColor(.primary)
                                                .frame(width: 32, height: 32)
                                        }
                                        .buttonStyle(LightModeButtonStyle())
                                        
                                        Spacer(minLength: 8)
                                        
                                        // 빠르게 재생 버튼
                                        Button {
                                            contentViewModel.changePlaybackRate(faster: true)
                                        } label: {
                                            Image(systemName: "hare.fill")
                                                .font(.system(size: 16))
                                                .foregroundColor(.primary)
                                                .frame(width: 32, height: 32)
                                        }
                                        .buttonStyle(LightModeButtonStyle())
                                        .keyboardShortcut(.upArrow, modifiers: [])
                                        
                                        Spacer(minLength: 8)
                                        
                                        // 앞으로 감기 버튼
                                        Button {
                                            contentViewModel.skipForward()
                                        } label: {
                                            Image(systemName: "goforward.5")
                                                .font(.system(size: 16))
                                                .foregroundColor(.primary)
                                                .frame(width: 32, height: 32)
                                        }
                                        .buttonStyle(LightModeButtonStyle())
                                        .keyboardShortcut(.rightArrow, modifiers: [])
                                        
                                        Spacer()
                                    }
                                    .padding(.vertical, 4)
                                    .background(Color(red: 0.93, green: 0.93, blue: 0.95))
                                }
                            }
                        }
                    } else {
                        ZStack {
                            Rectangle()
                                .fill(Color(red: 0.98, green: 0.98, blue: 0.98))
                                .frame(height: 120)
                            
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                                .scaleEffect(1.2)
                        }
                    }
                    
                    // 추가 정보 표시 영역 (현재 재생 속도)
                    HStack {
                        Text("재생 속도: ")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                        + Text(contentViewModel.currentPlaybackRateText())
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        // 단축키 안내
                        Text("단축키: 스페이스바(재생/정지), ←/→(이동), ↑/↓(속도)")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                        
                        Spacer()
                        
                        // 파일 삭제 버튼
                        Button {
                            contentViewModel.deleteImportedAudio()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                Text("삭제")
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(.red)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.95, green: 0.95, blue: 0.97))
                }
                .background(Color.white)
            }
        }
    }
}

// 라이트 모드 버튼 스타일
struct LightModeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ?
                Color(red: 0.9, green: 0.9, blue: 0.9) :
                Color.clear
            )
            .cornerRadius(4)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

#Preview {
    AudioControlView(contentViewModel: ContentViewModel())
}
