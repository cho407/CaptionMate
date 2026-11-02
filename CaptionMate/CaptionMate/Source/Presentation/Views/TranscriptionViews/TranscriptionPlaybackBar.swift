//
//  Copyright 2026 Harrison Cho
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//       http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import SwiftUI

struct TranscriptionPlaybackBar: View {
    @ObservedObject var viewModel: ContentViewModel
    @ObservedObject private var playbackState: AudioPlaybackState

    init(viewModel: ContentViewModel) {
        self.viewModel = viewModel
        playbackState = viewModel.audioPlaybackState
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Button { viewModel.skipBackward() } label: {
                    Label("Skip Back 5 Seconds", systemImage: "gobackward.5")
                        .labelStyle(.iconOnly)
                }
                Button {
                    if viewModel.audioState.isPlaying {
                        viewModel.pauseImportedAudio()
                    } else {
                        viewModel.playImportedAudio()
                    }
                } label: {
                    Label(
                        viewModel.audioState.isPlaying ? LocalizedStringKey("Pause") : LocalizedStringKey("Play"),
                        systemImage: viewModel.audioState.isPlaying ? "pause.fill" : "play.fill"
                    )
                    .labelStyle(.iconOnly)
                    .frame(width: 18)
                }
                .accessibilityIdentifier("transcription.playPauseButton")
                Button { viewModel.skipForward() } label: {
                    Label("Skip Forward 5 Seconds", systemImage: "goforward.5")
                        .labelStyle(.iconOnly)
                }
                Slider(
                    value: Binding(
                        get: { min(playbackState.currentPlayerTime, max(0, viewModel.audioState.totalDuration)) },
                        set: { viewModel.seekToPosition($0) }
                    ),
                    in: 0 ... max(viewModel.audioState.totalDuration, 0.01)
                )
                .accessibilityLabel(Text("Playback Position"))
                .accessibilityIdentifier("transcription.playbackPosition")
                Text(verbatim: "\(timeText(playbackState.currentPlayerTime)) / \(timeText(viewModel.audioState.totalDuration))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("transcription.playbackTime")
                Menu {
                    ForEach(viewModel.playbackRates.indices, id: \.self) { index in
                        Button(String(format: "%.2fx", viewModel.playbackRates[index])) {
                            viewModel.selectPlaybackRate(at: index)
                        }
                    }
                } label: {
                    Text(verbatim: viewModel.currentPlaybackRateText())
                        .monospacedDigit()
                }
                .fixedSize()
                .accessibilityLabel(Text("Playback Speed: "))
            }
            .buttonStyle(.borderless)
            .disabled(!viewModel.canPlayImportedAudio)
            if !viewModel.canPlayImportedAudio {
                Text("Original audio is missing. You can still edit and export subtitles.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("transcription.playbackBar")
    }

    private func timeText(_ seconds: Double) -> String {
        let seconds = Int(max(0, seconds.isFinite ? seconds : 0))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
