#!/usr/bin/env swift
// Copyright 2026 Harrison Cho
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import CoreGraphics
import Darwin
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("UI preflight failed: \(message)\n".utf8))
    exit(EXIT_FAILURE)
}

guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
      session["kCGSSessionOnConsoleKey"] as? Bool == true else {
    fail("An active macOS console session is required for UI testing.")
}
if session["CGSSessionScreenIsLocked"] as? Bool == true {
    fail("The macOS screen is locked. Unlock this Mac before running UI tests.")
}
print("UI session ready: unlocked console.")
