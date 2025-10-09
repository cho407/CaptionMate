//
//  ModelManagerView.swift
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

    // 다운로드 진행 상황 - 가중 평균 (모델 크기 고려)
    private var totalDownloadProgress: Double {
        let downloadingModels = viewModel.modelManagementState.currentDownloadingModels
        if downloadingModels.isEmpty { return 0 }

        var totalSize: Int64 = 0
        var downloadedSize: Double = 0

        for model in downloadingModels {
            let modelSize = viewModel.modelManagementState.modelSizes[model] ?? 0
            let progress = Double(viewModel.modelManagementState.downloadProgress[model] ?? 0)

            totalSize += modelSize
            downloadedSize += Double(modelSize) * progress
        }

        return totalSize > 0 ? downloadedSize / Double(totalSize) : 0
    }

    // 다운로드 중인 총 크기
    private var totalDownloadingSize: String {
        let downloadingModels = viewModel.modelManagementState.currentDownloadingModels
        let totalSize = downloadingModels.reduce(Int64(0)) { total, model in
            total + (viewModel.modelManagementState.modelSizes[model] ?? 0)
        }
        return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    // 다운로드된 크기 계산
    private var downloadedSize: String {
        let downloadingModels = viewModel.modelManagementState.currentDownloadingModels
        var downloaded: Int64 = 0

        for model in downloadingModels {
            let modelSize = viewModel.modelManagementState.modelSizes[model] ?? 0
            let progress = Double(viewModel.modelManagementState.downloadProgress[model] ?? 0)
            downloaded += Int64(Double(modelSize) * progress)
        }

        return ByteCountFormatter.string(fromByteCount: downloaded, countStyle: .file)
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Header

            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .foregroundStyle(.secondary)
                    Text("manage_models")
                        .font(.title3.weight(.semibold))
                }
                Spacer()
                Button {
                    viewModel.fetchModels()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.large)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text("Close"))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            Divider()
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            // 검색 필드
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("search_models", text: $searchText)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            // 로컬 모델 / 다운로드 가능 모델 섹션 분리
            let allModels = viewModel.modelManagementState.availableModels
            let localModels = allModels
                .filter { viewModel.modelManagementState.localModels.contains($0) }
            let remoteModels = allModels
                .filter { !viewModel.modelManagementState.localModels.contains($0) }

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

            // 상태 정보 표시
            GroupBox {
                VStack(spacing: 8) {
                    HStack {
                        Label("total_models", systemImage: "square.stack.3d.up")
                            .font(.caption)
                        Spacer()
                        Text("\(filteredLocalModels.count + filteredRemoteModels.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    HStack {
                        Label("downloaded", systemImage: "checkmark.circle")
                            .font(.caption)
                        Spacer()
                        Text("\(filteredLocalModels.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    if viewModel.modelManagementState.availableModels.isEmpty {
                        Divider()
                        HStack {
                            Text("loading_model_info")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Spacer()
                            ProgressView()
                                .scaleEffect(0.6)
                        }
                    }
                }
                .padding(.vertical, 4)
            } label: {
                Label("model_info", systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .backgroundStyle(Color(nsColor: .controlBackgroundColor))
            .padding(.horizontal, 16)

            // 다운로드 총 진행 상황 표시
            if !viewModel.modelManagementState.currentDownloadingModels.isEmpty {
                GroupBox {
                    VStack(spacing: 10) {
                        // 상단 정보 행
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(.blue)
                                .symbolEffect(.pulse)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(
                                    "downloading_models_count \(viewModel.modelManagementState.currentDownloadingModels.count)"
                                )
                                .font(.caption.weight(.medium))

                                HStack(spacing: 4) {
                                    Text(downloadedSize)
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.blue)
                                    Text("of")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(totalDownloadingSize)
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Text(String(format: "%.1f%%", totalDownloadProgress * 100))
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.blue)
                        }

                        // 진행 바
                        ZStack(alignment: .leading) {
                            // 배경
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.blue.opacity(0.1))
                                .frame(height: 8)

                            // 진행 바 (애니메이션)
                            GeometryReader { geometry in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(
                                        LinearGradient(
                                            colors: [.blue, .cyan],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(
                                        width: geometry.size.width * totalDownloadProgress,
                                        height: 8
                                    )
                                    .animation(
                                        .easeInOut(duration: 0.3),
                                        value: totalDownloadProgress
                                    )
                            }
                            .frame(height: 8)
                        }
                    }
                    .padding(.vertical, 6)
                } label: {
                    Label("downloading_status", systemImage: "chart.bar.fill")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
                .backgroundStyle(Color(nsColor: .controlBackgroundColor))
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            // 스크롤 영역 구분선
            Divider()
                .padding(.top, 12)

            // 메인 콘텐츠 영역
            ScrollView {
                if allModels.isEmpty {
                    // 모델이 없는 경우 로딩 표시
                    VStack(spacing: 16) {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("loading_model_list")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 300)
                    .onAppear {
                        viewModel.fetchModels()
                    }
                } else {
                    LazyVStack(spacing: 16, pinnedViews: []) {
                        // 로컬에 있는 모델 섹션
                        if !filteredLocalModels.isEmpty {
                            GroupBox {
                                LazyVStack(spacing: 8) {
                                    ForEach(filteredLocalModels, id: \.self) { model in
                                        ModelRowView(model: model, viewModel: viewModel)

                                        if model != filteredLocalModels.last {
                                            Divider()
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            } label: {
                                Label("downloaded_models", systemImage: "checkmark.circle.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(.green)
                            }
                            .backgroundStyle(Color(nsColor: .controlBackgroundColor))
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                        }

                        // 다운로드 가능한 모델 섹션
                        if !filteredRemoteModels.isEmpty {
                            GroupBox {
                                LazyVStack(spacing: 8) {
                                    ForEach(filteredRemoteModels, id: \.self) { model in
                                        ModelRowView(model: model, viewModel: viewModel)

                                        if model != filteredRemoteModels.last {
                                            Divider()
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            } label: {
                                HStack {
                                    Label("available_models", systemImage: "arrow.down.circle")
                                        .font(.subheadline)
                                        .foregroundStyle(.blue)
                                    Spacer()
                                    Text(
                                        "total_size: \(ByteCountFormatter.string(fromByteCount: totalRemoteSize, countStyle: .file))"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .backgroundStyle(Color(nsColor: .controlBackgroundColor))
                            .padding(.horizontal, 16)
                            .padding(.top, filteredLocalModels.isEmpty ? 12 : 0)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 모델 이름 행
            HStack(spacing: 12) {
                // 상태 인디케이터
                if viewModel.selectedModel == model && viewModel.modelManagementState
                    .modelState == .loaded {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                        .symbolEffect(.pulse)
                } else if viewModel.modelManagementState.localModels.contains(model) {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(Color.ultraBrightGray)
                        .font(.caption)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.modelManagementState.displayName(for: model))
                        .font(.subheadline.weight(.medium))

                    if viewModel.modelManagementState.isCancelling(model: model) {
                        LoadingDotsView(text: "Cancelling")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else if viewModel.modelManagementState.isDownloading(model: model) {
                        LoadingDotsView(text: "Downloading")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    } else {
                        Text(viewModel.modelManagementState.formattedModelSize(for: model))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // 모델 상태에 따른 버튼 표시
                modelActionButton(model: model)
            }

            // 다운로드 중이거나 취소 중인 경우 진행바 표시
            if viewModel.modelManagementState.isCancelling(model: model) {
                VStack(spacing: 6) {
                    HStack {
                        Text("Cancelling...")
                            .font(.caption2)
                            .foregroundStyle(.orange)

                        Spacer()

                        ProgressView()
                            .scaleEffect(0.6)
                            .tint(.orange)
                    }

                    // 취소 진행 바
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.orange.opacity(0.1))
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: [.orange.opacity(0.7), .orange],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 6)
                            .frame(maxWidth: .infinity)
                    }
                }
            } else if viewModel.modelManagementState.isDownloading(model: model) {
                VStack(spacing: 6) {
                    HStack {
                        Text(viewModel.modelManagementState.formattedDownloadProgress(for: model))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.blue)

                        Spacer()

                        // 취소 버튼
                        Button {
                            viewModel.cancelDownload(model)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                                .imageScale(.small)
                        }
                        .buttonStyle(.plain)
                    }

                    // 다운로드 진행 바 (상단 바와 동일한 스타일)
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.blue.opacity(0.1))
                            .frame(height: 6)

                        GeometryReader { geometry in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    LinearGradient(
                                        colors: [.blue, .cyan],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(
                                    width: geometry.size
                                        .width *
                                        CGFloat(viewModel.modelManagementState
                                            .downloadProgress[model] ?? 0),
                                    height: 6
                                )
                                .animation(
                                    .easeInOut(duration: 0.3),
                                    value: viewModel.modelManagementState.downloadProgress[model]
                                )
                        }
                        .frame(height: 6)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    // 모델 상태에 따른 동작 버튼
    @ViewBuilder
    private func modelActionButton(model: String) -> some View {
        if viewModel.modelManagementState.localModels.contains(model) {
            // 로컬에 있는 모델 - 상태에 따라 다른 버튼 표시
            if (viewModel.selectedModel == model) &&
                (viewModel.modelManagementState.modelState == .loaded) {
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
            } else if viewModel.modelManagementState.isCancelling(model: model) {
                // 취소 중 - 취소 아이콘
                Image(systemName: "hourglass")
                    .foregroundColor(.orange)
                    .overlay(
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.4)
                    )
            } else if viewModel.modelManagementState.isDownloading(model: model) {
                // 다운로드 중 - 상태 아이콘
                Image(systemName: "arrow.down.circle")
                    .foregroundColor(.blue)
                    .overlay(
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.5)
                    )
            } else if (viewModel.modelManagementState.modelState == .loading || viewModel
                .modelManagementState.modelState == .prewarming) && viewModel
                            .selectedModel == model {
                // 로드 중인 모델 - 로딩 아이콘 표시
                HStack(spacing: 6) {
                    Text("Loading")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView()
                        .scaleEffect(0.6)
                }
            } else if viewModel.modelManagementState.modelState == .unloading && viewModel
                .selectedModel == model {
                HStack(spacing: 6) {
                    Text("Unloading")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView()
                        .scaleEffect(0.6)
                }
            } else {
                // 로드되지 않은 로컬 모델 - 삭제 버튼
                Button {
                    viewModel.deleteModel(model)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
                .help("Delete Model")
            }

        } else if viewModel.modelManagementState.isCancelling(model: model) {
            // 취소 중 - 취소 아이콘
            Image(systemName: "hourglass")
                .foregroundColor(.orange)
                .overlay(
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.4)
                )
                .help("Cancelling download...")
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
            Button {
                viewModel.downloadModel(model)
            } label: {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.blue)
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
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
