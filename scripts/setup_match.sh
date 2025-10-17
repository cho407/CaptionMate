#!/bin/bash

# Fastlane Match 초기 설정 스크립트
# 이 스크립트는 최초 1회만 실행하면 됩니다.

set -e

echo "🔧 Fastlane Match 초기 설정 시작..."
echo "=================================="

# 필요한 환경 변수 확인
if [ -z "$MATCH_GIT_URL" ]; then
    echo "❌ MATCH_GIT_URL 환경 변수가 설정되지 않았습니다."
    echo "프라이빗 Git 저장소 URL을 설정해주세요."
    exit 1
fi

if [ -z "$MATCH_PASSWORD" ]; then
    echo "❌ MATCH_PASSWORD 환경 변수가 설정되지 않았습니다."
    echo "Match 암호화 비밀번호를 설정해주세요."
    exit 1
fi

# CaptionMate 디렉토리로 이동
cd "$(dirname "$0")/../CaptionMate"

echo "📦 Bundle 업데이트 중..."
bundle install

echo "🔐 Match 초기화 중..."
echo "⚠️  주의: 이 작업은 Apple Developer Portal에서 인증서를 생성합니다."
echo "계속하려면 Enter를 누르세요..."
read -r

# Match 초기화 실행
bundle exec fastlane match_init

echo ""
echo "✅ Match 초기화 완료!"
echo ""
echo "📋 다음 단계:"
echo "1. 생성된 프라이빗 저장소를 확인하세요"
echo "2. GitHub Secrets에 다음 값들을 추가하세요:"
echo "   - MATCH_GIT_URL: 프라이빗 저장소 URL"
echo "   - MATCH_GIT_AUTH: Git 인증 토큰 (base64 인코딩)"
echo "   - MATCH_PASSWORD: Match 암호화 비밀번호"
echo ""
echo "🔗 저장소 URL: $MATCH_GIT_URL"
