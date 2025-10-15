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
//  CaptionMateApp.swift
//  CaptionMate
//
//  Created by 조형구 on 2/22/25.
//

import SwiftUI

@main
struct CaptionMateApp: App {
    @StateObject var contentViewModel: ContentViewModel = .init()
    @State private var showLegalInfo = false

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: contentViewModel)
                .frame(minWidth: 1000, minHeight: 700)
                .environment(\.locale, Locale(identifier: contentViewModel.appLanguage))
                .preferredColorScheme(contentViewModel.appTheme.colorScheme)
                .sheet(isPresented: $showLegalInfo) {
                    LegalView()
                }
        }
        .commands {
            CommandMenu("Shortcuts") {
                Button("Volume Up") {
                    contentViewModel.setVolume(min(1.0, contentViewModel.audioVolume + 0.05))
                }
                .keyboardShortcut(.upArrow, modifiers: [])
                .disabled(contentViewModel.audioVolume == 1.0)

                Button("Volume Down") {
                    contentViewModel.setVolume(max(0.0, contentViewModel.audioVolume - 0.05))
                }
                .keyboardShortcut(.downArrow, modifiers: [])
                .disabled(contentViewModel.audioVolume == 0.0)
            }

            CommandMenu("Settings") {
                Menu("Language") {
                    Button("English") {
                        contentViewModel.changeAppLanguage(to: "en")
                    }
                    .disabled(contentViewModel.appLanguage == "en")

                    Button("한국어") {
                        contentViewModel.changeAppLanguage(to: "ko")
                    }
                    .disabled(contentViewModel.appLanguage == "ko")
                }
                .disabled(
                    contentViewModel.uiState.isFilePickerPresented ||
                        contentViewModel.isExporting
                )

                Divider()

                Menu("Theme") {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        Button(action: {
                            contentViewModel.appTheme = theme
                        }) {
                            Text(theme.localizedName)
                        }
                        .disabled(theme == contentViewModel.appTheme)
                    }
                }

                Divider()

                Text("Current Language: \(contentViewModel.getCurrentLanguageDisplayName())")
                    .disabled(true)
            }

            CommandGroup(after: .help) {
                Button("legal_information") {
                    showLegalInfo = true
                }
            }
        }
    }
}
