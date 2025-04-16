//
//  WaveFormView.swift
//  WhisperCaptionPro
//
//  Created by 조형구 on 4/14/25.
//

import SwiftUI

// 오디오 파형을 시각화하는 뷰
struct WaveFormView: View {
    @ObservedObject var viewModel: ContentViewModel
    
    let samples: [Float]
    let currentTime: Double
    let totalDuration: Double
    let onSeek: (Double) -> Void
    
    @State private var hoverLocation: CGFloat? = nil
    @State private var isDragging: Bool = false
    @State private var viewWidth: CGFloat = 0
    @State private var calculatedLineTime: Double = 120.0
    @State private var hoveredLineIndex: Int? = nil
    @State private var isInitialRender: Bool = false
    
    private let waveformHeight: CGFloat = 80
    private let verticalPadding: CGFloat = 3
    
    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: verticalPadding) { // 줄 간격 추가
                        ForEach(0..<max(1, Int(ceil(totalDuration / calculatedLineTime))), id: \.self) { lineIndex in
                            WaveformLineView(
                                viewModel: viewModel,
                                lineIndex: lineIndex,
                                samples: samples,
                                currentTime: currentTime,
                                totalDuration: max(0.001, totalDuration), // 0으로 나누는 것을 방지하기 위함
                                secondsPerLine: calculatedLineTime,
                                availableWidth: geometry.size.width - 40, // 32에서 40으로 좌우 여백 더 확보
                                waveformHeight: waveformHeight,
                                hoveredLineIndex: $hoveredLineIndex,
                                hoverLocation: $hoverLocation,
                                isDragging: $isDragging,
                                onSeek: onSeek
                            )
                            .id("line-\(lineIndex)")
                            .frame(width: geometry.size.width - 40) // 32에서 40으로 변경
                            .padding(.vertical, verticalPadding) // 각 줄에 상하 패딩 추가
                        }
                    }
                    .padding(.horizontal, 20) // 16에서 20으로 좌우 여백 더 확보
                    .padding(.vertical, verticalPadding) // 12에서 원래 값인 verticalPadding으로 복구
                    .id("content-\(Int(geometry.size.width))-\(Int(totalDuration))")
                }
                .onAppear {
                    // 초기 설정
                    viewWidth = geometry.size.width
                    updateLineTime(width: geometry.size.width)
                    
                    // 오디오가 로드되면 현재 재생 위치로 즉시 스크롤
                    if totalDuration > 0 {
                        DispatchQueue.main.async {
                            scrollToCurrentLine(proxy: proxy)
                            isInitialRender = true
                        }
                    }
                }
                .onChange(of: currentTime) { oldValue, newValue in
                    // 재생 위치가 바뀌면 해당 라인으로 스크롤
                    if totalDuration > 0 {
                        let oldLineIndex = Int(oldValue / calculatedLineTime)
                        let newLineIndex = Int(newValue / calculatedLineTime)
                        if oldLineIndex != newLineIndex {
                            withAnimation {
                                proxy.scrollTo("line-\(newLineIndex)", anchor: .top)
                            }
                        }
                    }
                }
                .onChange(of: geometry.size.width) { _, newWidth in
                    // 화면 너비가 변경될 때 파형 크기 조정
                    viewWidth = newWidth
                    let oldTime = calculatedLineTime
                    updateLineTime(width: newWidth)
                    
                    // 화면 크기 변경 후 스크롤 위치 유지
                    if oldTime != calculatedLineTime && totalDuration > 0 {
                        DispatchQueue.main.async {
                            scrollToCurrentLine(proxy: proxy)
                        }
                    }
                }
                .onChange(of: totalDuration) { _, newDuration in
                    // 오디오 파일이 변경되면 파형 다시 계산
                    if newDuration > 0 {
                        updateLineTime(width: viewWidth)
                        DispatchQueue.main.async {
                            scrollToCurrentLine(proxy: proxy)
                        }
                    }
                }
                .onChange(of: samples.count) { oldCount, newCount in
                    // 샘플 데이터가 변경되면 업데이트
                    if newCount > 0 && oldCount != newCount {
                        DispatchQueue.main.async {
                            scrollToCurrentLine(proxy: proxy)
                        }
                    }
                }
            }
        }
        .frame(minHeight: 100)
    }
    
    // 화면 너비에 따른 한 줄당 표시 시간 계산 (최적화된 로직)
    private func updateLineTime(width: CGFloat) {
        let availableWidth = max(300, width - 40) // 32에서 40으로 변경하여 일관성 유지
        
        // 픽셀당 시간 계산 (1픽셀당 0.15초가 적절) - 더 세밀한 파형을 위해 조정
        let pixelsPerSecond = 6.0 // 1초당 약 6픽셀
        let rawSeconds = availableWidth / CGFloat(pixelsPerSecond)
        
        // 적절한 범위로 제한 (최소 30초, 최대 5분)
        let boundedSeconds = min(300.0, max(30.0, Double(rawSeconds)))
        
        // 30초 단위로 반올림하여 자연스러운 시간 단위 사용
        let roundedSeconds = ceil(boundedSeconds / 30.0) * 30.0
        
        calculatedLineTime = roundedSeconds
    }
    
    // 현재 재생 시간에 해당하는 라인으로 스크롤
    private func scrollToCurrentLine(proxy: ScrollViewProxy) {
        if totalDuration > 0 {
            let currentLineIndex = Int(currentTime / calculatedLineTime)
            proxy.scrollTo("line-\(currentLineIndex)", anchor: .top)
        }
    }
}

