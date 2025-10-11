//
//  AudioControlView.swift
//  WhisperCaptionPro
//
//  Created by 조형구 on 4/14/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct AudioControlView: View {
    @ObservedObject var contentViewModel: ContentViewModel
    @ObservedObject var playbackState: AudioPlaybackState
    @Environment(\.colorScheme) private var colorScheme

    init(contentViewModel: ContentViewModel) {
        self.contentViewModel = contentViewModel
        self.playbackState = contentViewModel.audioPlaybackState
    }

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
                        // 파일 삭제 버튼
                        Button {
                            contentViewModel.deleteImportedAudio()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                Text("Delete")
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(.red)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.audioControlBackground(for: colorScheme))

                    // 오디오 파형 표시
                    if !contentViewModel.audioState.waveformSamples.isEmpty {
                        VStack(spacing: 0) {
                            // 재생 진행 상태 표시 (파형 + 시간 표시)
                            ZStack(alignment: .top) {
                                VStack(spacing: 0) {
                                    // 파형 영역 (시간 표시 없음)
                                    ZStack {
                                        WaveFormView(
                                            contentViewModel: contentViewModel
                                        )

                                        // 드래그 중일 때 파형 위에 오버레이 표시
                                        if contentViewModel.uiState.isTargeted {
                                            ZStack {
                                                // 배경 오버레이
                                                Rectangle()
                                                    .fill(Color.bluegray.opacity(0.25))
                                                    .overlay(
                                                        Rectangle()
                                                            .strokeBorder(
                                                                Color.blue,
                                                                lineWidth: 1.8
                                                            )
                                                    )

                                                // 콘텐츠
                                                VStack {
                                                    Image(systemName: "arrow.down.doc.fill")
                                                        .font(.largeTitle)
                                                        .foregroundColor(.secondary)
                                                        .padding(.bottom, 5)

                                                    Text("Replace with New File")
                                                        .font(.headline)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        }
                                    }

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
                                        .keyboardShortcut(.downArrow, modifiers: .command)

                                        Spacer(minLength: 8)

                                        // 재생 버튼
                                        Button {
                                            if contentViewModel.audioState.isPlaying {
                                                contentViewModel.pauseImportedAudio()
                                            } else {
                                                contentViewModel.playImportedAudio()
                                            }
                                        } label: {
                                            Image(systemName: contentViewModel.audioState
                                                .isPlaying ? "pause.fill" : "play.fill")
                                                .font(.system(size: 16))
                                                .foregroundColor(.primary)
                                                .frame(width: 32, height: 32)
                                        }
                                        .buttonStyle(LightModeButtonStyle())
                                        .keyboardShortcut(.space, modifiers: [])

                                        // 시간 표시 (HH:MM:SS.ss / HH:MM:SS.ss 형식)
                                        Text(
                                            "**\(formatTimeDetailed(playbackState.currentPlayerTime))** / \(formatTimeDetailed(contentViewModel.audioState.totalDuration))"
                                        )
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
                                        .keyboardShortcut(.upArrow, modifiers: .command)

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
                                    .background(Color
                                        .audioControlSectionBackground(for: colorScheme))
                                }
                            }
                        }
                    } else {
                        VStack(alignment: .center) {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }

                    HStack {
                        // 음량 조절
                        HStack(spacing: 6) {
                            // 음소거 토글 버튼
                            Button {
                                contentViewModel.toggleMute()
                            } label: {
                                Image(systemName: contentViewModel
                                    .isMuted ? "speaker.slash.fill" :
                                    getVolumeIcon(volume: contentViewModel.audioVolume))
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                                    .frame(width: 20, alignment: .leading)
                                    .contentTransition(.symbolEffect(.replace))
                                    .animation(
                                        .easeInOut(duration: 0.2),
                                        value: contentViewModel.isMuted
                                    )
                                    .animation(
                                        .easeInOut(duration: 0.2),
                                        value: contentViewModel.audioVolume
                                    )
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            .keyboardShortcut("m", modifiers: [])
                            .keyboardShortcut(KeyEquivalent("ㅡ"), modifiers: [])

                            // 볼륨 슬라이더
                            Slider(
                                value: Binding(
                                    get: {
                                        contentViewModel.isMuted ? 0 : contentViewModel.audioVolume
                                    },
                                    set: { newVolume in
                                        contentViewModel.setVolume(newVolume)
                                    }
                                ),
                                in: 0 ... 1,
                            )
                            .frame(width: 100)
                        }

                        Spacer()

                        // 단축키 안내 (중앙 정렬)
                        Text(
                            "Shortcut: Space (Play/Pause), ←/→(Navigate), ↑/↓(Volume), ⌘ + ↑/↓(Playback Speed)"
                        )
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)

                        Spacer()

                        // 재생 속도 표시 (좌측)
                        Text("Playback Speed: ")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                            + Text(contentViewModel.currentPlaybackRateText())
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.audioControlBackground(for: colorScheme))
                }
                .background(Color.audioControlContainerBackground(for: colorScheme))
            } else {
                AudioPlaceholderView(isTargeted: contentViewModel.uiState.isTargeted)
            }
            // 하단 컨드롤러
            ControlsView(viewModel: contentViewModel)
        }
        .onDrop(of: [UTType.fileURL.identifier],
                isTargeted: $contentViewModel.uiState.isTargeted) { providers in
            contentViewModel.handleDroppedFiles(providers: providers)
            return true
        }
    }

    // 여기에 볼륨 아이콘 선택 함수 추가
    private func getVolumeIcon(volume: Double) -> String {
        if volume <= 0 {
            return "speaker.slash.fill"
        } else if volume < 0.33 {
            return "speaker.wave.1.fill"
        } else if volume < 0.66 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }
}

// 라이트 모드 버튼 스타일
struct LightModeButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ?
                    Color.audioControlDivider(for: colorScheme) :
                    Color.clear
            )
            .cornerRadius(4)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

#Preview {
    AudioControlView(contentViewModel: ContentViewModel())
}
