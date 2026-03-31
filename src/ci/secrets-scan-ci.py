#!/usr/bin/env python3
"""Iron Dome G-CI-11 — Secrets Scan in CI (Defense in Depth)

Runs the same secret pattern scan as the pre-commit hook, but in CI.
If someone bypasses pre-commit (--no-verify), CI still catches it.

This is NOT a replacement for the pre-commit hook — it's a second layer.

Exit codes:
  0 = no secrets found
  1 = secrets detected
"""

import re
import sys
from pathlib import Path

# Same patterns as iron-dome.yml — keep in sync
SECRET_PATTERNS = [
    ("Private Key", r"-----BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----"),
    ("GitHub PAT", r"ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{60,}"),
    ("GitLab Token", r"glpat-[A-Za-z0-9\-_]{20,}"),
    ("AWS Access Key", r"AKIA[0-9A-Z]{16}"),
    ("AWS Secret Key", r"(?i)aws_secret_access_key\s*[:=]\s*[A-Za-z0-9/+=]{40}"),
    ("Azure Connection String", r"(?i)DefaultEndpointsProtocol=https?;AccountName=[^;]+;AccountKey=[A-Za-z0-9+/=]{40,}"),
    ("OpenAI / OpenRouter Key", r"sk-[a-zA-Z0-9]{20,}"),
    ("Generic API Key assignment", r'(?i)(api[_-]?key|apikey|api[_-]?secret)\s*[:=]\s*["\']?[A-Za-z0-9_\-]{20,}'),
    ("Generic Token assignment", r'(?i)(auth[_-]?token|access[_-]?token|bearer)\s*[:=]\s*["\']?[A-Za-z0-9_\-\.]{20,}'),
    ("Generic Password assignment", r'(?i)(password|passwd|pwd)\s*[:=]\s*["\'][^"\']{8,}["\']'),
    (".env file", r"^\.env$"),
]

# File extensions to skip (binary, images, etc.)
SKIP_EXTENSIONS = {
    ".png", ".jpg", ".jpeg", ".gif", ".ico", ".svg", ".woff", ".woff2",
    ".ttf", ".eot", ".otf", ".mp3", ".mp4", ".avi", ".mov", ".zip",
    ".tar", ".gz", ".bz2", ".xz", ".7z", ".rar", ".pdf", ".doc",
    ".docx", ".xls", ".xlsx", ".ppt", ".pptx", ".pyc", ".pyo",
    ".so", ".dll", ".exe", ".bin", ".dat", ".db", ".sqlite",
    ".lock", ".sum",
}

# Directories to skip
SKIP_DIRS = {
    "node_modules", ".git", "vendor", "__pycache__", ".venv", "venv",
    ".tox", ".mypy_cache", ".pytest_cache", "dist", "build", ".next",
    "coverage", ".nyc_output", ".eggs",
}

# Safe patterns (test fixtures, documentation, templates)
SAFE_LINE_PATTERNS = [
    r"^\s*#",           # comments
    r"^\s*//",          # JS/TS comments
    r"EXAMPLE",         # example values
    r"<YOUR",           # placeholder
    r"\$\{",            # variable interpolation
    r"\{\{",            # template
    r"process\.env",    # env reference
    r"os\.environ",     # env reference
    r"\.env\.secrets",  # reference to secrets file
    r"sk-test-",        # Stripe test keys
    r"sk-proj-",        # known safe prefix in docs
]


def should_skip(filepath: Path) -> bool:
    """Check if a file should be skipped."""
    if filepath.suffix.lower() in SKIP_EXTENSIONS:
        return True
    for part in filepath.parts:
        if part in SKIP_DIRS:
            return True
    return False


def is_safe_line(line: str) -> bool:
    """Check if a line contains a safe/benign pattern."""
    return any(re.search(p, line) for p in SAFE_LINE_PATTERNS)


def scan_file(filepath: Path) -> list[dict]:
    """Scan a single file for secret patterns."""
    findings = []
    try:
        content = filepath.read_text(encoding="utf-8", errors="replace")
    except (OSError, PermissionError):
        return findings

    # Special case: check if this IS a .env file
    if filepath.name == ".env" or filepath.name.startswith(".env."):
        if filepath.name not in (".env.example", ".env.template", ".env.sample"):
            findings.append({
                "file": str(filepath),
                "line": 0,
                "pattern": ".env file",
                "content": f"Environment file should not be committed: {filepath.name}",
            })
            return findings

    for line_num, line in enumerate(content.splitlines(), 1):
        if is_safe_line(line):
            continue

        for name, pattern in SECRET_PATTERNS:
            if name == ".env file":
                continue  # handled above
            try:
                if re.search(pattern, line):
                    findings.append({
                        "file": str(filepath),
                        "line": line_num,
                        "pattern": name,
                        "content": line.strip()[:120],
                    })
                    break  # one finding per line is enough
            except re.error:
                continue

    return findings


def main() -> int:
    repo_root = Path(".")
    all_findings = []
    scanned = 0

    for filepath in repo_root.rglob("*"):
        if not filepath.is_file():
            continue
        if should_skip(filepath):
            continue
        scanned += 1
        all_findings.extend(scan_file(filepath))

    if all_findings:
        print(f"G-CI-11: FAIL — {len(all_findings)} potential secret(s) found:")
        for f in all_findings:
            loc = f"{f['file']}:{f['line']}" if f['line'] else f['file']
            print(f"  [{f['pattern']}] {loc}")
            print(f"    {f['content']}")
        print("\nIf these are false positives, add to .iron-dome.yml whitelist with a reason.")
        return 1

    print(f"G-CI-11: PASS — {scanned} files scanned, no secrets found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
