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
//  CaptionMateUITestsLaunchTests.swift
//  CaptionMateUITests
//
//  Created by 조형구 on 2/22/25.
//

import XCTest

final class CaptionMateUITestsLaunchTests: XCTestCase {
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testImportPickerFromLaunch() throws {
        let app = XCUIApplication.captionMate()
        app.launchFreshForUITest()
        defer { app.terminate() }

        let importButton = app.buttons["Import File"]
        let importReady = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in importButton.exists && importButton.isHittable },
            object: nil
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [importReady], timeout: 5.0),
            .completed,
            "Import must remain reachable in the window"
        )
        importButton.click()
        let pickerOpened = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                app.dialogs.firstMatch.exists || app.sheets.firstMatch.exists
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [pickerOpened], timeout: 5.0), .completed)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 3.0))
        app.typeKey(.escape, modifierFlags: [])
        app.activate()
        let importAvailable = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                !app.dialogs.firstMatch.exists && !app.sheets.firstMatch.exists && importButton.isHittable
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [importAvailable], timeout: 5.0), .completed)

        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "Import picker cancelled after launch"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
