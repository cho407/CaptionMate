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
                    let color: Color = viewModel.modelManagementState
                        .modelState != .loaded ? .gray : .red
                    Button {
                        withAnimation {
                            viewModel.selectFile()
                        }
                    } label: {
                        Text("FROM FILE")
                            .font(.headline)
                            .foregroundColor(color)
                            .padding()
                            .cornerRadius(40)
                            .frame(minWidth: 70, minHeight: 70)
                            .overlay(
                                RoundedRectangle(cornerRadius: 40)
                                    .stroke(color, lineWidth: 4)
                            )
                    }
                    .fileImporter(
                        isPresented: $viewModel.uiState.isFilePickerPresented,
                        allowedContentTypes: [.audio],
                        allowsMultipleSelection: false,
                        onCompletion: viewModel.handleFilePicker
                    )
                    .lineLimit(1)
                    .contentTransition(.symbolEffect(.replace))
                    .buttonStyle(BorderlessButtonStyle())
                    .disabled(viewModel.modelManagementState.modelState != .loaded)
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .padding()
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
