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
//  ContentView.swift
//  CaptionMate
//
//  Created by 조형구 on 2/22/25.
//

import AVFAudio
import AVFoundation
import SwiftUI
import WhisperKit

struct ContentView: View {
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        NavigationSplitView(columnVisibility: $viewModel.uiState.columnVisibility) {
            VStack(alignment: .leading) {
                ModelSelectorView(viewModel: viewModel)
                    .padding(.vertical)
                ComputeUnitsView(viewModel: viewModel)
                    .disabled(viewModel.modelManagementState.modelState != .loaded && viewModel
                        .modelManagementState.modelState != .unloaded)
                    .padding(.bottom)

                ProjectLibraryView(viewModel: viewModel)
                    .padding(.bottom)

                Spacer()

                // 앱 및 디바이스 정보
                VStack(alignment: .leading, spacing: 4) {
                    let version = Bundle.main
                        .infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
                    let build = Bundle.main
                        .infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
                    Text("App Version: \(version) (\(build))")
                }
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
                .padding(.vertical)
            }
            .navigationTitle("CaptionMate")
            .navigationSplitViewColumnWidth(min: 300, ideal: 350)
            .padding(.horizontal)
            Spacer()
        } detail: {
            NavigationStack {
                AudioControlView(contentViewModel: viewModel)
            }
            .navigationBarBackButtonHidden(true)
        }
        .sheet(isPresented: $viewModel.uiState.isModelmanagerViewPresented) {
            ModelManagerView(viewModel: viewModel)
                .frame(minWidth: 600, minHeight: 500)
                .environment(\.locale, .init(identifier: viewModel.appLanguage))
        }
        .sheet(isPresented: $viewModel.uiState.showFirstRunGuide) {
            FirstRunGuideView(viewModel: viewModel)
                .frame(minWidth: 420, minHeight: 300)
                .environment(\.locale, .init(identifier: viewModel.appLanguage))
        }
        .alert("Language Changed", isPresented: $viewModel.uiState.isLanguageChanged) {
            Button("OK") {}
        } message: {
            Text("The language has been changed.")
        }
        .onAppear {
            viewModel.fetchModels()
            viewModel.refreshProjectLibrary()
            viewModel.prepareDefaultSpeakerDiarizationModelIfNeeded()
            viewModel.presentFirstRunGuideIfNeeded()
#if DEBUG
            viewModel.activateSpeakerFixtureNavigationForUITestingIfNeeded()
#endif
            // 앱 시작 시 이전 세션의 오래된 임시 파일 정리
            Task {
                await viewModel.performStartupCleanup()
            }
        }
        .onDisappear {
            viewModel.prepareForClose()
        }
        .overlay(alignment: .top) {
            if let message = viewModel.uiState.userMessage {
                StatusBannerView(message: message) {
                    viewModel.dismissUserMessage()
                }
                .padding(.top, 10)
                .padding(.horizontal, 20)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.uiState.userMessage?.id)
    }
}

private struct ProjectLibraryView: View {
    @ObservedObject var viewModel: ContentViewModel
    @State private var pendingProjectDeletion: CaptionMateProjectSummary?
    @State private var pendingProjectOpen: CaptionMateProjectSummary?
    @State private var pendingProjectRename: CaptionMateProjectSummary?
    @State private var pendingAudioRelink: CaptionMateProjectSummary?
    @State private var projectRenameText = ""
    @State private var isAudioRelinkImporterPresented = false

