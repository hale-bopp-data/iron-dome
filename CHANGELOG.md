# Changelog

All notable changes to Iron Dome will be documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.2.0] — 2026-05-19

### Added — 8 portable guards from EasyWay (Bug #2145)

These guards originated as polyrepo-specific extensions in the EasyWay project
(`/c/EW/easyway/infra/scripts/git-hooks/pre-commit`, 13 sections, S242-S519).
They are now first-class Iron Dome modules — useful for any team running an
AI-assisted development workflow with multiple agents and config drift risks.

- **`mcp_json_duplicate`** (G22) — Blocks `.mcp.json` in subdirectories.
  SSoT = root `.mcp.json` only. Prevents MCP server config fragmentation
  across agent runtimes (Claude Code, Codex, Cursor, etc.).
- **`wi_link`** (G26) — Auto-prepends work item reference (`#1234`) to
  commit messages when the branch name contains a WI number. Cross-branch
  staleness detection for `COMMIT_EDITMSG`.
- **`inline_credentials`** (S285/S297) — Blocks `https://user:pass@host`
  URLs. Better safe-pattern coverage than the secrets scan.
- **`exec_bit`** (S519) — Blocks `.sh` files in executable paths committed
  with mode 100644 (silent cron failures from Windows).
- **`env_secrets_source`** — Blocks `source .env.secrets` patterns. Direct
  sourcing fails silently if file missing.
- **`worktree_discipline`** (G28) — Blocks feature-branch commits from the
  base clone. Forces use of `git worktree` for `feat/`, `fix/`, etc.
- **`git_garbage`** (S242) — Auto-fixes accidental `git status`/`git diff`
  output baked into markdown/JSON/YAML files.
- **`anti_hardcoded`** (G16 "Presa Elettrica") — Advisory audit for absolute
  paths. Set `ANTI_HARDCODED_BLOCKING=1` to upgrade to blocking.

### Changed

- Schema version: `v2.1.0` → `v2.2.0`
- All 8 new guards default **enabled** with per-guard env-var escape hatch
- `iron-dome-core.sh` `_is_guard_enabled` default case extended

### Backward compatibility

Additive MINOR per semver. Existing v2.1.0 configs work unchanged.

## [2.1.0] — 2026-03-24

### Added

- **One-liner installer** — `curl -sL .../install.sh | bash` with auto-PATH setup, update, and uninstall
- **CONTRIBUTING.md** — contributor guide: bug reports, guard proposals, PR process, code style, guard template
- **Examples** — 4 ready-to-use configurations: `minimal.yml`, `multi-agent.yml`, `ci-only.yml`, `monorepo.yml`
- **README badges** — tests status, version, license, bash, zero dependencies
- **Cross-platform CI** — test matrix now runs on Ubuntu + macOS

### Changed

- **Quick Start** now leads with one-liner install, manual instructions in collapsible details
- **README** includes examples table and contributing link

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
