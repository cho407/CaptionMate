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
