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
                Text("Manage Models")
                    .font(.largeTitle)
                    .bold()
                Spacer()
                Button("Close") {
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
                TextField("Search Models", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            .padding(.horizontal)
            
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
            
            // 다운로드 가능한 모델의 총 크기 계산
            let totalRemoteSize = filteredRemoteModels.reduce(Int64(0)) { total, model in
                total + (viewModel.modelManagementState.modelSizes[model] ?? 0)
            }
            
            // 디버그 정보 표시
            VStack(alignment: .leading) {
                Text("Model Info")
                    .font(.headline)
                    .padding(.top, 2)
                
                HStack {
                    Text("Total Models Count: \(filteredLocalModels.count + filteredRemoteModels.count)")
                    Spacer()
                    Text("Downloaded Models Count: \(filteredLocalModels.count)")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                
                if viewModel.modelManagementState.availableModels.isEmpty {
                    Text("Loading Model Info...")
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
                        Text("Downloading: \(viewModel.modelManagementState.currentDownloadingModels.count) Models (\(totalDownloadingSize))")
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
            
            if allModels.isEmpty {
                // 모델이 없는 경우 로딩 표시
                VStack {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                    Text("Loading Model List...")
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
                            Text("Downloaded Models")
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
                            HStack {
                                Text("Available Models")
                                    .font(.headline)
                                Text("(Total: \(ByteCountFormatter.string(fromByteCount: totalRemoteSize, countStyle: .file)))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
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
                    if viewModel.modelManagementState.isDownloading(model: model){
                        LoadingDotsView(text: "Downloading")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else{
                        // 모델 크기 정보
                        Text(viewModel.modelManagementState.formattedModelSize(for: model))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
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
            // 로컬에 있는 모델 - 상태에 따라 다른 버튼 표시
            if (viewModel.selectedModel == model) && (viewModel.modelManagementState.modelState == .loaded) {
                // 현재 로드된 모델 - 해제 버튼
                Button {
                    Task {
                        await viewModel.releaseModel()
                    }
                } label: {
                    Text("Unload Model")
                        .foregroundColor(.red)
                }
                .help("You must unload the model before deleting it")
            } else if viewModel.modelManagementState.isDownloading(model: model) {
                // 다운로드 중 - 상태 아이콘
                Image(systemName: "arrow.down.circle")
                    .foregroundColor(.blue)
                    .overlay(
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.5)
                    )
            } else if (viewModel.modelManagementState.modelState == .loading || viewModel.modelManagementState.modelState == .prewarming) && viewModel.selectedModel == model {
                // 로드 중인 모델 - 로딩 아이콘 표시
                HStack {
                    
                    Text("Loading Model")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 0)
                    ProgressView()
                        .scaleEffect(0.5)
                        .foregroundColor(.secondary)
                }
            } else if viewModel.modelManagementState.modelState == .unloading && viewModel.selectedModel == model {
                HStack {
                    
                    Text("Unloading Model")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 0)
                    ProgressView()
                        .scaleEffect(0.5)
                        .foregroundColor(.secondary)
                }
            } else {
                // 로드되지 않은 로컬 모델 - 삭제 버튼
                Button(action: {
                    viewModel.deleteModel(model)
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(BorderlessButtonStyle())
                .help("Delete Model")
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
                .help("Downloading...")
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
                  "Maximum simultaneous downloads reached" : "Download Model")
        }
    }
}

#Preview {
    ModelManagerView(viewModel: ContentViewModel())
        .frame(width: 600, height: 500)
}
