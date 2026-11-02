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
//  SettingsView.swift
//  CaptionMate
//
//  Created by 조형구 on 3/21/25.
//

import SwiftUI
import WhisperKit

// 공통 행: 좌측 라벨(+정보) • 우측 컨트롤 정렬
private struct SettingRow<Control: View>: View {
    let title: LocalizedStringKey
    let infoKey: LocalizedStringKey?
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let infoKey {
                InfoButton(infoKey)
            }
            control()
                .accessibilityLabel(Text(title))
        }
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: ContentViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showExpertOptions = false

    private var tokenLimit: Int {
        min(viewModel.whisperKit?.textDecoder.kvCacheMaxSequenceLength ?? Constants.maxTokenContext,
            Constants.maxTokenContext)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("decoding_options", systemImage: "slider.horizontal.3")
                    .font(.title3.weight(.semibold))
                    .accessibilityIdentifier("settings.sheet")
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("settings.closeButton")
            }
            .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox {
                        VStack(spacing: 12) {
                            SettingRow(title: "Show Timestamps", infoKey: "info.show_timestamps") {
                                Toggle("Show Timestamps", isOn: $viewModel.enableTimestamps).labelsHidden()
                            }
                            SettingRow(title: "Word Timestamps", infoKey: "info.word_timestamps") {
                                Toggle("Word Timestamps", isOn: $viewModel.enableWordTimestamp).labelsHidden()
                            }
                            SettingRow(title: "Show Decoder Preview", infoKey: "info.show_decoder_preview") {
                                Toggle("Show Decoder Preview", isOn: $viewModel.enableDecoderPreview).labelsHidden()
                            }
                        }
                        .padding(8)
                    } label: {
                        Label("format_and_preview", systemImage: "doc.text")
                    }

                    DisclosureGroup(isExpanded: $showExpertOptions) {
                        VStack(spacing: 16) {
                            GroupBox {
                                VStack(spacing: 12) {
                                    SettingRow(title: "Prompt Prefill", infoKey: "info.prompt_prefill") {
                                        Toggle("Prompt Prefill", isOn: $viewModel.enablePromptPrefill).labelsHidden()
                                    }
                                    SettingRow(title: "Model Special Tokens", infoKey: nil) {
                                        Toggle("Model Special Tokens", isOn: $viewModel.enableSpecialCharacters).labelsHidden()
                                    }
                                    settingSlider("Starting Temperature", info: "info.starting_temperature",
                                                  value: $viewModel.temperatureStart, range: 0 ... 1, step: 0.1)
                                    settingSlider("Max Fallback Count", info: "info.max_fallback_count",
                                                  value: $viewModel.fallbackCount, range: 0 ... 5, step: 1)
                                    settingSlider("Compression Check Tokens", info: "info.compression_check_tokens",
                                                  value: $viewModel.compressionCheckWindow, range: 5 ... 100, step: 5)
                                    settingSlider(
                                        "Max Tokens Per Loop", info: "info.max_tokens_per_loop",
                                        value: Binding(
                                            get: { Double(viewModel.sampleLength) },
                                            set: { viewModel.sampleLength = Int($0) }
                                        ),
                                        range: 1 ... Double(tokenLimit), step: 1
                                    )
                                }
                                .padding(8)
                            } label: {
                                Label("decoding_quality", systemImage: "slider.horizontal.3")
                            }

                            GroupBox {
                                VStack(spacing: 12) {
                                    SettingRow(title: "Chunking Strategy", infoKey: "info.chunking_strategy") {
                                        Picker("Chunking Strategy", selection: $viewModel.chunkingStrategy) {
                                            Text("None").tag(ChunkingStrategy.none)
                                            Text("VAD").tag(ChunkingStrategy.vad)
                                        }
                                        .labelsHidden()
                                        .frame(width: 160)
                                    }
                                    settingSlider("Workers", info: "info.workers",
                                                  value: $viewModel.concurrentWorkerCount, range: 1 ... 8, step: 1)
                                    Button {
                                        viewModel.applyRecommendedPerformanceSettings()
                                    } label: {
                                        Label("Auto Tune Performance", systemImage: "wand.and.stars")
                                    }
                                }
                                .padding(8)
                            } label: {
                                Label("performance", systemImage: "speedometer")
                            }
                        }
                        .padding(.top, 12)
                    } label: {
                        Button("Advanced Settings") { showExpertOptions.toggle() }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("settings.advancedDisclosure")
                    }
                }
                .disabled(viewModel.isTranscriptionBusy)
                .padding(16)
            }
        }
        .frame(width: 520, height: 560)
        .onAppear {
            viewModel.sampleLength = min(max(viewModel.sampleLength, 1), tokenLimit)
            viewModel.concurrentWorkerCount = min(max(viewModel.concurrentWorkerCount, 1), 8)
            viewModel.compressionCheckWindow = min(max(viewModel.compressionCheckWindow, 5), 100)
        }
    }

    private func settingSlider(
        _ title: LocalizedStringKey, info: LocalizedStringKey,
        value: Binding<Double>, range: ClosedRange<Double>, step: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                InfoButton(info)
                Spacer()
                Text(value.wrappedValue.formatted(.number))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
                .accessibilityLabel(Text(title))
        }
    }
}

#Preview {
    SettingsView(viewModel: ContentViewModel())
}
