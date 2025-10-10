//
//  DownloadError.swift
//  WhisperCaptionPro
//
//  Created by 조형구 on 10/10/25.
//

import Foundation
import SwiftUI

/// 다운로드 에러 타입 정의
enum DownloadError: Equatable {
    case networkOffline
    case networkLost
    case cannotConnectToServer
    case timeout
    case diskSpaceFull
    case permissionDenied
    case fileNotFound
    case unknown(String)
    
    /// 에러로부터 DownloadError 생성
    static func from(_ error: Error) -> DownloadError? {
        let nsError = error as NSError
        
        // 파일 이동 에러 (취소 시 발생) - 무시
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == NSFileNoSuchFileError || nsError.code == NSFileWriteFileExistsError {
            return nil // 취소로 인한 에러는 무시
        }
        
        // URL 에러
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                return .networkOffline
            case NSURLErrorNetworkConnectionLost:
                return .networkLost
            case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost:
                return .cannotConnectToServer
            case NSURLErrorTimedOut:
                return .timeout
            default:
                return .unknown(error.localizedDescription)
            }
        }
        
        // 파일 시스템 에러
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileWriteOutOfSpaceError:
                return .diskSpaceFull
            case NSFileWriteNoPermissionError, NSFileReadNoPermissionError:
                return .permissionDenied
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError:
                return .fileNotFound
            default:
                return .unknown(error.localizedDescription)
            }
        }
        
        // 기타 에러
        return .unknown(error.localizedDescription)
    }
    
    /// LocalizedStringKey 반환
    var localizedKey: LocalizedStringKey {
        switch self {
        case .networkOffline:
            return "error.network_offline"
        case .networkLost:
            return "error.network_lost"
        case .cannotConnectToServer:
            return "error.cannot_connect_to_server"
        case .timeout:
            return "error.timeout"
        case .diskSpaceFull:
            return "error.disk_space_full"
        case .permissionDenied:
            return "error.permission_denied"
        case .fileNotFound:
            return "error.file_not_found"
        case .unknown(let message):
            return LocalizedStringKey(message)
        }
    }
}

