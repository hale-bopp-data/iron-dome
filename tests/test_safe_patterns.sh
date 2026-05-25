#!/usr/bin/env bash
# Iron Dome Tests — Safe Patterns (false-positive suppression)
# PBI #428.

suite "Safe Patterns"

setup_sandbox
reload_core
_build_safe_regex
GHP="gh""p_aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789"
assert_exit_code "env brace \${VAR} is safe"       0 _is_safe_match 'token = ${API_TOKEN}'
assert_exit_code "process.env is safe"             0 _is_safe_match 'const k = process.env.SECRET'
assert_exit_code "os.environ is safe"              0 _is_safe_match 'k = os.environ["SECRET"]'
assert_exit_code "System.getenv is safe"           0 _is_safe_match 'String k = System.getenv("SECRET")'
assert_exit_code "PowerShell \$env: is safe"        0 _is_safe_match 'Write-Output $env:API_KEY'
assert_exit_code "<REDACTED> is safe"              0 _is_safe_match 'password = <REDACTED>'
assert_exit_code ".env.example reference is safe"  0 _is_safe_match 'copy .env.example to .env'
assert_exit_code "your_api_key placeholder is safe" 0 _is_safe_match 'api_key = "your_api_key"'
assert_exit_code "a real GitHub PAT line is NOT safe" 1 _is_safe_match "token = \"$GHP\""
teardown_sandbox