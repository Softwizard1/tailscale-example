#!/usr/bin/env bash
# deploy.sh — one command, end to end: preflight → start → health check.
# This is the "give me a working demo from scratch" button.
#
# Prereqs (one-time, done in the Tailscale admin console — see README §5):
#   1. Apply policy.hujson under Access controls.
#   2. Generate a reusable + ephemeral auth key and put it in .env.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "═══ 1/3  Preflight ═══════════════════════════════════════"
bash scripts/bootstrap.sh

echo
echo "═══ 2/3  Start ═══════════════════════════════════════════"
bash scripts/start.sh

echo
echo "═══ 3/3  Health check ════════════════════════════════════"
bash scripts/doctor.sh

echo
echo "Done. Drive the live demo UI with:  ./scripts/demo.sh   (or: make demo)"
