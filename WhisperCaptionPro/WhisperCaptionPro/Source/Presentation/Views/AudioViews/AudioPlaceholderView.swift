//
//  AudioPlaceholderView.swift
//  WhisperCaptionPro
//
//  Created by 조형구 on 4/16/25.
//

import SwiftUI

// Audio Palceholder
struct AudioPlaceholderView: View {
    // 드래그 중인지 여부
    var isTargeted: Bool = false

    // 글로우 애니메이션을 위한 상태 변수
    @State private var isGlowing = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack {
            Spacer()
            Image(systemName: "document.badge.plus")
                .font(.largeTitle)
                .foregroundColor(isTargeted ? .secondary : .brightGray)
                .padding(.bottom, 5)
            Text("Drag and drop a file here")
                .font(.headline)
                .foregroundColor(isTargeted ? .secondary : .brightGray)
            Spacer()
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                // 기본 배경
                RoundedRectangle(cornerRadius: 12)
                    .fill(isTargeted ?
                        Color.blue.opacity(0.05) : Color
                        .audioPlaceholderBackground(for: colorScheme))

                // 추가 글로우 효과 (드래그 중일 때만)
                if isTargeted {
                    RoundedRectangle(cornerRadius: 12)
                        .glow(
                            color: isGlowing ? .blue : .cyan,
                            lineWidth: isGlowing ? 1.5 : 1.0,
                            blurRadius: isGlowing ? 8 : 4
                        )
                        .opacity(isGlowing ? 0.8 : 0.6)
                }
            }
        )
        .animatedBorder(isActive: isTargeted)
        .padding(20)
        .onChange(of: isTargeted) { _, newValue in
            if newValue {
                // 드래그 중일 때 글로우 애니메이션 시작
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    isGlowing = true
                }
            } else {
                // 드래그가 끝났을 때 애니메이션 중단
                withAnimation {
                    isGlowing = false
                }
            }
        }
    }
}

// 움직이는 그라데이션 테두리 효과
struct AnimatedBorderModifier: ViewModifier {
    let isActive: Bool
    @State private var progress1: Double = 0.0
    @State private var progress2: Double = 0.0

    private let delay = 0.2

    func body(content: Content) -> some View {
        content
            .overlay {
                ZStack {
                    // 기본 테두리
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isActive ? Color.blue : Color.gray,
                            style: StrokeStyle(lineWidth: 2, dash: isActive ? [] : [6])
                        )

                    if isActive {
                        // 첫 번째 움직이는 그라데이션
                        ProgressBorderView(progress: progress1)

                        // 두 번째 움직이는 그라데이션 (반대 방향)
                        ProgressBorderView(progress: progress2)
                            .rotationEffect(.degrees(180))
                    }
                }
            }

            .onChange(of: isActive) { _, newValue in
                if newValue {
                    // 첫 번째 애니메이션
                    withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                        progress1 = 1.0
                    }

                    // 두 번째 애니메이션 (딜레이 적용)
                    withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)
                        .delay(1.0)) {
                            progress2 = 1.0
                        }
                } else {
                    // 애니메이션 리셋
                    progress1 = 0.0
                    progress2 = 0.0
                }
            }
    }
}

// 프로그레스 테두리 뷰
struct ProgressBorderView: View, Animatable {
    var progress: Double
    private let delay = 0.2

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .trim(
                from: {
                    if progress > delay {
                        progress - delay
                    } else {
                        0
                    }
                }(),
                to: {
                    if progress > 0.5 {
                        0.5
                    } else {
                        progress
                    }
                }()
            )
            .stroke(
                LinearGradient(
                    colors: [.blue, .cyan, .blue.opacity(0.5)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )
            .blur(radius: 2)
            .opacity(0.9)
    }
}

#Preview {
    AudioPlaceholderView(isTargeted: true)
}
