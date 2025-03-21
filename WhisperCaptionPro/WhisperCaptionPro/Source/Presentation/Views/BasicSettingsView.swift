//
//  BasicSettingsView.swift
//  WhisperCaptionPro
//
//  Created by 조형구 on 3/21/25.
//

import SwiftUI
import WhisperKit

struct BasicSettingsView: View {
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        VStack {
            HStack {
                Picker("", selection: $viewModel.selectedTask) {
                    ForEach(DecodingTask.allCases, id: \.self) { task in
                        Text(task.description.capitalized).tag(task.description)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .disabled(!(viewModel.whisperKit?.modelVariant.isMultilingual ?? false))
            }
            .padding(.horizontal)

            LabeledContent {
                Picker("", selection: $viewModel.selectedLanguage) {
                    ForEach(viewModel.availableLanguages, id: \.self) { language in
                        Text(language.description).tag(language.description)
                    }
                }
                .disabled(!(viewModel.whisperKit?.modelVariant.isMultilingual ?? false))
            } label: {
                Label("Source Language", systemImage: "globe")
            }
            .padding(.horizontal)
            .padding(.top)

            HStack {
                Text("\(viewModel.effectiveRealTimeFactor, specifier: "%.3f") RTF")
                    .font(.body)
                Spacer()
                #if os(macOS)
                    Text("\(viewModel.effectiveSpeedFactor, specifier: "%.1f") Speed Factor")
                        .font(.body)
                        .lineLimit(1)
                    Spacer()
                #endif
                Text("\(viewModel.tokensPerSecond, specifier: "%.0f") tok/s")
                    .font(.body)
                Spacer()
                Text(
                    "First token: \(viewModel.firstTokenTime - viewModel.pipelineStart, specifier: "%.2f")s"
                )
                .font(.body)
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
    }
}

#Preview {
    BasicSettingsView(viewModel: ContentViewModel())
}