// 한 줄의 파형을 표시하는 뷰
struct WaveformLineView: View {
    @ObservedObject var viewModel: ContentViewModel
    
    let lineIndex: Int
    let samples: [Float]
    let currentTime: Double
    let totalDuration: Double
    let secondsPerLine: Double
    let availableWidth: CGFloat
    let waveformHeight: CGFloat
    
    @Binding var hoveredLineIndex: Int?
    @Binding var hoverLocation: CGFloat?
    @Binding var isDragging: Bool
    let onSeek: (Double) -> Void
    
    // 드래그 전 재생 상태 저장
    @State private var wasPlayingBeforeDrag: Bool = false
    
    private var startTime: Double { Double(lineIndex) * secondsPerLine }
    private var endTime: Double { min(startTime + secondsPerLine, totalDuration) }
    private var isCurrentLine: Bool { currentTime >= startTime && currentTime < endTime }
    // 모든 이전 줄이 재생 완료되었는지 확인
    private var isPreviouslyPlayed: Bool { currentTime >= endTime }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { // 2에서 0으로 원래 값으로 복원
            TimeLabelsView(startTime: startTime, endTime: endTime)
            ZStack(alignment: .leading) {
                // 배경
                Rectangle()
                    .fill(Color(red: 0.96, green: 0.96, blue: 0.98))
                    .frame(width: availableWidth, height: waveformHeight)
                
                // 파형
                WaveformShape(samples: computeLineSamples())
                    .fill(Color.blue.opacity(0.5))
                    .frame(width: availableWidth, height: waveformHeight)
                
                // 재생 영역 표시 로직 수정 - 세 가지 경우로 나눔
                Group {
                    if isCurrentLine {
                        // 현재 재생 중인 라인: 현재 시간까지 파란색 표시
                        PositionIndicatorView(
                            currentTime: currentTime,
                            startTime: startTime,
                            endTime: endTime,
                            availableWidth: availableWidth,
                            waveformHeight: waveformHeight,
                            isCurrentLine: true
                        )
                    } else if isPreviouslyPlayed {
                        // 이미 재생된 라인: 전체 영역 파란색 하이라이트
                        Rectangle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: availableWidth, height: waveformHeight)
                    } else {
                        // 아직 재생되지 않은 라인: 하이라이트 없음
                        EmptyView()
                    }
                }
                
                // 재생 위치 표시선 - 현재 재생 중인 라인에만 표시
                if isCurrentLine {
                    let positionRatio = min(1.0, max(0.0, (currentTime - startTime) / (endTime - startTime)))
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: 1, height: waveformHeight)
                        .offset(x: availableWidth * CGFloat(positionRatio) - 0.5) // 정확한 위치 조정
                        .zIndex(100)
                }
                
