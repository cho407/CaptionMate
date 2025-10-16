# CaptionMate 🎬

<p align="center">
<img src="https://img.shields.io/badge/macOS-15.0+-blue?style=flat-square&logo=apple&logoColor=white">
<img src="https://img.shields.io/badge/Swift-6.0.3-orange?style=flat-square&logo=swift&logoColor=white">
<img src="https://img.shields.io/badge/SwiftUI-5.0-blue?style=flat-square&logo=swift&logoColor=white">
<img src="https://img.shields.io/badge/License-Apache%202.0-green?style=flat-square&logo=apache&logoColor=white">
</p>

## 📱 앱스토어
> **[App Store 링크](https://apps.apple.com/kr/app/%EC%BA%A1%EC%85%98-%EB%A9%94%EC%9D%B4%ED%8A%B8-captionmate-%EC%9E%90%EB%8F%99-%EC%9E%90%EB%A7%89-%EC%83%9D%EC%84%B1/id6753956825?mt=12)**

### 페르소나
> 매 영상마다 자막을 직접 치느라 업로드가 늦어지는 컨텐츠 크리에이터.

### ADS
> CaptionMate는 AI를 활용해 음성을 텍스트로 전사해 자막 파일 형식(SRT/FCPXML/WebVTT/JSON)으로 만들어, 자막 작업 시간을 획기적으로 줄여주는 앱 입니다.

### 개발 기간
> 2025.02.23 ~ 2025.10.14

<br>

## 주요기능 및 스크린샷

### 🎙️ 음성 인식 및 전사

- **WhisperKit 기반 고품질 음성 인식**: OpenAI의 Whisper 모델을 사용한 정확한 음성-텍스트 변환
- **다양한 언어 지원**: 영어, 한국어 및 기타 다국어 지원
- **온디바이스 고속 처리**: 네트워크 없이 빠르고 안전하게 전사
- **단어 단위 타임스탬프**: 정확한 자막 동기화를 위한 세밀한 타임스탬프 제공
- **자동 번역**: 다양한 언어의 음성을 영문 자막으로 번역하여 제공

<div align="center">

| 메인 인터페이스 | 모델 관리 | 전사 설정 |
|-------|-------|-------|
| <img src="https://github.com/user-attachments/assets/4e8589bc-1c8c-4331-920e-8f833303f829" alt="메인 인터페이스" width="250" height="400">| <img src="https://github.com/user-attachments/assets/c2f23ed3-6203-4fb0-9936-d3eb2549f19f" alt="모델 관리" width="250" height="400"> | <img src="https://github.com/user-attachments/assets/9ee00eb1-f480-4976-b99b-1e56108a3a55" alt="전사 설정" width="250" height="400"> |

</div>

### 🎬 자막 내보내기

- **다양한 자막 형식**: SRT, WebVTT, JSON, Final Cut Pro XML 지원
- **실시간 미리보기**: 전사 결과를 실시간으로 확인

<div align="center">

| 전사 결과 | 자막 내보내기 | 파이널 컷 프로 연동 |
|-------|-------|-------|
| <img src="https://github.com/user-attachments/assets/c16ea6f8-ceee-4f97-894e-ec3b36a3fa2a" alt="전사 결과" width="250" height="400">| <img src="https://github.com/user-attachments/assets/0ba88f70-f56b-4938-859c-274aaaaf0803" alt="자막 내보내기" width="250" height="400"> | <img src="https://github.com/user-attachments/assets/5699150e-39a7-4c83-9c42-f4c254a66b84" alt="파이널 컷 프로 연동" width="250" height="400"> |

</div>

### ⚙️ 고급 설정 및 최적화

- **모델 선택**: 다양한 Whisper 모델 크기 선택 (tiny, base, small, medium, large)
- **성능 최적화**: Neural Engine, CPU, GPU 연산 유닛 설정과 prewarming 기능으로 성능 최적화
- **품질 조절**: 압축률, 온도, 타임스탬프 등 세밀한 설정 옵션
- **다국어 지원**: 영어, 한국어 언어 설정 지원
- **다크모드 지원**: 다크모드 지원

<div align="center">

| 다크 모드 | 다국어 지원 | 고급 설정 |
|-------|-------|-------|
| <img src="https://github.com/user-attachments/assets/5ff7a473-e12c-45b3-8046-754742df4efe" alt="다크 모드" width="250" height="400">| <img src="https://github.com/user-attachments/assets/95a0abb3-6b33-4c11-a637-ec966df0cadd" alt="다국어 지원" width="250" height="400"> | <img src="https://github.com/user-attachments/assets/9ee00eb1-f480-4976-b99b-1e56108a3a55" alt="고급 설정" width="250" height="400"> |

</div>

</div>
> 🔒 **Privacy**: 모든 전사는 **100% 온디바이스**로 처리됩니다. 파일/텍스트는 서버로 전송되지 않습니다.

## 🚀 빠른 시작

### 개발 환경 설정
새로운 개발자를 위한 상세한 설정 가이드는 [SETUP.md](SETUP.md)를 참고하세요.

### 필수 요구사항
- **macOS**: 15.0 이상
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
<img src="https://img.shields.io/badge/Xcode-147EFB?style=flat-square&logo=Xcode&logoColor=white"> <img src="https://img.shields.io/badge/v16.2-147EFB?style=flat-square">
<img src="https://img.shields.io/badge/macOS-15.0-blue?style=flat-square&logo=apple&logoColor=white">

### 사용 기술
<img src="https://img.shields.io/badge/Swift-F05138?style=flat-square&logo=Swift&logoColor=white"> <img src="https://img.shields.io/badge/v6.0.3-F05138?style=flat-square"> 
<img src="https://img.shields.io/badge/SwiftUI-0d42a0?style=flat-square&logo=swift&logoColor=white">
<img src="https://img.shields.io/badge/Combine-FF6B6B?style=flat-square&logo=swift&logoColor=white">

### 주요 라이브러리 및 프레임워크
<img src="https://img.shields.io/badge/WhisperKit-000000?style=flat-square&logo=openai&logoColor=white">
<img src="https://img.shields.io/badge/Core%20ML-FF6B6B?style=flat-square&logo=apple&logoColor=white">
<img src="https://img.shields.io/badge/AVFoundation-FF6B6B?style=flat-square&logo=apple&logoColor=white">
<img src="https://img.shields.io/badge/UniformTypeIdentifiers-FF6B6B?style=flat-square&logo=apple&logoColor=white">

> Powered by [WhisperKit](https://github.com/argmaxinc/WhisperKit) and [OpenAI Whisper](https://github.com/openai/whisper).

### 개발 도구
<img src="https://img.shields.io/badge/SwiftFormat-000000?style=flat-square&logo=swift&logoColor=white">
<img src="https://img.shields.io/badge/GitHub%20Actions-2088FF?style=flat-square&logo=github-actions&logoColor=white">
<img src="https://img.shields.io/badge/Mint-000000?style=flat-square&logo=swift&logoColor=white">
<img src="https://img.shields.io/badge/Pre--commit-FAB040?style=flat-square&logo=pre-commit&logoColor=white">

<br>

## 🏗️ 시스템 아키텍처

### MVVM 패턴
CaptionMate는 **MVVM (Model-View-ViewModel)** 아키텍처를 기반으로 구축되었습니다:

- **Model**: 데이터 모델 및 비즈니스 로직
- **View**: SwiftUI 기반 사용자 인터페이스
- **ViewModel**: 뷰와 모델 간의 데이터 바인딩 및 상태 관리

### 핵심 컴포넌트
- **ContentViewModel**: 메인 전사 로직 및 상태 관리
- **AudioViews**: 오디오 재생 및 파형 시각화
- **TranscriptionViews**: 전사 설정 및 결과 표시
- **ModelManagementViews**: AI 모델 관리 인터페이스

### 사용자 플로우 (User Flow)
<p align="center">
<img width="800" alt="CaptionMate User Flow" src="https://github.com/user-attachments/assets/46d4c513-70de-4836-a48a-1c6b4977152a">
</p>

### 엔티티 관계도 (ERD)
<p align="center">
<img width="800" alt="CaptionMate ERD" src="https://github.com/user-attachments/assets/58322566-82af-4e99-9aee-ab749a5eb981">
</p>

## 👥 개발자

<div align="center">
<table style="font-weight : bold">
<tr>
<td align="center">
<a href="https://github.com/cho407">
<img alt="조형구 (Harrison Cho)" src="https://avatars.githubusercontent.com/cho407" width="80" />
</a>
</td>
</tr>
<tr>
<td align="center">조형구 (Harrison Cho)</td>
</tr>
<tr>
<td align="center">
<strong>Lead Developer</strong><br>
iOS/macOS 개발자
</td>
</tr>
</table>
</div>

## 📞 문의 및 지원

- **이메일**: parfume407@gmail.com
- **GitHub Issues**: [버그 리포트 및 기능 요청](https://github.com/cho407/CaptionMate/issues)
- **Wiki**: [프로젝트 위키](https://github.com/cho407/CaptionMate/wiki)

## 📄 라이센스

CaptionMate는 **Apache License 2.0**에 따라 배포됩니다. 자세한 내용은 [LICENSE](https://github.com/cho407/CaptionMate/blob/main/LICENSE) 파일을 참조하세요.

---

<p align="center">
<strong>🎬 CaptionMate로 더 쉽고 빠른 자막 제작을 경험해보세요!</strong>
</p>
