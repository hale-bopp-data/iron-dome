#!/usr/bin/env bash
# Iron Dome Tests — Config Reader & Guard Enable/Disable

suite "Config Reader"

# --- Default config: secrets enabled ---
setup_sandbox
reload_core
_load_config
assert_eq "secrets enabled by default" "true" "${IRON_DOME_GUARD_ENABLED[secrets]}"
teardown_sandbox

# --- Default config: docker_run disabled ---
setup_sandbox
reload_core
_load_config
assert_eq "docker_run disabled by default" "false" "${IRON_DOME_GUARD_ENABLED[docker_run]}"
teardown_sandbox

# --- Default config: debt disabled ---
setup_sandbox
reload_core
_load_config
assert_eq "debt disabled by default" "false" "${IRON_DOME_GUARD_ENABLED[debt]}"
teardown_sandbox

# --- Custom config: disable secrets ---
setup_sandbox
reload_core
cat > iron-dome.yml <<'YAML'
guards:
  secrets:
    enabled: false
  conflict_markers:
    enabled: true
YAML
_load_config
assert_eq "respects secrets: false from YAML" "false" "${IRON_DOME_GUARD_ENABLED[secrets]}"
assert_eq "respects conflict_markers: true from YAML" "true" "${IRON_DOME_GUARD_ENABLED[conflict_markers]}"
teardown_sandbox

# --- Custom config: enable docker_run ---
setup_sandbox
reload_core
cat > iron-dome.yml <<'YAML'
guards:
  docker_run:
    enabled: true
YAML
_load_config
assert_eq "can enable docker_run via YAML" "true" "${IRON_DOME_GUARD_ENABLED[docker_run]}"
teardown_sandbox

# --- _is_guard_enabled works correctly ---
setup_sandbox
reload_core
_load_config
local_result=""
if _is_guard_enabled "secrets"; then local_result="yes"; else local_result="no"; fi
assert_eq "_is_guard_enabled returns true for secrets" "yes" "$local_result"
if _is_guard_enabled "docker_run"; then local_result="yes"; else local_result="no"; fi
assert_eq "_is_guard_enabled returns false for docker_run" "no" "$local_result"
teardown_sandbox

# --- CRLF handling in config ---
setup_sandbox
reload_core
printf "guards:\r\n  secrets:\r\n    enabled: false\r\n" > iron-dome.yml
_load_config
assert_eq "handles CRLF in config file" "false" "${IRON_DOME_GUARD_ENABLED[secrets]}"
teardown_sandbox
