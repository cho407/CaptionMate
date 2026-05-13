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

struct StorageCleanupReport: Equatable, Sendable {
    let removedItemCount: Int
    let removedBytes: Int64

    static let empty = StorageCleanupReport(removedItemCount: 0, removedBytes: 0)

    var isEmpty: Bool {
        removedItemCount == 0 && removedBytes == 0
    }
}

enum StorageCleanupService {
    static func cleanupStaleItems(
        in directoryURL: URL,
        olderThan maxAge: TimeInterval,
        preserving preservedURLs: Set<URL> = [],
        now: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> StorageCleanupReport {
        try cleanupContents(
            in: directoryURL,
            preserving: preservedURLs,
            shouldRemove: { itemURL in
                let values = try? itemURL.resourceValues(forKeys: [.contentModificationDateKey])
                let modificationDate = values?.contentModificationDate ?? .distantPast
                return now.timeIntervalSince(modificationDate) >= maxAge
            },
            fileManager: fileManager
        )
    }

    static func cleanupContents(
        in directoryURL: URL,
        preserving preservedURLs: Set<URL> = [],
        fileManager: FileManager = .default
    ) throws -> StorageCleanupReport {
        try cleanupContents(
            in: directoryURL,
            preserving: preservedURLs,
            shouldRemove: { _ in true },
            fileManager: fileManager
        )
    }

    private static func cleanupContents(
        in directoryURL: URL,
        preserving preservedURLs: Set<URL>,
        shouldRemove: (URL) -> Bool,
        fileManager: FileManager
    ) throws -> StorageCleanupReport {
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return .empty
        }

        let preserved = Set(preservedURLs.map(normalizedURL))
        let contents = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [
                .contentModificationDateKey,
                .fileAllocatedSizeKey,
                .fileSizeKey,
                .isDirectoryKey,
            ],
            options: [.skipsHiddenFiles]
        )

        var removedCount = 0
        var removedBytes: Int64 = 0

        for itemURL in contents {
            guard !preserved.contains(normalizedURL(itemURL)),
                  shouldRemove(itemURL) else {
                continue
            }

            let size = itemSize(url: itemURL, fileManager: fileManager)
            do {
                try fileManager.removeItem(at: itemURL)
                removedCount += 1
                removedBytes += size
            } catch {
                continue
            }
        }

        return StorageCleanupReport(
            removedItemCount: removedCount,
            removedBytes: removedBytes
        )
    }

    private static func itemSize(url: URL, fileManager: FileManager) -> Int64 {
        let values = try? url.resourceValues(forKeys: [
            .fileAllocatedSizeKey,
            .fileSizeKey,
            .isDirectoryKey,
        ])

        guard values?.isDirectory == true else {
            return Int64(values?.fileAllocatedSize ?? values?.fileSize ?? 0)
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileAllocatedSizeKey, .fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [
                .fileAllocatedSizeKey,
                .fileSizeKey,
                .isDirectoryKey,
            ])
            guard values?.isDirectory != true else { continue }
            totalSize += Int64(values?.fileAllocatedSize ?? values?.fileSize ?? 0)
        }
        return totalSize
    }

    private static func normalizedURL(_ url: URL) -> URL {
        url.standardizedFileURL
    }
}
