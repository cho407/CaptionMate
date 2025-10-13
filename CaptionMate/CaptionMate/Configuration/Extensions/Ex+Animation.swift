//
//  Ex+Animation.swift
//  CaptionMate
//
//  Created by 조형구 on 4/16/25.
//

import Foundation
import SwiftUI

// Shape에 글로우 효과를 추가하는 확장
extension Shape {
    func glow(color: Color, lineWidth: CGFloat, blurRadius: CGFloat = 4.0) -> some View {
        stroke(color, lineWidth: lineWidth)
            .overlay {
                self
                    .stroke(color, lineWidth: lineWidth * 2)
                    .blur(radius: blurRadius)
                    .opacity(0.7)
            }
            .overlay {
                self
                    .stroke(color, lineWidth: lineWidth)
                    .blur(radius: blurRadius / 2)
                    .opacity(0.9)
            }
    }
}

extension View {
    func animatedBorder(isActive: Bool) -> some View {
        modifier(AnimatedBorderModifier(isActive: isActive))
    }
}
