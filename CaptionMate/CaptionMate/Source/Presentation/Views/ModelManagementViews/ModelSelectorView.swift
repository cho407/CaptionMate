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
//  ModelSelectorView.swift
//  CaptionMate
//
//  Created by 조형구 on 3/21/25.
//

import SwiftUI
import WhisperKit

struct ModelSelectorView: View {
    @ObservedObject var viewModel: ContentViewModel
    @ObservedObject var modelState: ModelManagementState
    @Environment(\.colorScheme) private var colorScheme

    init(viewModel: ContentViewModel) {
        self.viewModel = viewModel
        modelState = viewModel.modelManagementState
    }

    private var modelLoadStatus: Text? {
        let modelName = modelState.displayName(for: viewModel.selectedModel)
        switch modelState.modelState {
        case .loading:
            return Text("Loading \(modelName)")
        case .prewarming:
            return Text("Specializing \(modelName)")
        case .unloading:
            return Text("Unloading")
        case .downloading:
            return Text("Downloading \(modelName)")
        default:
            return nil
        }
    }

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
                Text(viewModel.modelManagementState.modelState.captionMateLocalizedKey)
                    .accessibilityIdentifier("modelSelector.status")

                Spacer()

                if !viewModel.modelManagementState.availableModels.isEmpty {
                    Menu {
                        ForEach(viewModel.modelManagementState.availableModels, id: \.self) { model in
                            let isLocalModel = viewModel.modelManagementState.localModels
                                .contains(model)
                            let modelName = viewModel.modelManagementState.displayName(for: model)
                            let isSelectedModel = model == viewModel.selectedModel &&
                                modelState.hasVisibleModelSelection(for: model)
                            let modelSymbolName: String = isSelectedModel
                                ? "circle.fill" : "checkmark.circle"

                            Button(action: {
                                viewModel.selectModel(model)

                            }) {
                                HStack {
                                    let loadingColor: Color = viewModel.modelManagementState
                                        .modelState == .loaded ? .green : .red
                                    Text(modelName)
                                    Spacer()
                                    Image(systemName: isLocalModel ? modelSymbolName :
                                        "arrow.down.circle.dotted")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(isSelectedModel ? loadingColor : Color
                                            .modelSelectorText(for: colorScheme))
                                }
                            }
                            .disabled(viewModel.modelManagementState.isDownloading(model: model))
                        }
                    } label: {
                        HStack {
                            if modelState.hasVisibleModelSelection(for: viewModel.selectedModel) {
                                Text(modelState.displayName(for: viewModel.selectedModel))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            } else {
                                Text("Select model")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .cornerRadius(6)
                        .accessibilityIdentifier("modelSelector.selectedModel")
                    }
                    .disabled(!viewModel.canChangeModel)

                } else if modelState.catalogLoadState.isLoading {
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
                } else {
                    Text("Select model")
                        .foregroundStyle(.secondary)
                }

                Button {
                    viewModel.uiState.isModelmanagerViewPresented.toggle()
                } label: {
                    Image(systemName: "tray.and.arrow.down.fill")
                }
                .buttonStyle(BorderlessButtonStyle())
                .accessibilityLabel(Text("Manage Models"))
                .accessibilityIdentifier("modelSelector.manageModelsButton")
                .help("Manage Models")
            }

            if viewModel.modelManagementState.modelState == .unloaded {
                Divider()

                // 에러 메시지 표시
                if viewModel.modelManagementState.hasModelLoadError,
                   let errorMsg = viewModel.modelManagementState.modelLoadError {
                    Text(errorMsg)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            } else if let status = modelLoadStatus {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    status
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("modelSelector.loadActivity")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("modelSelector.container")
        .onAppear {
            // 모델 목록 갱신
            viewModel.fetchModels()

#if DEBUG
            if viewModel.shouldSkipModelSelectorAutoActionsForUITesting {
                return
            }
#endif

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
