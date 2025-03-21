//
//  ContentView.swift
//  WhisperCaptionPro
//
//  Created by 조형구 on 2/22/25.
//

import SwiftUI
import WhisperKit

struct ContentView: View {
    @StateObject var viewModel = ContentViewModel()

    var body: some View {
        NavigationSplitView(columnVisibility: $viewModel.columnVisibility) {
            VStack(alignment: .leading) {
                ModelSelectorView(viewModel: viewModel)
                    .padding(.vertical)
                ComputeUnitsView(viewModel: viewModel)
                    .disabled(viewModel.modelState != .loaded && viewModel.modelState != .unloaded)
                    .padding(.bottom)

                List(viewModel.menu, selection: $viewModel.selectedCategoryId) { item in
                    HStack {
                        Image(systemName: item.image)
                        Text(item.name)
                            .font(.title3)
                            .bold()
                    }
                }
                .onChange(of: viewModel.selectedCategoryId) { newValue, _ in
                    viewModel.selectedTab = viewModel.menu.first(where: { $0.id == newValue })?
                        .name ?? "Transcribe"
                }
                .disabled(viewModel.modelState != .loaded)
                .foregroundColor(viewModel.modelState != .loaded ? .secondary : .primary)

                Spacer()

                // 앱 및 디바이스 정보
                VStack(alignment: .leading, spacing: 4) {
                    let version = Bundle.main
                        .infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
                    let build = Bundle.main
                        .infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
                    Text("App Version: \(version) (\(build))")
                    #if os(iOS)
                        Text("Device Model: \(WhisperKit.deviceName())")
                        Text("OS Version: \(UIDevice.current.systemVersion)")
                    #elseif os(macOS)
                        Text("Device Model: \(WhisperKit.deviceName())")
                        Text("OS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)")
                    #endif
                }
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
                .padding(.vertical)
            }
            .navigationTitle("WhisperAX")
            .navigationSplitViewColumnWidth(min: 300, ideal: 350)
            .padding(.horizontal)
            Spacer()
        } detail: {
            VStack {
                #if os(iOS)
                    ModelSelectorView(viewModel: viewModel)
                        .padding()
                    TranscriptionView(viewModel: viewModel)
                #elseif os(macOS)
                    VStack(alignment: .leading) {
                        TranscriptionView(viewModel: viewModel)
                    }
                    .padding()
                #endif
                ControlsView(viewModel: viewModel)
            }
            .toolbar {
                ToolbarItem {
                    Button {
                        if !viewModel.enableEagerDecoding {
                            let fullTranscript = formatSegments(
                                viewModel.confirmedSegments + viewModel.unconfirmedSegments,
                                withTimestamps: viewModel.enableTimestamps
                            ).joined(separator: "\n")
                            #if os(iOS)
                                UIPasteboard.general.string = fullTranscript
                            #elseif os(macOS)
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(fullTranscript, forType: .string)
                            #endif
                        } else {
                            #if os(iOS)
                                UIPasteboard.general.string = viewModel.confirmedText + viewModel
                                    .hypothesisText
                            #elseif os(macOS)
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(
                                    viewModel.confirmedText + viewModel.hypothesisText,
                                    forType: .string
                                )
                            #endif
                        }
                    } label: {
                        Label("Copy Text", systemImage: "doc.on.doc")
                    }
                    .keyboardShortcut("c", modifiers: .command)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear {
            #if os(macOS)
                viewModel.selectedCategoryId = viewModel.menu
                    .first(where: { $0.name == viewModel.selectedTab })?.id
            #else
                if UIDevice.current.userInterfaceIdiom == .pad {
                    viewModel.selectedCategoryId = viewModel.menu
                        .first(where: { $0.name == viewModel.selectedTab })?.id
                }
            #endif
            viewModel.fetchModels()
        }
    }
}

#Preview {
    ContentView()
    #if os(macOS)
        .frame(width: 800, height: 500)
    #endif
}