                // 호버 인디케이터
                if hoveredLineIndex == lineIndex, let hoverPos = hoverLocation {
                    HoverIndicatorView(
                        hoverLocation: hoverPos,
                        isDragging: isDragging,
                        waveformHeight: waveformHeight
                    )
                }
            }
        }
        .frame(width: availableWidth, height: waveformHeight + 24) // 시간 레이블 공간 추가
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                    // 드래그 시작 시 처음 한 번만 실행
                    if !isDragging {
                        // 현재 재생 상태 저장
                        wasPlayingBeforeDrag = viewModel.audioState.isPlaying
                        
                        // 재생 중이면 일시정지
                        if viewModel.audioState.isPlaying {
                            viewModel.pauseImportedAudio()
                        }
                    }
                    
                    isDragging = true
                    hoveredLineIndex = lineIndex
                    hoverLocation = value.location.x
                    
                    // 정확한 시간 계산
                    let ratio = max(0, min(1, value.location.x / availableWidth))
                    let seekTime = startTime + (endTime - startTime) * Double(ratio)
                    onSeek(max(0, min(seekTime, totalDuration)))
                            }
                            .onEnded { value in
                    // 정확한 시간 계산
                    let ratio = max(0, min(1, value.location.x / availableWidth))
                    let seekTime = startTime + (endTime - startTime) * Double(ratio)
                    onSeek(max(0, min(seekTime, totalDuration)))
                    
                    // 드래그 종료 시 이전 재생 상태로 복원
                    if wasPlayingBeforeDrag {
                        viewModel.playImportedAudio()
                    }
                    
                    isDragging = false
                }
        )
        .onHover { hovering in
            if hovering {
                hoveredLineIndex = lineIndex
            } else if hoveredLineIndex == lineIndex && !isDragging {
                hoveredLineIndex = nil
                hoverLocation = nil
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                if !isDragging && hoveredLineIndex == lineIndex {
                    hoverLocation = location.x
                }
            case .ended:
                if !isDragging && hoveredLineIndex == lineIndex {
                    hoverLocation = nil
                }
            }
        }
    }
    
    // 현재 라인에 해당하는 오디오 샘플 계산 (정밀도 향상)
    private func computeLineSamples() -> [Float] {
        guard !samples.isEmpty, totalDuration > 0 else {
            // 샘플이 없는 경우 기본 파형 반환
            return Array(repeating: 0.5, count: Int(availableWidth))
        }
        
        let sampleRate = Double(samples.count) / totalDuration
        
        let startSampleIndex = Int(startTime * sampleRate)
        let endSampleIndex = Int(endTime * sampleRate)
        
        // 범위 체크
        let safeStartIndex = max(0, min(startSampleIndex, samples.count - 1))
        let safeEndIndex = max(safeStartIndex + 1, min(endSampleIndex, samples.count))
        
        // 해당 범위의 샘플 추출
        let lineSamples = Array(samples[safeStartIndex..<safeEndIndex])
        
        // 샘플 수가 화면 너비보다 많으면 다운샘플링, 적으면 보간
        if lineSamples.count > Int(availableWidth) {
            // 다운샘플링 (화면에 맞게)
            let downsampleFactor = lineSamples.count / Int(availableWidth)
            var downsampledSamples: [Float] = []
            
            for i in stride(from: 0, to: lineSamples.count, by: downsampleFactor) {
                // 각 구간에서 최대값 사용 (파형을 더 잘 표현하기 위함)
                let rangeEnd = min(i + downsampleFactor, lineSamples.count)
                if let maxValue = lineSamples[i..<rangeEnd].max() {
                    downsampledSamples.append(maxValue)
                }
            }
            
            return downsampledSamples
        } else if lineSamples.count < Int(availableWidth) && lineSamples.count > 1 {
            // 보간 (화면 너비에 맞게)
            let scaleFactor = Double(availableWidth) / Double(lineSamples.count)
            var interpolatedSamples: [Float] = []
            
            for i in 0..<Int(availableWidth) {
                let exactIndex = Double(i) / scaleFactor
                let lowerIndex = min(Int(exactIndex), lineSamples.count - 1)
                let upperIndex = min(lowerIndex + 1, lineSamples.count - 1)
                
                let fraction = Float(exactIndex - Double(lowerIndex))
                let interpolatedValue = lineSamples[lowerIndex] * (1 - fraction) + lineSamples[upperIndex] * fraction
                interpolatedSamples.append(interpolatedValue)
            }
            
            return interpolatedSamples
        }
        
        return lineSamples
    }
}

