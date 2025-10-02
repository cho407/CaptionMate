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
                        Text(LocalizedStringKey(task.description.capitalized)).tag(task.description)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.selectedTask) { _, newValue in
                    // Translate 작업 선택 시 자동 언어 감지 활성화
                    if newValue == "translate" {
                        viewModel.isAutoLanguageEnable = true
                    }
                }
            }
            .padding(.horizontal)
            
            HStack {
                Toggle("Auto Language", isOn: $viewModel.isAutoLanguageEnable)
                    .toggleStyle(.checkbox)
                    .disabled(!(viewModel.whisperKit?.modelVariant.isMultilingual ?? false) || viewModel.selectedTask == "translate")

                LabeledContent {
                    Picker("", selection: $viewModel.selectedLanguage) {
                        ForEach(viewModel.modelManagementState.availableLanguages,
                                id: \.self) { language in
                            Text(language.description).tag(language.description)
                        }
                    }
                    .disabled(!(viewModel.whisperKit?.modelVariant.isMultilingual ?? false))
                } label: {
                    Label("Source Language", systemImage: "globe")
                }
                .disabled(viewModel.isAutoLanguageEnable)
                .disabled(!(viewModel.whisperKit?.modelVariant.isMultilingual ?? false))
            }
            .padding(.horizontal)
            .padding(.top)
        }
    }
}

#Preview {
    BasicSettingsView(viewModel: ContentViewModel())
}
