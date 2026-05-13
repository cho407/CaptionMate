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

#if os(macOS)
import AppKit
#endif

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
                .onAppear {
                    stabilizeWindowForUITestingIfNeeded()
                }
                .sheet(isPresented: $showLegalInfo) {
                    LegalView()
                        .environment(\.locale, Locale(identifier: contentViewModel.appLanguage))
                }
        }
        .environment(\.locale, Locale(identifier: contentViewModel.appLanguage))
        .commands {
            CommandMenu(localizedMenuBarText("Shortcuts")) {
                Button(localizedMenuBarText("Volume Up")) {
                    contentViewModel.setVolume(min(1.0, contentViewModel.audioVolume + 0.05))
                }
                .keyboardShortcut(.upArrow, modifiers: [])
                .disabled(contentViewModel.audioVolume == 1.0)

                Button(localizedMenuBarText("Volume Down")) {
                    contentViewModel.setVolume(max(0.0, contentViewModel.audioVolume - 0.05))
                }
                .keyboardShortcut(.downArrow, modifiers: [])
                .disabled(contentViewModel.audioVolume == 0.0)
            }

            CommandMenu(localizedMenuBarText("Settings")) {
                Menu(localizedMenuBarText("Language")) {
                    ForEach(contentViewModel.supportedAppLanguages) { language in
                        Button(language.displayName) {
                            contentViewModel.changeAppLanguage(to: language.code)
                        }
                        .disabled(contentViewModel.appLanguage == language.code)
                    }
                }
                .disabled(
                    contentViewModel.uiState.isFilePickerPresented ||
                        contentViewModel.isExporting
                )

                Divider()

                Menu(localizedMenuBarText("Theme")) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        Button(action: {
                            contentViewModel.appTheme = theme
                        }) {
                            Text(localizedMenuBarText(theme.menuBarLocalizationKey))
                        }
                        .disabled(theme == contentViewModel.appTheme)
                    }
                }

                Divider()

                Text(localizedMenuBarText(
                    "Current Language: %@",
                    contentViewModel.getCurrentLanguageDisplayName()
                ))
                    .disabled(true)
            }

            CommandGroup(after: .help) {
                Button(localizedMenuBarText("legal_information")) {
                    showLegalInfo = true
                }
            }
        }
    }

    private func localizedMenuBarText(_ key: String, _ arguments: CVarArg...) -> String {
        let format = NSLocalizedString(key, bundle: menuBarLocalizationBundle, comment: "")
        guard !arguments.isEmpty else { return format }
        return String(
            format: format,
            locale: Locale(identifier: menuBarLanguage),
            arguments: arguments
        )
    }

    private var menuBarLanguage: String {
        contentViewModel.appLanguage
    }

    private var menuBarLocalizationBundle: Bundle {
        let languageCode = menuBarLanguage
        let baseLanguageCode = languageCode.split(separator: "-").first.map(String.init)
        var candidates = [languageCode]
        if languageCode == "en-US" {
            candidates.append("en")
        } else if let baseLanguageCode {
            candidates.append(baseLanguageCode)
        }
        candidates.append("en")

        for candidate in candidates {
            if let path = Bundle.main.path(forResource: candidate, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }

        return .main
    }

    private func stabilizeWindowForUITestingIfNeeded() {
#if DEBUG && os(macOS)
        guard ProcessInfo.processInfo.arguments.contains("-CaptionMateUITestResetDefaults"),
              let screenFrame = NSScreen.main?.visibleFrame else {
            return
        }

        DispatchQueue.main.async {
            let width = min(max(1000, screenFrame.width * 0.8), screenFrame.width)
            let height = min(max(700, screenFrame.height * 0.8), screenFrame.height)
            let frame = NSRect(
                x: screenFrame.midX - width / 2,
                y: screenFrame.midY - height / 2,
                width: width,
                height: height
            )

            NSApplication.shared.windows
                .first { $0.isVisible && $0.contentView != nil }?
                .setFrame(frame, display: true)
        }
#endif
    }
}

private extension AppTheme {
    var menuBarLocalizationKey: String {
        switch self {
        case .light:
            return "theme.light"
        case .dark:
            return "theme.dark"
        case .auto:
            return "theme.auto"
        }
    }
}
