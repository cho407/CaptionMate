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
    @NSApplicationDelegateAdaptor(ProjectCloseGuard.self) private var projectCloseGuard
    @StateObject var contentViewModel: ContentViewModel = .init()
    @State private var showLegalInfo = false

    var body: some Scene {
        Window("CaptionMate", id: "main") {
            ContentView(viewModel: contentViewModel)
                .frame(minWidth: 1000, minHeight: 700)
                .background(ProjectWindowCloseGuard(closeGuard: projectCloseGuard))
                .environment(\.locale, Locale(identifier: contentViewModel.appLanguage))
                .preferredColorScheme(contentViewModel.appTheme.colorScheme)
                .onAppear {
                    projectCloseGuard.confirmDiscardingChanges = { [weak contentViewModel] in
                        contentViewModel?.confirmDiscardingUnsavedChanges() ?? true
                    }
                    projectCloseGuard.prepareForTermination = { [weak contentViewModel] in
                        contentViewModel?.prepareForClose()
                    }
                    stabilizeWindowForUITestingIfNeeded()
                }
                .onChange(of: contentViewModel.appLanguage) { _, _ in
                    refreshMenuBarLocalization()
                }
                .sheet(isPresented: $showLegalInfo) {
                    LegalView()
                        .environment(\.locale, Locale(identifier: contentViewModel.appLanguage))
                }
        }
        .environment(\.locale, Locale(identifier: contentViewModel.appLanguage))
        .commands {
            CommandGroup(replacing: .saveItem) {
                Button(localizedMenuBarText("Save Project")) {
                    contentViewModel.saveCurrentProject()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!contentViewModel.canSaveCurrentProject || contentViewModel.projectLibraryState.isSaving)
            }

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
        MenuBarLocalization.text(
            key,
            language: menuBarLanguage,
            arguments: arguments
        )
    }

    private var menuBarLanguage: String {
        contentViewModel.appLanguage
    }

    private func refreshMenuBarLocalization() {
#if os(macOS)
        let language = contentViewModel.appLanguage
        let currentLanguageName = contentViewModel.getCurrentLanguageDisplayName()
        let supportedLanguages = contentViewModel.supportedAppLanguages

        // SwiftUI commands can keep their initial titles in the native menu bar.
        // Wait for menu tracking to finish before touching AppKit's top-level items.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            MenuBarLocalization.refreshMainMenu(
                language: language,
                currentLanguageName: currentLanguageName,
                supportedLanguages: supportedLanguages
            )
        }
#endif
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

#if os(macOS)
@MainActor
private enum MenuBarLocalization {
    private static let languageCodes = [
        "en-US", "en-GB", "ko", "ja", "es", "de", "fr", "pt-BR", "hi", "ar", "zh-Hans",
    ]

    static func text(
        _ key: String,
        language: String,
        arguments: [CVarArg] = []
    ) -> String {
        let format = bundle(for: language).localizedString(
            forKey: key,
            value: key,
            table: nil
        )
        guard !arguments.isEmpty else { return format }
        return String(
            format: format,
            locale: Locale(identifier: language),
            arguments: arguments
        )
    }

    static func refreshMainMenu(
        language: String,
        currentLanguageName: String,
        supportedLanguages: [AppLanguageOption]
    ) {
        guard let mainMenu = NSApp.mainMenu else { return }

        // AppKit owns these menus, so only update matching top-level items.
        // Avoid positional assumptions because SwiftUI can insert app commands.
        refreshSystemMenuTitles(in: mainMenu, language: language)

        let shortcutsItem = updateItem(
            in: mainMenu,
            key: "Shortcuts",
            language: language
        )
        if let shortcutsMenu = shortcutsItem?.submenu {
            _ = updateItem(in: shortcutsMenu, key: "Volume Up", language: language)
            _ = updateItem(in: shortcutsMenu, key: "Volume Down", language: language)
        }

        let settingsItem = updateItem(
            in: mainMenu,
            key: "Settings",
            language: language
        )
        if let settingsMenu = settingsItem?.submenu {
            let languageItem = updateItem(in: settingsMenu, key: "Language", language: language)
            if let languageMenu = languageItem?.submenu {
                updateLanguageMenuState(
                    languageMenu,
                    selectedLanguage: language,
                    supportedLanguages: supportedLanguages
                )
            }
            _ = updateItem(in: settingsMenu, key: "Theme", language: language)
            updateCurrentLanguageItem(
                in: settingsMenu,
                language: language,
                currentLanguageName: currentLanguageName
            )
        }

        for key in ["legal_information", "Save Project"] {
            if let item = findItem(in: mainMenu, titles: localizedTitles(for: key)) {
                item.title = text(key, language: language)
            }
        }
    }

