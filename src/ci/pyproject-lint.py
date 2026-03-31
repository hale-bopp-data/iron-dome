#!/usr/bin/env python3
"""Iron Dome G-CI-9 — pyproject.toml Lint

Verifies pyproject.toml follows best practices:
  - license is SPDX string (not deprecated table)
  - packages.find present if not src-layout
  - requires-python present
  - ruff configured (or ruff.toml exists)
  - pytest configured (or pytest.ini/conftest.py exists)

Exit codes:
  0 = all checks pass
  1 = lint violations found
  2 = no pyproject.toml (skip)
"""

import re
import sys
from pathlib import Path


def check_license_spdx(content: str) -> str | None:
    """License must be SPDX string, not deprecated table format."""
    # Bad: license = {text = "MIT"} or [project.license] with text/file keys
    if re.search(r'license\s*=\s*\{', content):
        return "license uses deprecated table format — use SPDX string: license = \"MIT\""
    if re.search(r'\[project\.license\]', content):
        return "license uses deprecated [project.license] section — use: license = \"MIT\""
    # Good: license = "MIT" — or missing (we won't enforce presence)
    return None


def check_packages_find(content: str, repo_root: Path) -> str | None:
    """If not using src-layout, packages.find must be explicit."""
    # src-layout: src/ directory exists
    if (repo_root / "src").is_dir():
        return None
    # Check if [tool.setuptools.packages.find] or packages = [...] is set
    if "packages.find" in content or "packages =" in content:
        return None
    # Check if it's a single-file module (no packages needed)
    py_files = list(repo_root.glob("*.py"))
    if py_files and not list(repo_root.glob("*/__init__.py")):
        return None  # single-file module, no packages needed
    # Has subdirectories with __init__.py but no packages config
    pkg_dirs = [p.parent.name for p in repo_root.glob("*/__init__.py") if p.parent.name not in ("tests", "test")]
    if pkg_dirs:
        return f"flat-layout detected ({', '.join(pkg_dirs)}) but no [tool.setuptools.packages.find] — setuptools may not find your packages"
    return None


def check_requires_python(content: str) -> str | None:
    """requires-python should be present."""
    if "requires-python" not in content:
        return "missing requires-python — add: requires-python = \">=3.10\""
    return None


def check_ruff(content: str, repo_root: Path) -> str | None:
    """Ruff should be configured somewhere."""
    if "[tool.ruff" in content:
        return None
    if (repo_root / "ruff.toml").exists() or (repo_root / ".ruff.toml").exists():
        return None
    return "ruff not configured — add [tool.ruff] section or ruff.toml"


def check_pytest(content: str, repo_root: Path) -> str | None:
    """Pytest should be configured if tests exist."""
    test_dirs = list(repo_root.glob("tests/**/*.py")) + list(repo_root.glob("test/**/*.py"))
    if not test_dirs:
        return None  # no tests, no need for pytest config
    if "[tool.pytest" in content:
        return None
    if (repo_root / "pytest.ini").exists() or (repo_root / "setup.cfg").exists():
        return None
    if (repo_root / "conftest.py").exists():
        return None  # conftest at root is acceptable
    return "tests exist but pytest not configured — add [tool.pytest.ini_options] section"


def main() -> int:
    repo_root = Path(".")
    pyproject = repo_root / "pyproject.toml"

    if not pyproject.exists():
        print("G-CI-9: SKIP — no pyproject.toml found")
        return 2

    content = pyproject.read_text(encoding="utf-8")
    violations = []

    checks = [
        check_license_spdx(content),
        check_packages_find(content, repo_root),
        check_requires_python(content),
        check_ruff(content, repo_root),
        check_pytest(content, repo_root),
    ]

    violations = [v for v in checks if v is not None]

    if violations:
        print(f"G-CI-9: FAIL — {len(violations)} pyproject.toml violation(s):")
        for v in violations:
            print(f"  - {v}")
        return 1

    print("G-CI-9: PASS — pyproject.toml lint clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
