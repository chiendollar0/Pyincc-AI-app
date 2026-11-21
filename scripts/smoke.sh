#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-https://pyincccrm.bothelper.vn}"
BASE_URL="${BASE_URL%/}"

echo "==> Running post-deploy smoke checks against ${BASE_URL}"

check_status() {
  local method="$1"
  local path="$2"
  local expected="$3"
  local body="${4:-}"
  local status

  if [ -n "$body" ]; then
    status="$(curl -sS -o /tmp/smoke_resp.txt -w '%{http_code}' -X "$method" \
      -H 'Content-Type: application/json' -d "$body" "${BASE_URL}${path}")"
  else
    status="$(curl -sS -o /tmp/smoke_resp.txt -w '%{http_code}' -X "$method" "${BASE_URL}${path}")"
  fi

  if [ "$status" != "$expected" ]; then
    echo "FAIL: ${method} ${path} -> HTTP ${status} (expected ${expected})"
    head -c 300 /tmp/smoke_resp.txt || true
    echo ""
    exit 1
  fi
  echo "PASS: ${method} ${path} -> HTTP ${status}"
}

check_status GET /health 200
grep -q '"ok":true' /tmp/smoke_resp.txt || { echo "FAIL: /health missing ok:true"; exit 1; }
echo "PASS: /health payload contains ok:true"

check_status GET /privacy 200
check_status GET /terms 200
check_status GET /data-deletion 200

# Security gates: webhook verify with wrong token must be 403; protected routes without JWT must be 401
check_status GET "/webhook?hub.mode=subscribe&hub.verify_token=invalid-smoke-token&hub.challenge=1234" 403
check_status GET /handoff-cases 401
check_status GET /catalog 401
check_status GET /bookings/reminders 401
check_status POST /api/tryon/generate 401 '{"image_base64":"dGVzdA=="}'

rm -f /tmp/smoke_resp.txt
echo "==> All smoke checks passed."
