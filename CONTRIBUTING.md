# Contributing to Iron Dome

Thank you for your interest in contributing to Iron Dome. This guide will help you get started.

## Quick Links

- [Issue Tracker](https://github.com/hale-bopp-data/iron-dome/issues)
- [Discussions](https://github.com/hale-bopp-data/iron-dome/discussions)
- [Security Policy](SECURITY.md)

## Reporting Bugs

Open an issue with:
1. What you expected to happen
2. What actually happened
3. Steps to reproduce
4. Your environment (OS, bash version, grep version)

Run `iron-dome doctor` and include its output.

## Suggesting New Guards

Iron Dome's strength is simplicity. Before proposing a new guard, consider:

- **Is it deterministic?** If it requires AI, ML, or heuristics, it doesn't belong in Iron Dome.
- **Is it universal?** A guard useful to 5% of users should be opt-in. A guard useful to 80% can be on by default.
- **Does it have false positives?** Every false positive erodes trust. Include safe-pattern suppression.
- **Is it bash-only?** Guards that require python3 or external tools must be clearly marked as optional.

Open an issue tagged `[Guard Proposal]` with:
- Guard name and one-line description
- What it catches (with examples)
- Default: enabled or opt-in?
- False positive risk

## Development Setup

```bash
# Clone
git clone https://github.com/hale-bopp-data/iron-dome.git
cd iron-dome

# Run tests
bash tests/run-tests.sh

# Install locally for testing
export PATH="$(pwd):$PATH"
cd /tmp && mkdir test-repo && cd test-repo && git init
iron-dome init
iron-dome doctor
```

## Running Tests

```bash
# All tests
bash tests/run-tests.sh

# Verbose (see each assertion)
bash tests/run-tests.sh --verbose
```

Tests use a self-contained test runner (no external test framework). Each test file follows the pattern:

```bash
test_description_of_behavior() {
  # setup
  # action
  # assertion using assert_equals, assert_contains, assert_exit_code
}
```

## Writing a New Guard

1. Create `src/guards/your-guard.sh`
2. Implement a function named `guard_your_guard` that takes a file path as argument
3. Use `_report_finding` to report violations
4. Use `_is_whitelisted` to check whitelist before reporting
5. Use `_guard_log` for telemetry
6. Add config entry in `iron-dome.yml` (default: `enabled: false` for new guards)
7. Add to the hook file (`pre-commit` or `pre-push`) behind `_is_guard_enabled` check
8. Write tests in `tests/test_your_guard.sh`
9. Update README and CHANGELOG

### Guard template

```bash
#!/usr/bin/env bash
# Guard: Your Guard Name
# Hook: pre-commit
# Default: opt-in (enabled: false)

guard_your_guard() {
  local file="$1"

  # Skip whitelisted files
  if _is_whitelisted "your_guard" "$file"; then return 0; fi

  # Your detection logic here
  # ...

  if [[ $violations -gt 0 ]]; then
    _report_finding "YOUR_GUARD" "Description" "$file" "$line_number"
    _guard_log "your_guard" "blocking" "detail"
    return 1
  fi

  return 0
}
```

## Code Style

- **Bash 4+** — no bashisms that break on older versions, but associative arrays are OK
- **`set -euo pipefail`** at the top of every script
- **Lowercase variables** for locals, **UPPER_CASE** for globals/constants
- **Functions** prefixed with `_` are internal (not called directly by users)
- **Guard functions** are prefixed with `guard_`
- **No external dependencies** — bash, git, grep only. Python3 is optional and isolated.
- Keep guards under 100 lines. If it needs more, reconsider the approach.

## Pull Request Process

1. Fork the repo and create a feature branch from `main`
2. Make your changes
3. Ensure all tests pass: `bash tests/run-tests.sh`
4. Update documentation (README, CHANGELOG) if applicable
5. Open a PR with a clear title and description
6. Link to the issue if applicable

### PR checklist

- [ ] Tests pass locally
- [ ] New guard has tests
- [ ] CHANGELOG updated
- [ ] README updated (if user-facing)
- [ ] No external dependencies added

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
