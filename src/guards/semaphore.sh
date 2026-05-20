#!/usr/bin/env bash
# Iron Dome — Semaphore Check
# Concurrency control for multi-agent environments.
# Blocks push if another agent/session is working on the repo.
#
# Semaphore file: .semaphore.json in repo root
# Format: {"status":"green|yellow|red","session":"...","agent":"...","since":"..."}
#
# Exit codes: 0=ok, 1=blocked, 2=warning

guard_semaphore() {
  # Escape hatch
  if [[ "${IRON_DOME_SEMAPHORE_SKIP:-}" == "1" ]]; then
    return 0
  fi

  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
  [[ -z "$repo_root" ]] && return 0

  local semaphore_file="${repo_root}/.semaphore.json"
  [[ ! -f "$semaphore_file" ]] && return 0

  # Parse with python3 (portable, no jq dependency)
  local sem_data
  sem_data=$(python3 -c "
import json, sys
try:
    with open('${semaphore_file}', 'r', encoding='utf-8') as f:
        sem = json.load(f)
    status = sem.get('status', 'green')
    session = sem.get('session', '')
    agent = sem.get('agent', '')
    user = sem.get('user', '')
    since = sem.get('since', '')
    note = sem.get('note', '')
    print(f'{status}|{session}|{agent}|{user}|{since}|{note}')
except Exception as e:
    print(f'error|{e}')
" 2>/dev/null) || sem_data="error|parse_failed"

  local sem_status sem_session sem_agent sem_user sem_since sem_note
  IFS='|' read -r sem_status sem_session sem_agent sem_user sem_since sem_note <<< "$sem_data"

  # Parse error = skip (non-blocking on failure)
  [[ "$sem_status" == "error" ]] && return 0

  # Green = free
  [[ "$sem_status" == "green" ]] && return 0

  # Detect current session/agent
  local my_session="${IRON_DOME_SESSION:-}"
  local my_agent="${IRON_DOME_AGENT:-unknown}"

  # RED = always block
  if [[ "$sem_status" == "red" ]]; then
    echo ""
    echo "  SEMAPHORE BLOCK: Repository is in DEPLOY mode!"
    echo "  Session: ${sem_session:-?}  |  Agent: ${sem_agent:-?}  |  User: ${sem_user:-?}"
    echo "  Since:   ${sem_since:-?}"
    [[ -n "$sem_note" ]] && echo "  Note:    $sem_note"
    echo ""
    echo "  Actions:"
    echo "    1. Wait for deploy to finish (semaphore will turn green)"
    echo "    2. Contact $sem_user to check status"
    echo "    3. Emergency bypass: IRON_DOME_SEMAPHORE_SKIP=1 git push"
    echo ""
    _guard_log "semaphore" "blocking" "RED: deploy by ${sem_agent} (${sem_session})"
    return 1
  fi

  # YELLOW — check if it's our session
  if [[ "$sem_status" == "yellow" ]]; then
    # Same session = ok
    if [[ -n "$my_session" ]] && [[ "$my_session" == "$sem_session" ]]; then
      return 0
    fi

    # Same agent, no session = likely us (warn)
    if [[ "$my_agent" == "$sem_agent" ]] && [[ -z "$my_session" ]]; then
      echo ""
      echo "  SEMAPHORE WARNING: Repository has an active session."
      echo "  Session: ${sem_session:-?}  |  Agent: ${sem_agent:-?}"
      echo "  Proceeding because same agent detected."
      echo ""
      return 2
    fi

    # Different session/agent = block
    echo ""
    echo "  SEMAPHORE BLOCK: Repository is occupied!"
    echo "  Session: ${sem_session:-?}  |  Agent: ${sem_agent:-?}  |  User: ${sem_user:-?}"
    echo "  Since:   ${sem_since:-?}"
    echo ""
    echo "  Actions:"
    echo "    1. Coordinate with session $sem_session before proceeding"
    echo "    2. If session is over: echo '{\"status\":\"green\"}' > .semaphore.json"
    echo "    3. Emergency bypass: IRON_DOME_SEMAPHORE_SKIP=1 git push"
    echo ""
    _guard_log "semaphore" "blocking" "YELLOW: occupied by ${sem_agent} (${sem_session})"
    return 1
  fi

  return 0
}
