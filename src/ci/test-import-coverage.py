#!/usr/bin/env python3
"""Iron Dome G-CI-8 — Test Import Coverage

Scans tests/**/*.py for import statements and verifies that every imported
third-party module is declared in pyproject.toml (dependencies + extras).

Exit codes:
  0 = all imports covered
  1 = uncovered imports found
  2 = no pyproject.toml or no tests (skip)
"""

import ast
import sys
import re
from pathlib import Path

# Standard library modules (Python 3.10+) — not exhaustive but covers common ones.
# We use sys.stdlib_module_names when available (3.10+), fallback to a curated set.
try:
    STDLIB = sys.stdlib_module_names
except AttributeError:
    STDLIB = {
        "abc", "aifc", "argparse", "array", "ast", "asynchat", "asyncio",
        "asyncore", "atexit", "base64", "bdb", "binascii", "binhex",
        "bisect", "builtins", "bz2", "calendar", "cgi", "cgitb", "chunk",
        "cmath", "cmd", "code", "codecs", "codeop", "collections",
        "colorsys", "compileall", "concurrent", "configparser", "contextlib",
        "contextvars", "copy", "copyreg", "cProfile", "crypt", "csv",
        "ctypes", "curses", "dataclasses", "datetime", "dbm", "decimal",
        "difflib", "dis", "distutils", "doctest", "email", "encodings",
        "enum", "errno", "faulthandler", "fcntl", "filecmp", "fileinput",
        "fnmatch", "fractions", "ftplib", "functools", "gc", "getopt",
        "getpass", "gettext", "glob", "grp", "gzip", "hashlib", "heapq",
        "hmac", "html", "http", "idlelib", "imaplib", "imghdr", "imp",
        "importlib", "inspect", "io", "ipaddress", "itertools", "json",
        "keyword", "lib2to3", "linecache", "locale", "logging", "lzma",
        "mailbox", "mailcap", "marshal", "math", "mimetypes", "mmap",
        "modulefinder", "multiprocessing", "netrc", "nis", "nntplib",
        "numbers", "operator", "optparse", "os", "ossaudiodev",
        "pathlib", "pdb", "pickle", "pickletools", "pipes", "pkgutil",
        "platform", "plistlib", "poplib", "posix", "posixpath", "pprint",
        "profile", "pstats", "pty", "pwd", "py_compile", "pyclbr",
        "pydoc", "queue", "quopri", "random", "re", "readline", "reprlib",
        "resource", "rlcompleter", "runpy", "sched", "secrets", "select",
        "selectors", "shelve", "shlex", "shutil", "signal", "site",
        "smtpd", "smtplib", "sndhdr", "socket", "socketserver", "sqlite3",
        "ssl", "stat", "statistics", "string", "stringprep", "struct",
        "subprocess", "sunau", "symtable", "sys", "sysconfig", "syslog",
        "tabnanny", "tarfile", "telnetlib", "tempfile", "termios", "test",
        "textwrap", "threading", "time", "timeit", "tkinter", "token",
        "tokenize", "tomllib", "trace", "traceback", "tracemalloc",
        "tty", "turtle", "turtledemo", "types", "typing", "unicodedata",
        "unittest", "urllib", "uu", "uuid", "venv", "warnings", "wave",
        "weakref", "webbrowser", "winreg", "winsound", "wsgiref",
        "xdrlib", "xml", "xmlrpc", "zipapp", "zipfile", "zipimport",
        "zlib", "_thread", "__future__",
    }

# Known test frameworks / tools that are test-only but commonly available
TEST_INFRA = {"pytest", "conftest", "_pytest", "hypothesis", "unittest", "mock"}

# Mapping: import name → pypi package name (common mismatches)
IMPORT_TO_PKG = {
    "cv2": "opencv-python",
    "PIL": "pillow",
    "sklearn": "scikit-learn",
    "yaml": "pyyaml",
    "bs4": "beautifulsoup4",
    "attr": "attrs",
    "dateutil": "python-dateutil",
    "dotenv": "python-dotenv",
    "jose": "python-jose",
    "jwt": "pyjwt",
    "gi": "pygobject",
    "serial": "pyserial",
    "usb": "pyusb",
    "wx": "wxpython",
    "lxml": "lxml",
    "msgpack": "msgpack",
    "google": "google-api-python-client",
}


def get_top_level_import(name: str) -> str:
    """Extract the top-level package from a dotted import."""
    return name.split(".")[0]


