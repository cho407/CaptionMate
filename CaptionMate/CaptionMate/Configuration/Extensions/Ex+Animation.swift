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
