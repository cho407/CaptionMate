//
//  SettingsView.swift
//  WhisperCaptionPro
//
//  Created by 조형구 on 3/21/25.
//

import SwiftUI
import WhisperKit

struct SettingsView: View {
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        List {
            HStack {
                Text("Show Timestamps")
                InfoButton(
                    "Toggling this will include/exclude timestamps in both the UI and the prefill tokens.\nEither <|notimestamps|> or <|0.00|> will be forced based on this setting unless \"Prompt Prefill\" is de-selected."
                )
                Spacer()
                Toggle("", isOn: $viewModel.settings.enableTimestamps)
            }
            .padding(.horizontal)

            HStack {
                Text("Special Characters")
                InfoButton(
                    "Toggling this will include/exclude special characters in the transcription text."
                )
                Spacer()
                Toggle("", isOn: $viewModel.settings.enableSpecialCharacters)
            }
            .padding(.horizontal)

            HStack {
                Text("Show Decoder Preview")
                InfoButton(
                    "Toggling this will show a small preview of the decoder output in the UI under the transcribe. This can be useful for debugging."
                )
                Spacer()
                Toggle("", isOn: $viewModel.settings.enableDecoderPreview)
            }
            .padding(.horizontal)

            HStack {
                Text("Prompt Prefill")
                InfoButton(
                    "When Prompt Prefill is on, it forces the task, language, and timestamp tokens in the decoding loop. Toggle it off if you'd like the model to generate those tokens itself."
                )
                Spacer()
                Toggle("", isOn: $viewModel.settings.enablePromptPrefill)
            }
            .padding(.horizontal)

            HStack {
                Text("Cache Prefill")
                InfoButton(
                    "When Cache Prefill is on, the decoder will try to use a lookup table of pre-computed KV caches instead of computing them during the decoding loop, which can speed up inference."
                )
                Spacer()
                Toggle("", isOn: $viewModel.settings.enableCachePrefill)
            }
            .padding(.horizontal)

            VStack {
                HStack {
                    Text("Chunking Strategy")
                    InfoButton(
                        "Select the strategy to use for chunking audio data. If VAD is selected, the audio will be chunked based on voice activity (split on silent portions)."
                    )
                    Spacer()
                    Picker("", selection: $viewModel.settings.chunkingStrategy) {
                        Text("None").tag(ChunkingStrategy.none)
                        Text("VAD").tag(ChunkingStrategy.vad)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                HStack {
                    Text("Workers:")
                    Slider(value: $viewModel.settings.concurrentWorkerCount, in: 0 ... 32, step: 1)
                    Text(viewModel.settings.concurrentWorkerCount.formatted(.number))
                    InfoButton(
                        "Number of concurrent transcription workers. Higher values may increase memory usage but can improve speed."
                    )
                }
            }
            .padding(.horizontal)
            .padding(.bottom)

            VStack {
                Text("Starting Temperature")
                HStack {
                    Slider(value: $viewModel.settings.temperatureStart, in: 0 ... 1, step: 0.1)
                    Text(viewModel.settings.temperatureStart.formatted(.number))
                    InfoButton(
                        "Controls the initial randomness of token selection in the decoding loop."
                    )
                }
            }
            .padding(.horizontal)

            VStack {
                Text("Max Fallback Count")
                HStack {
                    Slider(value: $viewModel.settings.fallbackCount, in: 0 ... 5, step: 1)
                    Text(viewModel.settings.fallbackCount.formatted(.number))
                        .frame(width: 30)
                    InfoButton("Number of fallback attempts for token selection.")
                }
            }
            .padding(.horizontal)

            VStack {
                Text("Compression Check Tokens")
                HStack {
                    Slider(
                        value: $viewModel.settings.compressionCheckWindow,
                        in: 0 ... 100,
                        step: 5
                    )
                    Text(viewModel.settings.compressionCheckWindow.formatted(.number))
                        .frame(width: 30)
                    InfoButton(
                        "Number of tokens used to check for repetitive patterns via compression."
                    )
                }
            }
            .padding(.horizontal)

            VStack {
                Text("Max Tokens Per Loop")
                HStack {
                    Slider(
                        value: $viewModel.settings.sampleLength,
                        in: 0 ... Double(min(
                            viewModel.whisperKit?.textDecoder.kvCacheMaxSequenceLength ?? Constants
                                .maxTokenContext,
                            Constants.maxTokenContext
                        )),
                        step: 10
                    )
                    Text(viewModel.settings.sampleLength.formatted(.number))
                        .frame(width: 30)
                    InfoButton("Maximum tokens generated per decoding loop.")
                }
            }
            .padding(.horizontal)

            VStack {
                Text("Silence Threshold")
                HStack {
                    Slider(value: $viewModel.settings.silenceThreshold, in: 0 ... 1, step: 0.05)
                    Text(viewModel.settings.silenceThreshold.formatted(.number))
                        .frame(width: 30)
                    InfoButton("Relative silence threshold for audio segmentation.")
                }
            }
            .padding(.horizontal)

            VStack {
                Text("Realtime Delay Interval")
                HStack {
                    Slider(value: $viewModel.settings.realtimeDelayInterval, in: 0 ... 30, step: 1)
                    Text(viewModel.settings.realtimeDelayInterval.formatted(.number))
                        .frame(width: 30)
                    InfoButton("Delay between successive streaming transcription loops.")
                }
            }
            .padding(.horizontal)

            Section(header: Text("Experimental")) {
                HStack {
                    Text("Eager Streaming Mode")
                    InfoButton("Updates transcription more frequently but may be less accurate.")
                    Spacer()
                    Toggle("", isOn: $viewModel.settings.enableEagerDecoding)
                }
                .padding(.horizontal)
                .padding(.top)

                VStack {
                    Text("Token Confirmations")
                    HStack {
                        Slider(
                            value: $viewModel.settings.tokenConfirmationsNeeded,
                            in: 1 ... 10,
                            step: 1
                        )
                        Text(viewModel.settings.tokenConfirmationsNeeded.formatted(.number))
                            .frame(width: 30)
                        InfoButton("Number of consecutive tokens required for confirmation.")
                    }
                }
                .padding(.horizontal)
            }
        }
        .frame(minHeight: 700)
        .navigationTitle("Decoding Options")
        .toolbar {
            ToolbarItem {
                Button {
                    viewModel.uiState.showAdvancedOptions = false
                } label: {
                    Label("Done", systemImage: "xmark.circle.fill")
                        .foregroundColor(.primary)
                }
            }
        }
    }
}

#Preview {
    SettingsView(viewModel: ContentViewModel())
}
