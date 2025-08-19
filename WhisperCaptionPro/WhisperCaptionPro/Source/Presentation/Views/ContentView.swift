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
            NavigationStack{
                AudioControlView(contentViewModel: viewModel)

            }
            .navigationBarBackButtonHidden(true)
        }
        .sheet(isPresented: $viewModel.uiState.isModelmanagerViewPresented) {
            ModelManagerView(viewModel: viewModel)
                .frame(minWidth: 600, minHeight: 500)
        }
        .onAppear {
            viewModel.fetchModels()
        }
    }
}

#Preview {
    ContentView(viewModel: ContentViewModel())
        .frame(width: 800, height: 500)
}
