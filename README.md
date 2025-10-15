# CaptionMate

<p align="center">

### 페르소나
> 영상 자막을 자동으로 첨부 하고 싶은 파이널 컷 프로 사용자

### ADS
> 음성 및 영상 속 말을 텍스트로 변환하여 자동으로 자막을 생성하는 앱

### 개발 기간
> 2025.2.23 ~

<br>

### 문의
-

<br>


## 주요기능과 스크린샷

### 홈 탭

## 🚀 빠른 시작

### 개발 환경 설정
새로운 개발자를 위한 상세한 설정 가이드는 [SETUP.md](SETUP.md)를 참고하세요.

### 필수 요구사항
- **macOS**: 12.0 이상
- **Xcode**: 16.2 이상
- **Swift**: 6.0.3 이상
- **Homebrew**: 패키지 관리자
- **Mint**: Swift 패키지 관리자

### 자동 설정 (권장)
```bash
git clone https://github.com/cho407/CaptionMate.git
cd CaptionMate
./scripts/setup.sh
open CaptionMate/CaptionMate.xcodeproj
```

### 수동 설정
```bash
git clone https://github.com/cho407/CaptionMate.git
cd CaptionMate
brew install mint
mint bootstrap
open CaptionMate/CaptionMate.xcodeproj
```

## 🛠️ 기술 스택

### 개발 환경
<img src="https://img.shields.io/badge/Xcode-147EFB?style=&logo=Xcode&logoColor=white"> <img src="https://img.shields.io/badge/v16.2-147EFB?">

### 사용 기술
<img src="https://img.shields.io/badge/Swift-F05138?style=&logo=Swift&logoColor=white"> <img src="https://img.shields.io/badge/v6.0.3-F05138?"> <img src="https://img.shields.io/badge/SwiftUI-0d42a0?style=&logo=swift&logoColor=white">

### 주요 라이브러리
- **WhisperKit**: Apple의 Whisper 모델을 사용한 음성 인식
- **SwiftUI**: 모던 UI 프레임워크
- **Combine**: 반응형 프로그래밍

### 개발 도구
- **SwiftFormat**: 코드 포맷팅
- **GitHub Actions**: CI/CD
- **Mint**: Swift 패키지 관리

<br>

## 데이터 구조


<br>

## 사용자 시나리오

![userScenario](https://github.com/user-attachments/assets/265beb09-43be-4299-8b0b-3f03c0dbae91)
## 참여자
<table style="font-weight : bold">
<td align="center">
<a href="https://github.com/cho407">
<img alt="조형구" src="https://avatars.githubusercontent.com/cho407" width="80" />
<tr>
<td align="center">조형구</td>
</tr>
</table>
</div>

## 라이센스
CaptionMate is released under the Apache License 2.0. See [LICENSE](https://github.com/cho407/CaptionMate/blob/main/LICENSE) for details.
