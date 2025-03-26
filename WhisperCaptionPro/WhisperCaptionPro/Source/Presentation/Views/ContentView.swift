//
//  ContentView.swift
//  WhisperCaptionPro
//
//  Created by 조형구 on 2/22/25.
//

import AVFAudio
import AVFoundation
import SwiftUI
import WhisperKit

struct ContentView: View {
    @StateObject var viewModel = ContentViewModel()

    var body: some View {
        NavigationSplitView(columnVisibility: $viewModel.uiState.columnVisibility) {
            VStack(alignment: .leading) {
                ModelSelectorView(viewModel: viewModel)
                    .padding(.vertical)
                ComputeUnitsView(viewModel: viewModel)
                    .disabled(viewModel.modelManagementState.modelState != .loaded && viewModel
                        .modelManagementState.modelState != .unloaded)
                    .padding(.bottom)

                List(viewModel.menu, selection: $viewModel.uiState.selectedCategoryId) { item in
                    HStack {
                        Image(systemName: item.image)
                        Text(item.name)
                            .font(.title3)
                            .bold()
                    }
                }
                .onChange(of: viewModel.uiState.selectedCategoryId) { newValue, _ in
                    viewModel.settings.selectedTab = viewModel.menu
                        .first(where: { $0.id == newValue })?
                        .name ?? "Transcribe"
                }
                .disabled(viewModel.modelManagementState.modelState != .loaded)
                .foregroundColor(viewModel.modelManagementState
                    .modelState != .loaded ? .secondary : .primary)

                Spacer()

                // 앱 및 디바이스 정보
                VStack(alignment: .leading, spacing: 4) {
                    let version = Bundle.main
                        .infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
                    let build = Bundle.main
                        .infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
                    Text("App Version: \(version) (\(build))")
                    #if os(iOS)
                        Text("Device Model: \(WhisperKit.deviceName())")
                        Text("OS Version: \(UIDevice.current.systemVersion)")
                    #elseif os(macOS)
                        Text("Device Model: \(WhisperKit.deviceName())")
                        Text("OS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)")
                    #endif
                }
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
                .padding(.vertical)
            }
            .navigationTitle("WhisperCaptionPro")
            .navigationSplitViewColumnWidth(min: 300, ideal: 350)
            .padding(.horizontal)
            Spacer()
        } detail: {
            VStack {
                #if os(iOS)
                    ModelSelectorView(viewModel: viewModel)
                        .padding()
                    TranscriptionView(viewModel: viewModel)
                #elseif os(macOS)
                    VStack(alignment: .leading) {
                        TranscriptionView(viewModel: viewModel)
                    }
                    .padding()
                #endif
                ControlsView(viewModel: viewModel)
            }
            .toolbar {
                ToolbarItem {
                    Button {
                        if !viewModel.settings.enableEagerDecoding {
                            let fullTranscript = formatSegments(
                                viewModel.transcriptionState.confirmedSegments + viewModel
                                    .transcriptionState.unconfirmedSegments,
                                withTimestamps: viewModel.settings.enableTimestamps
                            ).joined(separator: "\n")
                            #if os(iOS)
                                UIPasteboard.general.string = fullTranscript
                            #elseif os(macOS)
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(fullTranscript, forType: .string)
                            #endif
                        } else {
                            #if os(iOS)
                                UIPasteboard.general.string = viewModel.transcriptionState
                                    .confirmedText + viewModel
                                    .transcriptionState.hypothesisText
                            #elseif os(macOS)
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(
                                    viewModel.transcriptionState.confirmedText + viewModel
                                        .transcriptionState.hypothesisText,
                                    forType: .string
                                )
                            #endif
                        }
                    } label: {
                        Label("Copy Text", systemImage: "doc.on.doc")
                    }
                    .keyboardShortcut("c", modifiers: .command)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear {
            #if os(macOS)
                viewModel.uiState.selectedCategoryId = viewModel.menu
                    .first(where: { $0.name == viewModel.settings.selectedTab })?.id
            #else
                if UIDevice.current.userInterfaceIdiom == .pad {
                    viewModel.uiState.selectedCategoryId = viewModel.menu
                        .first(where: { $0.name == viewModel.settings.selectedTab })?.id
                }
            #endif
            viewModel.fetchModels()
        }
    }
}

#Preview {
    ContentView()
    #if os(macOS)
        .frame(width: 800, height: 500)
    #endif
}
