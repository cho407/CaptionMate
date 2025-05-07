//
//  LoadingDotsView.swift
//  WhisperCaptionPro
//
//  Created by 조형구 on 5/7/25.
//

import SwiftUI
import Combine

// 간단한 로딩 점 애니메이션 뷰
struct LoadingDotsView: View {
    let text: String
    @State private var dotsCount = 0
    
    // 타이머 참조 보관용
    @State private var timer: Timer.TimerPublisher = Timer.publish(every: 0.3, on: .main, in: .common)
    @State private var timerCancellable: Cancellable? = nil
    
    var body: some View {
        HStack(spacing: 0) {
            Text(text)
            
            // 점 애니메이션
            Text(dotString())
                .frame(width: 30, alignment: .leading)
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
    
    // 타이머 시작
    private func startTimer() {
        timer = Timer.publish(every: 0.3, on: .main, in: .common)
        timerCancellable = timer.autoconnect().sink { _ in
            dotsCount = (dotsCount + 1) % 4
        }
    }
    
    // 타이머 정지
    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }
}
#Preview {
    LoadingDotsView(text: "")
}
