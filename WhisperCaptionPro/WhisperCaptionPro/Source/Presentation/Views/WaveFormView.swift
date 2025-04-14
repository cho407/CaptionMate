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
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // 파형 배경
                Path { path in
                    let width = geometry.size.width
                    let height = geometry.size.height
                    let middle = height / 2
                    
                    // 샘플 수가 너무 많으면 다운샘플링하여 표시
                    let maxSamples = 200 // 최대 샘플 수 제한
                    let sampleStep = max(1, samples.count / maxSamples)
                    let step = width / CGFloat(samples.count / sampleStep)
                    
                    path.move(to: CGPoint(x: 0, y: middle))
                    
                    for i in stride(from: 0, to: samples.count, by: sampleStep) {
                        let x = CGFloat(i / sampleStep) * step
                        let amplitude = CGFloat(samples[i]) * height / 2
                        let y = middle - amplitude
                        
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                    
                    for i in stride(from: samples.count - 1, to: 0, by: -sampleStep) {
                        let x = CGFloat(i / sampleStep) * step
                        let amplitude = CGFloat(samples[i]) * height / 2
                        let y = middle + amplitude
                        
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                    
                    path.closeSubpath()
                }
                .fill(Color.blue.opacity(0.3))
                .overlay(
                    Path { path in
                        let width = geometry.size.width
                        let height = geometry.size.height
                        let middle = height / 2
                        
                        // 샘플 수가 너무 많으면 다운샘플링하여 표시
                        let maxSamples = 200 // 최대 샘플 수 제한
                        let sampleStep = max(1, samples.count / maxSamples)
                        let step = width / CGFloat(samples.count / sampleStep)
                        
                        path.move(to: CGPoint(x: 0, y: middle))
                        
                        for i in stride(from: 0, to: samples.count, by: sampleStep) {
                            let x = CGFloat(i / sampleStep) * step
                            let amplitude = CGFloat(samples[i]) * height / 2
                            let y = middle - amplitude
                            
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    .stroke(Color.blue, lineWidth: 1)
                )
                
                // 재생 위치 표시
                if totalDuration > 0 {
                    Rectangle()
                        .fill(Color.blue.opacity(0.5))
                        .frame(width: geometry.size.width * CGFloat(currentTime / totalDuration), height: geometry.size.height)
                }
                
                // 터치 영역 (탭으로 위치 이동)
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let percentage = value.location.x / geometry.size.width
                                let newTime = Double(percentage) * totalDuration
                                onSeek(max(0, min(newTime, totalDuration)))
                            }
                            .onEnded { value in
                                let percentage = value.location.x / geometry.size.width
                                let newTime = Double(percentage) * totalDuration
                                onSeek(max(0, min(newTime, totalDuration)))
                            }
                    )
            }
        }
    }
}
