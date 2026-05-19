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

struct CaptionMateProject: Codable, Equatable, Sendable {
    let id: String
    let displayName: String
    let createdAt: Date
    let updatedAt: Date
    let sourceAudioPath: String?
    let sourceAudioBookmarkData: Data?
    let lastExportedAt: Date?
    let sidecar: CaptionMateSidecar

    init(
        id: String,
        displayName: String,
        createdAt: Date,
        updatedAt: Date,
        sourceAudioPath: String?,
        sourceAudioBookmarkData: Data? = nil,
        lastExportedAt: Date?,
        sidecar: CaptionMateSidecar
    ) {
        self.id = id
        self.displayName = displayName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceAudioPath = sourceAudioPath
        self.sourceAudioBookmarkData = sourceAudioBookmarkData
        self.lastExportedAt = lastExportedAt
        self.sidecar = sidecar
    }
}

struct CaptionMateProjectSummary: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let createdAt: Date
    let updatedAt: Date
    let language: String
    let segmentCount: Int
    let speakerCount: Int
    let speakerDisplayNames: [String]
    let sourceAudioPath: String?
    let sourceAudioFileName: String?
    let sourceAudioExists: Bool
    let lastExportedAt: Date?
}

enum CaptionMateProjectStoreError: LocalizedError, Equatable {
    case unsafeProjectID(String)
    case emptyDisplayName
    case fileTooLarge(byteCount: Int64, limit: Int64)

    var errorDescription: String? {
        switch self {
        case let .unsafeProjectID(id):
            return "Unsafe CaptionMate project id: \(id)"
        case .emptyDisplayName:
            return "Project name cannot be empty."
        case let .fileTooLarge(byteCount, limit):
            let actual = ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
            let maximum = ByteCountFormatter.string(fromByteCount: limit, countStyle: .file)
            return "CaptionMate project is too large to restore safely: \(actual). Maximum: \(maximum)."
        }
    }
}

struct CaptionMateProjectStore {
    static let pathExtension = "captionmateproject.json"
    static let maxReadableProjectBytes: Int64 = 32 * 1024 * 1024

    let rootURL: URL

    static func defaultRootURL() throws -> URL {
        let applicationSupportURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return applicationSupportURL
            .appendingPathComponent("CaptionMate", isDirectory: true)
            .appendingPathComponent("Projects", isDirectory: true)
    }

    static func liveStore() -> CaptionMateProjectStore {
        let rootURL = (try? defaultRootURL()) ??
            FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionMateProjects", isDirectory: true)
        return CaptionMateProjectStore(rootURL: rootURL)
    }

    @discardableResult
    func save(_ project: CaptionMateProject) throws -> URL {
        let url = try projectURL(for: project.id)
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(project)
        try data.write(to: url, options: .atomic)
        return url
    }

