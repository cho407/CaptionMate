#!/usr/bin/env python3
# Copyright 2026 Harrison Cho
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

"""Require a passing xcresult with at least one executed, passing test."""

import json
import subprocess
import sys


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: check_test_results.py RESULTS.xcresult")

    result = subprocess.run(
        ["xcrun", "xcresulttool", "get", "test-results", "summary",
         "--path", sys.argv[1]],
        check=True, capture_output=True, text=True,
    )
    summary = json.loads(result.stdout)
    passed = summary["passedTests"]
    failed = summary["failedTests"]
    skipped = summary["skippedTests"]
    print(f"Tests: {passed} passed, {skipped} skipped, {failed} failed.")
    if summary["result"] != "Passed" or failed != 0 or passed < 1:
        raise SystemExit("Test gate failed: require a successful run with at least one passing test.")


if __name__ == "__main__":
    main()
