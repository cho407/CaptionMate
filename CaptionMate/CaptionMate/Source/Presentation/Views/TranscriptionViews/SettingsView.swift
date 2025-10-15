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
        }
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: ContentViewModel
    @Environment(\.dismiss) private var dismiss

    // 기존 포맷터 유지
    private var numberFormatter: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 0
        f.minimum = 1
        return f
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // MARK: Header

                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 8) {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(.secondary)
                        Text("decoding_options")
                            .font(.title3.weight(.semibold))
                    }
                    Spacer()
                    Button {
                        viewModel.uiState.showAdvancedOptions = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .imageScale(.large)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(Text("Close"))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                Divider()
                    .padding(.horizontal, 16)

                // MARK: 1. Output & Format

                GroupBox {
                    VStack(spacing: 8) {
                        SettingRow(title: "Show Timestamps", infoKey: "info.show_timestamps") {
                            Toggle("", isOn: $viewModel.enableTimestamps).labelsHidden()
                        }
                        Divider()
                        SettingRow(title: "Word Timestamps", infoKey: "info.word_timestamps") {
                            Toggle("", isOn: $viewModel.enableWordTimestamp).labelsHidden()
                        }
                        Divider()
                        SettingRow(title: "Special Characters",
                                   infoKey: "info.special_characters") {
                            Toggle("", isOn: $viewModel.enableSpecialCharacters).labelsHidden()
                        }
                        Divider()
                        SettingRow(
                            title: "Show Decoder Preview",
                            infoKey: "info.show_decoder_preview"
                        ) {
                            Toggle("", isOn: $viewModel.enableDecoderPreview).labelsHidden()
                        }
                        Divider()
                        HStack(spacing: 10) {
                            Text("Frame Rate (fps)")
                            InfoButton("info.frame_rate")
                            Spacer()
                            TextField("30", value: $viewModel.frameRate, formatter: numberFormatter)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 88)
                        }
                    }
                    .padding(.vertical, 6)
                } label: {
                    Label("format_and_preview", systemImage: "doc.text")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)

                // MARK: 2. Decoding Quality

                GroupBox {
                    VStack(spacing: 8) {
                        SettingRow(title: "Prompt Prefill", infoKey: "info.prompt_prefill") {
                            Toggle("", isOn: $viewModel.enablePromptPrefill).labelsHidden()
                        }
                        Divider()
                        SettingRow(title: "Cache Prefill", infoKey: "info.cache_prefill") {
                            Toggle("", isOn: $viewModel.enableCachePrefill).labelsHidden()
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Starting Temperature")
                                InfoButton("info.starting_temperature")
                            }
                            HStack(spacing: 10) {
                                Slider(value: $viewModel.temperatureStart, in: 0 ... 1, step: 0.1)
                                Text(viewModel.temperatureStart.formatted(.number))
                                    .monospacedDigit()
                                    .frame(width: 40, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Max Fallback Count")
                                InfoButton("info.max_fallback_count")
                            }
                            HStack(spacing: 10) {
                                Slider(value: $viewModel.fallbackCount, in: 0 ... 5, step: 1)
                                Text(viewModel.fallbackCount.formatted(.number))
                                    .monospacedDigit()
                                    .frame(width: 40, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Compression Check Tokens")
                                InfoButton("info.compression_check_tokens")
                            }
                            HStack(spacing: 10) {
                                Slider(
                                    value: $viewModel.compressionCheckWindow,
                                    in: 0 ... 100,
                                    step: 5
                                )
                                Text(viewModel.compressionCheckWindow.formatted(.number))
                                    .monospacedDigit()
                                    .frame(width: 40, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                } label: {
                    Label("decoding_quality", systemImage: "slider.horizontal.3")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)

                // MARK: 3. Performance

                GroupBox {
                    VStack(spacing: 12) {
                        HStack(spacing: 10) {
                            Text("Chunking Strategy")
                            InfoButton("info.chunking_strategy")
                            Spacer()
                            Picker("", selection: $viewModel.chunkingStrategy) {
                                Text("None").tag(ChunkingStrategy.none)
                                Text("VAD").tag(ChunkingStrategy.vad)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 160)
                        }

                        Divider()

                        HStack(spacing: 10) {
                            Text("Workers")
                            InfoButton("info.workers")
                            Spacer()
                            Slider(value: $viewModel.concurrentWorkerCount, in: 0 ... 32, step: 1)
                                .frame(maxWidth: 240)
                            Text(viewModel.concurrentWorkerCount.formatted(.number))
                                .monospacedDigit()
                                .frame(width: 36, alignment: .trailing)
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Max Tokens Per Loop")
                                InfoButton("info.max_tokens_per_loop")
                            }
                            HStack(spacing: 10) {
                                Slider(
                                    value: Binding(
                                        get: { Double(viewModel.sampleLength) },
                                        set: { viewModel.sampleLength = Int($0) }
                                    ),
                                    in: 0 ... Double(min(
                                        viewModel.whisperKit?.textDecoder.kvCacheMaxSequenceLength
                                            ?? Constants.maxTokenContext,
                                        Constants.maxTokenContext
                                    )),
                                    step: 10
                                )
                                Text("\(viewModel.sampleLength)")
                                    .monospacedDigit()
                                    .frame(width: 40, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                } label: {
                    Label("performance", systemImage: "speedometer")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 8)
            }
            .padding(.bottom, 16)
        }
        .padding(.vertical, 8)
        .frame(minHeight: 700)
    }
}

#Preview {
    SettingsView(viewModel: ContentViewModel())
}