    private var canSaveCurrentProject: Bool {
        !viewModel.transcriptionState.confirmedSegments.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Projects", systemImage: "folder")
                    .font(.headline)
                    .accessibilityIdentifier("projectLibrary.container")
                Spacer()
                Button {
                    viewModel.refreshProjectLibrary()
                } label: {
                    Label("Refresh Projects", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .help("Refresh Projects")
                .accessibilityLabel(Text("Refresh Projects"))
                .accessibilityIdentifier("projectLibrary.refreshButton")
                Button {
                    viewModel.saveCurrentProject()
                } label: {
                    Label("Save Project", systemImage: "square.and.arrow.down")
                        .labelStyle(.iconOnly)
                }
                .disabled(!canSaveCurrentProject || viewModel.projectLibraryState.isSaving)
                .help("Save Project")
                .accessibilityLabel(Text("Save Project"))
                .accessibilityIdentifier("projectLibrary.saveButton")
            }

            if let activeName = viewModel.projectLibraryState.activeProjectDisplayName {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(activeName)
                        .lineLimit(1)
                    Spacer()
                    if viewModel.hasUnsavedProjectChanges {
                        Label("Unsaved changes", systemImage: "pencil")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .labelStyle(.titleAndIcon)
                    } else if let lastSavedAt = viewModel.projectLibraryState.lastSavedAt {
                        Text(lastSavedAt, style: .time)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            } else if canSaveCurrentProject {
                Text("Unsaved transcript")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if viewModel.projectLibraryState.summaries.isEmpty {
                Text("No saved projects")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .accessibilityIdentifier("projectLibrary.emptyState")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(viewModel.projectLibraryState.summaries) { summary in
                            ProjectLibraryRow(
                                summary: summary,
                                isActive: viewModel.projectLibraryState.activeProjectID == summary.id,
                                openAction: {
                                    if viewModel.shouldConfirmOpeningProject(id: summary.id) {
                                        pendingProjectOpen = summary
                                    } else {
                                        viewModel.openProject(id: summary.id)
                                    }
                                },
                                renameAction: {
                                    projectRenameText = summary.displayName
                                    pendingProjectRename = summary
                                },
                                duplicateAction: {
                                    viewModel.duplicateProject(id: summary.id)
                                },
                                relinkAudioAction: {
                                    pendingAudioRelink = summary
                                    isAudioRelinkImporterPresented = true
                                },
                                deleteAction: {
                                    pendingProjectDeletion = summary
                                }
                            )
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .fileImporter(
            isPresented: $isAudioRelinkImporterPresented,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            guard let project = pendingAudioRelink else { return }
            defer {
                pendingAudioRelink = nil
            }

            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                viewModel.relinkProjectAudio(
                    id: project.id,
                    to: url,
                    needsSecurityScopedAccess: true
                )
            case .failure:
                break
            }
        }
        .alert(
            "Rename Project",
            isPresented: Binding(
                get: { pendingProjectRename != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingProjectRename = nil
                        projectRenameText = ""
                    }
                }
            )
        ) {
            TextField("Project Name", text: $projectRenameText)
            Button("Cancel", role: .cancel) {
                pendingProjectRename = nil
                projectRenameText = ""
            }
            Button("Rename") {
                guard let summary = pendingProjectRename else { return }
                if viewModel.renameProject(
                    id: summary.id,
                    displayName: projectRenameText
                ) {
                    pendingProjectRename = nil
                    projectRenameText = ""
                }
            }
        } message: {
            Text("Choose a short name for this saved subtitle project.")
        }
        .alert(
            "Delete This Project?",
            isPresented: Binding(
                get: { pendingProjectDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingProjectDeletion = nil
                    }
                }
            ),
            presenting: pendingProjectDeletion
        ) { summary in
            Button("Cancel", role: .cancel) {
                pendingProjectDeletion = nil
            }
            Button("Delete", role: .destructive) {
                viewModel.deleteProject(id: summary.id)
                pendingProjectDeletion = nil
            }
        } message: { summary in
            Text(
                "This removes the saved subtitle project from CaptionMate. Your original audio file is not deleted."
            )
            Text(summary.displayName)
        }
        .alert(
            "Save Changes Before Opening?",
            isPresented: Binding(
                get: { pendingProjectOpen != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingProjectOpen = nil
                    }
                }
            ),
            presenting: pendingProjectOpen
        ) { summary in
            Button("Cancel", role: .cancel) {
                pendingProjectOpen = nil
            }
            Button("Open Without Saving", role: .destructive) {
                viewModel.openProject(id: summary.id)
                pendingProjectOpen = nil
            }
            Button("Save and Open") {
                if viewModel.openProjectSavingCurrentChangesFirst(id: summary.id) {
                    pendingProjectOpen = nil
                }
            }
        } message: { summary in
            Text("Your current project has unsaved subtitle changes.")
            Text(summary.displayName)
        }
    }
}

private struct ProjectLibraryRow: View {
    let summary: CaptionMateProjectSummary
    let isActive: Bool
    let openAction: () -> Void
    let renameAction: () -> Void
    let duplicateAction: () -> Void
    let relinkAudioAction: () -> Void
    let deleteAction: () -> Void

    private var isMissingAudio: Bool {
        summary.sourceAudioPath != nil && !summary.sourceAudioExists
    }

