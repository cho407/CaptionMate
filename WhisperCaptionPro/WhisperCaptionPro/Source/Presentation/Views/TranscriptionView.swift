//
//  TranscriptionView.swift
//  WhisperCaptionPro
//
//  Created by 조형구 on 3/21/25.
//

import SwiftUI

struct TranscriptionView: View {
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        VStack {
            if !viewModel.bufferEnergy.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 1) {
                        let startIndex = max(viewModel.bufferEnergy.count - 300, 0)
                        ForEach(
                            Array(viewModel.bufferEnergy.enumerated())[startIndex...],
                            id: \.element
                        ) { _, energy in
                            ZStack {
                                RoundedRectangle(cornerRadius: 2)
                                    .frame(width: 2, height: CGFloat(energy) * 24)
                            }
                            .frame(maxHeight: 24)
                            .background(energy > Float(viewModel.silenceThreshold) ? Color.green
                                .opacity(0.2) : Color.red.opacity(0.2))
                        }
                    }
                }
                .defaultScrollAnchor(.trailing)
                .frame(height: 24)
                .scrollIndicators(.never)
            }

            ScrollView {
                VStack(alignment: .leading) {
                    if viewModel.enableEagerDecoding && viewModel.selectedTab == "Stream" {
                        let startSeconds = viewModel.eagerResults.first??.segments.first?.start ?? 0
                        let endSeconds = viewModel.lastAgreedSeconds > 0 ? viewModel
                            .lastAgreedSeconds : viewModel.eagerResults.last??.segments.last?
                            .end ?? 0
                        let timestampText = (viewModel.enableTimestamps && viewModel.eagerResults
                            .first != nil) ?
                            TimeInterval(startSeconds).formatTimeRange(to: TimeInterval(endSeconds)) :
                            ""
                        Text(
                            "\(timestampText) \(Text(viewModel.confirmedText).fontWeight(.bold))\(Text(viewModel.hypothesisText).fontWeight(.bold).foregroundColor(.gray))"
                        )
                        .font(.headline)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if viewModel.enableDecoderPreview {
                            Text("\(viewModel.currentText)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top)
                        }
                    } else {
                        ForEach(Array(viewModel.confirmedSegments.enumerated()),
                                id: \.element) { _, segment in
                            let timestampText = viewModel
                                .enableTimestamps ?
                                TimeInterval(segment.start).formatTimeRange(to: TimeInterval(segment.end)) :
                                ""
                            Text(timestampText + segment.text)
                                .font(.headline)
                                .fontWeight(.bold)
                                .tint(.green)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(Array(viewModel.unconfirmedSegments.enumerated()),
                                id: \.element) { _, segment in
                            let timestampText = viewModel
                                .enableTimestamps ?
                                TimeInterval(segment.start).formatTimeRange(to: TimeInterval(segment.end)) :
                                ""
                            Text(timestampText + segment.text)
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if viewModel.enableDecoderPreview {
                            Text("\(viewModel.currentText)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .defaultScrollAnchor(.bottom)
            .textSelection(.enabled)
            .padding()

            if let whisperKit = viewModel.whisperKit,
               viewModel.selectedTab != "Stream",
               viewModel.isTranscribing,
               let task = viewModel.transcribeTask,
               !task.isCancelled,
               whisperKit.progress.fractionCompleted < 1 {
                HStack {
                    ProgressView(whisperKit.progress)
                        .progressViewStyle(.linear)
                        .labelsHidden()
                        .padding(.horizontal)

                    Button {
                        viewModel.transcribeTask?.cancel()
                        viewModel.transcribeTask = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
            }
        }
    }
}

#Preview {
    TranscriptionView(viewModel: ContentViewModel())
}
