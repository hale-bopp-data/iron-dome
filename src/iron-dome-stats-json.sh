#!/usr/bin/env bash
# ============================================================================
# Iron Dome — Stats JSON Aggregation (PBI #567)
# ============================================================================
# Reads telemetry.jsonl and outputs structured JSON with:
# - Total interventions & blocks
# - Breakdown by guard type, severity, repo
# - Daily trend (last N days)
#
# Usage:
#   bash iron-dome-stats-json.sh [DAYS] [--pretty]
#
# Output: JSON to stdout (pipe to file or jq as needed)
# ============================================================================

set -euo pipefail

DAYS="${1:-30}"
PRETTY="${2:-}"
TELEMETRY_FILE="${IRON_DOME_TELEMETRY_DIR:-$HOME/.iron-dome}/telemetry.jsonl"

if [[ ! -f "$TELEMETRY_FILE" ]]; then
  echo '{"error":"no_telemetry_file","message":"No telemetry data yet.","file":"'"$TELEMETRY_FILE"'"}'
  exit 0
fi

INDENT="None"
if [[ "$PRETTY" == "--pretty" ]]; then
  INDENT="2"
fi

python3 -c "
import json, sys
from datetime import datetime, timedelta
from collections import Counter, defaultdict

days = $DAYS
indent = $INDENT
telemetry_file = '$TELEMETRY_FILE'
cutoff = datetime.utcnow() - timedelta(days=days)

total = 0
by_guard = Counter()
by_severity = Counter()
by_repo = Counter()
daily = defaultdict(lambda: {'total': 0, 'blocking': 0})
blocked = 0

with open(telemetry_file) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
            ts_str = entry.get('ts', '')
            # Parse ISO timestamp (handle both full and short formats)
            try:
                ts = datetime.fromisoformat(ts_str.replace('Z', '+00:00'))
            except:
                ts = datetime.utcnow()

            total += 1
            guard = entry.get('guard', 'unknown')
            sev = entry.get('severity', 'unknown')
            repo = entry.get('repo', 'unknown')

            by_guard[guard] += 1
            by_severity[sev] += 1
            by_repo[repo] += 1

            day_key = ts_str[:10] if len(ts_str) >= 10 else 'unknown'
            daily[day_key]['total'] += 1
            if sev == 'blocking':
                blocked += 1
                daily[day_key]['blocking'] += 1
        except:
            continue

# Build output
result = {
    'generated': datetime.utcnow().isoformat() + 'Z',
    'period_days': days,
    'telemetry_file': telemetry_file,
    'summary': {
        'total_interventions': total,
        'total_blocks': blocked,
        'block_rate': round(blocked / total, 3) if total > 0 else 0,
    },
    'by_guard': dict(by_guard.most_common()),
    'by_severity': dict(by_severity.most_common()),
    'by_repo': dict(by_repo.most_common(20)),
    'daily_trend': dict(sorted(daily.items())),
}

print(json.dumps(result, indent=indent, ensure_ascii=False))
" 2>/dev/null || echo '{"error":"python3_required","message":"Stats require python3."}'
