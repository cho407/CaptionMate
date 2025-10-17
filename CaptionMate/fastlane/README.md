fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## Mac

### mac develop_deploy

```sh
[bundle exec] fastlane mac develop_deploy
```

Develop 브랜치: 빌드 + 테스트 + TestFlight 배포

### mac main_archive

```sh
[bundle exec] fastlane mac main_archive
```

Main 브랜치: 빌드 + 테스트 + 아카이브만

### mac build_only

```sh
[bundle exec] fastlane mac build_only
```

빌드만 실행 (테스트 제외)

### mac test_only

```sh
[bundle exec] fastlane mac test_only
```

테스트만 실행

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
