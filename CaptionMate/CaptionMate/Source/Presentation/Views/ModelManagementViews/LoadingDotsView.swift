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
//  LoadingDotsView.swift
//  CaptionMate
//
//  Created by 조형구 on 5/7/25.
//

import Combine
import SwiftUI

// 로딩 점 애니메이션을 위한 ViewModifier
struct LoadingDotsModifier: ViewModifier {
    let text: String
    @State private var dotsCount = 0
    @State private var timer: AnyCancellable?
    private let id = UUID() // 각 인스턴스를 구분하기 위한 고유 ID

    func body(content: Content) -> some View {
        HStack(spacing: 0) {
            Text(text)

            // 점 애니메이션
            Text(dotString())
                .frame(width: 30, alignment: .leading)
                .id("dots-\(id)") // 고유 ID로 식별
        }
        .onAppear {
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
    }

    // 점의 개수에 따른 문자열 생성
    private func dotString() -> String {
        switch dotsCount {
        case 0: return " "
        case 1: return "."
        case 2: return ".."
        case 3: return "..."
        default: return " "
        }
    }

    // 타이머 시작 - Combine 사용
    private func startTimer() {
        stopTimer() // 기존 타이머 정리

        timer = Timer.publish(every: 0.3, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                dotsCount = (dotsCount + 1) % 4
            }
    }

    // 타이머 정지
    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }
}

// 뷰에 로딩 점 애니메이션을 추가하는 확장
extension View {
    func withLoadingDots(_ text: String) -> some View {
        modifier(LoadingDotsModifier(text: text))
    }
}

// 기존 LoadingDotsView 유지 (하위 호환성)
struct LoadingDotsView: View {
    let text: String

    var body: some View {
        EmptyView()
            .withLoadingDots(text)
    }
}

// 더 깔끔한 사용을 위한 String 확장
extension String {
    func withLoadingDots() -> some View {
        EmptyView().withLoadingDots(self)
    }
}

#Preview {
    VStack(spacing: 20) {
        LoadingDotsView(text: "기존 방식 로딩 중")

        Text("").withLoadingDots("새로운 방식 로딩 중")

        "직접 문자열 로딩 중".withLoadingDots()
    }
}
