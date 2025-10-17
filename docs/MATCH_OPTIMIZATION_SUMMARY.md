# Fastlane Match 최적화 요약

## 🎯 최적화된 Match 설정

### **핵심 변경사항**
- **개발용 인증서**: Match에 저장하지 않음 (로컬에서 자동 관리)
- **배포용 인증서**: Match에 저장 (App Store 제출용)

## 📋 인증서 종류별 관리 방식

### 🔧 개발용 인증서 (Mac Development)
- **위치**: 로컬 Mac (Xcode에서 자동 관리)
- **용도**: 로컬 개발 및 테스트
- **생성**: Xcode에서 자동 생성
- **Match 저장**: ❌ 불필요

### 📦 배포용 인증서 (Mac App Distribution)
- **위치**: Match 저장소 (암호화됨)
- **용도**: App Store 제출, TestFlight 배포
- **생성**: Match 초기화 시 자동 생성
- **Match 저장**: ✅ 필수

## 🏗️ 최적화된 저장소 구조

```
captionmate-certificates/
├── README.md
├── certs/
│   └── distribution/
│       └── Mac App Distribution: com.cho407.CaptionMate.p12
├── profiles/
│   └── appstore/
│       └── Mac App Store_com.cho407.CaptionMate.mobileprovision
└── Matchfile
```

## 🎯 GitHub Actions 워크플로우

### develop 브랜치 (TestFlight 배포)
1. **Match에서 배포용 인증서 다운로드**
2. **테스트 실행** (코드 서명 없이)
3. **아카이브 빌드** (배포용 인증서 사용)
4. **TestFlight 업로드**

### main 브랜치 (빌드만)
1. **빌드만 실행** (인증서 불필요)
2. **아카이브 및 export 건너뛰기**

## ✅ 장점

### 효율성
- **저장소 크기 감소**: 배포용 인증서만 저장
- **초기화 시간 단축**: 개발용 인증서 생성 생략
- **관리 복잡성 감소**: 필요한 인증서만 관리

### 보안
- **최소 권한 원칙**: 필요한 인증서만 저장
- **자동 관리**: 개발용은 Xcode에서 자동 처리
- **중앙 집중식**: 배포용만 중앙에서 관리

### 협업
- **팀원 간 공유**: 배포용 인증서만 공유
- **로컬 독립성**: 개발용은 각자 로컬에서 관리
- **충돌 방지**: 개발용 인증서 충돌 없음

## 🔄 설정 변경사항

### Matchfile
```ruby
# 변경 전
type("development")  # 개발용도 포함

# 변경 후
type("appstore")     # 배포용만
```

### Fastfile
```ruby
# 변경 전
match(type: "development")  # 개발용도 포함

# 변경 후
match(type: "appstore")     # 배포용만
```

## 📚 관련 문서

- **상세 설정 가이드**: `docs/MATCH_REPOSITORY_SETUP.md`
- **저장소 구조**: `docs/MATCH_REPOSITORY_STRUCTURE.md`
- **초기화 스크립트**: `scripts/create_match_repo.sh`

## 🎉 결론

이제 Match는 **배포용 인증서만 관리**하므로 더욱 효율적이고 간단해졌습니다. 개발용 인증서는 각 개발자의 로컬 환경에서 Xcode가 자동으로 관리하므로 Match에 저장할 필요가 없습니다.

**결과**: 저장소 크기 감소, 초기화 시간 단축, 관리 복잡성 감소
