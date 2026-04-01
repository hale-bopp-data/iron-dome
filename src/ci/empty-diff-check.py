#!/usr/bin/env python3
"""Iron Dome G-CI-14 — Empty Diff Check (PR Fantasma Prevention)

Verifies that a PR actually contains file changes. Catches the scenario
where a commit lands on the wrong branch and the PR has an empty diff
(GEDI Case #30 — "La PR Fantasma").

Layer 2 defense in depth: L1 is the ScrumMaster gate (PBI #883).

Exit codes:
  0 = PR has file changes (pass)
  1 = PR has zero file changes (fail — possible wrong branch)
  2 = not a PR build or target branch unknown (skip)
"""

import os
import subprocess
import sys


def get_target_branch() -> str | None:
    """Resolve the PR target branch from Azure Pipelines env vars."""
    target = os.environ.get("SYSTEM_PULLREQUEST_TARGETBRANCH", "")
    if not target:
        return None
    # ADO passes "refs/heads/develop" — strip prefix
    return target.removeprefix("refs/heads/")


def count_changed_files(target_branch: str) -> int:
    """Count files changed between HEAD and the target branch merge-base."""
    try:
        # Ensure we have the target branch ref
        subprocess.run(
            ["git", "fetch", "origin", target_branch],
            capture_output=True, timeout=30,
        )
        result = subprocess.run(
            ["git", "diff", "--name-only", f"origin/{target_branch}...HEAD"],
            capture_output=True, text=True, timeout=30,
        )
        if result.returncode != 0:
            print(f"G-CI-14: WARNING — git diff failed: {result.stderr.strip()}")
            return -1
        files = [f for f in result.stdout.strip().splitlines() if f]
        return len(files)
    except subprocess.TimeoutExpired:
        print("G-CI-14: WARNING — git diff timed out")
        return -1


def main() -> int:
    target = get_target_branch()
    if not target:
        print("G-CI-14: SKIP — not a PR build (no SYSTEM_PULLREQUEST_TARGETBRANCH)")
        return 2

    print(f"G-CI-14: checking diff against origin/{target}")

    count = count_changed_files(target)

    if count < 0:
        # Git command failed — don't block the build, warn only
        print("G-CI-14: SKIP — could not determine diff (git error)")
        return 2

    if count == 0:
        print("G-CI-14: FAIL — EMPTY_DIFF: PR has 0 file changes")
        print("  Possible causes:")
        print("    - Commit landed on wrong branch (PR Fantasma)")
        print("    - Source and target branches are already aligned")
        print("  Action: verify git branch --show-current before committing")
        return 1

    print(f"G-CI-14: PASS — {count} file(s) changed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
