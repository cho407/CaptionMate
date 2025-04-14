//
//  WaveFormView.swift
//  WhisperCaptionPro
//
//  Created by 조형구 on 4/14/25.
//

import SwiftUI

// 오디오 파형을 시각화하는 뷰
struct WaveFormView: View {
    let samples: [Float]
    let currentTime: Double
    let totalDuration: Double
    let onSeek: (Double) -> Void
    
    @State private var hoverLocation: CGFloat? = nil
    @State private var isDragging: Bool = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // 파형 배경 (라이트 모드 스타일)
                Rectangle()
                    .fill(Color(red: 0.96, green: 0.96, blue: 0.98))
                    .frame(width: geometry.size.width, height: geometry.size.height)
                
                // 파형 그리기
                Path { path in
                    let width = geometry.size.width
                    let height = geometry.size.height
                    let middle = height / 2
                    
                    // 샘플 수가 너무 많으면 다운샘플링하여 표시
                    let maxSamples = 500 // 더 세밀한 파형을 위해 최대 샘플 수 증가
                    let sampleStep = max(1, samples.count / maxSamples)
                    let step = width / CGFloat(maxSamples)
                    
                    path.move(to: CGPoint(x: 0, y: middle))
                    
                    for i in stride(from: 0, to: min(samples.count, sampleStep * maxSamples), by: sampleStep) {
                        let x = CGFloat(i / sampleStep) * step
                        let amplitude = CGFloat(samples[i]) * height / 2.0 // 더 큰 파형을 위해 진폭 증가
                        let y = middle - amplitude
                        
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                    
                    for i in stride(from: min(samples.count - 1, sampleStep * maxSamples - 1), to: 0, by: -sampleStep) {
                        let x = CGFloat(i / sampleStep) * step
                        let amplitude = CGFloat(samples[i]) * height / 2.0 // 더 큰 파형을 위해 진폭 증가
                        let y = middle + amplitude
                        
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                    
                    path.closeSubpath()
                }
                .fill(Color.blue.opacity(0.5)) // 라이트 모드에 맞는 블루 색상
                
                // 재생 진행 표시 (투명도가 있는 영역)
                if totalDuration > 0 {
                    Rectangle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: geometry.size.width * CGFloat(currentTime / totalDuration), height: geometry.size.height)
                }
                
                // 재생 위치를 표시하는 요소들 그룹
                ZStack {
                    // 현재 재생 위치를 나타내는 세로 바 (파란색)
                    if totalDuration > 0 {
                        Rectangle()
                            .fill(Color.blue) // 라이트 모드 스타일의 파란색 현재 위치 선
                            .frame(width: 1, height: geometry.size.height) // 두께를 1로 줄임
                            .offset(x: geometry.size.width * CGFloat(currentTime / totalDuration) - 0.5) // 위치 조정
                            .zIndex(100)
                    }
                    
                    // 마우스 호버 위치를 나타내는 세로 바 (빨간색)
                    if let hoverPos = hoverLocation, !isDragging {
                        Rectangle()
                            .fill(Color.red) // 마우스가 위치한 곳을 표시하는 빨간색 선
                            .frame(width: 1, height: geometry.size.height) // 두께를 1로 줄임
                            .offset(x: hoverPos - 0.5) // 위치 조정
                            .zIndex(90)
                    }
                    
                    // 드래그 중인 위치를 나타내는 세로 바 (빨간색)
                    if isDragging, let hoverPos = hoverLocation {
                        Rectangle()
                            .fill(Color.red) // 드래그 중인 위치를 표시하는 빨간색 선
                            .frame(width: 1, height: geometry.size.height) // 두께를 1로 줄임
                            .offset(x: hoverPos - 0.5) // 위치 조정
                            .zIndex(95)
                    }
                }
                
                // 그리드 라인 (라이트 모드 스타일)
                Path { path in
                    let height = geometry.size.height
                    let width = geometry.size.width
                    
                    // 가로 그리드 라인 (중앙)
                    path.move(to: CGPoint(x: 0, y: height / 2))
                    path.addLine(to: CGPoint(x: width, y: height / 2))
                    
                    // 시간 간격 표시 (10% 단위로 세로 그리드 라인)
                    for i in 1..<10 {
                        let x = width * CGFloat(i) / 10.0
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: height))
                    }
                }
                .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                
                // 터치 영역 (탭으로 위치 이동)
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isDragging = true
                                let percentage = value.location.x / geometry.size.width
                                let newTime = Double(percentage) * totalDuration
                                hoverLocation = value.location.x
                                onSeek(max(0, min(newTime, totalDuration)))
                            }
                            .onEnded { value in
                                isDragging = false
                                let percentage = value.location.x / geometry.size.width
                                let newTime = Double(percentage) * totalDuration
                                hoverLocation = nil
                                onSeek(max(0, min(newTime, totalDuration)))
                            }
                    )
                    .onHover { hovering in
                        if !hovering && !isDragging {
                            hoverLocation = nil
                        }
                    }
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            if !isDragging {
                                hoverLocation = location.x
                            }
                        case .ended:
                            if !isDragging {
                                hoverLocation = nil
                            }
                        }
                    }
            }
        }
    }
}
