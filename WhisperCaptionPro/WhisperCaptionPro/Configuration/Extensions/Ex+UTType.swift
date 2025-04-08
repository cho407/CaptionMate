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
        // 1. 시스템에 등록된 Final Cut Pro의 UTType을 먼저 확인
        if let registeredType = UTType(tag: "com.apple.finalcutpro.fcpxml", 
                                      tagClass: .filenameExtension, 
                                      conformingTo: .data) {
            return registeredType
        }
        
        // 2. MIME 타입으로 시도
        if let mimeType = UTType(tag: "application/vnd.apple.fcpxml", 
                                tagClass: .mimeType, 
                                conformingTo: .data) {
            return mimeType
        }
        
        // 3. 확장자로 생성 시도
        if let extensionType = UTType(filenameExtension: "fcpxml", conformingTo: .data) {
            return extensionType
        }
        
        // 4. 마지막 폴백으로 XML 타입 반환
        return .xml
    }
}
