#!/usr/bin/env bash
# bootstrap.sh — preflight checks. Fails fast with clear guidance.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

red(){ printf '\033[31m%s\033[0m\n' "$*"; }
grn(){ printf '\033[32m%s\033[0m\n' "$*"; }
ylw(){ printf '\033[33m%s\033[0m\n' "$*"; }

ok=1
check(){ if eval "$2" >/dev/null 2>&1; then grn "✓ $1"; else red "✗ $1"; ok=0; fi; }

echo "── Tailnet demo: preflight ──────────────────────────────"
check "Docker installed"      "command -v docker"
check "Docker daemon running" "docker info"

# Accept EITHER compose v2 (docker compose) or v1 (docker-compose).
if have_compose; then
  grn "✓ Docker Compose present (${DC[*]})"
else
  red "✗ Docker Compose not found (neither 'docker compose' nor 'docker-compose')"
  ylw "   or:  brew install docker-compose"
  ok=0
fi

check "curl available" "command -v curl"
check "jq available"   "command -v jq"

if [[ -f .env ]]; then
  grn "✓ .env present"
  set -a; source .env; set +a
  [[ "${TS_AUTHKEY:-}" == tskey-auth-* ]] && grn "✓ TS_AUTHKEY looks well-formed" \
    || { red "✗ TS_AUTHKEY missing or malformed"; ok=0; }
else
  red "✗ .env missing — run:  cp .env.example .env  then edit it"; ok=0
fi

echo "─────────────────────────────────────────────────────────"
if [[ $ok -eq 1 ]]; then
  grn "Preflight passed. Next:  ./scripts/deploy.sh   (or: make deploy)"
else
  ylw "Fix the ✗ items above, then re-run: ./scripts/bootstrap.sh"
  echo
  ylw "Reminder: apply policy.hujson in the Tailscale admin console first,"
  ylw "so tag:backend / tag:client / tag:dev exist before nodes join."
  exit 1
fi
