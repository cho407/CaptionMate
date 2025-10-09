//
//  TranscriptionControlView.swift
//  WhisperCaptionPro
//
//  Created by 조형구 on 6/13/25.
//

import SwiftUI

struct TranscriptionControlView: View {
    @ObservedObject var viewModel: ContentViewModel
    let disableColor: Color = .brightGray
    var body: some View {
        VStack {
            HStack {
                Text(
                    "\(viewModel.transcriptionState.effectiveRealTimeFactor, specifier: "%.3f") RTF"
                )
                .font(.body)
                Spacer()
                Text(
                    "\(viewModel.transcriptionState.effectiveSpeedFactor, specifier: "%.1f") Speed Factor"
                )
                .font(.body)
                .lineLimit(1)
                Spacer()
                Text("\(viewModel.transcriptionState.tokensPerSecond, specifier: "%.0f") tok/s")
                    .font(.body)
                Spacer()
                Text(
                    "First token: \(viewModel.transcriptionState.firstTokenTime - viewModel.transcriptionState.pipelineStart, specifier: "%.2f")s"
                )
                .font(.body)
            }
            .padding()
            .frame(maxWidth: .infinity)
            Divider()
            HStack {
                Button {
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
                .padding()

                Spacer()

                // 자막 내보내기 버튼
                Button {
                    Task {
                        await viewModel.exportTranscription()
                    }
                } label: {
                    HStack {
                        Label("Export Subtitle", systemImage: "laptopcomputer.and.arrow.down")
                            .font(.headline)
                            .padding(8)
                    }
                }
                .environment(\.locale, .init(identifier: viewModel.appLanguage))
                .disabled(viewModel.transcriptionResult == nil)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
    }
}

#Preview {
    TranscriptionControlView(viewModel: ContentViewModel())
}