    private var speakerNamesPreview: String? {
        let names = summary.speakerDisplayNames.prefix(3)
        guard !names.isEmpty else { return nil }
        let suffix = summary.speakerDisplayNames.count > names.count ? ", ..." : ""
        return names.joined(separator: ", ") + suffix
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: openAction) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: isActive ? "folder.fill" : "folder")
                        .foregroundStyle(isActive ? Color.accentColor : .secondary)
                        .frame(width: 18, height: 18)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(summary.displayName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 10) {
                            Label {
                                HStack(spacing: 2) {
                                    Text(summary.segmentCount, format: .number)
                                    Text("Segments")
                                }
                            } icon: {
                                Image(systemName: "text.alignleft")
                            }
                            .help("Segments")
                            .accessibilityLabel(Text("Segments"))

                            if summary.speakerCount > 0 {
                                Label {
                                    HStack(spacing: 2) {
                                        Text(summary.speakerCount, format: .number)
                                        Text("Speakers")
                                    }
                                } icon: {
                                    Image(systemName: "person.2")
                                }
                                .help("Speakers")
                                .accessibilityLabel(Text("Speakers"))
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                        if let speakerNamesPreview {
                            Text(speakerNamesPreview)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .accessibilityIdentifier("projectLibrary.speakerNames.\(summary.id)")
                        }

                        if let sourceAudioFileName = summary.sourceAudioFileName {
                            HStack(spacing: 4) {
                                Image(systemName: isMissingAudio ? "exclamationmark.triangle" : "waveform")
                                    .frame(width: 12)
                                if isMissingAudio {
                                    Text("Audio Missing")
                                } else {
                                    Text("Audio")
                                }
                                Text(verbatim: sourceAudioFileName)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .font(.caption2)
                            .foregroundStyle(isMissingAudio ? .orange : .secondary)
                            .accessibilityIdentifier("projectLibrary.audioStatus.\(summary.id)")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer()
                    Text(summary.updatedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("projectLibrary.open.\(summary.id)")

            Menu {
                Button(action: renameAction) {
                    Label("Rename Project", systemImage: "pencil")
                }
                Button(action: duplicateAction) {
                    Label("Duplicate Project", systemImage: "doc.on.doc")
                }
                Button(action: relinkAudioAction) {
                    Label(
                        isMissingAudio ? "Reconnect Audio" : "Relink Audio",
                        systemImage: "waveform.badge.plus"
                    )
                }
                Divider()
                Button(role: .destructive, action: deleteAction) {
                    Label("Delete Project", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .frame(width: 28, height: 28)
            .help("More Project Actions")
            .accessibilityLabel(Text("More Project Actions"))
            .accessibilityIdentifier("projectLibrary.actions.\(summary.id)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color.accentColor.opacity(0.10) : Color.clear)
        )
    }
}

private struct FirstRunGuideView: View {
    @ObservedObject var viewModel: ContentViewModel

    private var recommendedModel: String {
        WhisperKit.recommendedModels().default
    }

    private var recommendedModelIsLocal: Bool {
        viewModel.modelManagementState.localModels.contains(recommendedModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Ready CaptionMate", systemImage: "sparkles")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button {
                    viewModel.dismissFirstRunGuide()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
            }

            VStack(alignment: .leading, spacing: 12) {
                FirstRunChecklistRow(
                    symbol: recommendedModelIsLocal ? "checkmark.circle.fill" : "arrow.down.circle",
                    title: recommendedModelIsLocal ?
                        LocalizedStringKey("Recommended model is local") :
                        LocalizedStringKey("Recommended model"),
                    detail: Text(verbatim: viewModel.modelManagementState.displayName(for: recommendedModel))
                )
                FirstRunChecklistRow(
                    symbol: viewModel.modelManagementState.isSpeakerDiarizationModelReady ? "checkmark.circle.fill" : "person.2.wave.2",
                    title: "Speaker diarization",
                    detail: viewModel.modelManagementState.isSpeakerDiarizationModelReady ?
                        Text("Offline model is ready") :
                        Text("Default offline model · \(viewModel.modelManagementState.formattedSpeakerDiarizationModelSize)")
                )
                FirstRunChecklistRow(
                    symbol: "waveform",
                    title: "Audio",
                    detail: Text("Import one file or a batch queue.")
                )
                FirstRunChecklistRow(
                    symbol: "checklist",
                    title: "Subtitle review",
                    detail: Text("Fix quality warnings before export.")
                )
            }

            Spacer()

            HStack {
                Button("Later") {
                    viewModel.dismissFirstRunGuide()
                }
                Spacer()
                Button {
                    viewModel.dismissFirstRunGuide()
                    viewModel.uiState.isModelmanagerViewPresented = true
                } label: {
                    Label("Models", systemImage: "tray.full")
                }
                Button {
                    viewModel.prepareRecommendedModelFromGuide()
                } label: {
                    Label(
                        recommendedModelIsLocal ? "Load Model" : "Download Model",
                        systemImage: recommendedModelIsLocal ? "bolt.fill" : "arrow.down.circle.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
    }
}

private struct FirstRunChecklistRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: Text

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                detail
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct StatusBannerView: View {
    let message: UserMessage
    let onDismiss: () -> Void

    private var accentColor: Color {
        switch message.kind {
        case .info:
            return .blue
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    private var symbolName: String {
        switch message.kind {
        case .info:
            return "info.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbolName)
                .foregroundStyle(accentColor)
                .imageScale(.large)

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(message.title))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("statusBanner.title")
                if let detail = message.detail, !detail.isEmpty {
                    Text(LocalizedStringKey(detail))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .accessibilityIdentifier("statusBanner.detail")
                }
            }

            Spacer(minLength: 12)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .imageScale(.small)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: 520)
        .background(.regularMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(accentColor.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .accessibilityIdentifier("statusBanner")
    }
}

#Preview {
    ContentView(viewModel: ContentViewModel())
        .frame(width: 800, height: 500)
}
