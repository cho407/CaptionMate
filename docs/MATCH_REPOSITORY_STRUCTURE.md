# Fastlane Match 저장소 구조

## 📁 저장소 구조 예시

Match 초기화 후 생성되는 프라이빗 저장소의 구조:

```
captionmate-certificates/
├── README.md
├── certs/
│   ├── development/
│   │   └── Mac Development: com.cho407.CaptionMate.p12
│   └── distribution/
│       └── Mac App Distribution: com.cho407.CaptionMate.p12
├── profiles/
│   ├── development/
│   │   └── Mac Development_com.cho407.CaptionMate.mobileprovision
│   └── appstore/
│       └── Mac App Store_com.cho407.CaptionMate.mobileprovision
└── Matchfile
```

## 🔐 파일 설명

### 인증서 파일 (certs/)
- **development/**: 개발용 인증서
  - `Mac Development: com.cho407.CaptionMate.p12`
  - 로컬 개발 및 테스트용
- **distribution/**: 배포용 인증서
  - `Mac App Distribution: com.cho407.CaptionMate.p12`
  - App Store 배포용

### 프로비저닝 프로필 (profiles/)
- **development/**: 개발용 프로필
  - `Mac Development_com.cho407.CaptionMate.mobileprovision`
  - 개발 환경에서 앱 실행용
- **appstore/**: App Store용 프로필
  - `Mac App Store_com.cho407.CaptionMate.mobileprovision`
  - App Store 제출용

## 🔒 암호화 특징

### 모든 파일이 암호화됨
- **OpenSSL**을 사용하여 암호화
- `MATCH_PASSWORD`로 암호화/복호화
- Git 저장소에 저장되는 모든 파일은 암호화된 상태

### 암호화 예시
```bash
# 원본 파일
Mac Development: com.cho407.CaptionMate.p12

# 암호화된 파일 (실제로는 바이너리)
Mac Development: com.cho407.CaptionMate.p12.enc
```

## 📋 Matchfile 내용

```ruby
# Matchfile
git_url("https://github.com/cho407/captionmate-certificates.git")
storage_mode("git")
app_identifier("com.cho407.CaptionMate")
team_id("H6P789M74Y")
type("appstore")
readonly(true)
force_for_new_devices(false)
keychain_name("login.keychain")
keychain_password("")
```

## 🔄 워크플로우

### Match 초기화 시
1. Apple Developer Portal에 로그인
2. 인증서 생성/확인
3. 프로비저닝 프로필 생성/확인
4. 파일을 암호화하여 Git 저장소에 업로드
5. Git 커밋 및 푸시

### CI/CD에서 사용 시
1. Git 저장소에서 암호화된 파일 다운로드
2. `MATCH_PASSWORD`로 복호화
3. 키체인에 인증서 설치
4. 프로비저닝 프로필 설치
5. 빌드 및 배포 수행

## ⚠️ 중요 사항

1. **프라이빗 저장소 필수**: 반드시 Private 저장소를 사용
2. **암호화 비밀번호 보안**: `MATCH_PASSWORD`를 안전하게 보관
3. **Git 접근 권한**: Personal Access Token에 repo 권한 필요
4. **Apple Developer Portal**: Match 초기화 시 로그인 필요
5. **자동 갱신**: Match가 인증서 만료를 자동으로 감지하고 갱신

## 🎯 장점

✅ **보안**: 모든 파일이 암호화되어 저장  
✅ **자동화**: Apple Developer Portal과 자동 동기화  
✅ **협업**: 팀원 간 안전한 인증서 공유  
✅ **효율성**: base64 방식 대비 훨씬 효율적  
✅ **관리**: 인증서 만료 자동 감지 및 갱신  

## 📚 관련 파일

- **설정 가이드**: `docs/MATCH_REPOSITORY_SETUP.md`
- **초기화 스크립트**: `scripts/create_match_repo.sh`
- **Match 설정**: `CaptionMate/fastlane/Matchfile`
