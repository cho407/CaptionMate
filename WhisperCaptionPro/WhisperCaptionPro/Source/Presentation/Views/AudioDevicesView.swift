//
//  AudioDevicesView.swift
//  WhisperCaptionPro
//
//  Created by 조형구 on 3/21/25.
//

import SwiftUI
import WhisperKit

struct AudioDevicesView: View {
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        #if os(macOS)
            HStack {
                if let devices = viewModel.audioState.audioDevices, !devices.isEmpty {
                    Picker("", selection: $viewModel.selectedAudioInput) {
                        ForEach(devices, id: \.self) { device in
                            Text(device.name).tag(device.name)
                        }
                    }
                    .frame(width: 250)
                    .disabled(viewModel.audioState.isRecording)
                }
            }
            .onAppear {
                viewModel.audioState.audioDevices = AudioProcessor.getAudioDevices()
                if let devices = viewModel.audioState.audioDevices,
                   !devices.isEmpty,
                   viewModel.selectedAudioInput == "No Audio Input",
                   let device = devices.first {
                    viewModel.selectedAudioInput = device.name
                }
            }
        #else
            EmptyView()
        #endif
    }
}

#Preview {
    AudioDevicesView(viewModel: ContentViewModel())
}
