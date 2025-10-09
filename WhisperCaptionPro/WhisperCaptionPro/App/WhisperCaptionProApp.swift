//
//  WhisperCaptionProApp.swift
//  WhisperCaptionPro
//
//  Created by 조형구 on 2/22/25.
//

import SwiftUI

@main
struct WhisperCaptionProApp: App {
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
                .keyboardShortcut(.downArrow, modifiers: []) // ↓ 키만 눌러도 실행
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
                    contentViewModel.uiState.isFilePickerPresented || // 파일 불러오기 창 열림
                        contentViewModel.isExporting // 자막 내보내기 창 열림
                )

                Divider()

                Menu("Theme") {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        Button(action: {
                            contentViewModel.appTheme = theme
                        }) {
                            HStack {
                                Text(theme.localizedName)
                                if contentViewModel.appTheme == theme {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
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
