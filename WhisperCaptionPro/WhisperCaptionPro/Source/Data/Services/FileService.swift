//
//  FileService.swift
//  WhisperCaptionPro
//
//  Created by 조형구 on 3/21/25.
//

import Foundation

/// 파일 입출력 및 내보내기 관련 기능을 담당하는 서비스
class FileService {
    /// 주어진 데이터를 임시 디렉터리에 저장하고 URL을 반환합니다.
    func saveFile(data: Data, withExtension fileExtension: String) throws -> URL {
        let uniqueFileName = UUID().uuidString + "." + fileExtension
        let tempDirectoryURL = FileManager.default.temporaryDirectory
        let localFileURL = tempDirectoryURL.appendingPathComponent(uniqueFileName)
        try data.write(to: localFileURL)
        return localFileURL
    }

    // 추가적인 파일 내보내기(export) 로직 구현 가능.
}
