# Fastlane Match 설정 가이드

## 🎯 개요

Fastlane Match를 사용하여 인증서와 프로비저닝 프로필을 안전하게 관리합니다.

## 🔧 초기 설정

### 1. 프라이빗 Git 저장소 생성

```bash
# GitHub에서 새로운 프라이빗 저장소 생성
# 저장소명: captionmate-certificates
# 설명: CaptionMate 인증서 및 프로비저닝 프로필 저장소
```

### 2. 환경 변수 설정

로컬에서 다음 환경 변수를 설정하세요:

```bash
export MATCH_GIT_URL="https://github.com/cho407/captionmate-certificates.git"
export MATCH_PASSWORD="your-strong-password-here"
```

### 3. Match 초기화

```bash
# 초기화 스크립트 실행
./scripts/setup_match.sh
```

## 🔐 GitHub Secrets 설정

GitHub 저장소의 Settings > Secrets and variables > Actions에서 다음 Secrets를 추가하세요:

### 필수 Secrets

| Secret Name | 설명 | 예시 값 |
|-------------|------|---------|
| `MATCH_GIT_URL` | 프라이빗 Git 저장소 URL | `https://github.com/cho407/captionmate-certificates.git` |
| `MATCH_GIT_AUTH` | Git 인증 토큰 (base64) | `dXNlcm5hbWU6dG9rZW4=` |
| `MATCH_PASSWORD` | Match 암호화 비밀번호 | `your-strong-password-here` |

### Git 인증 토큰 생성

```bash
# GitHub Personal Access Token 생성
# 1. GitHub > Settings > Developer settings > Personal access tokens
# 2. Generate new token (classic)
# 3. 권한: repo (전체 저장소 접근)
# 4. base64 인코딩:
echo -n "username:token" | base64
```

## 🚀 사용법

### 로컬에서 인증서 갱신

```bash
cd CaptionMate
bundle exec fastlane match_renew
```

### GitHub Actions에서 자동 사용

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
```

## 🔄 워크플로우

### develop_deploy lane

1. **Match를 통한 인증서 다운로드**
2. **테스트 실행**
3. **아카이브 빌드**
4. **TestFlight 업로드**

### main_archive lane

- **빌드만 실행** (인증서 불필요)

## 📋 장점

✅ **보안**: 암호화된 Git 저장소 사용  
✅ **자동화**: 인증서 자동 생성 및 갱신  
✅ **협업**: 팀원 간 인증서 공유  
✅ **관리**: Apple Developer Portal과 자동 동기화  
✅ **효율성**: base64 방식 대비 훨씬 효율적  

## ⚠️ 주의사항

- 프라이빗 Git 저장소가 필요합니다
- Match 암호화 비밀번호를 안전하게 보관하세요
- GitHub Personal Access Token 권한을 적절히 설정하세요
- 인증서 만료 전에 정기적으로 갱신하세요

## 🔗 참고 자료

- [Fastlane Match 공식 문서](https://docs.fastlane.tools/actions/match/)
- [GitHub Personal Access Token](https://github.com/settings/tokens)
- [Apple Developer Portal](https://developer.apple.com/account/)
