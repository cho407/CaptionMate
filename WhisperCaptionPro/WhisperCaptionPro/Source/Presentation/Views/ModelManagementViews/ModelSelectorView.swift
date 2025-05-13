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
    
    let filterWords: [String] = ["distil","MB", "2024"]
    
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
                    let filteredModels = viewModel.modelManagementState.availableModels.filter { model in
                        !filterWords.contains { filter in
                            model.lowercased().contains(filter.lowercased())
                        }
                    }
                    
                    Menu {
                        ForEach(filteredModels, id: \.self) { model in
                            let isLocalModel = viewModel.modelManagementState.localModels.contains(model)
                            let modelName = model.components(separatedBy: "_").dropFirst().joined(separator: " ")
                            let modelSymbolName: String = model == viewModel.selectedModel ? "circle.fill" : "checkmark.circle"
                            
                            Button(action: {
                           
                                    viewModel.selectedModel = model
                                    viewModel.loadModel(model)
                
                            }) {
                                HStack {
                                    let loadingColor: Color = viewModel.modelManagementState.modelState == .loaded ? .green : .red
                                    Text(modelName)
                                    Spacer()
                                    Image(systemName: isLocalModel ? modelSymbolName : "arrow.down.circle.dotted")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(model == viewModel.selectedModel ? loadingColor : .black)
                                }
                            }
                            .disabled((!isLocalModel && model != "openai_whisper-tiny") || viewModel.modelManagementState.isDownloading(model: model))
                        }
                    } label: {
                        HStack {
                            let selectedModelName = viewModel.selectedModel.components(separatedBy: "_").dropFirst().joined(separator: " ")
                            Text(selectedModelName)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .cornerRadius(6)
                    }
                    .disabled(viewModel.modelManagementState.modelState == .loading)
                    
                } else {
                    HStack {
                        Spacer()
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.5)
                        Spacer()
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .cornerRadius(6)

                }

                Button {
                    viewModel.uiState.isModelmanagerViewPresented.toggle()
                } label: {
                    Image(systemName: "tray.and.arrow.down.fill")
                }
                .buttonStyle(BorderlessButtonStyle())
                .help("모델 관리")
            }

            if viewModel.modelManagementState.modelState == .unloaded {
                Divider()
            } else if viewModel.modelManagementState.loadingProgressValue < 1.0 {
                VStack {
                    HStack {
                        ProgressView(
                            value: viewModel.modelManagementState.loadingProgressValue,
                            total: 1.0
                        )
                        .progressViewStyle(.linear)
                        

                        Text(String(
                            format: "%.1f%%",
                            viewModel.modelManagementState.loadingProgressValue * 100
                        ))
                        .font(.caption)
                        .foregroundColor(.middleDarkGray)
                        .monospacedDigit()
                        
                    }
                    if viewModel.modelManagementState.modelState == .loading {
                        // 로딩 텍스트와 점 애니메이션만 표시
                        LoadingDotsView(text: "\(viewModel.selectedModel.components(separatedBy: "_").dropFirst().joined(separator: " ")) 모델 로드 중")
                            .font(.callout)
                            .foregroundColor(.middleDarkGray)
                    }
                }
            }
        }
        .onAppear {
            // 모델 목록 갱신
            viewModel.fetchModels()
            
            // 자동 로드 기능 - 선택된 모델이 로컬에 있으면 자동으로 로드
            if viewModel.modelManagementState.localModels.isEmpty {
                // 모델이 없으면 자동으로 모델 관리 화면 표시
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    viewModel.uiState.isModelmanagerViewPresented = true
                }
            } else if viewModel.modelManagementState.localModels.contains(viewModel.selectedModel) {
                // 선택된 모델이 로컬에 있으면 로드
                viewModel.loadModel(viewModel.selectedModel)
            } else if !viewModel.modelManagementState.localModels.isEmpty {
                // 선택된 모델이 로컬에 없지만 다른 모델이 있으면 첫 번째 모델 선택
                viewModel.selectedModel = viewModel.modelManagementState.localModels[0]
                viewModel.loadModel(viewModel.selectedModel)
            }
        }
        .onChange(of: viewModel.selectedModel) { _, newModel in
            if viewModel.modelManagementState.localModels.contains(newModel) {
                viewModel.loadModel(newModel)
            }
        }
    }
}

#Preview {
    ModelSelectorView(viewModel: ContentViewModel())
}
