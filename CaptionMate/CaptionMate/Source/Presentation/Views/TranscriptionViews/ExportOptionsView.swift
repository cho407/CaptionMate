//
//  Copyright 2026 Harrison Cho
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

import SwiftUI

struct ExportOptionsView: View {
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("File Format") {
                    Picker("File Format", selection: $viewModel.selectedExportFileType) {
                        ForEach(SubtitleFileType.allCases, id: \.self) { format in
                            Text(verbatim: format.rawValue.uppercased()).tag(format)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                    .accessibilityIdentifier("subtitleReview.formatPicker")
                }
                if viewModel.selectedExportFileType.supportsCaptionLayout {
                    LabeledContent("Export Preset") {
                        Picker("Export Preset", selection: Binding(
                            get: { viewModel.selectedExportPreset },
                            set: {
                                viewModel.selectedExportPreset = $0
                                viewModel.applySelectedExportPreset(showMessage: false)
                            }
                        )) {
                            ForEach(SubtitleExportPreset.allCases) { preset in
                                Text(preset.displayNameKey).tag(preset)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 180)
                        .accessibilityIdentifier("subtitleReview.presetPicker")
                    }
                }
                if viewModel.selectedExportFileType == .fcpxml {
                    LabeledContent("Frame Rate (fps)") {
                        TextField("Frame Rate (fps)", value: $viewModel.frameRate,
                                  format: .number.precision(.fractionLength(0 ... 3)))
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                            .accessibilityIdentifier("subtitleReview.frameRateField")
                    }
                    if !viewModel.frameRate.isFinite || !(1 ... 240).contains(viewModel.frameRate) {
                        Text("Frame rate must be between 1 and 240.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Toggle("Export Speaker Labels", isOn: $viewModel.includeSpeakerLabelsInExport)
                    .disabled(viewModel.availableSpeakerIDs().isEmpty)
                    .accessibilityIdentifier("transcription.exportSpeakerLabelsToggle")
            }
            .padding(8)
        }
        .onChange(of: viewModel.includeSpeakerLabelsInExport) { _, _ in
            viewModel.refreshSubtitleQualityIssues()
        }
    }
}
