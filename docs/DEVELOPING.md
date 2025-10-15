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
* `Command + R`: Run the app in simulator

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

Run tests with `Command + U` in Xcode or use the build script.

## Continuous Integration

GitHub Actions automatically:
- Builds the project
- Runs tests
- Creates archives
- Checks code quality

See `.github/workflows/Caption-Mate.yml` for details.
