//
//  Ex+NSSavePanel.swift
//  CaptionMate
//
//  Created by 조형구 on 3/29/25.
//

import AppKit
import UniformTypeIdentifiers

extension NSSavePanel {
    /// Presents an NSSavePanel with the specified options and returns the selected file URL and
    /// selected content type asynchronously.
    /// - Parameters:
    ///   - allowedFileTypes: An array of allowed UTTypes (e.g. [UTType.srt, UTType.vtt,
    /// UTType.json]).
    ///   - defaultFileName: The default file name (without extension).
    ///   - title: The panel title.
    /// - Returns: A tuple containing the URL selected by the user and the selected UTType, or (nil,
    /// nil) if cancelled.
    static func showSavePanel(allowedFileTypes: [UTType],
                              defaultFileName: String,
                              title: String = "Export Subtitle") async -> (URL?, UTType?) {
        await withCheckedContinuation { continuation in
            let panel = NSSavePanel()
            panel.title = title
            panel.nameFieldStringValue = defaultFileName
            panel.allowedContentTypes = allowedFileTypes
            panel.allowsOtherFileTypes = false
            panel.showsContentTypes = true
            panel.showsTagField = false

            let response = panel.runModal()
            if response == .OK {
                // 선택된 파일 형식을 가져옴
                let selectedType = panel.currentContentType
                continuation.resume(returning: (panel.url, selectedType))
            } else {
                continuation.resume(returning: (nil, nil))
            }
        }
    }
}
