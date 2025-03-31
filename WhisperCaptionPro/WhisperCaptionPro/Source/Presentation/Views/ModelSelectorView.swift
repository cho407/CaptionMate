//
//  ModelSelectorView.swift
//  WhisperCaptionPro
//
//  Created by 조형구 on 3/21/25.
//

import SwiftUI
import WhisperKit

struct ModelSelectorView: View {
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        VStack {
            HStack {
                Image(systemName: "circle.fill")
                    .foregroundStyle(viewModel
                        .modelManagementState.modelState == .loaded ? .green :
                        (viewModel.modelManagementState
                            .modelState == .unloaded ? .red : .yellow))
                    .symbolEffect(
                        .variableColor,
                        isActive: viewModel.modelManagementState.modelState != .loaded && viewModel
                            .modelManagementState.modelState != .unloaded
                    )
                Text(viewModel.modelManagementState.modelState.description)

                Spacer()

                if !viewModel.modelManagementState.availableModels.isEmpty {
                    Picker("", selection: $viewModel.selectedModel) {
                        ForEach(viewModel.modelManagementState.availableModels,
                                id: \.self) { model in
                            HStack {
                                let modelIcon = viewModel.modelManagementState.localModels
                                    .contains { $0 == model.description } ? "checkmark.circle" :
                                    "arrow.down.circle.dotted"
                                Text(
                                    "\(Image(systemName: modelIcon)) \(model.description.components(separatedBy: "_").dropFirst().joined(separator: " "))"
                                )
                                .tag(model.description)
                            }
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .onChange(of: viewModel.selectedModel) { _, _ in
                        viewModel.modelManagementState.modelState = .unloaded
                    }
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.5)
                }

                Button {
                    viewModel.deleteModel()
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete model")
                .buttonStyle(BorderlessButtonStyle())
                .disabled(viewModel.modelManagementState.localModels.isEmpty || !viewModel
                    .modelManagementState.localModels
                    .contains(viewModel.selectedModel))

                #if os(macOS)
                    Button {
                        let folderURL = viewModel.whisperKit?
                            .modelFolder ??
                            (viewModel.modelManagementState.localModels
                                .contains(viewModel.selectedModel) ?
                                URL(
                                    fileURLWithPath: viewModel.modelManagementState.localModelPath
                                ) :
                                nil)
                        if let folder = folderURL {
                            NSWorkspace.shared.open(folder)
                        }
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(BorderlessButtonStyle())
                #endif

                Button {
                    if let url =
                        URL(string: "https://huggingface.co/\(viewModel.repoName)") {
                        #if os(macOS)
                            NSWorkspace.shared.open(url)
                        #else
                            UIApplication.shared.open(url)
                        #endif
                    }
                } label: {
                    Image(systemName: "link.circle")
                }
                .buttonStyle(BorderlessButtonStyle())
            }

            if viewModel.modelManagementState.modelState == .unloaded {
                Divider()
                Button {
                    viewModel.resetState()
                    viewModel.loadModel(viewModel.selectedModel)
                    viewModel.modelManagementState.modelState = .loading
                    if !(viewModel.whisperKit?.modelVariant.isMultilingual ?? false) {
                        viewModel.isAutoLanguageEnable = false
                    }
                   

                } label: {
                    Text("Load Model")
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                }
                .buttonStyle(.borderedProminent)
            } else if viewModel.modelManagementState.loadingProgressValue < 1.0 {
                VStack {
                    HStack {
                        ProgressView(
                            value: viewModel.modelManagementState.loadingProgressValue,
                            total: 1.0
                        )
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(maxWidth: .infinity)

                        Text(String(
                            format: "%.1f%%",
                            viewModel.modelManagementState.loadingProgressValue * 100
                        ))
                        .font(.caption)
                        .foregroundColor(.gray)
                    }
                    if viewModel.modelManagementState.modelState == .prewarming {
                        Text(
                            "Specializing \(viewModel.selectedModel) for your device...\nThis can take several minutes on first load"
                        )
                        .font(.caption)
                        .foregroundColor(.gray)
                    }
                }
            }
        }
    }
}

#Preview {
    ModelSelectorView(viewModel: ContentViewModel())
}
