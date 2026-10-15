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

enum TranscriptionLanguageSelection {
    static func resolvedValue(
        selectedLanguage: String,
        availableLanguages: [String]
    ) -> String? {
        availableLanguages.contains(selectedLanguage) ? selectedLanguage : nil
    }
}

struct BasicSettingsView: View {
    @ObservedObject var viewModel: ContentViewModel

    private var languageSelection: Binding<String?> {
        Binding(
            get: {
                TranscriptionLanguageSelection.resolvedValue(
                    selectedLanguage: viewModel.selectedLanguage,
                    availableLanguages: viewModel.modelManagementState.availableLanguages
                )
            },
            set: { selectedLanguage in
                guard let selectedLanguage else { return }
                viewModel.selectedLanguage = selectedLanguage
            }
        )
    }

    private var speakerDiarizationSelection: Binding<Bool> {
        Binding(
            get: { viewModel.enableSpeakerDiarization },
            set: { viewModel.setSpeakerDiarizationEnabled($0) }
        )
    }

    private var speakerModelAvailabilityMessage: LocalizedStringKey {
        viewModel.modelManagementState.isSpeakerDiarizationModelPreparing
            ? "Speaker model is still preparing."
            : "Speaker model is not ready."
    }

    var body: some View {
        VStack(spacing: 0) {
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

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 14) {
                    Spacer(minLength: 0)

                    languageOptions

                    Divider()
                        .frame(height: 22)

                    speakerOptions

                    Spacer(minLength: 0)
                }
                .padding(.top)

                VStack(spacing: 8) {
                    languageOptions
                        .frame(maxWidth: .infinity, alignment: .leading)
                    speakerOptions
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top)
            }
        }
    }

    @ViewBuilder
    private var languageOptions: some View {
        HStack {
            Toggle("Auto Language", isOn: $viewModel.isAutoLanguageEnable)
                .toggleStyle(.checkbox)
                .fixedSize(horizontal: true, vertical: false)
                .disabled(!(viewModel.whisperKit?.modelVariant.isMultilingual ?? false) ||
                    viewModel.selectedTask == "translate")

            LabeledContent {
                Picker("", selection: languageSelection) {
                    if languageSelection.wrappedValue == nil {
                        Text("Select language")
                            .tag(nil as String?)
                    }
                    ForEach(viewModel.modelManagementState.availableLanguages,
                            id: \.self) { language in
                        Text(verbatim: viewModel.transcriptionLanguageTitle(for: language.description))
                            .tag(Optional(language.description))
                    }
                }
                .accessibilityIdentifier("transcription.sourceLanguagePicker")
                .accessibilityValue(
                    languageSelection.wrappedValue.map {
                        Text(verbatim: viewModel.transcriptionLanguageTitle(for: $0))
                    } ?? Text("Select language")
                )
                .disabled(!(viewModel.whisperKit?.modelVariant.isMultilingual ?? false))
            } label: {
                Label("Source Language", systemImage: "globe")
            }
            .disabled(viewModel.isAutoLanguageEnable)
            .disabled(!(viewModel.whisperKit?.modelVariant.isMultilingual ?? false))
        }
        .fixedSize(horizontal: true, vertical: true)
    }

    @ViewBuilder
    private var speakerOptions: some View {
        HStack(alignment: .center, spacing: 14) {
            Toggle(isOn: speakerDiarizationSelection) {
                Label("Speaker Diarization", systemImage: "person.2.wave.2")
            }
            .toggleStyle(.checkbox)
            .fixedSize(horizontal: true, vertical: false)
            .disabled(!viewModel.isSpeakerDiarizationAvailable)
            .accessibilityIdentifier("transcription.speakerDiarizationToggle")

            HStack(spacing: 8) {
                Label("Speaker Count", systemImage: "person.2")
                Picker("", selection: $viewModel.speakerDiarizationSpeakerCount) {
                    ForEach(0 ... 8, id: \.self) { count in
                        Text(viewModel.speakerCountOptionTitleKey(for: count)).tag(count)
                    }
                }
                .frame(width: 104)
                .disabled(!viewModel.enableSpeakerDiarization ||
                    !viewModel.isSpeakerDiarizationAvailable)
                .accessibilityLabel(Text("Speaker Count"))
                .accessibilityIdentifier("transcription.speakerCountPicker")
            }
            .fixedSize(horizontal: true, vertical: false)

            Toggle(
                "Include Speaker Names",
                isOn: $viewModel.includeSpeakerLabelsInExport
            )
            .toggleStyle(.checkbox)
            .fixedSize(horizontal: true, vertical: false)
            .disabled(!viewModel.enableSpeakerDiarization ||
                !viewModel.isSpeakerDiarizationAvailable)
            .accessibilityIdentifier("transcription.exportSpeakerLabelsToggle")

            if !viewModel.isSpeakerDiarizationAvailable {
                Label(speakerModelAvailabilityMessage, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(Text(speakerModelAvailabilityMessage))
                    .accessibilityLabel(Text(speakerModelAvailabilityMessage))
                    .frame(maxWidth: 220, alignment: .leading)
            }

        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

#Preview {
    BasicSettingsView(viewModel: ContentViewModel())
}
