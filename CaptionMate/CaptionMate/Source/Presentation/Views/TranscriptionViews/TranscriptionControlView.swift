//
//  Copyright 2025 Harrison Cho
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

//
//  TranscriptionControlView.swift
//  CaptionMate
//
//  Created by 조형구 on 6/13/25.
//

import SwiftUI

struct TranscriptionControlView: View {
    @ObservedObject var viewModel: ContentViewModel
    let disableColor: Color = .brightGray
    @State private var showDiagnostics = false
    var body: some View {
        VStack {
            DisclosureGroup("Decoder Diagnostics", isExpanded: $showDiagnostics) {
                HStack(spacing: 12) {
                    Text("\(viewModel.transcriptionState.effectiveRealTimeFactor, specifier: "%.3f") RTF")
                    Spacer()
                    Text("\(viewModel.transcriptionState.effectiveSpeedFactor, specifier: "%.1f") Speed Factor")
                        .lineLimit(1)
                    Spacer()
                    Text("\(viewModel.transcriptionState.tokensPerSecond, specifier: "%.0f") tok/s")
                    Spacer()
                    Text("First token: \(viewModel.transcriptionState.firstTokenTime - viewModel.transcriptionState.pipelineStart, specifier: "%.2f")s")
                }
                .font(.caption.monospacedDigit())
            }
            .padding()
            .frame(maxWidth: .infinity)
            Divider()
            HStack {
                Button {
                    guard viewModel.confirmDiscardingUnsavedChanges() else { return }
                    withAnimation {
                        viewModel.resetState()
                    }
                } label: {
                    Text("Back")
                        .font(.headline)
                        .foregroundStyle(viewModel.audioState.isTranscribing ? disableColor : .red)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                }
                .lineLimit(1)
                .disabled(viewModel.audioState.isTranscribing)
                .accessibilityIdentifier("transcription.backButton")
                .padding()

                Spacer()

                // 자막 내보내기 버튼
                Button {
                    viewModel.refreshSubtitleQualityIssues()
                    viewModel.uiState.showSubtitleReview = true
                } label: {
                    HStack {
                        if viewModel.isExporting {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                        Label(
                            viewModel.isExporting ? "Exporting" : "Export Subtitle",
                            systemImage: "laptopcomputer.and.arrow.down"
                        )
                        .font(.headline)
                        .padding(8)
                    }
                }
                .environment(\.locale, .init(identifier: viewModel.appLanguage))
                .disabled(viewModel.transcriptionResult == nil || viewModel.isExporting ||
                    viewModel.isSpeakerDiarizationBusy)
                .accessibilityIdentifier("transcription.exportButton")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
    }
}

#Preview {
    TranscriptionControlView(viewModel: ContentViewModel())
}
