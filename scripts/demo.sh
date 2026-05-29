#!/usr/bin/env bash
# demo.sh — launch the single-page demo cockpit at http://127.0.0.1:8700
set -euo pipefail
cd "$(dirname "$0")/.."
command -v open >/dev/null && (sleep 1; open http://127.0.0.1:8700) >/dev/null 2>&1 &
exec python3 cockpit/server.py