// 시간 레이블 뷰: 시작 및 종료 시간을 표시
struct TimeLabelsView: View {
    let startTime: Double
    let endTime: Double
    
    var body: some View {
        HStack {
            Text(formatTime(startTime))
                .font(.system(size: 10))
                .foregroundColor(.gray)
            Spacer()
            Text(formatTime(endTime))
                .font(.system(size: 10))
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 4) // 6에서 원래 값인 4로 복원
        .padding(.bottom, 4) // 8에서 원래 값인 4로 복원
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let totalSec = Int(seconds)
        let hours = totalSec / 3600
        let minutes = (totalSec % 3600) / 60
        let secs = totalSec % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

// 파형 패스 뷰: 샘플 데이터를 기반으로 파형 경로를 생성
struct WaveformShape: Shape {
    let samples: [Float]
    // 파형 높이 증폭 계수
    private let heightMultiplier: CGFloat = 2.0
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !samples.isEmpty else {
            return defaultWaveformPath(in: rect)
        }
        
        let width = rect.width
        let height = rect.height
        let middle = height / 2
        
        // 표시할 최대 샘플 수 (화면 해상도에 맞춤)
        let maxSamples = min(Int(width * 2), samples.count)
        let sampleStep = max(1, samples.count / maxSamples)
        let step = width / CGFloat(min(maxSamples, samples.count / sampleStep))
        
        // 상단 곡선 그리기 (높이 증폭)
        path.move(to: CGPoint(x: 0, y: middle))
        for i in stride(from: 0, to: min(samples.count, sampleStep * maxSamples), by: sampleStep) {
            let x = CGFloat(i / sampleStep) * step
            // 높이를 2배로 증폭, 최대치 제한
            let amplitude = min(middle, CGFloat(samples[i]) * height / 2.0 * heightMultiplier)
            path.addLine(to: CGPoint(x: x, y: max(0, middle - amplitude)))
        }
        
        // 하단 곡선 그리기 (역순) (높이 증폭)
        for i in stride(from: min(samples.count - 1, sampleStep * maxSamples - 1), to: 0, by: -sampleStep) {
            let x = CGFloat(i / sampleStep) * step
            // 높이를 2배로 증폭, 최대치 제한
            let amplitude = min(middle, CGFloat(samples[i]) * height / 2.0 * heightMultiplier)
            path.addLine(to: CGPoint(x: x, y: min(height, middle + amplitude)))
        }
        
        path.closeSubpath()
        return path
    }
    
    private func defaultWaveformPath(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        let middle = height / 2
        path.move(to: CGPoint(x: 0, y: middle))
        path.addLine(to: CGPoint(x: width, y: middle))
        return path
    }
}

// 현재 위치 표시 뷰
struct PositionIndicatorView: View {
    let currentTime: Double
    let startTime: Double
    let endTime: Double
    let availableWidth: CGFloat
    let waveformHeight: CGFloat
    let isCurrentLine: Bool
    
    private var positionRatio: CGFloat {
        if endTime <= startTime { return 0 }
        let ratio = (currentTime - startTime) / (endTime - startTime)
        return CGFloat(max(0, min(1, ratio)))
    }
    
    var body: some View {
        // 현재 재생 위치까지의 파형 영역 하이라이트
        Rectangle()
            .fill(Color.blue.opacity(0.2))
            .frame(width: availableWidth * positionRatio, height: waveformHeight)
    }
}

// 호버/드래그 위치 표시 뷰
struct HoverIndicatorView: View {
    let hoverLocation: CGFloat
    let isDragging: Bool
    let waveformHeight: CGFloat
    
    var body: some View {
        Rectangle()
            .fill(Color.red)
            .frame(width: 1, height: waveformHeight)
            .offset(x: hoverLocation - 0.5) // 정확한 위치 조정
            .zIndex(isDragging ? 95 : 90)
    }
}
