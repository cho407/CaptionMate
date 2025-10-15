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
//  BasicSettingsView.swift
//  CaptionMate
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
                    .disabled(!(viewModel.whisperKit?.modelVariant.isMultilingual ?? false) ||
                        viewModel.selectedTask == "translate")

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
