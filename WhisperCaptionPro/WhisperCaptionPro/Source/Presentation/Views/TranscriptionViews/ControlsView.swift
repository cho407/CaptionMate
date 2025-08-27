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
                            .padding(8)
                    }
                    .fileImporter(
                        isPresented: $viewModel.uiState.isFilePickerPresented,
                        allowedContentTypes: [.audio],
                        allowsMultipleSelection: false,
                        onCompletion: viewModel.handleFilePicker
                    )
                    .lineLimit(1)
                    .disabled(viewModel.audioState.isTranscribing ||
                              viewModel.uiState.isTranscribingView)
                    .padding()
                    
                    Spacer()
                    Button("전사 시작") {
                        if let url = viewModel.audioState.importedAudioURL {
                            viewModel.transcribeFile(path: url.path)
                        }
                        viewModel.uiState.isTranscribingView = true
                    }
                    .simpleButtonStyle(
                        background: (viewModel.audioState.isTranscribing || viewModel.modelManagementState.modelState != .loaded || viewModel.audioState.importedAudioURL == nil) ? .brightGray : .accentColor,
                        foreground: .white,
                        cornerRadius: 8,
                        horizontalPadding: 16,
                        verticalPadding: 10
                    )
                    .disabled(viewModel.audioState.isTranscribing || viewModel.modelManagementState.modelState != .loaded || viewModel.audioState.importedAudioURL == nil)
                    // 전사 시작 버튼

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
        .navigationDestination(isPresented: $viewModel.uiState.isTranscribingView) {
            TranscriptionView(viewModel: viewModel)
        }
    }
}

#Preview {
    ControlsView(viewModel: ContentViewModel())
}
