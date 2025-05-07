//
//  ModelManageView.swift
//  WhisperCaptionPro
//
//  Created by 조형구 on 4/23/25.
//

import SwiftUI
import WhisperKit

struct ModelManagerView: View {
    @ObservedObject var viewModel: ContentViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    
    // 필터링할 단어 목록
    let filterWords: [String] = ["distil", "MB", "2024"]
    
    // 다운로드 진행 상황에 대한 계산 속성
    private var totalDownloadProgress: Double {
        let downloads = viewModel.modelManagementState.downloadProgress
        if downloads.isEmpty { return 0 }
        
        let sum = downloads.values.reduce(0.0) { $0 + Double($1) }
        return sum / Double(downloads.count)
    }
    
    // 다운로드 중인 총 크기
    private var totalDownloadingSize: String {
        let downloadingModels = viewModel.modelManagementState.currentDownloadingModels
        let totalSize = downloadingModels.reduce(Int64(0)) { total, model in
            total + (viewModel.modelManagementState.modelSizes[model] ?? 0)
        }
        return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    var body: some View {
        VStack {
            // 상단 타이틀 및 닫기 버튼
            HStack {
                Text("모델 관리")
                    .font(.largeTitle)
                    .bold()
                Spacer()
                Button("닫기") {
                    viewModel.fetchModels()
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding()
            
            // 검색 필드
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                TextField("모델 검색", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            .padding(.horizontal)
            
            // 디버그 정보 표시
            VStack(alignment: .leading) {
                Text("모델 정보")
                    .font(.headline)
                    .padding(.top, 2)
                
                HStack {
                    Text("전체 모델 수: \(viewModel.modelManagementState.availableModels.count)")
                    Spacer()
                    Text("다운로드된 모델 수: \(viewModel.modelManagementState.localModels.count)")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                
                if viewModel.modelManagementState.availableModels.isEmpty {
                    Text("모델 정보를 불러오는 중...")
                        .foregroundColor(.orange)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal)
            .padding(.top, 4)
            
            // 다운로드 총 진행 상황 표시
            if !viewModel.modelManagementState.currentDownloadingModels.isEmpty {
                VStack(spacing: 4) {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.blue)
                        Text("다운로드 중: \(viewModel.modelManagementState.currentDownloadingModels.count)개 모델 (\(totalDownloadingSize))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    
                    // 전체 다운로드 진행률 표시
                    ProgressView(value: totalDownloadProgress, total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(maxWidth: .infinity)
                    
                    Text(String(format: "전체 진행률: %.1f%%", totalDownloadProgress * 100))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.top, 4)
            }
            
            // 로컬 모델 / 다운로드 가능 모델 섹션 분리
            let allModels = viewModel.modelManagementState.availableModels
            let localModels = allModels.filter { viewModel.modelManagementState.localModels.contains($0) }
            let remoteModels = allModels.filter { !viewModel.modelManagementState.localModels.contains($0) }
            
            // 필터링된 모델 목록
            let filteredLocalModels = localModels.filter { model in
                let matchesFilter = searchText.isEmpty || 
                    model.lowercased().contains(searchText.lowercased())
                
                let notFiltered = !filterWords.contains { filter in
                    model.lowercased().contains(filter.lowercased())
                }
                
                return matchesFilter && notFiltered
            }
            
            let filteredRemoteModels = remoteModels.filter { model in
                let matchesFilter = searchText.isEmpty || 
                    model.lowercased().contains(searchText.lowercased())
                
                let notFiltered = !filterWords.contains { filter in
                    model.lowercased().contains(filter.lowercased())
                }
                
                return matchesFilter && notFiltered
            }
            
            if allModels.isEmpty {
                // 모델이 없는 경우 로딩 표시
                VStack {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                    Text("모델 목록을 불러오는 중...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding()
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    // 모델 목록 갱신 시도
                    viewModel.fetchModels()
                }
            } else {
                // 메인 목록 영역
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // 로컬에 있는 모델 섹션
                        if !filteredLocalModels.isEmpty {
                            Text("설치된 모델")
                                .font(.headline)
                                .padding(.horizontal)
                                .padding(.top, 8)
                            
                            VStack(spacing: 8) {
                                ForEach(filteredLocalModels, id: \.self) { model in
                                    ModelRowView(model: model, viewModel: viewModel)
                                        .padding(.horizontal)
                                        .background(Color.blue.opacity(0.05))
                                        .cornerRadius(8)
                                }
                            }
                            .padding(.horizontal)
                        }
                        
                        // 다운로드 가능한 모델 섹션
                        if !filteredRemoteModels.isEmpty {
                            Text("다운로드 가능한 모델")
                                .font(.headline)
                                .padding(.horizontal)
                                .padding(.top, 8)
                            
                            VStack(spacing: 8) {
                                ForEach(filteredRemoteModels, id: \.self) { model in
                                    ModelRowView(model: model, viewModel: viewModel)
                                        .padding(.horizontal)
                                        .background(Color.gray.opacity(0.1))
                                        .cornerRadius(8)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
        }
        .onAppear {
            // 뷰가 나타날 때 모델 목록 갱신
            viewModel.fetchModels()
        }
    }
}

// 각 모델 행을 표시하는 뷰
struct ModelRowView: View {
    let model: String
    @ObservedObject var viewModel: ContentViewModel
    
    // 행의 높이를 동적으로 조정하기 위한 상태
    @State private var isExpanded: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 모델 이름 행
            HStack {
                VStack(alignment: .leading) {
                    HStack {
                        if viewModel.selectedModel == model && viewModel.modelManagementState.modelState == .loaded {
                            Image(systemName: "circle.fill")
                                .foregroundColor(.green)
                                .font(.callout)
                                .symbolEffect(.pulse)
                        } else if viewModel.modelManagementState.localModels.contains(model) {
                            Image(systemName: "circle.fill")
                                .foregroundColor(.ultraBrightGray)
                                .font(.callout)
                        }
                        Text(viewModel.modelManagementState.displayName(for: model))
                            .font(.headline)
                    }
                    
                    // 모델 크기 정보
                    Text(viewModel.modelManagementState.formattedModelSize(for: model))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // 모델 상태에 따른 버튼 표시
                modelActionButton(model: model)
            }
            
            // 다운로드 중인 경우 진행바 표시
            if viewModel.modelManagementState.isDownloading(model: model) {
                HStack {
                    ProgressView(value: viewModel.modelManagementState.downloadProgress[model] ?? 0, total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle())
                    
                    Text(viewModel.modelManagementState.formattedDownloadProgress(for: model))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 40, alignment: .trailing)
                    
                    // 취소 버튼
                    Button(action: {
                        viewModel.cancelDownload(model)
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation {
                isExpanded.toggle()
            }
        }
    }
    
    // 모델 상태에 따른 동작 버튼
    @ViewBuilder
    private func modelActionButton(model: String) -> some View {
        if viewModel.modelManagementState.localModels.contains(model) {
            // 로컬에 있는 모델 - 삭제 버튼 표시
            if (viewModel.selectedModel == model) && (viewModel.modelManagementState.modelState == .loaded) {
                Button {
                    Task {
                        await viewModel.releaseModel()
                    }
                } label: {
                    Text("모델 해제")
                        .foregroundColor(.red)
                }
                .help("모델을 삭제하시려면 해제 해야합니다")
            } else {
                Button(action: {
                    viewModel.deleteModel(model)
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(BorderlessButtonStyle())
                .help("모델 삭제")
            }

        } else if viewModel.modelManagementState.isDownloading(model: model) {
            // 다운로드 중 - 상태 아이콘
            Image(systemName: "arrow.down.circle")
                .foregroundColor(.blue)
                .overlay(
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.5)
                )
                .help("다운로드 중...")
        } else {
            // 다운로드 가능한 모델 - 다운로드 버튼
            Button(action: {
                viewModel.downloadModel(model)
            }) {
                Image(systemName: "arrow.down.circle")
                    .foregroundColor(.blue)
            }
            .buttonStyle(BorderlessButtonStyle())
            .disabled(!viewModel.modelManagementState.canStartDownload(model: model))
            .help(!viewModel.modelManagementState.canStartDownload(model: model) ? 
                 "최대 동시 다운로드 수에 도달했습니다" : "모델 다운로드")
        }
    }
}

#Preview {
    ModelManagerView(viewModel: ContentViewModel())
        .frame(width: 600, height: 500)
}
