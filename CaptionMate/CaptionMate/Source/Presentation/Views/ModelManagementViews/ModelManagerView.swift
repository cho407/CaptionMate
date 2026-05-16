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
//  ModelManagerView.swift
//  CaptionMate
//
//  Created by 조형구 on 4/23/25.
//

import SwiftUI
import WhisperKit

struct ModelManagerView: View {
    @ObservedObject var viewModel: ContentViewModel
    @ObservedObject var modelState: ModelManagementState
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""

    // 필터링할 단어 목록
    let filterWords: [String] = ["distil", "MB", "2024"]

    init(viewModel: ContentViewModel) {
        self.viewModel = viewModel
        modelState = viewModel.modelManagementState
    }

    private var downloadStatusModels: [String] {
        viewModel.modelManagementState.trackedDownloadModels(
            orderedBy: viewModel.modelManagementState.availableModels
        )
    }

    private var activeDownloadModels: [String] {
        viewModel.modelManagementState.downloadActivityModels(
            orderedBy: viewModel.modelManagementState.availableModels
        )
    }

    // 다운로드 진행 상황 - 가중 평균 (모델 크기 고려)
    private var totalDownloadProgress: Double {
        viewModel.modelManagementState.weightedDownloadProgress(for: downloadStatusModels)
    }

