//
//  Ex+UTType.swift
//  WhisperCaptionPro
//
//  Created by 조형구 on 4/2/25.
//

import Foundation
import UniformTypeIdentifiers

extension UTType {
    static var fcpxml: UTType {
        return UTType(filenameExtension: "fcpxml", conformingTo: .xml) ?? .xml
    }
}
