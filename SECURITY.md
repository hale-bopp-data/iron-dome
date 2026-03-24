# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 2.0.x   | Yes       |
| < 2.0   | No        |

## Reporting a Vulnerability

Iron Dome is a security tool. We take vulnerabilities in our own code seriously.

**Do NOT open a public issue for security vulnerabilities.**

Instead, please report them via email:

- **Email**: security@hale-bopp.dev
- **Subject**: `[Iron Dome] Vulnerability Report — <brief description>`
- **PGP**: Not required, but appreciated if you have it

### What to include

1. Description of the vulnerability
2. Steps to reproduce (or a proof-of-concept)
3. Impact assessment (what can an attacker do?)
4. Affected version(s)

### What to expect

- **Acknowledgment** within 48 hours
- **Triage** within 7 days
- **Fix or mitigation** within 30 days for confirmed vulnerabilities
- **Credit** in the CHANGELOG and release notes (unless you prefer anonymity)

### Scope

In scope:
- Pattern bypass (a real secret that evades detection)
- Whitelist logic flaws (bypassing guards without proper reason)
- Hook injection (using Iron Dome's install mechanism to inject malicious code)
- Telemetry data leakage

Out of scope:
- `--no-verify` bypass (this is by design; the CI layer catches it)
- Regex performance (ReDoS) on crafted input over 512KB (files above this limit are skipped)
- Issues in dependencies (bash, grep, git) — report those upstream

## Security Design

Iron Dome is deliberately non-intelligent:

- **No network calls** — runs entirely offline
- **No dependencies** beyond bash, git, and grep
- **No code execution** — regex matching only, never evals user content
- **No secrets stored** — telemetry logs guard names and file paths, never secret values
