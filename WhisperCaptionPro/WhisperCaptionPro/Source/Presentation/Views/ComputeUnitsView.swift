//
//  ComputeUnitsView.swift
//  WhisperCaptionPro
//
//  Created by 조형구 on 3/21/25.
//

import CoreML
import SwiftUI
import WhisperKit

struct ComputeUnitsView: View {
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        DisclosureGroup(isExpanded: $viewModel.showComputeUnits) {
            VStack(alignment: .leading) {
                HStack {
                    Image(systemName: "circle.fill")
                        .foregroundStyle((viewModel.whisperKit?.audioEncoder as? WhisperMLModel)?
                            .modelState == .loaded ? .green :
                            (viewModel.modelState == .unloaded ? .red : .yellow))
                        .symbolEffect(
                            .variableColor,
                            isActive: viewModel.modelState != .loaded && viewModel
                                .modelState != .unloaded
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
                            (viewModel.modelState == .unloaded ? .red : .yellow))
                        .symbolEffect(
                            .variableColor,
                            isActive: viewModel.modelState != .loaded && viewModel
                                .modelState != .unloaded
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
                viewModel.showComputeUnits.toggle()
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
