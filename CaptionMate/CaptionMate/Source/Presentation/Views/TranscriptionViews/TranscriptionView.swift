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
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading) {
                        if !viewModel.transcriptionState.confirmedSegments.isEmpty {
                            SubtitleSearchReplaceBar(viewModel: viewModel)
                                .padding(.bottom, 8)
                        }

                        if !viewModel.uiState.subtitleQualityIssues.isEmpty {
                            SubtitleQualitySummaryView(viewModel: viewModel)
                                .padding(.bottom, 8)
                        }

                        if viewModel.enableSpeakerDiarization,
                           (viewModel.transcriptionState.speakerDiarization.isRunning ||
                               viewModel.transcriptionState.speakerDiarization.errorMessage != nil) {
                            SpeakerDiarizationStatusView(viewModel: viewModel)
                                .padding(.bottom, 8)
                        }

                        if viewModel.enableSpeakerDiarization,
                           !viewModel.transcriptionState.confirmedSegments.isEmpty {
                            SpeakerNameEditorView(viewModel: viewModel)
                                .padding(.bottom, 8)
                        }

                        ForEach(viewModel.transcriptionState.confirmedSegments.indices, id: \.self) { index in
                            let segment = viewModel.transcriptionState.confirmedSegments[index]
                            let issues = viewModel.qualityIssues(forSegmentAt: index)
                            let timestampText = viewModel
                                .enableTimestamps ?
                                TimeInterval(segment.start)
                                .formatTimeRange(to: TimeInterval(segment.end)) :
                                ""
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    if !timestampText.isEmpty {
                                        Text(timestampText)
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }

                                    if viewModel.enableSpeakerDiarization ||
                                        viewModel.speakerAssignment(forSegmentAt: index) != nil {
                                        SpeakerAssignmentMenu(viewModel: viewModel, index: index)
                                    }

                                    ForEach(issues.prefix(3)) { issue in
                                        SubtitleIssueBadge(issue: issue)
                                    }

                                    Spacer()
                                    SubtitleSegmentToolButtons(viewModel: viewModel, index: index)
                                }

                                if viewModel.enableTimestamps {
                                    SubtitleTimingFieldsView(viewModel: viewModel, index: index)
                                }

                                TextEditor(
                                    text: Binding(
                                        get: {
                                            guard viewModel.transcriptionState.confirmedSegments
                                                .indices.contains(index) else {
                                                return ""
                                            }
                                            return viewModel.transcriptionState.confirmedSegments[index].text
                                        },
                                        set: { newText in
                                            viewModel.updateTranscriptionSegmentText(
                                                at: index,
                                                text: newText
                                            )
                                        }
                                    )
                                )
                                .font(.headline)
                                .fontWeight(.bold)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 52)
                                .padding(6)
                                .background(Color(nsColor: .textBackgroundColor).opacity(0.55))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(
                                            issuesBorderColor(for: issues),
                                            lineWidth: issues.isEmpty ? 0 : 1
                                        )
                                )
                            }
                            .id(index)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
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
                .accessibilityIdentifier("transcription.view")
                .onChange(of: viewModel.uiState.focusedSubtitleSegmentIndex) { _, index in
                    guard let index else { return }
                    withAnimation {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
            }
            .background(Color.transcriptionBackground(for: colorScheme))
            .frame(maxWidth: .infinity)
            .defaultScrollAnchor(.bottom)
            .textSelection(.enabled)

            if let whisperKit = viewModel.whisperKit,
               viewModel.isTranscriptionProgressVisible {
                HStack {
                    ProgressView(whisperKit.progress)
                        .progressViewStyle(.linear)
                        .labelsHidden()
                        .padding(.leading)

                    Button {
                        viewModel.cancelTranscription()
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
        .sheet(isPresented: $viewModel.uiState.showSubtitleReview) {
            SubtitleReviewSheet(viewModel: viewModel)
                .frame(minWidth: 480, minHeight: 420)
                .environment(\.locale, .init(identifier: viewModel.appLanguage))
        }
    }

    private func issuesBorderColor(for issues: [SubtitleQualityIssue]) -> Color {
        if issues.contains(where: { $0.severity == .error }) {
            return .red.opacity(0.7)
        }
        if issues.contains(where: { $0.severity == .warning }) {
            return .orange.opacity(0.7)
        }
        if !issues.isEmpty {
            return .blue.opacity(0.45)
        }
        return .clear
    }
}

private struct SubtitleQualitySummaryView: View {
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        let errors = viewModel.uiState.subtitleQualityIssues
            .filter { $0.severity == .error }.count
        let warnings = viewModel.uiState.subtitleQualityIssues
            .filter { $0.severity == .warning }.count
        let infos = viewModel.uiState.subtitleQualityIssues
            .filter { $0.severity == .info }.count

        HStack(spacing: 8) {
            Image(systemName: summaryIconName(errors: errors, warnings: warnings))
                .foregroundStyle(summaryColor(errors: errors, warnings: warnings))
            Text(summaryText(errors: errors, warnings: warnings, infos: infos))
                .font(.subheadline.weight(.medium))
            Spacer()
            Button {
                viewModel.uiState.showSubtitleReview = true
            } label: {
                Label("Review", systemImage: "list.bullet.rectangle")
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("subtitleQuality.summary")
    }

    private func summaryIconName(errors: Int, warnings: Int) -> String {
        if errors > 0 { return "xmark.octagon.fill" }
        if warnings > 0 { return "exclamationmark.triangle.fill" }
        return "info.circle.fill"
    }

    private func summaryColor(errors: Int, warnings: Int) -> Color {
        if errors > 0 { return .red }
        if warnings > 0 { return .orange }
        return .blue
    }

    private func summaryText(errors: Int, warnings: Int, infos: Int) -> LocalizedStringKey {
        if errors > 0 {
            return "\(errors) errors · \(warnings) warnings"
        }
        if warnings > 0 {
            return "\(warnings) warnings"
        }
        return "\(infos) notes"
    }
}

private struct SubtitleIssueBadge: View {
    let issue: SubtitleQualityIssue

    private var color: Color {
        switch issue.severity {
        case .error:
            return .red
        case .warning:
            return .orange
        case .info:
            return .blue
        }
    }

    private var symbolName: String {
        switch issue.severity {
        case .error:
            return "xmark.octagon.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .info:
            return "info.circle.fill"
        }
    }

    var body: some View {
        Image(systemName: symbolName)
            .foregroundStyle(color)
            .font(.caption)
            .help("\(issue.message): \(issue.suggestion)")
    }
}

private struct SubtitleSegmentToolButtons: View {
    @ObservedObject var viewModel: ContentViewModel
    let index: Int

    var body: some View {
        HStack(spacing: 6) {
            Button {
                viewModel.nudgeTranscriptionSegment(at: index, by: -0.1)
            } label: {
                Image(systemName: "backward.frame")
            }
            .help("Nudge Earlier")

            Button {
                viewModel.nudgeTranscriptionSegment(at: index, by: 0.1)
            } label: {
                Image(systemName: "forward.frame")
            }
            .help("Nudge Later")

            Menu {
                Button("Start -0.1s") {
                    viewModel.adjustTranscriptionSegmentStart(at: index, by: -0.1)
                }
                Button("Start +0.1s") {
                    viewModel.adjustTranscriptionSegmentStart(at: index, by: 0.1)
                }
                Divider()
                Button("End -0.1s") {
                    viewModel.adjustTranscriptionSegmentEnd(at: index, by: -0.1)
                }
                Button("End +0.1s") {
                    viewModel.adjustTranscriptionSegmentEnd(at: index, by: 0.1)
                }
            } label: {
                Image(systemName: "timer")
            }
            .menuStyle(.borderlessButton)
            .help("Adjust Timing")

            Button {
                viewModel.mergeTranscriptionSegment(at: index, withNext: false)
            } label: {
                Image(systemName: "arrow.up.square")
            }
            .disabled(index == 0)
            .help("Merge Previous")

            Button {
                viewModel.splitTranscriptionSegment(at: index)
            } label: {
                Image(systemName: "scissors")
            }
            .help("Split")

            Button {
                viewModel.mergeTranscriptionSegment(at: index, withNext: true)
            } label: {
                Image(systemName: "arrow.down.square")
            }
            .disabled(index >= viewModel.transcriptionState.confirmedSegments.count - 1)
            .help("Merge Next")

            Button {
                viewModel.deleteTranscriptionSegment(at: index)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .help("Delete")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
    }
}

private struct SubtitleTimingFieldsView: View {
    @ObservedObject var viewModel: ContentViewModel
    let index: Int

    var body: some View {
        HStack(spacing: 8) {
            Label("Timing", systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Start", value: Binding(
                get: {
                    guard viewModel.transcriptionState.confirmedSegments.indices.contains(index)
                    else { return 0 }
                    return Double(viewModel.transcriptionState.confirmedSegments[index].start)
                },
                set: { value in
                    viewModel.setTranscriptionSegmentStart(at: index, to: Float(value))
                }
            ), format: .number.precision(.fractionLength(2)))
            .textFieldStyle(.roundedBorder)
            .frame(width: 74)
            .help("Start Time")

            Text("to")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("End", value: Binding(
                get: {
                    guard viewModel.transcriptionState.confirmedSegments.indices.contains(index)
                    else { return 0 }
                    return Double(viewModel.transcriptionState.confirmedSegments[index].end)
                },
                set: { value in
                    viewModel.setTranscriptionSegmentEnd(at: index, to: Float(value))
                }
            ), format: .number.precision(.fractionLength(2)))
            .textFieldStyle(.roundedBorder)
            .frame(width: 74)
            .help("End Time")

            Spacer()
        }
        .controlSize(.small)
    }
}

private struct SubtitleSearchReplaceBar: View {
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Find", text: Binding(
                get: { viewModel.uiState.subtitleSearchText },
                set: { viewModel.uiState.subtitleSearchText = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 120)

            TextField("Replace", text: Binding(
                get: { viewModel.uiState.subtitleReplaceText },
                set: { viewModel.uiState.subtitleReplaceText = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 120)

            Text("\(viewModel.subtitleSearchMatchCount())")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)

            Button {
                viewModel.focusNextSubtitleSearchMatch()
            } label: {
                Image(systemName: "arrow.down.circle")
            }
            .help("Next Match")

            Button {
                viewModel.replaceNextSubtitleMatch()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .help("Replace Next")

            Button("All") {
                viewModel.replaceAllSubtitleMatches()
            }
            .help("Replace All")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SpeakerDiarizationStatusView: View {
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        HStack(spacing: 8) {
            if viewModel.transcriptionState.speakerDiarization.isRunning {
                ProgressView(value: viewModel.transcriptionState.speakerDiarization.progress)
                    .frame(width: 90)
                Label("Analyzing Speakers", systemImage: "person.2.wave.2")
                    .font(.caption.weight(.medium))
            } else if let errorMessage = viewModel.transcriptionState.speakerDiarization.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("speakerDiarization.status")
    }
}

private struct SpeakerNameEditorView: View {
    @ObservedObject var viewModel: ContentViewModel

    private var speakerIDs: [Int] {
        viewModel.availableSpeakerIDs()
    }

    private var columns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 170), spacing: 8),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Speakers", systemImage: "person.2.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("speakerEditor.container")
                Spacer()
                Picker("", selection: $viewModel.speakerDiarizationSpeakerCount) {
                    ForEach(0 ... 8, id: \.self) { count in
                        Text(viewModel.speakerCountOptionTitleKey(for: count)).tag(count)
                    }
                }
                .frame(width: 96)
                .disabled(viewModel.transcriptionState.speakerDiarization.isRunning)
                .accessibilityLabel(Text("Speaker Count"))
                .accessibilityIdentifier("speakerEditor.speakerCountPicker")
                Button {
                    viewModel.reanalyzeSpeakersForCurrentAudio()
                } label: {
                    Label("Reanalyze", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(viewModel.transcriptionState.speakerDiarization.isRunning ||
                    viewModel.audioState.importedAudioURL == nil)
                .help("Run speaker analysis again")
                .accessibilityIdentifier("speakerEditor.reanalyzeButton")
            }
            Text("Rename speakers used in subtitles and exports.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !speakerIDs.isEmpty {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(speakerIDs, id: \.self) { speakerID in
                        HStack(spacing: 6) {
                            Text("Speaker \(speakerID + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 70, alignment: .leading)
                            TextField(
                                LocalizedStringKey("Speaker \(speakerID + 1)"),
                                text: Binding(
                                    get: { viewModel.speakerName(for: speakerID) },
                                    set: { viewModel.setSpeakerName($0, for: speakerID) }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel(Text("Name for \(viewModel.defaultSpeakerName(for: speakerID))"))
                            .accessibilityIdentifier("speakerEditor.nameField.\(speakerID)")
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SpeakerAssignmentMenu: View {
    @ObservedObject var viewModel: ContentViewModel
    let index: Int

    private var assignment: SpeakerSegmentAssignment? {
        viewModel.speakerAssignment(forSegmentAt: index)
    }

    private func speakerNameText(for speakerID: Int) -> Text {
        let customName = viewModel.speakerName(for: speakerID)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard customName.isEmpty else { return Text(verbatim: customName) }
        return Text("Speaker \(speakerID + 1)")
    }

    private var selectedSpeakerText: Text {
        guard let assignment else { return Text("No Speaker") }
        return speakerNameText(for: assignment.speakerID)
    }

    private var selectedSpeakerAccessibilityName: String {
        guard let assignment else { return "No Speaker" }
        return viewModel.speakerDisplayName(for: assignment.speakerID)
    }

    var body: some View {
        Menu {
            Button {
                viewModel.setSpeakerAssignment(at: index, speakerID: nil)
            } label: {
                Label("No Speaker", systemImage: assignment == nil ? "checkmark" : "person.slash")
            }

            ForEach(viewModel.availableSpeakerIDs(), id: \.self) { speakerID in
                Button {
                    viewModel.setSpeakerAssignment(at: index, speakerID: speakerID)
                } label: {
                    Label {
                        speakerNameText(for: speakerID)
                    } icon: {
                        Image(systemName: assignment?.speakerID == speakerID ? "checkmark" : "person")
                    }
                }
            }
        } label: {
            Label {
                selectedSpeakerText
            } icon: {
                Image(systemName: "person.wave.2.fill")
            }
                .font(.caption.weight(.semibold))
                .foregroundStyle(assignment == nil ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 160, alignment: .leading)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.borderlessButton)
        .help("Assign Speaker")
        .accessibilityLabel(
            Text("Speaker assignment for segment \(index + 1): \(selectedSpeakerAccessibilityName)")
        )
        .accessibilityHint(Text("Choose the speaker name used for this subtitle and export."))
        .accessibilityIdentifier("speakerAssignmentMenu.segment.\(index)")
    }
}

private struct SubtitleReviewSheet: View {
    @ObservedObject var viewModel: ContentViewModel
    @Environment(\.dismiss) private var dismiss

    private var hasBlockingIssues: Bool {
        viewModel.uiState.subtitleQualityIssues.contains { $0.severity == .error }
    }

    private var filteredIssues: [SubtitleQualityIssue] {
        viewModel.uiState.subtitleQualityIssues.filter {
            viewModel.uiState.subtitleIssueFilter.matches($0)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Review Before Export", systemImage: "checklist")
                    .font(.title3.weight(.semibold))
                    .accessibilityIdentifier("subtitleReview.sheet")
                Spacer()
            }

            Picker("", selection: Binding(
                get: { viewModel.uiState.subtitleIssueFilter },
                set: { viewModel.uiState.subtitleIssueFilter = $0 }
            )) {
                ForEach(SubtitleIssueFilter.allCases) { filter in
                    Text(filter.titleKey).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(Text("Subtitle Review Filter"))
            .accessibilityIdentifier("subtitleReview.filterPicker")

            if filteredIssues.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No issues in this filter")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("subtitleReview.emptyFilter")
            } else {
                List(filteredIssues) { issue in
                    HStack(alignment: .top, spacing: 10) {
                        SubtitleIssueBadge(issue: issue)
                            .padding(.top, 3)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Segment \(issue.segmentIndex + 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(LocalizedStringKey(issue.message))
                                .font(.subheadline.weight(.medium))
                            Text(LocalizedStringKey(issue.suggestion))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            viewModel.focusSubtitleIssue(issue)
                            dismiss()
                        } label: {
                            Image(systemName: "arrow.right.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Go to Segment")
                        .accessibilityLabel(Text("Go to Segment \(issue.segmentIndex + 1)"))
                        .accessibilityIdentifier("subtitleReview.goToSegment.\(issue.segmentIndex)")
                    }
                    .padding(.vertical, 4)
                    .accessibilityIdentifier(
                        "subtitleReview.issue.segment.\(issue.segmentIndex).\(issue.kind)"
                    )
                }
            }

            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .accessibilityIdentifier("subtitleReview.cancelButton")
                Button {
                    viewModel.applySubtitleReviewQuickFixes()
                } label: {
                    Label("Quick Fix", systemImage: "wand.and.stars")
                }
                .disabled(viewModel.uiState.subtitleQualityIssues.isEmpty)
                .accessibilityIdentifier("subtitleReview.quickFixButton")
                Spacer()
                if hasBlockingIssues {
                    Text("Fix errors before export")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("subtitleReview.blockingMessage")
                }
                Button("Export Anyway") {
                    viewModel.uiState.showSubtitleReview = false
                    Task {
                        await viewModel.exportTranscription(skipQualityReview: true)
                    }
                }
                .disabled(hasBlockingIssues)
                .accessibilityIdentifier("subtitleReview.exportAnywayButton")
            }
        }
        .padding()
    }
}

#Preview {
    TranscriptionView(viewModel: ContentViewModel())
}
