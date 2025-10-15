# CaptionMate 개발 환경 설정 가이드

## 📋 필요 조건

### 시스템 요구사항
- **macOS**: 12.0 (Monterey) 이상
- **Xcode**: 16.2 이상
- **Swift**: 6.0.3 이상

### 필수 도구
- **Homebrew**: 패키지 관리자
- **Git**: 버전 관리

## 🚀 초기 설정

### 1. 저장소 클론
```bash
git clone https://github.com/cho407/CaptionMate.git
cd CaptionMate
```

### 2. 자동 설정 (권장)
```bash
# 프로젝트 루트에서 실행
./scripts/setup.sh
```

이 스크립트가 다음을 자동으로 처리합니다:
- Homebrew 설치 (없는 경우)
- Mint 설치
- 프로젝트 의존성 설치
- 스크립트 권한 설정
- 빌드 테스트
- 코드 품질 검사

### 3. Xcode 프로젝트 열기
```bash
open CaptionMate/CaptionMate.xcodeproj
```

---

## 🔧 수동 설정 (자동 설정이 실패하는 경우)

### 2. Homebrew 설치 (없는 경우)
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### 3. Mint 설치 (Swift 패키지 관리자)
```bash
brew install mint
```

### 4. 프로젝트 의존성 설치
```bash
mint bootstrap
```

이 명령어는 `Mintfile`에 정의된 SwiftFormat을 설치합니다.

### 5. 스크립트 권한 설정
```bash
chmod +x scripts/*.sh
```

## 🛠️ 개발 도구

### SwiftFormat (코드 포맷팅)
```bash
# 수동 포맷팅
scripts/style.sh

# 특정 파일 포맷팅
mint run swiftformat --indent 4 --maxwidth 100 CaptionMate/Source/YourFile.swift
```

### 빌드 및 테스트
```bash
# 빌드
scripts/build.sh CaptionMate macOS

# 또는 Xcode에서
# Command + B: 빌드
# Command + U: 테스트 실행
# Command + R: 앱 실행
```

## 📁 프로젝트 구조

```
CaptionMate/
├── CaptionMate/
│   ├── App/                    # 앱 진입점
│   ├── Configuration/          # 설정 및 상수
│   ├── Source/
│   │   ├── Data/              # 데이터 모델 및 서비스
│   │   └── Presentation/      # UI (Views, ViewModels)
│   ├── Assets.xcassets/       # 이미지 및 색상 리소스
│   └── CaptionMate.xcodeproj  # Xcode 프로젝트
├── Tests/                     # 단위 테스트 및 UI 테스트
├── scripts/                   # 개발 도구 스크립트
├── docs/                      # 문서
└── Mintfile                   # Swift 패키지 의존성
```

## 🔧 개발 워크플로우

### 1. 코드 작성
- SwiftUI 기반 UI 개발
- WhisperKit을 사용한 음성 인식
- MVVM 아키텍처 패턴 사용

### 2. 코드 품질 검사
```bash
# 카피라이트 확인
scripts/check_copyright.sh

# Whitespace 확인
scripts/check_whitespace.sh

# 파일명 공백 확인
scripts/check_filename_spaces.sh
```

### 3. 커밋 전 확인
```bash
# 코드 포맷팅
scripts/style.sh

# 빌드 확인
scripts/build.sh CaptionMate macOS
```

## 🚨 문제 해결

### Mint 설치 오류
```bash
# Homebrew 업데이트
brew update && brew upgrade

# Mint 재설치
brew uninstall mint && brew install mint
```

### Xcode 프로젝트 오류
```bash
# Derived Data 정리
rm -rf ~/Library/Developer/Xcode/DerivedData

# Xcode 재시작
```

### Swift Package 의존성 문제
```bash
# Xcode에서: File > Packages > Reset Package Caches
# 또는 터미널에서:
cd CaptionMate
xcodebuild -resolvePackageDependencies -project CaptionMate.xcodeproj -scheme CaptionMate
```

## 📚 추가 정보

### 주요 라이브러리
- **WhisperKit**: 음성 인식 (Apple의 Whisper 모델)
- **SwiftUI**: UI 프레임워크
- **Combine**: 반응형 프로그래밍

### 개발 가이드라인
- Swift 코딩 스타일: SwiftFormat 규칙 준수
- 커밋 메시지: 명확하고 간결하게
- 브랜치 전략: feature 브랜치 사용

### GitHub Actions
- 자동 빌드, 테스트, 아카이브
- Pull Request 시 자동 실행
- 코드 품질 검사 포함

## 🤝 기여하기

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📞 지원

문제가 발생하면:
1. GitHub Issues에서 검색
2. 새로운 Issue 생성
3. 개발자에게 연락

---

**Happy Coding! 🎉**
