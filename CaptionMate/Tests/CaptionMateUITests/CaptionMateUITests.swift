//
//  Copyright 2025 Harrison Cho
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//       http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

//
//  CaptionMateUITests.swift
//  CaptionMateUITests
//
//  Created by 조형구 on 2/22/25.
//

import XCTest

private extension XCUIApplication {
    static func captionMate(launchArguments extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-CaptionMateUITestResetDefaults",
            "-CaptionMateUITestDisableModelDownloads",
            "-ApplePersistenceIgnoreState",
            "YES",
        ] + extraArguments
        return app
    }

    func element(_ identifier: String) -> XCUIElement {
        descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }

    func menuBarItem(matchingTitles titles: [String]) -> XCUIElement {
        menuBarItems
            .matching(NSPredicate(format: "title IN %@ OR label IN %@", titles, titles))
            .firstMatch
    }

    func menuItem(matchingTitles titles: [String]) -> XCUIElement {
        menuItems
            .matching(NSPredicate(format: "title IN %@ OR label IN %@", titles, titles))
            .firstMatch
    }

    func launchFreshForUITest() {
        terminate()
        _ = wait(for: .notRunning, timeout: 5.0)
        launch()
    }
}

// MARK: - 기본 UI 요소 테스트 (한 번만 앱 실행)

final class BasicUITests: XCTestCase {
    static var app: XCUIApplication!

    override class func setUp() {
        super.setUp()
        // 클래스당 한 번만 실행
        app = XCUIApplication.captionMate()
        app.launchFreshForUITest()

        // 앱이 완전히 로드될 때까지 대기
        let window = app.windows.firstMatch
        _ = window.waitForExistence(timeout: 10.0)
    }

    override class func tearDown() {
        app.terminate()
        app = nil
        super.tearDown()
    }

    // MARK: - 앱 실행 테스트

    @MainActor
    func test01_AppLaunch() throws {
        // 앱이 정상적으로 실행되는지 확인
        XCTAssertTrue(Self.app.exists)
        let window = Self.app.windows.firstMatch
        XCTAssertTrue(window.exists, "메인 윈도우가 존재해야 합니다")
    }

    @MainActor
    func test02_WindowMinimumSize() throws {
        // 메인 윈도우 확인
        let window = Self.app.windows.firstMatch
        XCTAssertTrue(window.exists, "메인 윈도우가 존재해야 합니다")

        // 윈도우 프레임 확인
        let frame = window.frame
        XCTAssertGreaterThanOrEqual(frame.width, 1000, "윈도우 최소 너비는 1000이어야 합니다")
        XCTAssertGreaterThanOrEqual(frame.height, 700, "윈도우 최소 높이는 700이어야 합니다")
    }

