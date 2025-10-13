//
//  Ex+Theme.swift
//  CaptionMate
//
//  Created by 조형구 on 10/9/25.
//

import SwiftUI

// MARK: - Theme Enum

enum AppTheme: String, CaseIterable {
    case light = "Light"
    case dark = "Dark"
    case auto = "Auto"

    var localizedName: LocalizedStringKey {
        switch self {
        case .light:
            return "theme.light"
        case .dark:
            return "theme.dark"
        case .auto:
            return "theme.auto"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light:
            return .light
        case .dark:
            return .dark
        case .auto:
            let appearance = NSApp.effectiveAppearance
            return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
        }
    }
}

// MARK: - Theme Colors Extension

extension Color {
    // MARK: - Transcription View Colors

    /// TranscriptionView 배경색
    static func transcriptionBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.12, green: 0.12, blue: 0.14) // 다크: 어두운 회색
            : Color(red: 0.99, green: 0.99, blue: 1.0) // 라이트: 연한 보라빛 흰색 (기존 lotionWhite)
    }

    // MARK: - Audio Control View Colors

    /// AudioControlView 메인 배경색
    static func audioControlBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.15, green: 0.15, blue: 0.17) // 다크: 진한 회색
            : Color(red: 0.95, green: 0.95, blue: 0.97) // 라이트: 연한 회색 (기존)
    }

    /// AudioControlView 내부 섹션 배경색
    static func audioControlSectionBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.18, green: 0.18, blue: 0.20) // 다크: 중간 회색
            : Color(red: 0.93, green: 0.93, blue: 0.95) // 라이트: 약간 진한 회색 (기존)
    }

    /// AudioControlView 컨테이너 배경색 (가장 밝은 배경)
    static func audioControlContainerBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.12, green: 0.12, blue: 0.14) // 다크: 어두운 배경
            : Color.white // 라이트: 흰색 (기존)
    }

    /// AudioControlView 구분선/테두리 색상
    static func audioControlDivider(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.25, green: 0.25, blue: 0.27) // 다크: 밝은 회색
            : Color(red: 0.9, green: 0.9, blue: 0.9) // 라이트: 연한 회색 (기존)
    }

    // MARK: - Audio Placeholder View Colors

    /// AudioPlaceholderView 배경색
    static func audioPlaceholderBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.15, green: 0.15, blue: 0.17) // 다크: 진한 회색
            : Color(red: 0.97, green: 0.97, blue: 0.99) // 라이트: 연한 회색 (기존)
    }

    // MARK: - WaveForm View Colors

    /// WaveFormView 배경색
    static func waveformBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.15, green: 0.15, blue: 0.17) // 다크: 진한 회색
            : Color(red: 0.96, green: 0.96, blue: 0.98) // 라이트: 연한 회색 (기존)
    }

    // MARK: - Control View Colors

    /// ControlsView 버튼 foreground 색상
    static func controlButtonForeground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.9, green: 0.9, blue: 0.92) // 다크: 밝은 회색
            : Color.white // 라이트: 흰색 (기존)
    }

    // MARK: - Model Selector View Colors

    /// ModelSelectorView 텍스트 색상
    static func modelSelectorText(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white // 다크: 흰색
            : Color.black // 라이트: 검정 (기존)
    }
}
