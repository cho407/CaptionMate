//
//  Constants.swift
//  CaptionMate
//
//  Created by 조형구 on 3/3/25.
//

import SwiftUI

// 1) 버튼 스타일 정의
struct SimpleButtonStyle: ButtonStyle {
    var background: Color = .blue
    var foreground: Color = .white
    var cornerRadius: CGFloat = 6
    var horizontalPadding: CGFloat = 12
    var verticalPadding: CGFloat = 8
    var pressedScale: CGFloat = 0.95

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(background)
            .foregroundColor(foreground)
            .cornerRadius(cornerRadius)
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// 2) View에 붙이기 위한 extension
extension View {
    func simpleButtonStyle(background: Color = .blue,
                           foreground: Color = .white,
                           cornerRadius: CGFloat = 6,
                           horizontalPadding: CGFloat = 12,
                           verticalPadding: CGFloat = 8,
                           pressedScale: CGFloat = 0.95) -> some View {
        buttonStyle(
            SimpleButtonStyle(
                background: background,
                foreground: foreground,
                cornerRadius: cornerRadius,
                horizontalPadding: horizontalPadding,
                verticalPadding: verticalPadding,
                pressedScale: pressedScale
            )
        )
    }
}