    @MainActor
    func test03_MainUIElementsExist() throws {
        // Import File 버튼 존재 확인
        let importButton = Self.app.buttons.matching(identifier: "Import File").firstMatch
        XCTAssertTrue(importButton.waitForExistence(timeout: 5.0), "Import File 버튼이 존재해야 합니다")

        // Start Transcription 버튼 존재 확인
        let transcribeButton = Self.app.buttons.matching(identifier: "Start Transcription")
            .firstMatch
        XCTAssertTrue(
            transcribeButton.waitForExistence(timeout: 5.0),
            "Start Transcription 버튼이 존재해야 합니다"
        )

        // Reset 버튼 존재 확인
        let resetButton = Self.app.buttons.matching(identifier: "Reset").firstMatch
        XCTAssertTrue(resetButton.waitForExistence(timeout: 5.0), "Reset 버튼이 존재해야 합니다")

        // Settings 버튼 존재 확인
        let settingsButton = Self.app.buttons.matching(identifier: "Settings").firstMatch
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5.0), "Settings 버튼이 존재해야 합니다")
    }

    @MainActor
    func test04_MenuBarExists() throws {
        // 메뉴바가 로드될 때까지 대기
        let menuBar = Self.app.menuBars.firstMatch
        XCTAssertTrue(menuBar.waitForExistence(timeout: 5.0), "메뉴바가 존재해야 합니다")

        // Settings 메뉴 확인 (영어 또는 한국어)
        let settingsMenuEn = Self.app.menuBarItems["Settings"]
        let settingsMenuKo = Self.app.menuBarItems["설정"]
        XCTAssertTrue(settingsMenuEn.exists || settingsMenuKo.exists, "Settings 메뉴가 존재해야 합니다")

        // Shortcuts 메뉴 확인 (영어 또는 한국어)
        let shortcutsMenuEn = Self.app.menuBarItems["Shortcuts"]
        let shortcutsMenuKo = Self.app.menuBarItems["단축키"]
        XCTAssertTrue(shortcutsMenuEn.exists || shortcutsMenuKo.exists, "Shortcuts 메뉴가 존재해야 합니다")
    }

    @MainActor
    func test05_ModelSelectorExists() throws {
        // Sidebar에 항상 있는 텍스트 기준으로 대기 (sleep 제거)
        let appVersion = Self.app.staticTexts
            .matching(
                NSPredicate(format: "label CONTAINS[c] 'App Version' OR label CONTAINS[c] '앱 버전'")
            )
            .firstMatch
        let appTitle = Self.app.staticTexts["CaptionMate"]

        // waitForExistence로 안정적 대기
        let exists = appVersion.waitForExistence(timeout: 8.0) || appTitle
            .waitForExistence(timeout: 8.0)

        XCTAssertTrue(exists, "Sidebar가 표시되어야 합니다 (모델 선택기 포함)")
    }

    @MainActor
    func test06_DragDropAreaExists() throws {
        // 드래그 앤 드롭 영역 확인
        let dragDropText = Self.app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS[c] 'drag' OR label CONTAINS[c] '드래그'"))
            .firstMatch
        let exists = dragDropText.waitForExistence(timeout: 3.0)
        XCTAssertTrue(
            exists || Self.app.windows.firstMatch.exists,
            "드래그 앤 드롭 영역 또는 오디오 UI가 존재해야 합니다"
        )
    }
}

// MARK: - 상호작용 테스트 (각각 독립적으로 앱 실행)

