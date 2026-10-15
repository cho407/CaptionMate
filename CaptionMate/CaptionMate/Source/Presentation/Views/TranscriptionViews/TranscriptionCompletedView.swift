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

import SwiftUI
import WhisperKit

struct TranscriptionReadBlock: Identifiable, Equatable {
    let id: Int
    let start: Float
    var end: Float
    var text: String
    let speakerID: Int?

    static func grouped(
        segments: [TranscriptionSegment],
        speakerAssignments: [SpeakerSegmentAssignment?]
    ) -> [Self] {
        var blocks: [Self] = []
        blocks.reserveCapacity(segments.count)

        for (index, segment) in segments.enumerated() {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            let speakerID = speakerAssignments.indices.contains(index)
                ? speakerAssignments[index]?.speakerID
                : nil

            if let lastIndex = blocks.indices.last,
               blocks[lastIndex].speakerID == speakerID {
                blocks[lastIndex].end = max(blocks[lastIndex].end, segment.end)
                blocks[lastIndex].text += " \(text)"
            } else {
                blocks.append(
                    Self(
                        id: index,
                        start: segment.start,
                        end: segment.end,
                        text: text,
                        speakerID: speakerID
                    )
                )
            }
        }

        return blocks
    }
}

struct TranscriptionModeHeader: View {
    @ObservedObject var viewModel: ContentViewModel

    private var title: LocalizedStringKey {
        viewModel.uiState.isSubtitleEditing
            ? "Edit Subtitles"
            : "Transcription Complete"
    }

    static func shouldShow(
        isTranscribing: Bool,
        isEditing: Bool,
        hasSegments: Bool
    ) -> Bool {
        !isTranscribing && (isEditing || hasSegments)
    }

    private var shouldShowHeader: Bool {
        Self.shouldShow(
            isTranscribing: viewModel.audioState.isTranscribing,
            isEditing: viewModel.uiState.isSubtitleEditing,
            hasSegments: !viewModel.transcriptionState.confirmedSegments.isEmpty
        )
    }

    var body: some View {
        if shouldShowHeader {
            HStack(spacing: 12) {
                Label(
                    title,
                    systemImage: viewModel.uiState.isSubtitleEditing
                        ? "pencil.line"
                        : "checkmark.circle.fill"
                )
                .font(.headline)
                .foregroundStyle(
                    viewModel.uiState.isSubtitleEditing ? Color.primary : Color.green
                )

                Spacer()

                if viewModel.uiState.isSubtitleEditing {
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            viewModel.applySubtitleEdits()
                        }
                    } label: {
                        Label("Apply Changes", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .accessibilityIdentifier("transcription.applyEditsButton")
                } else {
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            viewModel.beginSubtitleEditing()
                        }
                    } label: {
                        Label("Edit Subtitles", systemImage: "pencil")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("transcription.editButton")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial)
        }
    }
}

struct TranscriptionCompletedView: View {
    @ObservedObject var viewModel: ContentViewModel
    @Environment(\.colorScheme) private var colorScheme

    private var readBlocks: [TranscriptionReadBlock] {
        TranscriptionReadBlock.grouped(
            segments: viewModel.transcriptionState.confirmedSegments,
            speakerAssignments: viewModel.transcriptionState.speakerAssignments
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if viewModel.enableSpeakerDiarization,
                   viewModel.transcriptionState.speakerDiarization.isRunning ||
                   viewModel.transcriptionState.speakerDiarization.errorMessage != nil {
                    SpeakerDiarizationStatusView(viewModel: viewModel)
                }

                ForEach(readBlocks) { block in
                    VStack(alignment: .leading, spacing: 6) {
                        if block.speakerID != nil || viewModel.enableTimestamps {
                            HStack(spacing: 10) {
                                if let speakerID = block.speakerID {
                                    speakerLabel(for: speakerID)
                                        .accessibilityIdentifier(
                                            "transcription.completedSpeaker.\(block.id)"
                                        )
                                }

                                if viewModel.enableTimestamps {
                                    Text(
                                        TimeInterval(block.start)
                                            .formatTimeRange(to: TimeInterval(block.end))
                                    )
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                                }
                            }
                        }

                        Text(block.text)
                            .font(.body)
                            .lineSpacing(3)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel(Text(verbatim: block.text))
                            .accessibilityIdentifier(
                                "transcription.completedText.\(block.id)"
                            )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("transcription.completedBlock.\(block.id)")
                }

                if viewModel.enableDecoderPreview {
                    Text(viewModel.transcriptionState.currentText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .background(Color.transcriptionBackground(for: colorScheme))
        .frame(maxWidth: .infinity)
        .defaultScrollAnchor(.bottom)
        .textSelection(.enabled)
        .accessibilityIdentifier("transcription.completedView")
    }

    @ViewBuilder
    private func speakerLabel(for speakerID: Int) -> some View {
        let customName = viewModel.speakerName(for: speakerID)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        Label {
            if customName.isEmpty {
                Text("Speaker \(speakerID + 1)")
            } else {
                Text(verbatim: customName)
            }
        } icon: {
            Image(systemName: "person.fill")
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}
