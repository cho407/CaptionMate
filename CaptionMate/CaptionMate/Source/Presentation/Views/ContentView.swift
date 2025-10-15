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
        .alert("Language Changed", isPresented: $viewModel.uiState.isLanguageChanged) {
            Button("OK") {}
        } message: {
            Text("The language has been changed.")
        }
        .onAppear {
            viewModel.fetchModels()
            // 앱 시작 시 이전 세션의 모든 임시 파일 정리
            Task {
                await viewModel.performStartupCleanup()
            }
        }
    }
}

#Preview {
    ContentView(viewModel: ContentViewModel())
        .frame(width: 800, height: 500)
}
