# Developing CaptionMate

> **참고**: 새로운 개발자를 위한 상세한 설정 가이드는 [SETUP.md](../SETUP.md)를 참고하세요.

## Prerequisites

* macOS 12.0 (Monterey) or newer
* Xcode 16.2 or newer
* Swift 6.0.3 or newer
* Homebrew
* Mint (Swift package manager)

## Setting up your development environment

### Quick Setup
```bash
git clone git@github.com:cho407/CaptionMate.git
cd CaptionMate
brew install mint
mint bootstrap
open CaptionMate/CaptionMate.xcodeproj
```

### Development Commands
* `Command + B`: Build the project
* `Command + U`: Run unit tests
* `Command + R`: Run the native macOS app

### Scripts
```bash
# Code formatting
./scripts/style.sh

# Build project
./scripts/build.sh CaptionMate macOS

# Check code quality
./scripts/check_copyright.sh
./scripts/check_whitespace.sh
```

## Code Style

Before submitting a pull request, make sure to check your code against the
style guide by running:

```bash
./scripts/style.sh
```

This will format your code according to the project's SwiftFormat configuration.

## Architecture

CaptionMate follows the MVVM (Model-View-ViewModel) pattern:

- **Models**: Data structures and business logic
- **Views**: SwiftUI user interface components
- **ViewModels**: Business logic and state management

## Key Technologies

- **SwiftUI**: Modern declarative UI framework
- **WhisperKit**: Apple's Whisper model for speech recognition
- **Combine**: Reactive programming framework
- **SwiftFormat**: Automated code formatting

## Testing

The project includes both unit tests and UI tests:

- **Unit Tests**: Business logic and data processing
- **UI Tests**: User interface interactions and workflows

Run tests with `Command + U` in Xcode. The shared `CaptionMate` scheme contains
unit tests; use the separate shared `CaptionMateUITests` scheme for UI tests.

For command-line verification, select the full Xcode developer directory rather
than Command Line Tools and write result bundles outside the repository:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
RESULT_ROOT=$(mktemp -d)
xcodebuild test -project CaptionMate/CaptionMate.xcodeproj \
  -scheme CaptionMate -destination "platform=macOS,arch=$(uname -m)" \
  -resultBundlePath "$RESULT_ROOT/UnitTests.xcresult" \
  CAPTIONMATE_TEST_BUNDLE_SUFFIX=.Testing \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
  CODE_SIGN_ENTITLEMENTS= DEVELOPMENT_TEAM=
python3 scripts/check_test_results.py "$RESULT_ROOT/UnitTests.xcresult"

xcrun swift scripts/check_ui_session.swift
xcodebuild test -project CaptionMate/CaptionMate.xcodeproj \
  -scheme CaptionMateUITests -destination "platform=macOS,arch=$(uname -m)" \
  -parallel-testing-enabled NO \
  -resultBundlePath "$RESULT_ROOT/UITests.xcresult" \
  CAPTIONMATE_TEST_BUNDLE_SUFFIX=.Testing \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
  CODE_SIGN_ENTITLEMENTS= DEVELOPMENT_TEAM=
