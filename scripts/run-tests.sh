#!/usr/bin/env bash
# Queues a test-suite run in HDBResale_Tests, polls until it finishes, prints
# every result, writes JUnit XML for the CI system and exits non-zero on any
# failure. Runs execute in a timer on the server, so long end-to-end suites
# never hit HTTP request timeouts.
#
#   TESTS_BASE_URL=https://test.example.com/HDBResale_Tests \
#   TEST_API_TOKEN=... ./scripts/run-tests.sh [unit|integration|e2e|contract|all] [junit.xml]
#
# Dev/Test only: the runner refuses unless Site.TestsEnabled = True and the
# X-Test-Token header matches Site.TestApiToken.
set -euo pipefail
PY=""; for c in python3 python; do if "$c" -c "import json" >/dev/null 2>&1; then PY="$c"; break; fi; done
[ -n "$PY" ] || { echo "python3 or python is required" >&2; exit 3; }

: "${TESTS_BASE_URL:?set TESTS_BASE_URL, e.g. https://test.example.com/HDBResale_Tests}"
: "${TEST_API_TOKEN:?set TEST_API_TOKEN from the pipeline secret store}"
SUITE="${1:-all}"
JUNIT="${2:-junit-${SUITE}.xml}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-3300}"
API="${TESTS_BASE_URL%/}/rest/TestRunnerAPI"

run_id=$(curl --fail-with-body -sS --max-time 30 -X POST \
  -H "X-Test-Token: ${TEST_API_TOKEN}" "${API}/runs?suite=${SUITE}")
echo "Queued ${SUITE} as run ${run_id}"

deadline=$(( $(date +%s) + TIMEOUT_SECONDS ))
while :; do
  report=$(curl --fail-with-body -sS --max-time 30 \
    -H "X-Test-Token: ${TEST_API_TOKEN}" "${API}/runs/${run_id}")
  status=$(printf '%s' "$report" | "$PY" -c 'import json,sys; print(json.load(sys.stdin).get("Status",""))')
  case "$status" in
    Done|Error|NotFound) break ;;
  esac
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "Timed out waiting for run ${run_id} (last status: ${status})" >&2
    exit 2
  fi
  sleep 10
done

printf '%s' "$report" | JUNIT="$JUNIT" "$PY" -c '
import json, os, sys
from xml.sax.saxutils import escape, quoteattr
r = json.load(sys.stdin)
results = r.get("Results", []) or []
for t in results:
    print(("PASS " if t.get("Passed") else "FAIL ") + t.get("Suite", "?") + "/" + t.get("TestName", "?") + ": " + t.get("Message", ""))
passed, failed = r.get("PassedCount", 0), r.get("FailedCount", 0)
status, error = r.get("Status"), r.get("ErrorMessage") or ""
print("\nRun " + str(r.get("RunId")) + " [" + str(status) + "]: " + str(passed) + " passed, " + str(failed) + " failed")
if error:
    print("Runner error: " + error, file=sys.stderr)

suites = {}
for t in results:
    suites.setdefault(t.get("Suite", "tests"), []).append(t)
with open(os.environ["JUNIT"], "w", encoding="utf-8") as f:
    f.write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<testsuites>\n")
    for name, cases in suites.items():
        fails = sum(1 for c in cases if not c.get("Passed"))
        f.write("  <testsuite name=" + quoteattr(name) + " tests=\"" + str(len(cases)) + "\" failures=\"" + str(fails) + "\">\n")
        for c in cases:
            msg = c.get("Message", "") or ""
            f.write("    <testcase classname=" + quoteattr("HDBResale." + name) + " name=" + quoteattr(c.get("TestName", "?")) + ">")
            if not c.get("Passed"):
                f.write("<failure message=" + quoteattr(msg[:500]) + ">" + escape(msg) + "</failure>")
            f.write("</testcase>\n")
        f.write("  </testsuite>\n")
    f.write("</testsuites>\n")
print("JUnit report: " + os.environ["JUNIT"])
sys.exit(0 if status == "Done" and failed == 0 and results else 1)
'
