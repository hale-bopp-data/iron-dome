#!/usr/bin/env bash
# Iron Dome Tests — Docker Run Guard

suite "Docker Run Guard"

# --- Detects docker run ---
setup_sandbox
reload_core
echo 'docker run -d nginx' > deploy.sh
output=$(guard_docker_run "deploy.sh" 2>&1 || true)
assert_contains "detects docker run in .sh" "DOCKER_RUN" "$output"
teardown_sandbox

# --- Allows docker compose ---
setup_sandbox
reload_core
echo 'docker compose up -d' > deploy.sh
output=$(guard_docker_run "deploy.sh" 2>&1 || true)
assert_not_contains "allows docker compose" "DOCKER_RUN" "$output"
teardown_sandbox

# --- Ignores non-script files ---
setup_sandbox
reload_core
echo 'docker run hello' > notes.txt
output=$(guard_docker_run "notes.txt" 2>&1 || true)
assert_not_contains "ignores non-script files" "DOCKER_RUN" "$output"
teardown_sandbox

# --- Ignores commented lines ---
setup_sandbox
reload_core
echo '# docker run -d nginx' > deploy.sh
output=$(guard_docker_run "deploy.sh" 2>&1 || true)
assert_not_contains "ignores commented docker run" "DOCKER_RUN" "$output"
teardown_sandbox