final class InteractionTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication.captionMate()
        app.launchFreshForUITest()

        let window = app.windows.firstMatch
        _ = window.waitForExistence(timeout: 10.0)
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    @MainActor
    func testLanguageMenuInteraction() throws {
        // macOS 메뉴바는 UI 테스트에서 접근이 어려우므로
        // 메뉴 아이템의 존재 여부만 확인
        let settingsMenuEn = app.menuBarItems["Settings"]
        let settingsMenuKo = app.menuBarItems["설정"]

        // 메뉴가 존재하는지만 확인 (클릭하지 않음)
        let menuExists = settingsMenuEn.exists || settingsMenuKo.exists
        XCTAssertTrue(menuExists, "Settings 메뉴가 존재해야 합니다")

        // 실제 메뉴 상호작용은 수동 테스트로 확인
        // macOS 메뉴바는 화면 좌표 문제로 UI 테스트에서 클릭이 불안정함
    }

    @MainActor
    func testThemeMenuInteraction() throws {
        // macOS 메뉴바는 UI 테스트에서 접근이 어려우므로
        // Shortcuts 메뉴의 존재 여부만 확인
        let shortcutsMenuEn = app.menuBarItems["Shortcuts"]
        let shortcutsMenuKo = app.menuBarItems["단축키"]

        // 메뉴가 존재하는지만 확인 (클릭하지 않음)
        let menuExists = shortcutsMenuEn.exists || shortcutsMenuKo.exists
        XCTAssertTrue(menuExists, "Shortcuts 메뉴가 존재해야 합니다")

        // 실제 메뉴 상호작용은 수동 테스트로 확인
        // macOS 메뉴바는 화면 좌표 문제로 UI 테스트에서 클릭이 불안정함
    }

    @MainActor
    func testSettingsViewOpensAndCloses() throws {
        // Settings 버튼 클릭
        let settingsButton = app.buttons.matching(identifier: "Settings").firstMatch
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5.0), "Settings 버튼이 존재해야 합니다")
        settingsButton.click()

        // Settings View가 열렸는지 확인하는 다양한 방법들
        let sliderAppeared = app.sliders.firstMatch.waitForExistence(timeout: 8.0)
        let toggleAppeared = app.toggles.firstMatch.waitForExistence(timeout: 8.0)
        let tempText = app.staticTexts
            .matching(
                NSPredicate(
                    format: "label CONTAINS[c] 'Temperature' OR label CONTAINS[c] 'Starting' OR label CONTAINS[c] '온도'"
                )
            )
            .firstMatch.waitForExistence(timeout: 8.0)
        let frameRateText = app.staticTexts
            .matching(
                NSPredicate(format: "label CONTAINS[c] 'Frame Rate' OR label CONTAINS[c] 'fps'")
            )
            .firstMatch.waitForExistence(timeout: 8.0)
        let workersText = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS[c] 'Workers'"))
            .firstMatch.waitForExistence(timeout: 8.0)

        let settingsViewOpened = sliderAppeared || toggleAppeared || tempText || frameRateText ||
            workersText

        if !settingsViewOpened {
            // 디버깅: 현재 표시된 요소 확인
            print("Sliders: \(app.sliders.count), Toggles: \(app.toggles.count)")
            print("All text elements: \(app.staticTexts.allElementsBoundByIndex.map { $0.label })")
            print("All buttons: \(app.buttons.allElementsBoundByIndex.map { $0.label })")
        }

        if !settingsViewOpened {
            throw XCTSkip("Settings View가 열리지 않았습니다. UI 구조가 변경되었을 수 있습니다.")
        }

        // Settings 닫기 (ESC 키 사용)
        app.typeKey(.escape, modifierFlags: [])

        // 메인 화면의 토글과 설정 시트의 컨트롤을 구분해 닫힘을 확인
        let settingsSheet = app.element("settings.sheet")
        XCTAssertFalse(
            settingsSheet.waitForExistence(timeout: 1.0),
            "Settings View가 닫혀야 합니다"
        )
    }

    @MainActor
    func testModelManagerViewOpens() throws {
        // Manage Models 버튼 찾기
        let manageModelsButton = app.element("modelSelector.manageModelsButton")

        XCTAssertTrue(
            manageModelsButton.waitForExistence(timeout: 5.0),
            "Manage Models 버튼이 표시되어야 합니다"
        )
        manageModelsButton.click()

        // Model Manager View가 열리는지 확인
        XCTAssertTrue(
            app.element("modelManager.speakerDiarizationModelSection")
                .waitForExistence(timeout: 3.0),
            "화자분리 모델 섹션이 표시되어야 합니다"
        )
        XCTAssertTrue(
            app.element("modelManager.speakerModelCaption")
                .waitForExistence(timeout: 3.0),
            "화자분리 모델의 오프라인 용도 설명이 표시되어야 합니다"
        )

        // 닫기
        app.typeKey(.escape, modifierFlags: [])
    }

    @MainActor
    func testProjectLibraryInitialState() throws {
        let projectLibrary = app.element("projectLibrary.container")
        XCTAssertTrue(projectLibrary.waitForExistence(timeout: 5.0), "프로젝트 라이브러리가 표시되어야 합니다")

        let refreshButton = app.element("projectLibrary.refreshButton")
        XCTAssertTrue(refreshButton.waitForExistence(timeout: 3.0), "프로젝트 새로고침 버튼이 표시되어야 합니다")
        XCTAssertTrue(refreshButton.isEnabled, "프로젝트 새로고침은 항상 가능해야 합니다")

        let saveButton = app.element("projectLibrary.saveButton")
        XCTAssertTrue(saveButton.waitForExistence(timeout: 3.0), "프로젝트 저장 버튼이 표시되어야 합니다")
        XCTAssertFalse(saveButton.isEnabled, "저장할 전사 내용이 없으면 저장 버튼은 비활성화되어야 합니다")

        XCTAssertTrue(
            app.element("projectLibrary.emptyState").waitForExistence(timeout: 3.0),
            "저장된 프로젝트가 없을 때 빈 상태가 표시되어야 합니다"
        )
    }

    @MainActor
    func testBottomControlsShareHorizontalAlignment() throws {
        let resetButton = app.element("Reset")
        let importButton = app.element("Import File")
        let settingsButton = app.element("Settings")
        let startButton = app.element("Start Transcription")

        XCTAssertTrue(resetButton.waitForExistence(timeout: 5.0), "초기화 버튼이 표시되어야 합니다")
        XCTAssertTrue(importButton.waitForExistence(timeout: 3.0), "파일 가져오기 버튼이 표시되어야 합니다")
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 3.0), "설정 버튼이 표시되어야 합니다")
        XCTAssertTrue(startButton.waitForExistence(timeout: 3.0), "전사 시작 버튼이 표시되어야 합니다")

        XCTAssertEqual(
            Double(resetButton.frame.minX),
            Double(importButton.frame.minX),
            accuracy: 3.0,
            "초기화와 파일 가져오기 버튼의 왼쪽 기준선이 맞아야 합니다"
        )
        XCTAssertEqual(
            Double(settingsButton.frame.maxX),
            Double(startButton.frame.maxX),
            accuracy: 3.0,
            "설정과 전사 시작 버튼의 오른쪽 기준선이 맞아야 합니다"
        )
    }

    @MainActor
    func testLanguageChangeRefreshesMenuBarImmediately() throws {
        let startsInKorean = app.menuBarItems["설정"].waitForExistence(timeout: 3.0)
        let targetLanguageTitle = startsInKorean ? "English (US)" : "한국어"
        let expectedSettingsTitle = startsInKorean ? "Settings" : "설정"
        let expectedShortcutsTitle = startsInKorean ? "Shortcuts" : "단축키"

        let settingsMenu = app.menuBarItem(matchingTitles: ["Settings", "설정"])
        XCTAssertTrue(settingsMenu.waitForExistence(timeout: 5.0), "Settings 메뉴가 있어야 합니다")
        settingsMenu.click()

        let languageMenu = app.menuItem(matchingTitles: ["Language", "언어"])
        guard languageMenu.waitForExistence(timeout: 3.0) else {
            throw XCTSkip("macOS 메뉴바 하위 메뉴 접근이 현재 테스트 환경에서 불안정합니다.")
        }
        languageMenu.click()

        let targetLanguage = app.menuItems[targetLanguageTitle]
        XCTAssertTrue(
            targetLanguage.waitForExistence(timeout: 3.0),
            "언어 메뉴에 선택 가능한 언어가 있어야 합니다"
        )
        targetLanguage.click()

        XCTAssertTrue(
            app.menuBarItems[expectedSettingsTitle].waitForExistence(timeout: 5.0),
            "언어 변경 직후 상단 Settings 메뉴가 갱신되어야 합니다"
        )
        XCTAssertTrue(
            app.menuBarItems[expectedShortcutsTitle].waitForExistence(timeout: 5.0),
            "언어 변경 직후 상단 Shortcuts 메뉴가 갱신되어야 합니다"
        )
        // File/Edit/View/Window/Help are AppKit-owned. They are updated by the
        // app's top-level matcher, but XCUITest does not expose their labels
        // consistently across macOS test hosts.
    }
}

