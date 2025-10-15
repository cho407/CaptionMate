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
//  ComputeUnitsView.swift
//  CaptionMate
//
//  Created by 조형구 on 3/21/25.
//

import CoreML
import SwiftUI
import WhisperKit

struct ComputeUnitsView: View {
    @ObservedObject var viewModel: ContentViewModel
    @ObservedObject var modelState: ModelManagementState

    init(viewModel: ContentViewModel) {
        self.viewModel = viewModel
        modelState = viewModel.modelManagementState
    }

    var body: some View {
        DisclosureGroup(isExpanded: $viewModel.uiState.showComputeUnits) {
            VStack(alignment: .leading) {
                HStack {
                    Image(systemName: "circle.fill")
                        .foregroundStyle((viewModel.whisperKit?.audioEncoder as? WhisperMLModel)?
                            .modelState == .loaded ? .green :
                            (viewModel.modelManagementState
                                .modelState == .unloaded ? .red : .yellow))
                        .symbolEffect(
                            .variableColor,
                            isActive: viewModel.modelManagementState
                                .modelState != .loaded && viewModel
                                .modelManagementState.modelState != .unloaded
                        )
                    Text("Audio Encoder")
                    Spacer()
                    Picker("", selection: $viewModel.encoderComputeUnits) {
                        Text("CPU").tag(MLComputeUnits.cpuOnly)
                        Text("GPU").tag(MLComputeUnits.cpuAndGPU)
                        Text("Neural Engine").tag(MLComputeUnits.cpuAndNeuralEngine)
                    }
                    .onChange(of: viewModel.encoderComputeUnits) { _, _ in
                        viewModel.loadModel(viewModel.selectedModel)
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 150)
                }
                HStack {
                    Image(systemName: "circle.fill")
                        .foregroundStyle((viewModel.whisperKit?.textDecoder as? WhisperMLModel)?
                            .modelState == .loaded ? .green :
                            (viewModel.modelManagementState
                                .modelState == .unloaded ? .red : .yellow))
                        .symbolEffect(
                            .variableColor,
                            isActive: viewModel.modelManagementState
                                .modelState != .loaded && viewModel
                                .modelManagementState.modelState != .unloaded
                        )
                    Text("Text Decoder")
                    Spacer()
                    Picker("", selection: $viewModel.decoderComputeUnits) {
                        Text("CPU").tag(MLComputeUnits.cpuOnly)
                        Text("GPU").tag(MLComputeUnits.cpuAndGPU)
                        Text("Neural Engine").tag(MLComputeUnits.cpuAndNeuralEngine)
                    }
                    .onChange(of: viewModel.decoderComputeUnits) { _, _ in
                        viewModel.loadModel(viewModel.selectedModel)
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 150)
                }
            }
            .padding(.top)
        } label: {
            Button {
                viewModel.uiState.showComputeUnits.toggle()
            } label: {
                Text("Compute Units")
                    .font(.headline)
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    ComputeUnitsView(viewModel: ContentViewModel())
}
