#!/usr/bin/env bash
# Post-deploy gate and canary logic: fails unless /rest/HealthAPI/Health
# reports Status = OK (a snapshot is active and the last successful sync is
# younger than Site.StaleAfterHours).
#
#   CORE_BASE_URL=https://prod.example.com/HDBResale_Core ./scripts/check-health.sh
set -euo pipefail
PY=""; for c in python3 python; do if "$c" -c "import json" >/dev/null 2>&1; then PY="$c"; break; fi; done
[ -n "$PY" ] || { echo "python3 or python is required" >&2; exit 3; }

: "${CORE_BASE_URL:?set CORE_BASE_URL, e.g. https://prod.example.com/HDBResale_Core}"

body=$(curl --fail-with-body -sS --max-time 30 "${CORE_BASE_URL%/}/rest/HealthAPI/Health")

printf '%s' "$body" | "$PY" -c '
import json, sys
h = json.load(sys.stdin)
print(json.dumps(h, indent=2))
if h.get("Status") != "OK":
    status, last, hours = h.get("Status"), h.get("LastSyncStatus"), h.get("HoursSinceSuccess")
    print(f"UNHEALTHY: Status={status}, LastSyncStatus={last}, HoursSinceSuccess={hours}", file=sys.stderr)
    sys.exit(1)
'
