//
//  WhisperCaptionProApp.swift
//  WhisperCaptionPro
//
//  Created by 조형구 on 2/22/25.
//

import SwiftData
import SwiftUI

@main
struct WhisperCaptionProApp: App {
    @StateObject var contentViewModel: ContentViewModel = ContentViewModel()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: contentViewModel)
                .frame(minWidth: 1000, minHeight: 700)
                .environment(\.locale, Locale(identifier: contentViewModel.appLanguage))
        }
        .modelContainer(sharedModelContainer)
        // MARK: - 상단 툴바
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
                
                Divider()
                
                Text("Current Language: \(contentViewModel.getCurrentLanguageDisplayName())")
                    .disabled(true)
            }
        }
    }
}