    private static func refreshSystemMenuTitles(in menu: NSMenu, language: String) {
        for (key, titles) in systemMenuTitles {
            let knownTitles = Set(titles.values)
            guard let item = menu.items.first(where: { knownTitles.contains($0.title) }) else {
                continue
            }

            let baseLanguage = language.split(separator: "-").first.map(String.init) ?? language
            item.title = titles[language] ?? titles[baseLanguage] ?? titles["en"] ?? key
        }
    }

    private static func updateItem(in menu: NSMenu, key: String, language: String) -> NSMenuItem? {
        guard let item = findItem(in: menu, titles: localizedTitles(for: key)) else {
            return nil
        }
        let localizedTitle = text(key, language: language)
        item.title = localizedTitle
        return item
    }

    private static func updateCurrentLanguageItem(
        in menu: NSMenu,
        language: String,
        currentLanguageName: String
    ) {
        let prefixes = Set(languageCodes.map { code in
            text("Current Language: %@", language: code, arguments: [""])
        })
        guard let item = menu.items.first(where: { item in
            prefixes.contains { item.title.hasPrefix($0) }
        }) else {
            return
        }
        item.title = text(
            "Current Language: %@",
            language: language,
            arguments: [currentLanguageName]
        )
    }

    private static func updateLanguageMenuState(
        _ menu: NSMenu,
        selectedLanguage: String,
        supportedLanguages: [AppLanguageOption]
    ) {
        for item in menu.items {
            guard let option = supportedLanguages.first(where: { $0.displayName == item.title }) else {
                continue
            }
            item.isEnabled = option.code != selectedLanguage
        }
    }

    private static func localizedTitles(for key: String) -> Set<String> {
        Set(languageCodes.map { text(key, language: $0) })
    }

    private static func findItem(in menu: NSMenu, titles: Set<String>) -> NSMenuItem? {
        for item in menu.items {
            if titles.contains(item.title) {
                return item
            }
            if let submenu = item.submenu,
               let nestedItem = findItem(in: submenu, titles: titles) {
                return nestedItem
            }
        }
        return nil
    }

    private static func bundle(for language: String) -> Bundle {
        let baseLanguageCode = language.split(separator: "-").first.map(String.init)
        var candidates = [language]
        if language == "en-US" {
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

    private static let systemMenuTitles: [String: [String: String]] = [
        "File": [
            "en": "File", "en-US": "File", "en-GB": "File", "ko": "파일", "ja": "ファイル",
            "es": "Archivo", "de": "Ablage", "fr": "Fichier", "pt-BR": "Arquivo",
            "hi": "फ़ाइल", "ar": "ملف", "zh-Hans": "文件",
        ],
        "Edit": [
            "en": "Edit", "en-US": "Edit", "en-GB": "Edit", "ko": "편집", "ja": "編集",
            "es": "Editar", "de": "Bearbeiten", "fr": "Édition", "pt-BR": "Editar",
            "hi": "संपादन", "ar": "تحرير", "zh-Hans": "编辑",
        ],
        "View": [
            "en": "View", "en-US": "View", "en-GB": "View", "ko": "보기", "ja": "表示",
            "es": "Ver", "de": "Darstellung", "fr": "Présentation", "pt-BR": "Visualizar",
            "hi": "दृश्य", "ar": "عرض", "zh-Hans": "显示",
        ],
        "Window": [
            "en": "Window", "en-US": "Window", "en-GB": "Window", "ko": "윈도우", "ja": "ウインドウ",
            "es": "Ventana", "de": "Fenster", "fr": "Fenêtre", "pt-BR": "Janela",
            "hi": "विंडो", "ar": "نافذة", "zh-Hans": "窗口",
        ],
        "Help": [
            "en": "Help", "en-US": "Help", "en-GB": "Help", "ko": "도움말", "ja": "ヘルプ",
            "es": "Ayuda", "de": "Hilfe", "fr": "Aide", "pt-BR": "Ajuda",
            "hi": "सहायता", "ar": "مساعدة", "zh-Hans": "帮助",
        ],
    ]
}
#endif
