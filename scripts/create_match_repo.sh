#!/bin/bash

# Fastlane Match 저장소 생성 및 초기 설정 스크립트
# 이 스크립트는 Match 초기 설정을 도와줍니다.

set -e

echo "🚀 Fastlane Match 저장소 생성 및 초기 설정"
echo "=========================================="
echo ""

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 1. 프라이빗 저장소 생성 확인
echo -e "${BLUE}1. 프라이빗 Git 저장소 생성 확인${NC}"
echo "=================================="
echo ""
echo "다음 단계를 따라 프라이빗 저장소를 생성하세요:"
echo ""
echo "1. GitHub에서 새로운 저장소 생성:"
echo "   - 저장소명: captionmate-certificates"
echo "   - 설명: CaptionMate 인증서 및 프로비저닝 프로필 저장소"
echo "   - 중요: 반드시 Private으로 설정!"
echo ""
echo "2. 저장소 URL 확인:"
echo "   예시: https://github.com/cho407/captionmate-certificates.git"
echo ""
read -p "프라이빗 저장소를 생성했습니까? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}❌ 프라이빗 저장소를 먼저 생성해주세요.${NC}"
    exit 1
fi

# 2. 저장소 URL 입력
echo ""
echo -e "${BLUE}2. 저장소 URL 입력${NC}"
echo "=================="
echo ""
read -p "프라이빗 저장소 URL을 입력하세요: " REPO_URL
if [[ -z "$REPO_URL" ]]; then
    echo -e "${RED}❌ 저장소 URL을 입력해주세요.${NC}"
    exit 1
fi

# 3. Match 암호화 비밀번호 입력
echo ""
echo -e "${BLUE}3. Match 암호화 비밀번호 설정${NC}"
echo "============================="
echo ""
echo "Match에서 인증서를 암호화할 비밀번호를 설정하세요."
echo "이 비밀번호는 GitHub Secrets에도 설정해야 합니다."
echo ""
read -s -p "Match 암호화 비밀번호를 입력하세요: " MATCH_PASSWORD
echo ""
if [[ -z "$MATCH_PASSWORD" ]]; then
    echo -e "${RED}❌ 암호화 비밀번호를 입력해주세요.${NC}"
    exit 1
fi

# 4. Apple ID 정보 확인
echo ""
echo -e "${BLUE}4. Apple Developer Portal 정보 확인${NC}"
echo "===================================="
echo ""
echo "Match 초기화 시 Apple Developer Portal에 로그인해야 합니다."
echo "Apple ID와 비밀번호를 준비해주세요."
echo ""
read -p "Apple ID를 입력하세요: " APPLE_ID
if [[ -z "$APPLE_ID" ]]; then
    echo -e "${RED}❌ Apple ID를 입력해주세요.${NC}"
    exit 1
fi

# 5. 환경 변수 설정
echo ""
echo -e "${BLUE}5. 환경 변수 설정${NC}"
echo "=================="
echo ""
export MATCH_GIT_URL="$REPO_URL"
export MATCH_PASSWORD="$MATCH_PASSWORD"
export APPLE_ID="$APPLE_ID"

echo "환경 변수가 설정되었습니다:"
echo "MATCH_GIT_URL: $MATCH_GIT_URL"
echo "MATCH_PASSWORD: [숨김]"
echo "APPLE_ID: $APPLE_ID"

# 6. CaptionMate 디렉토리로 이동
echo ""
echo -e "${BLUE}6. Match 초기화 준비${NC}"
echo "===================="
echo ""
cd "$(dirname "$0")/../CaptionMate"

# 7. Bundle 업데이트
echo "Bundle 업데이트 중..."
bundle install

# 8. Match 초기화 실행
echo ""
echo -e "${YELLOW}⚠️  Match 초기화를 시작합니다.${NC}"
echo "이 과정에서 다음 작업이 수행됩니다:"
echo "1. Apple Developer Portal에 로그인"
echo "2. 인증서 생성/확인"
echo "3. 프로비저닝 프로필 생성/확인"
echo "4. 파일 암호화 및 Git 저장소에 업로드"
echo ""
read -p "계속하시겠습니까? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}❌ Match 초기화가 취소되었습니다.${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}Match 초기화 실행 중... (배포용 인증서만)${NC}"
echo "Apple ID 비밀번호를 입력하라는 프롬프트가 나타날 수 있습니다."
echo ""
echo "💡 참고: 개발용 인증서는 로컬에서 자동 관리되므로 Match에 저장하지 않습니다."
echo "   배포용 인증서만 저장됩니다 (App Store 제출용)."
echo ""

# Match 초기화 실행
bundle exec fastlane match_init

echo ""
echo -e "${GREEN}✅ Match 초기화 완료! (배포용 인증서만 저장됨)${NC}"
echo ""

# 9. GitHub Secrets 설정 안내
echo -e "${BLUE}7. GitHub Secrets 설정${NC}"
echo "===================="
echo ""
echo "이제 GitHub 저장소의 Secrets에 다음 값들을 추가하세요:"
echo ""
echo "1. GitHub 저장소 > Settings > Secrets and variables > Actions"
echo ""
echo "2. 다음 Secrets를 추가:"
echo ""
echo -e "${YELLOW}MATCH_GIT_URL:${NC}"
echo "$MATCH_GIT_URL"
echo ""
echo -e "${YELLOW}MATCH_PASSWORD:${NC}"
echo "$MATCH_PASSWORD"
echo ""
echo -e "${YELLOW}MATCH_GIT_AUTH:${NC}"
echo "GitHub Personal Access Token을 base64로 인코딩한 값"
echo "생성 방법: echo -n \"username:token\" | base64"
echo ""

# 10. Personal Access Token 생성 안내
echo -e "${BLUE}8. GitHub Personal Access Token 생성${NC}"
echo "===================================="
echo ""
echo "GitHub Personal Access Token을 생성하세요:"
echo ""
echo "1. GitHub > Settings > Developer settings > Personal access tokens"
echo "2. Generate new token (classic)"
echo "3. 권한: repo (전체 저장소 접근)"
echo "4. 생성된 토큰을 사용하여 base64 인코딩:"
echo ""
echo "예시:"
echo "echo -n \"cho407:ghp_your_token_here\" | base64"
echo ""

echo -e "${GREEN}🎉 Match 설정이 완료되었습니다!${NC}"
echo ""
echo "📋 다음 단계:"
echo "1. GitHub Personal Access Token 생성"
echo "2. GitHub Secrets에 MATCH_GIT_AUTH 추가"
echo "3. GitHub Actions 워크플로우 테스트"
echo ""
echo "🔗 저장소 확인:"
echo "$MATCH_GIT_URL"
echo ""
echo "📚 상세 가이드: docs/MATCH_REPOSITORY_SETUP.md"
