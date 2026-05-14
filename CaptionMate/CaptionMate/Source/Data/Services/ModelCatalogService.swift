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

import Foundation

struct LocalModelFolderInfo: Equatable, Sendable {
    let name: String
    let size: Int64
}

enum ModelCatalogServiceError: LocalizedError, Equatable {
    case unsafeModelName(String)

    var errorDescription: String? {
        switch self {
        case let .unsafeModelName(model):
            return "Unsafe model folder name: \(model)"
        }
    }
}

enum ModelCatalogService {
    private struct RemoteSizeCache: Codable {
        let updatedAt: Date
        let sizes: [String: Int64]
    }

    private struct HuggingFaceTreeEntry: Decodable {
        struct LFSMetadata: Decodable {
            let size: Int64?
        }

        let type: String?
        let size: Int64?
        let lfs: LFSMetadata?
    }

    private static let remoteSizeCacheMaxAge: TimeInterval = 60 * 60 * 24
    static let maxRemoteTreeResponseBytes: Int64 = 8 * 1024 * 1024

    static func localModelDirectoryURL(
        modelStorage: String,
        fileManager: FileManager = .default
    ) -> URL? {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(modelStorage, isDirectory: true)
    }

    static func loadLocalModelFolders(
        modelStorage: String,
        fileManager: FileManager = .default
    ) throws -> (directoryURL: URL, folders: [LocalModelFolderInfo]) {
        guard let directoryURL = localModelDirectoryURL(
            modelStorage: modelStorage,
            fileManager: fileManager
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }

        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        }

        let folderURLs = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        let folders = folderURLs.map { url in
            LocalModelFolderInfo(
                name: url.lastPathComponent,
                size: folderSize(url: url, fileManager: fileManager)
            )
        }

        return (directoryURL, folders)
    }

    static func orderedLocalModelFolders(
        _ folders: [LocalModelFolderInfo],
        formattingNamesWith formatter: ([String]) -> [String]
    ) -> [LocalModelFolderInfo] {
        let foldersByName = Dictionary(
            folders.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return formatter(folders.map(\.name)).compactMap { foldersByName[$0] }
    }

    static func modelFolderURL(for model: String, in localModelPath: String) throws -> URL {
        guard isSafeModelFolderName(model) else {
            throw ModelCatalogServiceError.unsafeModelName(model)
        }

        let rootURL = URL(fileURLWithPath: localModelPath, isDirectory: true)
            .standardizedFileURL
        let folderURL = rootURL
            .appendingPathComponent(model, isDirectory: true)
            .standardizedFileURL

        guard folderURL.deletingLastPathComponent().standardizedFileURL == rootURL else {
            throw ModelCatalogServiceError.unsafeModelName(model)
        }

        return folderURL
    }

    static func folderSize(url: URL, fileManager: FileManager = .default) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileAllocatedSizeKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [
                .isDirectoryKey,
                .fileAllocatedSizeKey,
                .fileSizeKey,
            ])
            guard values?.isDirectory != true else { continue }
            totalSize += Int64(values?.fileAllocatedSize ?? values?.fileSize ?? 0)
        }
        return totalSize
    }

    static func estimatedDownloadSize(for model: String) -> Int64 {
        if let encodedSize = sizeEncodedInModelName(model) {
            return encodedSize
        }

        let lowercasedModel = model.lowercased()
        if lowercasedModel.contains("large-v3_turbo") {
            return 3_200_000_000
        }
        if lowercasedModel.contains("large") {
            return 3_100_000_000
        }
        if lowercasedModel.contains("medium") {
            return 1_500_000_000
        }
        if lowercasedModel.contains("small") {
            return lowercasedModel.contains(".en") ? 466_000_000 : 465_000_000
        }
        if lowercasedModel.contains("base") {
            return lowercasedModel.contains(".en") ? 295_000_000 : 147_000_000
        }
        if lowercasedModel.contains("tiny") {
            return lowercasedModel.contains(".en") ? 153_000_000 : 76_600_000
        }
        return 150_000_000
    }

    static func cachedRemoteSizes(repoName: String, userDefaults: UserDefaults = .standard) -> [String: Int64] {
        guard let data = userDefaults.data(forKey: remoteSizeCacheKey(repoName: repoName)) else {
            return [:]
        }

        if let cache = try? JSONDecoder().decode(RemoteSizeCache.self, from: data) {
            guard Date().timeIntervalSince(cache.updatedAt) <= remoteSizeCacheMaxAge else {
                return [:]
            }
            return cache.sizes
        }

        guard let sizes = try? JSONDecoder().decode([String: Int64].self, from: data) else {
            return [:]
        }
        return sizes
    }

    static func saveCachedRemoteSizes(
        _ sizes: [String: Int64],
        repoName: String,
        userDefaults: UserDefaults = .standard
    ) {
        let cache = RemoteSizeCache(updatedAt: Date(), sizes: sizes)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        userDefaults.set(data, forKey: remoteSizeCacheKey(repoName: repoName))
    }

    static func remoteFolderSize(
        repoName: String,
        model: String,
        session: URLSession = .shared
    ) async throws -> Int64 {
        guard let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://huggingface.co/api/models/\(repoName)/tree/main/\(encodedModel)?recursive=true") else {
            throw URLError(.badURL)
        }

        let (data, response) = try await session.data(from: url)
        if let httpResponse = response as? HTTPURLResponse,
           !(200 ..< 300).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }
        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.expectedContentLength > maxRemoteTreeResponseBytes {
            throw URLError(.dataLengthExceedsMaximum)
        }
        guard data.count <= maxRemoteTreeResponseBytes else {
            throw URLError(.dataLengthExceedsMaximum)
        }

        let entries = try JSONDecoder().decode([HuggingFaceTreeEntry].self, from: data)
        return entries.reduce(Int64(0)) { total, entry in
            guard entry.type != "directory" else { return total }
            return total + (entry.lfs?.size ?? entry.size ?? 0)
        }
    }

    private static func sizeEncodedInModelName(_ model: String) -> Int64? {
        guard let regex = try? NSRegularExpression(pattern: #"_(\d+)(MB|GB)$"#) else {
            return nil
        }

        let range = NSRange(model.startIndex ..< model.endIndex, in: model)
        guard let match = regex.firstMatch(in: model, range: range),
              match.numberOfRanges == 3,
              let valueRange = Range(match.range(at: 1), in: model),
              let unitRange = Range(match.range(at: 2), in: model),
              let value = Int64(model[valueRange]) else {
            return nil
        }

        let unit = String(model[unitRange])
        return unit == "GB" ? value * 1_000_000_000 : value * 1_000_000
    }

    private static func remoteSizeCacheKey(repoName: String) -> String {
        "remoteModelSizes.\(repoName)"
    }

    private static func isSafeModelFolderName(_ model: String) -> Bool {
        guard !model.isEmpty,
              model == model.trimmingCharacters(in: .whitespacesAndNewlines),
              model != ".",
              model != ".." else {
            return false
        }

        let disallowedCharacters = CharacterSet(charactersIn: "/\\:")
            .union(.controlCharacters)
        return model.rangeOfCharacter(from: disallowedCharacters) == nil
    }
}
