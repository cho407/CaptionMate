# Fastlane Match 저장소 설정 가이드

## 🎯 개요

Fastlane Match는 **별도의 프라이빗 Git 저장소**에 인증서와 프로비저닝 프로필을 암호화하여 저장합니다.

## 📋 필수 작업 순서

### 1. 프라이빗 Git 저장소 생성

```bash
# GitHub에서 새로운 프라이빗 저장소 생성
# 저장소명: captionmate-certificates (또는 원하는 이름)
# 설명: CaptionMate 인증서 및 프로비저닝 프로필 저장소
# 중요: 반드시 Private 저장소로 생성!
```

### 2. 저장소 구조 (Match가 자동 생성)

Match 초기화 후 다음과 같은 구조가 생성됩니다:

```
captionmate-certificates/
├── certs/
│   ├── development/
│   │   └── Mac Development: com.cho407.CaptionMate (암호화된 파일)
│   └── distribution/
│       └── Mac App Distribution: com.cho407.CaptionMate (암호화된 파일)
├── profiles/
│   ├── development/
│   │   └── Mac Development_com.cho407.CaptionMate.mobileprovision (암호화된 파일)
│   └── appstore/
│       └── Mac App Store_com.cho407.CaptionMate.mobileprovision (암호화된 파일)
└── README.md
```

### 3. Match 초기화 과정

```bash
# 1. 환경 변수 설정
export MATCH_GIT_URL="https://github.com/cho407/captionmate-certificates.git"
export MATCH_PASSWORD="your-strong-password-here"

# 2. Apple Developer Portal 로그인 정보 필요
export APPLE_ID="your-apple-id@example.com"
export APPLE_ID_PASSWORD="your-apple-id-password"

# 3. Match 초기화 실행
cd CaptionMate
bundle exec fastlane match_init
```

### 4. Match 초기화 시 수행되는 작업

1. **Apple Developer Portal에 로그인**
2. **인증서 생성/확인**:
   - Mac Development Certificate
   - Mac App Distribution Certificate
3. **프로비저닝 프로필 생성/확인**:
   - Mac Development Profile
   - Mac App Store Profile
4. **파일 암호화 및 Git 저장소에 업로드**
5. **Git 커밋 및 푸시**

### 5. GitHub Actions에서 사용

```yaml
# .github/workflows/Caption-Mate-Fastlane.yml
- name: Setup Match Environment
  env:
    MATCH_GIT_URL: ${{ secrets.MATCH_GIT_URL }}
    MATCH_GIT_AUTH: ${{ secrets.MATCH_GIT_AUTH }}
    MATCH_PASSWORD: ${{ secrets.MATCH_PASSWORD }}
  run: |
    echo "MATCH_GIT_URL=$MATCH_GIT_URL" >> $GITHUB_ENV
    echo "MATCH_GIT_AUTH=$MATCH_GIT_AUTH" >> $GITHUB_ENV
    echo "MATCH_PASSWORD=$MATCH_PASSWORD" >> $GITHUB_ENV

- name: Deploy to TestFlight
  run: |
    cd CaptionMate
    bundle exec fastlane develop_deploy
```

## 🔐 보안 특징

### 암호화
- 모든 인증서와 프로비저닝 프로필은 **OpenSSL**로 암호화됩니다
- `MATCH_PASSWORD`를 사용하여 암호화/복호화합니다
- Git 저장소에 저장되는 모든 파일은 암호화된 상태입니다

### 접근 제어
- 프라이빗 Git 저장소로 접근 제한
- GitHub Personal Access Token으로 인증
- 팀원 간 안전한 인증서 공유

## 📋 GitHub Secrets 설정

| Secret Name | 설명 | 값 |
|-------------|------|-----|
| `MATCH_GIT_URL` | 프라이빗 Git 저장소 URL | `https://github.com/cho407/captionmate-certificates.git` |
| `MATCH_GIT_AUTH` | Git 인증 토큰 (base64) | `username:token`을 base64 인코딩 |
| `MATCH_PASSWORD` | Match 암호화 비밀번호 | 강력한 비밀번호 (예: `MyStrongPassword123!`) |

### Git 인증 토큰 생성

```bash
# GitHub Personal Access Token 생성
# 1. GitHub > Settings > Developer settings > Personal access tokens
# 2. Generate new token (classic)
# 3. 권한: repo (전체 저장소 접근)
# 4. base64 인코딩:
echo -n "cho407:ghp_your_token_here" | base64
```

## ⚠️ 중요 사항

1. **프라이빗 저장소 필수**: 반드시 Private 저장소를 생성해야 합니다
2. **Apple Developer Portal 접근**: Match 초기화 시 Apple Developer Portal 로그인이 필요합니다
3. **인증서 생성**: Match가 Apple Developer Portal에서 인증서를 자동으로 생성합니다
4. **암호화 비밀번호**: `MATCH_PASSWORD`를 안전하게 보관하세요
5. **Git 토큰 권한**: Personal Access Token에 repo 권한이 필요합니다

## 🔄 워크플로우

### 초기 설정 (1회만)
1. 프라이빗 Git 저장소 생성
2. Match 초기화 (인증서 생성 및 업로드)
3. GitHub Secrets 설정

### 정기 사용
1. CI/CD에서 Match를 통해 인증서 다운로드
2. 빌드 및 배포 수행
3. 필요시 인증서 갱신

## 🎯 장점

✅ **자동화**: Apple Developer Portal과 자동 동기화  
✅ **보안**: 암호화된 저장소 사용  
✅ **협업**: 팀원 간 인증서 공유  
✅ **효율성**: base64 방식 대비 훨씬 효율적  
✅ **관리**: 인증서 만료 자동 감지 및 갱신  

## 🔗 참고 자료

- [Fastlane Match 공식 문서](https://docs.fastlane.tools/actions/match/)
- [Apple Developer Portal](https://developer.apple.com/account/)
- [GitHub Personal Access Token](https://github.com/settings/tokens)