python3 scripts/check_test_results.py "$RESULT_ROOT/UITests.xcresult"
```

`check_test_results.py` requires Python 3 and Xcode's `xcresulttool`. It rejects
failed, empty, and all-skipped runs; an `xcodebuild` exit code alone is not proof
that tests executed.

UI tests require an unlocked graphical session and macOS approval for **Enable UI
Automation**. Complete the system authentication prompt before the runner's
initialization timeout; this is separate from app code signing.
`CAPTIONMATE_TEST_BUNDLE_SUFFIX=.Testing` isolates the test app's container and
preferences from the normal app. UI fixtures reset only that test app's preferences.
Do not omit the suffix when running fixtures against a development checkout.
Do not reset system privacy permissions or disable signing to work around an
automation approval failure.
If automation initialization times out, inspect `DevToolsSecurity -status`.
Enabling developer-tool authorization is a persistent, administrator-approved
system change; obtain explicit approval rather than changing it from a test.

`check_ui_session.swift` fails before launching XCTest when the console is missing
or the screen is locked. A locked session can launch the app in the background
but cannot activate it; do not retry or change app code to hide that failure.

Resolve unrelated system permission dialogs outside the test run; tests must not
approve them. Kept UI evidence targets the app window, not the whole desktop.

Do not type or switch apps during a UI run; an unlocked session does not provide
exclusive focus. XCTest's automatic failure captures can still include other apps.
Keep xcresults local and review attachments before sharing; prefer explicit
app-window captures.
Check for deliberate user interruption before treating lost-connection or
authorization errors as app or permission defects. On a user stop request, cancel
the active run and defer GUI verification until they explicitly resume it.

Debug UI fixtures place the main window on the primary display so mixed-scale
monitors do not skew XCTest input coordinates or app-window captures. After a
menu action, activate the test app and confirm it is foreground before sending
keyboard shortcuts. XCTest maps command characters through the current input
method; the test-only `typeCommandKey` helper selects an available ASCII input
source and restores the original in `defer`. Keep native undo routing unchanged.
The speaker fixture writes a local silent WAV, allowing the playback UI test to
exercise first seek, pause, and resume with a real player.

The readiness fixture changes only the nested model-state object after the first
render. Its UI regression verifies that Start and speaker controls become usable
without an unrelated view-model publication. This controlled fixture is not an
ASR or diarization accuracy test; use real cached models for runtime smoke checks.

## Editing and Export Contracts

- Recovery sidecars use schema version 2 and preserve optional word timings.
  Version 1 remains readable; missing legacy alignments are not reconstructed.
  Project save/load, recovery, and structural Undo must preserve existing words,
  timestamps, speaker assignments, and speaker names.
- Speaker labels and caption layout are export-only transformations. SRT, VTT,
  and FCPXML must apply them to word-timed output as well as segment output,
  without modifying the editor or recovery sidecar. JSON word alignments stay
  canonical; caption layout does not apply to JSON, text, or document output.
- Export opens the format/options review from both completed and editing modes.
  Caption presets apply only to subtitle formats; frame rate applies only to
  FCPXML. Missing speaker attribution needs manual review or acoustic analysis:
  Quick Fix must not infer identity from adjacent captions.
- Export must not collapse co-starting captions to zero duration. Preserve their
  positive spans and keep overlap review warnings. FCPXML sequences must cover
  the furthest retained cue end, not just the final start-sorted cue.
- Playback uses the original imported audio. Verify seek-before-play, segment
  end boundaries, pause/resume, and playback rate. Exercise split/delete/merge
  Undo and Redo through the window's native undo manager, including Command-Z.
- Cancellation requests do not release a task's slot until its worker exits.
  Keep model selection, unloading, deletion, and compute changes blocked while
  relevant work is active. SpeakerKit does not promise immediate interruption;
  use indeterminate analysis/cancellation UI rather than a guessed percentage.
- Model loading, Core ML specialization, and unloading expose stages rather than
  measured fractions. Show indeterminate activity only during those stages;
  loaded/unloaded states must not retain a loading bar. Do not synthesize load
  percentages from timers. Download percentages remain measured values.
- `ModelManagementState` is a separate observable reference. Views deriving
  readiness, language choices, or enablement from it must observe it directly,
  not only `ContentViewModel`. Other UI/audio/transcription states are published
  value types; playback time is isolated in `AudioPlaybackState`.
- An unavailable speaker model blocks enabling diarization, not disabling an
  already-enabled option restored from a project. Opting out must remain possible
  so a loaded transcription model can be used alone; preserve edited attribution.
- Decode and compute tuning belong in collapsed advanced sections. Worker
  counts are bounded to 1–8 and token limits to 1–the SDK context limit; small
  token limits can truncate output. Hiding timestamps changes presentation,
  not inference. Translation targets English.
- Keep WhisperKit/SpeakerKit on the pinned Argmax API until replacement engines
  prove model-format, word-timing, cancellation, licensing, and native-runtime
  compatibility. VAD chunk failures must propagate instead of returning a
  silently shortened success.
- Decoder previews must not stop unfinished windows on provisional log probability
  or rolling token compression. Let WhisperKit apply its completed-window quality
  thresholds and temperature fallback; cancellation remains task-based.
- Repeated speech can trigger compression/no-speech decisions in the SDK itself.
  Use it for lifecycle stress, not as an accuracy baseline, and do not disable
  quality thresholds merely to pass that fixture. Nonrepeating speech smoke
  runs are still not Korean ASR or multi-speaker accuracy benchmarks.

## Continuous Integration

GitHub Actions:
- Builds the app and runs unit tests.
- Runs the shared UI-test scheme as a required step.
- Rejects zero-test, all-skipped, and failed result bundles.
- Preserves `xcodebuild` failures through log pipelines with `pipefail`.

Hosted unit and UI tests use ad-hoc signing without developer credentials. Those
commands omit the certificate-only increased-memory-limit entitlement; generated
app sandbox, outgoing-network, and user-selected-file permissions remain enabled.
The normal app identifier and developer/distribution signing defaults are unchanged.
Release archive/export and distribution signing must be verified separately.

See `.github/workflows/Caption-Mate.yml` for details.

## Runtime and Release Verification

- Verify completion → editing → apply through the UI, including reading the
  completed transcript. Native text already exposes its content to accessibility;
  redundant label overrides must not create a recursive accessibility tree.
- Keep Compute Units captions single-line with full-label tooltips. Localized
  wrapping can enlarge the split-view layout beyond the window and hide import
  controls. Exercise import-picker opening/cancellation across the UI configuration
  matrix using native [XCUIElement](https://developer.apple.com/documentation/xcuiautomation/xcuielement)
  actions; a window-exists assertion alone does not prove those controls work.
- Project persistence must accept directory URLs with or without a directory hint.
  ID/path traversal validation and existing project JSON limits still apply.
- Use real local speech/model execution for memory and cancellation measurements,
  not source-string assertions about `Task`, captures, or SDK calls.
- Argmax 1.1.1 incremental loading rejects non-empty `clipTimestamps`, including
  the app's file-relative seek options. Keep the array path until seek/resume
  compatibility and the memory/throughput tradeoff justify a cutover. Do not
  silently discard seek options to make incremental loading succeed.

Build the production archive without the test-app suffix or CI signing overrides:

```bash
xcodebuild archive -project CaptionMate/CaptionMate.xcodeproj \
  -scheme CaptionMate -configuration Release -destination 'generic/platform=macOS' \
  -archivePath "$RESULT_ROOT/CaptionMate.xcarchive" \
  CAPTIONMATE_TEST_BUNDLE_SUFFIX=
codesign --verify --deep --strict \
  "$RESULT_ROOT/CaptionMate.xcarchive/Products/Applications/CaptionMate.app"
```

Check the built app's identifier, version, architectures, and signed entitlements.
An archive signed for development is not a distribution or notarization result.
App Store export requires the matching distribution certificate/private key and
provisioning profile. Developer ID export and notarization have their own signing
and keychain-credential requirements. Never disable sandbox/hardened runtime or
strip production entitlements to bypass a distribution failure. Upload an archive
or submit it for notarization only with explicit authorization.