    // 다운로드 중인 총 크기
    private var totalDownloadingSize: String {
        let totalSize = viewModel.modelManagementState
            .totalDownloadByteCount(for: downloadStatusModels)
        return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    // 다운로드된 크기 계산
    private var downloadedSize: String {
        let downloaded = viewModel.modelManagementState
            .downloadedByteCount(for: downloadStatusModels)
        return ByteCountFormatter.string(fromByteCount: downloaded, countStyle: .file)
    }

    private var speakerModelStatusText: Text {
        if modelState.speakerDiarizationModelNeedsRepair {
            return Text("Needs repair")
        }
        if modelState.speakerDiarizationModelNeedsUpdate {
            return Text("Update available")
        }
        switch modelState.speakerDiarizationModelState {
        case .downloaded:
            return Text("Offline ready")
        case .downloading:
            if modelState.speakerDiarizationModelProgress == nil {
                return Text("Downloading")
            }
            return Text("Downloading \(modelState.formattedSpeakerDiarizationProgress)")
        case .loading, .prewarming:
            return Text("Preparing")
        default:
            return Text("Not downloaded")
        }
    }

    private var speakerModelStatusSymbol: String {
        if modelState.speakerDiarizationModelNeedsRepair ||
            modelState.speakerDiarizationModelNeedsUpdate {
            return "exclamationmark.triangle.fill"
        }
        switch modelState.speakerDiarizationModelState {
        case .downloaded:
            return "checkmark.circle.fill"
        case .downloading, .loading, .prewarming:
            return "arrow.down.circle.fill"
        default:
            return "person.2.wave.2.fill"
        }
    }

    private var speakerModelActionLabel: String {
        if modelState.speakerDiarizationModelNeedsUpdate {
            return "Update speaker model"
        }
        if modelState.speakerDiarizationModelNeedsRepair {
            return "Repair speaker model"
        }
        return "Download speaker model"
    }

    private var speakerModelActionSymbol: String {
        if modelState.speakerDiarizationModelNeedsUpdate {
            return "arrow.triangle.2.circlepath"
        }
        if modelState.speakerDiarizationModelNeedsRepair {
            return "wrench.and.screwdriver"
        }
        return "arrow.down.circle"
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
                    viewModel.fetchModels(forceRefresh: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .imageScale(.medium)
                        .accessibilityLabel(Text("Refresh models"))
                }
                .buttonStyle(.plain)
                .disabled(modelState.catalogLoadState.isLoading)
                .help("Refresh model catalog")

                Button {
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
            let localModels = viewModel.modelManagementState.downloadedSectionModels(
                orderedBy: allModels
            )
            let remoteModels = viewModel.modelManagementState.availableSectionModels(
                orderedBy: allModels
            )

            let filteredDownloadingModels = activeDownloadModels.filter { model in
                let matchesFilter = searchText.isEmpty ||
                    model.lowercased().contains(searchText.lowercased())

                let notFiltered = !filterWords.contains { filter in
                    model.lowercased().contains(filter.lowercased())
                }

                return matchesFilter && notFiltered
            }

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
                        Text("\(filteredDownloadingModels.count + filteredLocalModels.count + filteredRemoteModels.count)")
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

                    if viewModel.modelManagementState.availableModels.isEmpty ||
                        modelState.catalogLoadState.isLoading ||
                        modelState.isRemoteModelSizeLoading {
                        Divider()
                        HStack {
                            if modelState.isRemoteModelSizeLoading {
                                Text("Updating download sizes")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            } else {
                                Text(LocalizedStringKey(modelState.catalogLoadState.statusText))
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
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

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Label {
                            speakerModelStatusText
                        } icon: {
                            Image(systemName: speakerModelStatusSymbol)
                        }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(modelState.isSpeakerDiarizationModelReady ? .green : .secondary)
                            .accessibilityIdentifier("modelManager.speakerModelStatus")
                        Spacer()
                        Text(modelState.formattedSpeakerDiarizationModelSize)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(Text("Speaker model size"))

                        if modelState.isSpeakerDiarizationModelPreparing {
                            if let progress = modelState.speakerDiarizationModelProgress {
                                ProgressView(value: Double(progress))
                                    .frame(width: 90)
                                    .accessibilityIdentifier("modelManager.speakerModelProgress")
                            } else {
                                ProgressView()
                                    .frame(width: 90)
                                    .accessibilityIdentifier("modelManager.speakerModelProgress")
                            }
                            Button {
                                viewModel.cancelDefaultSpeakerDiarizationModelDownload()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                            .help("Cancel speaker model download")
                            .accessibilityLabel(Text("Cancel speaker model download"))
                        } else if !modelState.isSpeakerDiarizationModelReady {
                            Button {
                                viewModel.prepareDefaultSpeakerDiarizationModelIfNeeded(
                                    showSuccessMessage: true
                                )
                            } label: {
                                Image(systemName: speakerModelActionSymbol)
                            }
                            .buttonStyle(.borderless)
                            .help(speakerModelActionLabel)
                            .accessibilityLabel(Text(speakerModelActionLabel))
                            .accessibilityHint(
                                Text("Repairs the local offline speaker model used by speaker diarization.")
                            )
                            .accessibilityIdentifier("modelManager.speakerModelActionButton")
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .accessibilityHidden(true)
                        }
                    }

                    Text("Required for speaker diarization. Stored locally for offline speaker labels.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .accessibilityIdentifier("modelManager.speakerModelCaption")

                    if let error = modelState.speakerDiarizationModelError,
                       !modelState.isSpeakerDiarizationModelReady {
                        Text(LocalizedStringKey(error))
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, 4)
            } label: {
                Label("speaker_diarization_model", systemImage: "person.2.wave.2")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .backgroundStyle(Color(nsColor: .controlBackgroundColor))
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .accessibilityIdentifier("modelManager.speakerDiarizationModelSection")

            // 다운로드 총 진행 상황 표시
            if modelState.hasVisibleDownloadActivity, !activeDownloadModels.isEmpty {
                GroupBox {
                    VStack(spacing: 10) {
                        // 상단 정보 행
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(.blue)
                                .symbolEffect(.pulse)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("downloading_models_count \(activeDownloadModels.count)")
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
                                    if !modelState.queuedDownloadModels.isEmpty {
                                        Text("Queued \(modelState.queuedDownloadModels.count)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
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
                if allModels.isEmpty && filteredDownloadingModels.isEmpty {
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
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                            } label: {
                                Label("downloaded_models", systemImage: "checkmark.circle.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(.green)
                            }
                            .backgroundStyle(Color(nsColor: .controlBackgroundColor))
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                        }

                        if !filteredDownloadingModels.isEmpty {
                            GroupBox {
                                LazyVStack(spacing: 8) {
                                    ForEach(filteredDownloadingModels, id: \.self) { model in
                                        ModelRowView(model: model, viewModel: viewModel)

                                        if model != filteredDownloadingModels.last {
                                            Divider()
                                        }
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                            } label: {
                                Label("downloading_models", systemImage: "arrow.down.circle.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(.blue)
                            }
                            .backgroundStyle(Color(nsColor: .controlBackgroundColor))
                            .padding(.horizontal, 16)
                            .padding(.top, filteredLocalModels.isEmpty ? 12 : 0)
                            .accessibilityIdentifier("modelManager.downloadingModelsSection")
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
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                            } label: {
                                HStack {
                                    Label("available_models", systemImage: "arrow.down.circle")
                                        .font(.subheadline)
                                        .foregroundStyle(.blue)
                                    Spacer()
                                    Text(
                                        "total size: \(ByteCountFormatter.string(fromByteCount: totalRemoteSize, countStyle: .file))"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .backgroundStyle(Color(nsColor: .controlBackgroundColor))
                            .padding(.horizontal, 16)
                            .padding(.top, filteredLocalModels.isEmpty && filteredDownloadingModels.isEmpty ? 12 : 0)
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
        .alert(
            "Download Failed",
            isPresented: $viewModel.uiState.showDownloadErrorAlert
        ) {
            Button("OK") {
                viewModel.uiState.showDownloadErrorAlert = false
                viewModel.uiState.downloadError = nil
            }
            .keyboardShortcut(.defaultAction)
        } message: {
            if let error = viewModel.uiState.downloadError {
                Text(error.localizedKey)
            }
        }
    }
}

// 각 모델 행을 표시하는 뷰
struct ModelRowView: View {
    let model: String
    @ObservedObject var viewModel: ContentViewModel
    @State private var isDeleteConfirmationPresented = false
    @State private var observedDownloadProgress: Float = 0

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
                    } else if viewModel.modelManagementState.isQueued(model: model) {
                        Text("Queued")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(viewModel.modelManagementState.formattedModelSizeWithSource(for: model))
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
                        Text(String(format: "%.1f%%", observedDownloadProgress * 100))
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
                                        CGFloat(observedDownloadProgress),
                                    height: 6
                                )
                                .animation(
                                    .easeInOut(duration: 0.3),
                                    value: observedDownloadProgress
                                )
                        }
                        .frame(height: 6)
                    }
                }
            } else if viewModel.modelManagementState.isQueued(model: model) {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                    Text("Waiting for an available download slot")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        viewModel.cancelDownload(model)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .imageScale(.small)
                    }
                    .buttonStyle(.plain)
                    .help("Cancel queued download")
                }
            } else if let error = viewModel.modelManagementState.downloadErrors[model] {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(LocalizedStringKey(error))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Spacer()

                    Button {
                        viewModel.downloadModel(model)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.modelManagementState.canStartDownload(model: model))
                    .help("Retry Download")
                }
            }
        }
        .padding(.vertical, 6)
        .alert("Delete Model", isPresented: $isDeleteConfirmationPresented) {
            Button("Delete", role: .destructive) {
                viewModel.deleteModel(model)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Delete \(viewModel.modelManagementState.displayName(for: model)) from this Mac?")
        }
        .onReceive(viewModel.modelManagementState.downloadProgressPublisher(for: model)) { progress in
            observedDownloadProgress = progress
        }
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
                    isDeleteConfirmationPresented = true
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
        } else if viewModel.modelManagementState.isQueued(model: model) {
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
                .help("Queued for download")
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
            .help(viewModel.modelManagementState.canStartDownload(model: model) ?
                "Download Model" : "Download already scheduled")
        }
    }
}

#Preview {
    ModelManagerView(viewModel: ContentViewModel())
        .frame(width: 600, height: 500)
}
