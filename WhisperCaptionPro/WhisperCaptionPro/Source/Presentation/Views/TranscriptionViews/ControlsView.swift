//
//  ControlsView.swift
//  WhisperCaptionPro
//
//  Created by 조형구 on 3/21/25.
//

import SwiftUI

struct ControlsView: View {
    @ObservedObject var viewModel: ContentViewModel
    
    var body: some View {
        VStack {
            BasicSettingsView(viewModel: viewModel)
                        
            VStack {
                HStack {
                    Button {
                        viewModel.resetState()
                    } label: {
                        Label("Reset", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    
                    Spacer()
                    
                    Button {
                        viewModel.uiState.showAdvancedOptions.toggle()
                    } label: {
                        Label("Settings", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
                
                HStack {
                    Button {
                        withAnimation {
                            viewModel.selectFile()
                        }
                    } label: {
                        Text("Import File")
                            .font(.headline)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .cornerRadius(8)
                    }
                    .fileImporter(
                        isPresented: $viewModel.uiState.isFilePickerPresented,
                        allowedContentTypes: [.audio],
                        allowsMultipleSelection: false,
                        onCompletion: viewModel.handleFilePicker
                    )
                    .lineLimit(1)
                    .disabled(viewModel.audioState.isTranscribing || viewModel.modelManagementState.modelState != .loaded || viewModel.uiState.isTranscribingView)
                    .padding()
                    
                    Spacer()
                    
                    // 전사 시작 버튼
                    Button {
                        if let url = viewModel.audioState.importedAudioURL {
                            viewModel.transcribeFile(path: url.path)
                        }
                        viewModel.uiState.isTranscribingView = true
                    } label: {
                        Text("전사 시작")
                            .font(.headline)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .cornerRadius(8)
                    }
                    .lineLimit(1)
                    .disabled(viewModel.audioState.isTranscribing || viewModel.modelManagementState.modelState != .loaded || viewModel.audioState.importedAudioURL == nil)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .sheet(isPresented: $viewModel.uiState.showAdvancedOptions) {
            SettingsView(viewModel: viewModel)
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled)
                .presentationContentInteraction(.scrolls)
        }
    }
}

#Preview {
    ControlsView(viewModel: ContentViewModel())
}
