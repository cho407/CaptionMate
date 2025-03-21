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
                        .modelState == .loaded ? .green :
                        (viewModel.modelState == .unloaded ? .red : .yellow))
                    .symbolEffect(
                        .variableColor,
                        isActive: viewModel.modelState != .loaded && viewModel
                            .modelState != .unloaded
                    )
                Text(viewModel.modelState.description)

                Spacer()

                if !viewModel.availableModels.isEmpty {
                    Picker("", selection: $viewModel.selectedModel) {
                        ForEach(viewModel.availableModels, id: \.self) { model in
                            HStack {
                                let modelIcon = viewModel.localModels
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
                        viewModel.modelState = .unloaded
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
                .disabled(viewModel.localModels.isEmpty || !viewModel.localModels
                    .contains(viewModel.selectedModel))

                #if os(macOS)
                    Button {
                        let folderURL = viewModel.whisperKit?
                            .modelFolder ??
                            (viewModel.localModels
                                .contains(viewModel.selectedModel) ?
                                URL(fileURLWithPath: viewModel.localModelPath) : nil)
                        if let folder = folderURL {
                            NSWorkspace.shared.open(folder)
                        }
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(BorderlessButtonStyle())
                #endif

                Button {
                    if let url = URL(string: "https://huggingface.co/\(viewModel.repoName)") {
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

            if viewModel.modelState == .unloaded {
                Divider()
                Button {
                    viewModel.resetState()
                    viewModel.loadModel(viewModel.selectedModel)
                    viewModel.modelState = .loading
                } label: {
                    Text("Load Model")
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                }
                .buttonStyle(.borderedProminent)
            } else if viewModel.loadingProgressValue < 1.0 {
                VStack {
                    HStack {
                        ProgressView(value: viewModel.loadingProgressValue, total: 1.0)
                            .progressViewStyle(LinearProgressViewStyle())
                            .frame(maxWidth: .infinity)

                        Text(String(format: "%.1f%%", viewModel.loadingProgressValue * 100))
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    if viewModel.modelState == .prewarming {
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
