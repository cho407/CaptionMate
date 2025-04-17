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
                    Text("Device Model: \(WhisperKit.deviceName())")
                    Text("OS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)")
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
                if viewModel.uiState.isTranscribingView{
                    VStack(alignment: .leading) {
                        TranscriptionView(viewModel: viewModel)
                    }
                } else {
                    AudioControlView(contentViewModel: viewModel)
                }
                ControlsView(viewModel: viewModel)
            }
            .toolbar {
                ToolbarItem {
                    Button("Export Subtitle") {
                        Task {
                            await viewModel.exportTranscription()
                        }
                    }
                }
            }
        }
        .onAppear {
            viewModel.fetchModels()
        }
        // 볼륨 증가 (위쪽 화살표)
        .onKeyPress(.upArrow) { 
            if viewModel.audioState.importedAudioURL != nil {
                let newVolume = min(1.0, viewModel.audioVolume + 0.05)
                viewModel.setVolume(newVolume)
                return .handled
            }
            return .ignored
        }
        // 볼륨 감소 (아래쪽 화살표)
        .onKeyPress(.downArrow) { 
            if viewModel.audioState.importedAudioURL != nil {
                let newVolume = max(0.0, viewModel.audioVolume - 0.05)
                viewModel.setVolume(newVolume)
                return .handled
            }
            return .ignored
        }
    }
}

#Preview {
    ContentView(viewModel: ContentViewModel())
        .frame(width: 800, height: 500)
}
