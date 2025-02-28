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

# USAGE: build.sh product [platform] [method] [workspace]
#
# Builds the given product for the given platform using the given build method

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 product [platform] [method] [workspace]"
  exit 1
fi

product="$1"
platform="${2:-iOS}"
method="${3:-xcodebuild}"
workspace="${4:-.}"

echo "Building $product for $platform using $method"

scripts_dir=$(dirname "${BASH_SOURCE[0]}")

system=$(uname -s)
case "$system" in
  Darwin)
    xcode_version=$(xcodebuild -version | head -n 1)
    xcode_version="${xcode_version/Xcode /}"
    xcode_major="${xcode_version/.*/}"
    ;;
  *)
    xcode_major="0"
    ;;
esac

# Source secrets-check script, if any.
source "${scripts_dir}/check_secrets.sh"

# Function: Run xcodebuild with output piped to xcpretty.
function RunXcodebuild() {
  echo "Running: xcodebuild $@"
  xcpretty_cmd=(xcpretty)
  result=0
  xcodebuild "$@" | tee xcodebuild.log | "${xcpretty_cmd[@]}" || result=$?
  if [[ $result == 65 ]]; then
    ExportLogs "$@"
    echo "xcodebuild exited with 65, retrying" 1>&2
    sleep 5
    result=0
    xcodebuild "$@" | tee xcodebuild.log | "${xcpretty_cmd[@]}" || result=$?
  fi
  if [[ $result != 0 ]]; then
    echo "xcodebuild exited with $result" 1>&2
    ExportLogs "$@"
    exit $result
  fi
}

# Function: Export logs from the xcresult bundle.
function ExportLogs() {
  python3 "${scripts_dir}/xcresult_logs.py" "$@"
}

# SDK flags per platform.
ios_flags=(-sdk 'iphonesimulator')
ios_device_flags=(-sdk 'iphoneos')
ipad_flags=(-sdk 'iphonesimulator')
# macOS SDK는 정확한 이름으로 지정.
macos_flags=(-sdk 'macosx15.2')
tvos_flags=(-sdk "appletvsimulator")
watchos_flags=()
visionos_flags=()
catalyst_flags=(
  ARCHS=x86_64
  VALID_ARCHS=x86_64
  SUPPORTS_MACCATALYST=YES
  -sdk 'macosx15.2'
  CODE_SIGN_IDENTITY=-
  CODE_SIGNING_REQUIRED=NO
  CODE_SIGNING_ALLOWED=NO
)

destination=""
xcb_flags=()

# Compute SDK and destination based on platform.
case "$platform" in
  iOS)
    xcb_flags=("${ios_flags[@]}")
    destination="platform=iOS Simulator,name=iPhone 15"
    ;;
  iOS-device)
    xcb_flags=("${ios_device_flags[@]}")
    destination="generic/platform=iOS"
    ;;
  iPad)
    xcb_flags=("${ipad_flags[@]}")
    destination="platform=iOS Simulator,name=iPad Pro (9.7-inch)"
    ;;
  macOS)
    xcb_flags=("${macos_flags[@]}")
    # destination에 arm64만 지정하여, Apple Silicon 환경에서 오직 arm64로 빌드.
    destination="platform=macOS,arch=arm64"
    ;;
  tvOS)
    xcb_flags=("${tvos_flags[@]}")
    destination="platform=tvOS Simulator,name=Apple TV"
    ;;
  watchOS)
    xcb_flags=("${watchos_flags[@]}")
    destination="platform=watchOS Simulator,name=Apple Watch Series 7 (45mm)"
    ;;
  visionOS)
    xcb_flags=("${visionos_flags[@]}")
    destination="platform=visionOS Simulator"
    ;;
  catalyst)
    xcb_flags=("${catalyst_flags[@]}")
    destination='platform="macOS,variant=Mac Catalyst,name=Any Mac"'
    ;;
  all|Linux)
    xcb_flags=()
    ;;
  *)
    echo "Unknown platform: $platform" 1>&2
    exit 1
    ;;
esac

# Append common flags.
if [[ "$platform" == "macOS" ]]; then
  # Archive 빌드 시에는 ONLY_ACTIVE_ARCH 제거하고 arm64만 명시.
  if [[ "$method" == "archive" ]]; then
    xcb_flags+=(ARCHS=arm64 VALID_ARCHS=arm64 CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES COMPILER_INDEX_STORE_ENABLE=NO)
  else
    # 일반 빌드 시에도 arm64만 사용.
    xcb_flags+=(ONLY_ACTIVE_ARCH=YES ARCHS=arm64 VALID_ARCHS=arm64 CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES COMPILER_INDEX_STORE_ENABLE=NO)
  fi
else
  xcb_flags+=(ONLY_ACTIVE_ARCH=YES CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES COMPILER_INDEX_STORE_ENABLE=NO)
fi

fail_on_warnings=SWIFT_TREAT_WARNINGS_AS_ERRORS=YES

# Build command: if workspace ends with .xcodeproj, use -project; otherwise, use -workspace.
if [[ $workspace == *.xcodeproj ]]; then
  # macOS Archive 빌드: destination 옵션은 그대로 전달.
  RunXcodebuild -project "$workspace" -scheme "$product" -destination "$destination" "${xcb_flags[@]}" $fail_on_warnings $method
else
  RunXcodebuild -workspace "$workspace" -scheme "$product" -destination "$destination" "${xcb_flags[@]}" $fail_on_warnings $method
fi