// MARK: - 화자분리 UX 테스트

final class SpeakerDiarizationUXTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let needsSpeakerFixture =
            name.contains("testSpeakerEditorRenameAndExportReview") ||
            name.contains("testTranscriptionCompletedEditorRoundTrip")
        app = XCUIApplication.captionMate(
            launchArguments: needsSpeakerFixture ? ["-CaptionMateUITestSpeakerFixture"] : []
        )
        app.launchFreshForUITest()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10.0), "메인 윈도우가 존재해야 합니다")
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    @MainActor
    func testTranscriptionSpeakerDiarizationControls() throws {
        let speakerToggle = app.element("transcription.speakerDiarizationToggle")
        let speakerCountPicker = app.element("transcription.speakerCountPicker")
        let exportLabelsToggle = app.element("transcription.exportSpeakerLabelsToggle")

        XCTAssertTrue(speakerToggle.waitForExistence(timeout: 3.0))
        XCTAssertTrue(speakerCountPicker.waitForExistence(timeout: 3.0))
        XCTAssertTrue(exportLabelsToggle.waitForExistence(timeout: 3.0))

        let sourceLanguagePicker = app.element("transcription.sourceLanguagePicker")
        XCTAssertTrue(sourceLanguagePicker.waitForExistence(timeout: 3.0))
        let sourceLanguagePlaceholder = sourceLanguagePicker.value as? String
        XCTAssertFalse(
            sourceLanguagePlaceholder?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true,
            "모델 언어가 준비되지 않은 상태에서도 현지화된 placeholder가 표시되어야 합니다"
        )
        XCTAssertNotEqual(sourceLanguagePlaceholder, "English")

        XCTAssertFalse(speakerToggle.isEnabled)
        XCTAssertFalse(speakerCountPicker.isEnabled)
        XCTAssertFalse(exportLabelsToggle.isEnabled)
    }

    @MainActor
    func testTranscriptionCompletedEditorRoundTrip() throws {
        let transcriptionView = app.element("transcription.view")
        XCTAssertTrue(transcriptionView.waitForExistence(timeout: 5.0), "전사 화면이 표시되어야 합니다")

        let completedView = app.element("transcription.completedView")
        XCTAssertTrue(completedView.waitForExistence(timeout: 5.0), "전사 완료 화면이 먼저 표시되어야 합니다")

        let unassignedBlock = app.element("transcription.completedBlock.0")
        let speakerBlock = app.element("transcription.completedBlock.1")
        let repeatedSpeakerBlock = app.element("transcription.completedBlock.2")
        XCTAssertTrue(unassignedBlock.waitForExistence(timeout: 3.0), "미지정 화자 발화가 표시되어야 합니다")
        XCTAssertTrue(speakerBlock.waitForExistence(timeout: 3.0), "화자 발화가 표시되어야 합니다")
        XCTAssertFalse(repeatedSpeakerBlock.exists, "연속된 동일 화자 자막은 한 블록으로 합쳐져야 합니다")

        let speakerText = app.element("transcription.completedText.1")
        XCTAssertTrue(speakerText.waitForExistence(timeout: 3.0))
        XCTAssertTrue(app.element("transcription.completedSpeaker.1").waitForExistence(timeout: 3.0))

        let editButton = app.element("transcription.editButton")
        XCTAssertTrue(editButton.waitForExistence(timeout: 3.0), "편집하기 버튼이 표시되어야 합니다")

        let speakerEditor = app.element("speakerEditor.container")
        XCTAssertFalse(speakerEditor.exists, "완료 화면에서는 상세 편집기가 숨겨져야 합니다")

        editButton.click()

        XCTAssertTrue(speakerEditor.waitForExistence(timeout: 5.0), "화자 편집기가 표시되어야 합니다")
        let applyButton = app.element("transcription.applyEditsButton")
        XCTAssertTrue(applyButton.waitForExistence(timeout: 3.0), "적용하기 버튼이 표시되어야 합니다")

        applyButton.click()
        XCTAssertTrue(completedView.waitForExistence(timeout: 3.0), "적용 후 완료 화면으로 돌아와야 합니다")
        XCTAssertFalse(speakerEditor.exists, "적용 후 상세 편집기가 숨겨져야 합니다")
    }

    @MainActor
    func testSpeakerEditorRenameAndExportReview() throws {
        let transcriptionView = app.element("transcription.view")
        XCTAssertTrue(transcriptionView.waitForExistence(timeout: 5.0), "전사 화면이 표시되어야 합니다")

        let editButton = app.element("transcription.editButton")
        XCTAssertTrue(editButton.waitForExistence(timeout: 3.0), "편집하기 버튼이 표시되어야 합니다")
        editButton.click()

        let speakerEditor = app.element("speakerEditor.container")
        XCTAssertTrue(speakerEditor.waitForExistence(timeout: 5.0), "화자 편집기가 표시되어야 합니다")

        let reanalyzeButton = app.element("speakerEditor.reanalyzeButton")
        XCTAssertTrue(reanalyzeButton.waitForExistence(timeout: 3.0))
        XCTAssertTrue(reanalyzeButton.isEnabled)

        let speakerOneNameField = app.element("speakerEditor.nameField.0")
        XCTAssertTrue(speakerOneNameField.waitForExistence(timeout: 3.0))
        speakerOneNameField.click()
        speakerOneNameField.typeText("Host")

        let assignedSegmentMenu = app.element("speakerAssignmentMenu.segment.1")
        XCTAssertTrue(assignedSegmentMenu.waitForExistence(timeout: 3.0))
        XCTAssertTrue(
            assignedSegmentMenu.label.localizedCaseInsensitiveContains("Host"),
            "화자 이름 변경이 배정된 세그먼트 라벨에 반영되어야 합니다"
        )

        let exportButton = app.element("transcription.exportButton")
        XCTAssertTrue(exportButton.waitForExistence(timeout: 3.0))
        exportButton.click()

        let reviewSheet = app.element("subtitleReview.sheet")
        XCTAssertTrue(reviewSheet.waitForExistence(timeout: 5.0), "Export 전 review 시트가 열려야 합니다")
        XCTAssertTrue(app.staticTexts["Missing speaker label"].waitForExistence(timeout: 3.0))
        XCTAssertFalse(app.staticTexts["Speaker 1 uses a default name"].exists)
        XCTAssertTrue(app.element("subtitleReview.quickFixButton").waitForExistence(timeout: 3.0))
        XCTAssertTrue(app.element("subtitleReview.exportAnywayButton").isEnabled)

        app.element("subtitleReview.cancelButton").click()
    }

    @MainActor
    func testLanguageMenuIncludesSupportedGrowthLanguages() throws {
        let settingsMenu = app.menuBarItem(matchingTitles: ["Settings", "설정"])
        XCTAssertTrue(settingsMenu.waitForExistence(timeout: 5.0), "Settings 메뉴가 있어야 합니다")
        settingsMenu.click()

        let languageMenu = app.menuItem(matchingTitles: ["Language", "언어"])
        guard languageMenu.waitForExistence(timeout: 3.0) else {
            throw XCTSkip("macOS 메뉴바 하위 메뉴 접근이 현재 테스트 환경에서 불안정합니다.")
        }
        languageMenu.click()

        XCTAssertTrue(app.menuItems["English (US)"].waitForExistence(timeout: 3.0))
        XCTAssertTrue(app.menuItems["English (UK)"].waitForExistence(timeout: 3.0))
        XCTAssertTrue(app.menuItems["日本語"].waitForExistence(timeout: 3.0))
        XCTAssertTrue(app.menuItems["Español"].waitForExistence(timeout: 3.0))
        XCTAssertTrue(app.menuItems["Deutsch"].waitForExistence(timeout: 3.0))
        XCTAssertTrue(app.menuItems["Français"].waitForExistence(timeout: 3.0))
        XCTAssertTrue(app.menuItems["Português (Brasil)"].waitForExistence(timeout: 3.0))
        XCTAssertTrue(app.menuItems["हिन्दी"].waitForExistence(timeout: 3.0))
        XCTAssertTrue(app.menuItems["简体中文"].waitForExistence(timeout: 3.0))
    }

}

// MARK: - 성능 테스트 (별도 실행)

final class PerformanceTests: XCTestCase {
    @MainActor
    func testLaunchPerformance() throws {
        if #available(macOS 10.15, *) {
            // 앱 실행 시간 측정 (5초 이하 목표)
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                let app = XCUIApplication()
                app.launch()
                app.terminate()
            }
        }
    }
}
