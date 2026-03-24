# Changelog

All notable changes to Iron Dome will be documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] — 2026-03-24

Initial public release.

### Guards — Pre-Commit

- **Secrets Scan** — 11 regex patterns (private keys, PATs, AWS, Azure, OpenAI, passwords, tokens) with safe-pattern suppression and per-pattern whitelist
- **Conflict Markers** — blocks unresolved `<<<<<<<` / `=======` / `>>>>>>>`
- **Large File** — blocks files over configurable size (default 1MB)
- **Sensitive Files** — blocks `.env`, `*.pem`, `id_rsa`, `credentials.json` etc. by filename
- **Docker Run** — enforces compose-only policy (opt-in)
- **Debt Tracker** — advisory tracking of TODO/FIXME/HACK (opt-in)

### Guards — Pre-Push

- **Branch Policy** — blocks direct push to main/master
- **Semaphore** — concurrency control for multi-agent repos (opt-in)
- **Orphan Guard** — blocks push to branches with merged PRs (opt-in)

### CI Integration

- GitHub Actions reusable workflow
- Azure Pipelines template (universal + template reference)
- Server-side scanner (same checks, non-bypassable)

### Features

- YAML configuration (`iron-dome.yml`) with per-repo overrides (`.iron-dome.yml`)
- Auditable whitelist with mandatory reason and optional expiry
- Telemetry logging to `~/.iron-dome/telemetry.jsonl`
- CLI: `init`, `scan`, `doctor`, `stats`, `config`, `version`, `help`
- ADO and GitHub Actions integration (auto-detected in CI)