    func load(id: String) throws -> CaptionMateProject {
        let url = try projectURL(for: id)
        try validateReadableSize(of: url)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CaptionMateProject.self, from: data)
    }

    func delete(id: String) throws {
        let url = try projectURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func rename(
        id: String,
        displayName: String,
        now: Date = Date()
    ) throws -> CaptionMateProject {
        let project = try load(id: id)
        let renamedProject = CaptionMateProject(
            id: project.id,
            displayName: try Self.normalizedDisplayName(displayName),
            createdAt: project.createdAt,
            updatedAt: now,
            sourceAudioPath: project.sourceAudioPath,
            sourceAudioBookmarkData: project.sourceAudioBookmarkData,
            lastExportedAt: project.lastExportedAt,
            sidecar: project.sidecar
        )
        try save(renamedProject)
        return renamedProject
    }

    @discardableResult
    func relinkSourceAudio(
        id: String,
        sourceAudioURL: URL,
        bookmarkData: Data?,
        now: Date = Date()
    ) throws -> CaptionMateProject {
        let project = try load(id: id)
        let relinkedProject = CaptionMateProject(
            id: project.id,
            displayName: project.displayName,
            createdAt: project.createdAt,
            updatedAt: now,
            sourceAudioPath: sourceAudioURL.path,
            sourceAudioBookmarkData: bookmarkData,
            lastExportedAt: project.lastExportedAt,
            sidecar: project.sidecar
        )
        try save(relinkedProject)
        return relinkedProject
    }

    @discardableResult
    func duplicate(
        id: String,
        displayName: String,
        now: Date = Date(),
        newID: String = UUID().uuidString
    ) throws -> CaptionMateProject {
        try Self.validateProjectID(newID)
        let project = try load(id: id)
        let duplicatedProject = CaptionMateProject(
            id: newID,
            displayName: try Self.normalizedDisplayName(displayName),
            createdAt: now,
            updatedAt: now,
            sourceAudioPath: project.sourceAudioPath,
            sourceAudioBookmarkData: project.sourceAudioBookmarkData,
            lastExportedAt: nil,
            sidecar: project.sidecar
        )
        try save(duplicatedProject)
        return duplicatedProject
    }

    func listSummaries() throws -> [CaptionMateProjectSummary] {
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            return []
        }

        let urls = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        let projects = try urls
            .filter { $0.lastPathComponent.hasSuffix(".\(Self.pathExtension)") }
            .map { url in
                try validateReadableSize(of: url)
                let data = try Data(contentsOf: url)
                return try JSONDecoder().decode(CaptionMateProject.self, from: data)
            }

        return projects
            .map(Self.summary)
            .sorted {
                if $0.updatedAt == $1.updatedAt {
                    return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                }
                return $0.updatedAt > $1.updatedAt
            }
    }

    private func projectURL(for id: String) throws -> URL {
        try Self.validateProjectID(id)
        let standardizedRootURL = rootURL.standardizedFileURL
        let projectURL = standardizedRootURL
            .appendingPathComponent(id, isDirectory: false)
            .appendingPathExtension(Self.pathExtension)
            .standardizedFileURL
        guard projectURL.deletingLastPathComponent().standardizedFileURL == standardizedRootURL else {
            throw CaptionMateProjectStoreError.unsafeProjectID(id)
        }
        return projectURL
    }

    private static func validateProjectID(_ id: String) throws {
        let allowedCharacters = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "-_"))
        guard !id.isEmpty,
              id.count <= 64,
              id.rangeOfCharacter(from: allowedCharacters.inverted) == nil else {
            throw CaptionMateProjectStoreError.unsafeProjectID(id)
        }
    }

    private static func normalizedDisplayName(_ displayName: String) throws -> String {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw CaptionMateProjectStoreError.emptyDisplayName
        }
        return trimmedName
    }

    private func validateReadableSize(of url: URL) throws {
        let values = try url
            .resolvingSymlinksInPath()
            .resourceValues(forKeys: [.fileSizeKey])
        guard let byteCount = values.fileSize.map(Int64.init),
              byteCount > Self.maxReadableProjectBytes else {
            return
        }
        throw CaptionMateProjectStoreError.fileTooLarge(
            byteCount: byteCount,
            limit: Self.maxReadableProjectBytes
        )
    }

    private static func summary(for project: CaptionMateProject) -> CaptionMateProjectSummary {
        let speakerIDs = Set(project.sidecar.segments.compactMap(\.speakerID))
            .union(project.sidecar.speakerNames.keys.compactMap(Int.init))
        let speakerDisplayNames = speakerIDs
            .sorted()
            .compactMap { project.sidecar.speakerNames[String($0)] }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let sourceAudioExists = project.sourceAudioPath.map {
            FileManager.default.fileExists(atPath: $0)
        } ?? false
        let sourceAudioFileName = project.sourceAudioPath.flatMap { path in
            let fileName = URL(fileURLWithPath: path).lastPathComponent
            return fileName.isEmpty ? nil : fileName
        }

        return CaptionMateProjectSummary(
            id: project.id,
            displayName: project.displayName,
            createdAt: project.createdAt,
            updatedAt: project.updatedAt,
            language: project.sidecar.language,
            segmentCount: project.sidecar.segments.count,
            speakerCount: speakerIDs.count,
            speakerDisplayNames: speakerDisplayNames,
            sourceAudioPath: project.sourceAudioPath,
            sourceAudioFileName: sourceAudioFileName,
            sourceAudioExists: sourceAudioExists,
            lastExportedAt: project.lastExportedAt
        )
    }
}
