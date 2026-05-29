#!/usr/bin/env bash
# doctor.sh — full health check: diagnostics + the validation suite.
#
# Exits 0 only if ALL functional checks pass. Use this as the single
# "is everything working?" command, in CI, or before a demo.
#
# It runs TWO sections:
#   A. Diagnostics  — networking mode, serve status, tailnet reachability
#   B. Checks (1-6) — the security proofs (developer in, attacker out, etc.)
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

SOCKS=127.0.0.1:1055
pass=0; fail=0
ok(){ printf '\033[32m  PASS\033[0m  %s\n' "$*"; pass=$((pass+1)); }
no(){ printf '\033[31m  FAIL\033[0m  %s\n' "$*"; fail=$((fail+1)); }
inc(){ printf '\033[36m  ····\033[0m  %s\n' "$*"; }
hdr(){ printf '\n\033[1m%s\033[0m\n' "$*"; }

have_compose || { printf '\033[31mDocker Compose not found.\033[0m Run ./bootstrap.sh\n'; exit 1; }

# ---------------------------------------------------------------------------
hdr "A. DIAGNOSTICS"
# ---------------------------------------------------------------------------
if ! dc exec -T ts-backend tailscale status >/dev/null 2>&1; then
  printf '\033[31m  Backend node is not running.\033[0m  Run ./start.sh first.\n'
  printf '  Logs:  %s logs ts-backend\n' "${DC[*]}"
  exit 1
fi

MODE=$(dc exec -T ts-client sh -c 'ip -br addr 2>/dev/null | grep -q tailscale0 && echo kernel || echo userspace')
inc "networking mode: ${MODE} (this build is designed for userspace)"

BACKEND_IP=$(dc exec -T ts-backend tailscale ip -4 2>/dev/null | tr -d '\r' | head -1)
inc "backend tailnet IP: ${BACKEND_IP:-<unresolved>}"

SERVE=$(dc exec -T ts-backend tailscale serve status 2>/dev/null | tr '\n' ' ' | xargs || true)
inc "serve: ${SERVE:-<none — backend will be unreachable; check serve.json>}"

# Bring up probes (curl + nc) and wait for their tools.
dc --profile probe up -d client-probe dev-probe >/dev/null 2>&1 || true
for i in $(seq 1 20); do
  dc exec -T client-probe sh -c 'command -v curl && command -v nc' >/dev/null 2>&1 && break; sleep 1
done
# Warm up the relay session.
dc exec -T ts-client tailscale ping --c 5 "$BACKEND_IP" >/dev/null 2>&1 || true

web(){ dc exec -T "$1" curl -s -o /dev/null -w '%{http_code}' --socks5 "$SOCKS" \
       --max-time 12 "http://${BACKEND_IP}:80/" 2>/dev/null || true; }
tcp(){ dc exec -T "$1" nc -X 5 -x "$SOCKS" -z -w 8 "$BACKEND_IP" 5432 >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
hdr "B. CHECKS"
# ---------------------------------------------------------------------------
WEB_OK=0; DB_OK=0

# 1 — developer reaches dashboard (retry while the DERP relay settles)
code=000; for i in $(seq 1 6); do code=$(web client-probe); [[ "$code" == "200" ]] && break; sleep 3; done
if [[ "$code" == "200" ]]; then ok "1. developer → dashboard  (HTTP $code via tailnet serve)"; WEB_OK=1
else no "1. developer → dashboard  (got '${code:-no response}', wanted 200)"; fi

# 2 — attacker blocked from dashboard
if [[ $WEB_OK -eq 1 && "$(web dev-probe)" != "200" ]]; then ok "2. attacker → dashboard  (blocked by ACL)"
elif [[ $WEB_OK -eq 0 ]]; then no "2. attacker → dashboard  (cannot trust: dashboard down for the developer too)"
else no "2. attacker → dashboard  (REACHED it — ACL not enforcing!)"; fi

# 3 — developer reaches database
if tcp client-probe; then ok "3. developer → postgres :5432  (reachable over tailnet)"; DB_OK=1
else no "3. developer → postgres :5432  (unreachable)"; fi

# 4 — attacker blocked from database
if [[ $DB_OK -eq 1 ]] && ! tcp dev-probe; then ok "4. attacker → postgres :5432  (blocked by ACL)"
elif [[ $DB_OK -eq 0 ]]; then no "4. attacker → postgres  (cannot trust: db down for the developer too)"
else no "4. attacker → postgres  (REACHED it — ACL not enforcing!)"; fi

# 5 — no public attack surface
ports=$(dc ps --format '{{.Publishers}}' ts-backend 2>/dev/null | tr -d '[]' | xargs)
[[ -z "$ports" ]] && ok "5. backend publishes no host port  (no public attack surface)" \
                  || no "5. backend publishes ports: $ports"

# 6 — encrypted tailnet link exists (direct OR relay both count)
out=$(dc exec -T ts-client tailscale ping --c 3 "$BACKEND_IP" 2>/dev/null || true)
if echo "$out" | grep -qi "direct"; then ok "6. encrypted WireGuard link  (direct peer-to-peer)"
elif echo "$out" | grep -qi "DERP"; then ok "6. encrypted WireGuard link  (via DERP relay — expected on one host)"
else no "6. no encrypted link to backend (nodes not negotiating)"; fi

hdr "RESULT"
printf 'Passed: %d   Failed: %d\n' "$pass" "$fail"
if [[ $fail -eq 0 ]]; then printf '\033[32mAll checks passed — the demo is healthy.\033[0m\n'; exit 0
else printf '\033[31mSome checks failed — see above.\033[0m\n'; exit 1; fi
