#!/usr/bin/env python3
"""Iron Dome G-CI-13 — Minimum Test Gate

Verifies that the test runner actually executed at least 1 test.
pytest with 0 collected items exits 0 by default — which is a silent pass.

Usage:
  # After running tests, pipe the output:
  pytest ... 2>&1 | tee test-output.txt
  python min-test-gate.py test-output.txt

  # Or pass the count directly:
  python min-test-gate.py --count 42

  # Or auto-detect from pytest cache:
  python min-test-gate.py --auto

Exit codes:
  0 = tests were executed (>= 1)
  1 = zero tests executed
  2 = cannot determine test count (skip)
"""

import re
import sys
from pathlib import Path


def count_from_output(filepath: Path) -> int | None:
    """Parse test count from pytest/vitest output file."""
    try:
        content = filepath.read_text(encoding="utf-8", errors="replace")
    except (OSError, FileNotFoundError):
        return None

    # pytest: "5 passed", "3 passed, 1 failed", "no tests ran"
    m = re.search(r"(\d+)\s+passed", content)
    if m:
        return int(m.group(1))

    m = re.search(r"(\d+)\s+failed", content)
    if m:
        # Failed tests still count as executed
        passed = 0
        mp = re.search(r"(\d+)\s+passed", content)
        if mp:
            passed = int(mp.group(1))
        return int(m.group(1)) + passed

    if "no tests ran" in content or "collected 0 items" in content:
        return 0

    # vitest: "Tests  3 passed (3)"
    m = re.search(r"Tests\s+(\d+)\s+passed", content)
    if m:
        return int(m.group(1))

    # vitest: "Test Files  1 passed (1)"
    m = re.search(r"Test Files\s+(\d+)\s+passed", content)
    if m:
        return int(m.group(1))

    # Jest: "Tests:       3 passed, 3 total"
    m = re.search(r"Tests:\s+(\d+)\s+passed", content)
    if m:
        return int(m.group(1))

    return None


def count_from_pytest_cache() -> int | None:
    """Try to read last test count from .pytest_cache."""
    cache_dir = Path(".pytest_cache/v/cache")
    lastfailed = cache_dir / "lastfailed"
    stepwise = cache_dir / "stepwise"

    # If lastfailed exists and is empty dict, all passed (but how many?)
    # This is unreliable — return None to fall through
    return None


def count_from_auto() -> int | None:
    """Auto-detect: look for common test output files."""
    for candidate in ["test-output.txt", "pytest-output.txt", "test-results.txt"]:
        p = Path(candidate)
        if p.exists():
            return count_from_output(p)

    # Check if junit XML exists (common CI artifact)
    for junit in Path(".").glob("**/junit*.xml"):
        try:
            content = junit.read_text(encoding="utf-8", errors="replace")
            m = re.search(r'tests="(\d+)"', content)
            if m:
                return int(m.group(1))
        except OSError:
            continue

    return None


def main() -> int:
    args = sys.argv[1:]

    count = None

    if not args:
        # Auto mode
        count = count_from_auto()
    elif args[0] == "--count":
        if len(args) < 2:
            print("G-CI-13: ERROR — --count requires a number")
            return 2
        try:
            count = int(args[1])
        except ValueError:
            print(f"G-CI-13: ERROR — invalid count: {args[1]}")
            return 2
    elif args[0] == "--auto":
        count = count_from_auto()
    else:
        # Assume it's a file path
        count = count_from_output(Path(args[0]))

    if count is None:
        print("G-CI-13: SKIP — cannot determine test count")
        print("  Tip: pipe test output to a file and pass it as argument")
        print("  Example: pytest 2>&1 | tee test-output.txt && python min-test-gate.py test-output.txt")
        return 2

    if count == 0:
        print("G-CI-13: FAIL — 0 tests executed")
        print("  A green build with 0 tests is NOT a success.")
        print("  Add tests or mark as expected with --count 0 override.")
        return 1

    print(f"G-CI-13: PASS — {count} test(s) executed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
