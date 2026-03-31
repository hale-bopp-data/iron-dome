#!/usr/bin/env python3
"""Iron Dome G-CI-10 — CI YAML Lint

Scans azure-pipelines.yml for banned patterns that cause CI failures:
  - vmImage (G-CI-1): hosted agents are slow and unreliable
  - UsePythonVersion@0 (G-CI-2): breaks on self-hosted agents
  - pip install without venv: PEP 668 breaks on Ubuntu 24+
  - python -m pip without venv: same issue

Exit codes:
  0 = no banned patterns
  1 = banned patterns found
  2 = no CI YAML found (skip)
"""

import re
import sys
from pathlib import Path

BANNED_PATTERNS = [
    {
        "id": "G-CI-1",
        "name": "vmImage (hosted agent)",
        "pattern": r"vmImage\s*:",
        "fix": "Use 'pool: { name: Default }' for self-hosted agent",
    },
    {
        "id": "G-CI-2",
        "name": "UsePythonVersion@0",
        "pattern": r"UsePythonVersion@\d+",
        "fix": "Remove — self-hosted agent has Python pre-installed, use venv instead",
    },
    {
        "id": "G-CI-10a",
        "name": "pip install without venv",
        "pattern": r"(?<!venv/bin/)pip\s+install(?!.*venv)",
        "fix": "Use: python -m venv .venv && .venv/bin/pip install",
    },
    {
        "id": "G-CI-10b",
        "name": "python -m pip without venv",
        "pattern": r"python3?\s+-m\s+pip(?!.*venv)",
        "fix": "Use: python -m venv .venv && .venv/bin/pip install",
    },
]

# Lines that are comments or inside Iron Dome's own banned-pattern documentation
SAFE_CONTEXTS = [
    r"^\s*#",           # comments
    r"^\s*echo\s",      # echo statements
    r"displayName:",    # task display names
    r"^\s*-\s*name:",   # variable names
]


def is_safe_line(line: str) -> bool:
    """Check if a line is in a safe context (comment, echo, etc.)."""
    return any(re.search(p, line) for p in SAFE_CONTEXTS)


def scan_yaml(filepath: Path) -> list[dict]:
    """Scan a YAML file for banned patterns."""
    findings = []
    lines = filepath.read_text(encoding="utf-8").splitlines()

    for line_num, line in enumerate(lines, 1):
        if is_safe_line(line):
            continue

        for banned in BANNED_PATTERNS:
            if re.search(banned["pattern"], line):
                findings.append({
                    "file": str(filepath),
                    "line": line_num,
                    "content": line.strip(),
                    **banned,
                })

    return findings


def main() -> int:
    repo_root = Path(".")

    # Find CI YAML files
    yaml_files = []
    for name in ["azure-pipelines.yml", "azure-pipelines.yaml", ".azure-pipelines.yml"]:
        f = repo_root / name
        if f.exists():
            yaml_files.append(f)
    # Also check ci/ and .pipelines/ directories
    for d in ["ci", ".pipelines", ".azure-pipelines"]:
        yaml_files.extend((repo_root / d).glob("*.yml"))
        yaml_files.extend((repo_root / d).glob("*.yaml"))

    if not yaml_files:
        print("G-CI-10: SKIP — no CI YAML files found")
        return 2

    all_findings = []
    for yf in yaml_files:
        all_findings.extend(scan_yaml(yf))

    if all_findings:
        print(f"G-CI-10: FAIL — {len(all_findings)} banned CI pattern(s) found:")
        for f in all_findings:
            print(f"  [{f['id']}] {f['file']}:{f['line']} — {f['name']}")
            print(f"    Line: {f['content']}")
            print(f"    Fix:  {f['fix']}")
        return 1

    print(f"G-CI-10: PASS — {len(yaml_files)} CI YAML file(s) clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
