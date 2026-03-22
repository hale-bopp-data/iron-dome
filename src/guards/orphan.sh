#!/usr/bin/env bash
# Iron Dome — Orphan Guard
# Blocks push to branches that already have a completed/merged PR.
# Prevents orphan commits that bypass code review.
#
# Supports: GitHub, GitLab, Azure DevOps (auto-detected from remote URL).

guard_orphan() {
  # Escape hatch
  if [[ "${IRON_DOME_ORPHAN_SKIP:-}" == "1" ]]; then
    return 0
  fi

  local branch
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  [[ -z "$branch" ]] && return 0

  # Skip non-feature branches
  if [[ "$branch" == "main" ]] || [[ "$branch" == "master" ]] || [[ "$branch" == "develop" ]]; then
    return 0
  fi
  if [[ "$branch" =~ ^(release|hotfix|merge)/ ]]; then
    return 0
  fi

  # Detect provider from remote URL
  local remote_url
  remote_url=$(git remote get-url origin 2>/dev/null || echo "")
  [[ -z "$remote_url" ]] && return 0

  local provider=""
  local repo_slug=""

  if [[ "$remote_url" =~ github\.com[:/]([^/]+/[^/.]+) ]]; then
    provider="github"
    repo_slug="${BASH_REMATCH[1]}"
  elif [[ "$remote_url" =~ gitlab\.com[:/]([^/]+/[^/.]+) ]]; then
    provider="gitlab"
    repo_slug="${BASH_REMATCH[1]}"
  elif [[ "$remote_url" =~ dev\.azure\.com/([^/]+)/([^/]+)/_git/([^/]+) ]]; then
    provider="ado"
    local ado_org="${BASH_REMATCH[1]}"
    local ado_project="${BASH_REMATCH[2]}"
    local ado_repo="${BASH_REMATCH[3]}"
  elif [[ "$remote_url" =~ /_git/([^/]+)$ ]]; then
    provider="ado"
    ado_repo="${BASH_REMATCH[1]}"
    ado_org="${IRON_DOME_ADO_ORG:-}"
    ado_project="${IRON_DOME_ADO_PROJECT:-}"
  fi

  # Override provider if explicitly set
  [[ -n "${IRON_DOME_ORPHAN_PROVIDER:-}" ]] && provider="$IRON_DOME_ORPHAN_PROVIDER"

  echo "  Orphan Guard: checking PR status for $branch..."

  local pr_status="CLEAN"

  case "$provider" in
    github)
      if command -v gh &>/dev/null; then
        local merged_pr
        merged_pr=$(gh pr list --repo "$repo_slug" --head "$branch" --state merged --json number,title --limit 1 2>/dev/null || echo "")
        if [[ -n "$merged_pr" ]] && [[ "$merged_pr" != "[]" ]]; then
          local pr_num pr_title
          pr_num=$(echo "$merged_pr" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0]['number'] if d else '')" 2>/dev/null || echo "")
          pr_title=$(echo "$merged_pr" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0]['title'][:60] if d else '')" 2>/dev/null || echo "")
          if [[ -n "$pr_num" ]]; then
            pr_status="MERGED|${pr_num}|${pr_title}"
          fi
        fi
      fi
      ;;
    ado)
      if [[ -n "$ado_org" ]] && [[ -n "$ado_project" ]] && [[ -n "$ado_repo" ]]; then
        local ado_result
        ado_result=$(curl -s --max-time 10 \
          -H "Authorization: Bearer ${IRON_DOME_ADO_TOKEN:-${SYSTEM_ACCESSTOKEN:-}}" \
          "https://dev.azure.com/${ado_org}/${ado_project}/_apis/git/repositories/${ado_repo}/pullrequests?searchCriteria.sourceRefName=refs/heads/${branch}&searchCriteria.status=completed&\$top=1&api-version=7.1" \
          2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    prs = data.get('value', [])
    if prs:
        pr = prs[0]
        print(f\"MERGED|{pr['pullRequestId']}|{pr['title'][:60]}\")
    else:
        print('CLEAN')
except:
    print('ERROR')
" 2>/dev/null) || ado_result="ERROR"
        [[ "$ado_result" != "ERROR" ]] && pr_status="$ado_result"
      fi
      ;;
    gitlab)
      # GitLab: use glab CLI if available
      if command -v glab &>/dev/null; then
        local merged_mr
        merged_mr=$(glab mr list --source-branch "$branch" --state merged --per-page 1 2>/dev/null || echo "")
        if [[ -n "$merged_mr" ]] && [[ "$merged_mr" != *"No merge requests"* ]]; then
          pr_status="MERGED|?|$merged_mr"
        fi
      fi
      ;;
  esac

  if [[ "$pr_status" == MERGED* ]]; then
    local pr_id pr_title
    pr_id=$(echo "$pr_status" | cut -d'|' -f2)
    pr_title=$(echo "$pr_status" | cut -d'|' -f3)
    echo ""
    echo "  ORPHAN GUARD: Branch '$branch' has a MERGED PR #${pr_id}!"
    echo "  PR: $pr_title"
    echo ""
    echo "  Pushing here would create orphan commits that bypass code review."
    echo ""
    echo "  Solutions:"
    echo "    1. Create a new branch:  git checkout -b feat/next-change"
    echo "    2. Cherry-pick commits:  git cherry-pick <commit>"
    echo "    3. Emergency bypass:     IRON_DOME_ORPHAN_SKIP=1 git push"
    echo ""
    _guard_log "orphan" "blocking" "branch has merged PR #${pr_id}: ${pr_title}"
    return 1
  fi

  echo "  Orphan Guard: branch is clean."
  return 0
}
