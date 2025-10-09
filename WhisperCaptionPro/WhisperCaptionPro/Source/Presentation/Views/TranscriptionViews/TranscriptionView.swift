//
//  TranscriptionView.swift
//  WhisperCaptionPro
//
//  Created by 조형구 on 3/21/25.
//

import SwiftUI

struct TranscriptionView: View {
    @ObservedObject var viewModel: ContentViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack {
            ScrollView {
                VStack(alignment: .leading) {
                    ForEach(Array(viewModel.transcriptionState.confirmedSegments.enumerated()),
                            id: \.element) { _, segment in
                        let timestampText = viewModel
                            .enableTimestamps ?
                            TimeInterval(segment.start)
                            .formatTimeRange(to: TimeInterval(segment.end)) :
                            ""
                        Text(timestampText + segment.text)
                            .font(.headline)
                            .fontWeight(.bold)
                            .tint(.green)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if viewModel.enableDecoderPreview {
                        Text("\(viewModel.transcriptionState.currentText)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .background(Color.transcriptionBackground(for: colorScheme))
            .frame(maxWidth: .infinity)
            .defaultScrollAnchor(.bottom)
            .textSelection(.enabled)

            if let whisperKit = viewModel.whisperKit,
               viewModel.audioState.isTranscribing,
               let task = viewModel.uiState.transcribeTask,
               !task.isCancelled,
               whisperKit.progress.fractionCompleted < 1 {
                HStack {
                    ProgressView(whisperKit.progress)
                        .progressViewStyle(.linear)
                        .labelsHidden()
                        .padding(.leading)

                    Button {
                        viewModel.uiState.transcribeTask?.cancel()
                        viewModel.uiState.transcribeTask = nil
                        viewModel.resetState()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .padding(.trailing)
                }
            }
            TranscriptionControlView(viewModel: viewModel)
        }
    }
}

#Preview {
    TranscriptionView(viewModel: ContentViewModel())
}
