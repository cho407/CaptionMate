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
                Picker("", selection: $viewModel.settings.selectedTask) {
                    ForEach(DecodingTask.allCases, id: \.self) { task in
                        Text(task.description.capitalized).tag(task.description)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            .padding(.horizontal)
            // TODO: - 자동 언어 감지 관련해서 모델별 UI 로직 조금더 세세하게 고려
            HStack {
                Toggle("Auto Language", isOn: $viewModel.settings.isAutoLanguageEnable)
                    .toggleStyle(.checkbox)

                LabeledContent {
                    Picker("", selection: $viewModel.settings.selectedLanguage) {
                        ForEach(viewModel.modelManagementState.availableLanguages,
                                id: \.self) { language in
                            Text(language.description).tag(language.description)
                        }
                    }
                    .disabled(!(viewModel.whisperKit?.modelVariant.isMultilingual ?? false))
                } label: {
                    Label("Source Language", systemImage: "globe")
                }
                .disabled(viewModel.settings.isAutoLanguageEnable)
                .disabled(!(viewModel.whisperKit?.modelVariant.isMultilingual ?? false))
            }
            .padding(.horizontal)
            .padding(.top)

            HStack {
                Text(
                    "\(viewModel.transcriptionState.effectiveRealTimeFactor, specifier: "%.3f") RTF"
                )
                .font(.body)
                Spacer()
                #if os(macOS)
                    Text(
                        "\(viewModel.transcriptionState.effectiveSpeedFactor, specifier: "%.1f") Speed Factor"
                    )
                    .font(.body)
                    .lineLimit(1)
                    Spacer()
                #endif
                Text("\(viewModel.transcriptionState.tokensPerSecond, specifier: "%.0f") tok/s")
                    .font(.body)
                Spacer()
                Text(
                    "First token: \(viewModel.transcriptionState.firstTokenTime - viewModel.transcriptionState.pipelineStart, specifier: "%.2f")s"
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
