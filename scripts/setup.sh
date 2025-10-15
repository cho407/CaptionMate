#!/bin/bash

# Copyright 2025 Harrison Cho
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# CaptionMate 프로젝트 자동 설정 스크립트
# 사용법: ./scripts/setup.sh

set -e

echo "🚀 CaptionMate 개발 환경 자동 설정을 시작합니다..."

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 함수 정의
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 시스템 요구사항 확인
check_system_requirements() {
    print_status "시스템 요구사항을 확인합니다..."
    
    # macOS 버전 확인
    if [[ "$OSTYPE" != "darwin"* ]]; then
        print_error "이 프로젝트는 macOS에서만 실행됩니다."
        exit 1
    fi
    
    macos_version=$(sw_vers -productVersion)
    print_success "macOS 버전: $macos_version"
    
    # Xcode 확인
    if ! command -v xcodebuild &> /dev/null; then
        print_error "Xcode가 설치되어 있지 않습니다. App Store에서 Xcode를 설치해주세요."
        exit 1
    fi
    
    xcode_version=$(xcodebuild -version | head -n 1)
    print_success "Xcode 버전: $xcode_version"
    
    # Swift 버전 확인
    if ! command -v swift &> /dev/null; then
        print_error "Swift가 설치되어 있지 않습니다."
        exit 1
    fi
    
    swift_version=$(swift --version | head -n 1)
    print_success "Swift 버전: $swift_version"
}

# Homebrew 확인 및 설치
check_homebrew() {
    print_status "Homebrew 설치 확인 중..."
    if ! command -v brew &> /dev/null; then
        print_warning "Homebrew가 설치되어 있지 않습니다."
        print_status "Homebrew를 설치합니다..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        
        # PATH 업데이트 (Apple Silicon Mac의 경우)
        if [[ $(uname -m) == "arm64" ]]; then
            echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
            eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
        
        print_success "Homebrew가 설치되었습니다."
    else
        print_success "Homebrew가 이미 설치되어 있습니다."
        brew_version=$(brew --version | head -n 1)
        print_status "Homebrew 버전: $brew_version"
    fi
}

# Mint 설치
install_mint() {
    print_status "Mint 설치 확인 중..."
    if ! command -v mint &> /dev/null; then
        print_status "Mint 설치 중..."
        brew install mint
        print_success "Mint가 설치되었습니다."
    else
        print_success "Mint가 이미 설치되어 있습니다."
        mint_version=$(mint version 2>/dev/null || echo "version unknown")
        print_status "Mint 버전: $mint_version"
    fi
}

# 프로젝트 의존성 설치
bootstrap_mint() {
    print_status "프로젝트 의존성을 설치합니다..."
    if [[ -f "Mintfile" ]]; then
        mint bootstrap
        print_success "Mint 의존성이 설치되었습니다."
    else
        print_error "Mintfile을 찾을 수 없습니다. 프로젝트 루트에서 실행해주세요."
        exit 1
    fi
}

# 스크립트 권한 설정
set_script_permissions() {
    print_status "스크립트 실행 권한을 설정합니다..."
    if [[ -d "scripts" ]]; then
        chmod +x scripts/*.sh
        print_success "스크립트 실행 권한이 설정되었습니다."
    else
        print_warning "scripts 디렉토리를 찾을 수 없습니다."
    fi
}

# SwiftFormat 테스트
test_swiftformat() {
    print_status "SwiftFormat 동작을 테스트합니다..."
    if mint run swiftformat --version &> /dev/null; then
        print_success "SwiftFormat이 정상적으로 작동합니다."
    else
        print_error "SwiftFormat 테스트에 실패했습니다."
        exit 1
    fi
}

# Xcode 프로젝트 확인
check_xcode_project() {
    print_status "Xcode 프로젝트를 확인합니다..."
    if [[ -f "CaptionMate/CaptionMate.xcodeproj/project.pbxproj" ]]; then
        print_success "Xcode 프로젝트가 발견되었습니다."
    else
        print_error "Xcode 프로젝트를 찾을 수 없습니다. 프로젝트 구조를 확인해주세요."
        exit 1
    fi
}

# 빌드 테스트
test_build() {
    print_status "프로젝트 빌드를 테스트합니다..."
    if [[ -f "scripts/build.sh" ]]; then
        print_status "빌드 스크립트를 실행합니다..."
        if scripts/build.sh CaptionMate macOS &> /dev/null; then
            print_success "빌드 테스트가 성공했습니다."
        else
            print_warning "빌드 테스트에 실패했습니다. Xcode에서 수동으로 빌드를 확인해주세요."
        fi
    else
        print_warning "빌드 스크립트를 찾을 수 없습니다."
    fi
}

# 메인 실행 함수
main() {
    echo "=========================================="
    echo "CaptionMate 개발 환경 자동 설정"
    echo "=========================================="
    echo ""

    check_system_requirements
    check_homebrew
    install_mint
    bootstrap_mint
    set_script_permissions
    check_xcode_project
    test_swiftformat
    test_build

    echo ""
    echo "=========================================="
    print_success "🎉 개발 환경 설정이 완료되었습니다!"
    echo "=========================================="
    echo ""
    echo "🎯 개발 준비 완료!"
    echo ""
    echo "Xcode에서 프로젝트를 열려면:"
    echo "  open CaptionMate/CaptionMate.xcodeproj"
    echo ""
    echo "빠른 시작:"
    echo "  Command + B: 빌드"
    echo "  Command + U: 테스트 실행"
    echo "  Command + R: 앱 실행"
    echo ""
    echo "📝 개발 도구:"
    echo "  • scripts/style.sh          - Swift 코드 포맷팅"
    echo "  • scripts/build.sh          - 프로젝트 빌드"
    echo "  • scripts/check_copyright.sh - 저작권 확인"
    echo "  • scripts/check_whitespace.sh - Whitespace 확인"
    echo ""
    echo "자세한 정보는 SETUP.md를 참고하세요."
    echo ""
}

# 스크립트 실행
main "$@"
