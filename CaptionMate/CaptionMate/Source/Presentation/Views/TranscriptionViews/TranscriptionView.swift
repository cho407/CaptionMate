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
//  TranscriptionView.swift
//  CaptionMate
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