def extract_imports(filepath: Path) -> set[str]:
    """Extract top-level import names from a Python file using AST."""
    try:
        source = filepath.read_text(encoding="utf-8", errors="replace")
        tree = ast.parse(source, filename=str(filepath))
    except (SyntaxError, ValueError):
        return set()

    imports = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                imports.add(get_top_level_import(alias.name))
        elif isinstance(node, ast.ImportFrom):
            if node.module and node.level == 0:  # absolute imports only
                imports.add(get_top_level_import(node.module))
    return imports


def parse_pyproject_deps(pyproject_path: Path) -> set[str]:
    """Parse dependency names from pyproject.toml (dependencies + all extras)."""
    text = pyproject_path.read_text(encoding="utf-8")
    deps = set()

    # Match lines like: "fastapi>=0.100", "openpyxl", "ruff>=0.1"
    # Inside [project.dependencies] or [project.optional-dependencies.*]
    dep_pattern = re.compile(r'^\s*"([a-zA-Z0-9_][a-zA-Z0-9_.+-]*)', re.MULTILINE)

    in_deps = False
    for line in text.splitlines():
        stripped = line.strip()

        # Section headers
        if stripped.startswith("["):
            in_deps = (
                stripped == "[project]"
                or "dependencies" in stripped.lower()
            )
            continue

        if in_deps and stripped.startswith('"'):
            m = dep_pattern.match(stripped)
            if m:
                pkg = m.group(1).lower().replace("-", "_").replace(".", "_")
                deps.add(pkg)

        # Also catch: dependencies = ["pkg1", "pkg2"]
        if "dependencies" in stripped and "=" in stripped:
            for m in re.finditer(r'"([a-zA-Z0-9_][a-zA-Z0-9_.+-]*)', stripped):
                pkg = m.group(1).lower().replace("-", "_").replace(".", "_")
                deps.add(pkg)

    return deps


def normalize(name: str) -> str:
    """Normalize a package/import name for comparison."""
    return name.lower().replace("-", "_").replace(".", "_")


def main() -> int:
    repo_root = Path(".")

    pyproject = repo_root / "pyproject.toml"
    if not pyproject.exists():
        print("G-CI-8: SKIP — no pyproject.toml found")
        return 2

    test_files = list(repo_root.glob("tests/**/*.py")) + list(repo_root.glob("test/**/*.py"))
    if not test_files:
        print("G-CI-8: SKIP — no test files found")
        return 2

    # Collect declared deps
    declared = parse_pyproject_deps(pyproject)

    # Also check requirements*.txt if present
    for req_file in repo_root.glob("requirements*.txt"):
        for line in req_file.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and not line.startswith("-"):
                pkg = re.split(r"[>=<!\[;]", line)[0].strip()
                declared.add(normalize(pkg))

    # Collect local package names (src dirs that are importable)
    local_packages = set()
    for init in repo_root.glob("src/*/__init__.py"):
        local_packages.add(init.parent.name)
    for init in repo_root.glob("*/__init__.py"):
        if init.parent.name not in ("tests", "test", "src"):
            local_packages.add(init.parent.name)
    # Also the project name itself from pyproject.toml
    name_match = re.search(r'name\s*=\s*"([^"]+)"', pyproject.read_text())
    if name_match:
        local_packages.add(normalize(name_match.group(1)))

    # Scan test imports
    all_imports = set()
    for tf in test_files:
        all_imports |= extract_imports(tf)

    # Filter: remove stdlib, test infra, local packages, conftest
    third_party = set()
    for imp in all_imports:
        norm = normalize(imp)
        if imp in STDLIB or norm in STDLIB:
            continue
        if imp in TEST_INFRA or norm in TEST_INFRA:
            continue
        if norm in local_packages:
            continue
        if imp.startswith("_"):  # private/internal
            continue
        third_party.add(imp)

    # Check coverage
    uncovered = []
    for imp in sorted(third_party):
        norm = normalize(imp)
        # Check direct match
        if norm in declared:
            continue
        # Check known mapping
        mapped = IMPORT_TO_PKG.get(imp)
        if mapped and normalize(mapped) in declared:
            continue
        # Check if any declared dep starts with the import name
        if any(d.startswith(norm) for d in declared):
            continue
        if any(norm.startswith(d) for d in declared):
            continue
        uncovered.append(imp)

    if uncovered:
        print(f"G-CI-8: FAIL — {len(uncovered)} test import(s) not in pyproject.toml:")
        for imp in uncovered:
            mapped = IMPORT_TO_PKG.get(imp, imp)
            print(f"  - {imp} (pip: {mapped})")
        print("\nFix: add missing packages to [project.dependencies] or [project.optional-dependencies]")
        return 1

    print(f"G-CI-8: PASS — {len(third_party)} third-party import(s) all covered ({len(test_files)} test files)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
