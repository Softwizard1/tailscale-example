#!/usr/bin/env bash
# stop.sh — stop everything. Ephemeral nodes auto-remove from the tailnet.
# Pass --purge to also delete persisted Tailscale state volumes.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
echo "Tearing down + removing state volumes..."
dc down -v
echo "Done. Ephemeral nodes will disappear from the admin console shortly."
