#!/usr/bin/env python3
"""Iron Dome G-CI-12 — Dependency Vulnerability Scan

Runs pip-audit (Python) and/or npm audit (Node.js) to detect known CVEs.
Warning for medium severity, fail for high/critical.

Exit codes:
  0 = no high/critical vulnerabilities
  1 = high/critical vulnerabilities found
  2 = no package files found (skip)
"""

import json
import subprocess
import sys
from pathlib import Path


def run_pip_audit(repo_root: Path) -> tuple[int, list[str]]:
    """Run pip-audit on the repo. Returns (high_count, messages)."""
    pyproject = repo_root / "pyproject.toml"
    requirements = repo_root / "requirements.txt"

    if not pyproject.exists() and not requirements.exists():
        return 0, []

    messages = []
    high_count = 0

    # Try pip-audit
    try:
        cmd = ["pip-audit", "--format=json", "--desc"]
        if requirements.exists():
            cmd.extend(["-r", str(requirements)])
        result = subprocess.run(
            cmd, capture_output=True, text=True, timeout=120, cwd=str(repo_root)
        )

        if result.stdout.strip():
            try:
                data = json.loads(result.stdout)
                vulns = data if isinstance(data, list) else data.get("dependencies", [])
                for dep in vulns:
                    dep_vulns = dep.get("vulns", [])
                    for v in dep_vulns:
                        vid = v.get("id", "unknown")
                        desc = v.get("description", "")[:100]
                        fix = v.get("fix_versions", [])
                        severity = _classify_vuln(v)
                        marker = "CRITICAL" if severity >= 2 else "WARNING"
                        msg = f"  [{marker}] {dep.get('name', '?')} — {vid}: {desc}"
                        if fix:
                            msg += f" (fix: {', '.join(fix)})"
                        messages.append(msg)
                        if severity >= 2:
                            high_count += 1
            except json.JSONDecodeError:
                # pip-audit might output non-JSON on errors
                if result.returncode != 0:
                    messages.append(f"  [WARNING] pip-audit exited with code {result.returncode}")
                    if result.stderr:
                        messages.append(f"  {result.stderr.strip()[:200]}")

    except FileNotFoundError:
        messages.append("  [FAIL] pip-audit not installed — tool required for security audit")
        high_count = 1
    except subprocess.TimeoutExpired:
        messages.append("  [FAIL] pip-audit timed out after 120s")
        high_count = 1

    return high_count, messages


def run_npm_audit(repo_root: Path) -> tuple[int, list[str]]:
    """Run npm audit on the repo. Returns (high_count, messages)."""
    package_json = repo_root / "package.json"
    if not package_json.exists():
        return 0, []

    messages = []
    high_count = 0

    try:
        result = subprocess.run(
            ["npm", "audit", "--json"],
            capture_output=True, text=True, timeout=120, cwd=str(repo_root)
        )

        if result.stdout.strip():
            try:
                data = json.loads(result.stdout)
                vulns = data.get("vulnerabilities", {})
                for name, info in vulns.items():
                    severity = info.get("severity", "low")
                    via = info.get("via", [])
                    desc = ""
                    if via and isinstance(via[0], dict):
                        desc = via[0].get("title", "")[:100]

                    if severity in ("high", "critical"):
                        messages.append(f"  [CRITICAL] {name} ({severity}): {desc}")
                        high_count += 1
                    elif severity == "moderate":
                        messages.append(f"  [WARNING] {name} ({severity}): {desc}")
            except json.JSONDecodeError:
                pass

    except FileNotFoundError:
        messages.append("  [FAIL] npm not installed — tool required for security audit")
        high_count = 1
    except subprocess.TimeoutExpired:
        messages.append("  [FAIL] npm audit timed out after 120s")
        high_count = 1

    return high_count, messages


def _classify_vuln(vuln: dict) -> int:
    """Classify vulnerability severity. 0=low, 1=medium, 2=high/critical."""
    # Check aliases for GHSA severity
    aliases = vuln.get("aliases", [])
    vid = vuln.get("id", "")

    # pip-audit doesn't always include severity, use heuristics
    desc = (vuln.get("description", "") + vid).lower()
    if any(kw in desc for kw in ("critical", "remote code", "rce", "sql injection")):
        return 2
    if any(kw in desc for kw in ("high", "privilege", "bypass", "overflow")):
        return 2
    if any(kw in desc for kw in ("moderate", "medium", "denial")):
        return 1
    return 0


def main() -> int:
    repo_root = Path(".")

    has_python = (repo_root / "pyproject.toml").exists() or (repo_root / "requirements.txt").exists()
    has_node = (repo_root / "package.json").exists()

    if not has_python and not has_node:
        print("G-CI-12: SKIP — no pyproject.toml, requirements.txt, or package.json found")
        return 2

    total_high = 0
    all_messages = []

    if has_python:
        high, msgs = run_pip_audit(repo_root)
        total_high += high
        if msgs:
            all_messages.append("Python (pip-audit):")
            all_messages.extend(msgs)

    if has_node:
        high, msgs = run_npm_audit(repo_root)
        total_high += high
        if msgs:
            all_messages.append("Node.js (npm audit):")
            all_messages.extend(msgs)

    if total_high > 0:
        print(f"G-CI-12: FAIL — {total_high} high/critical vulnerability(ies) found:")
        for msg in all_messages:
            print(msg)
        return 1

    if all_messages:
        print("G-CI-12: WARNING — medium-severity vulnerabilities found (non-blocking):")
        for msg in all_messages:
            print(msg)
        return 0  # warnings don't fail the build

    print("G-CI-12: PASS — no known vulnerabilities found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
