#!/usr/bin/env bash
# start.sh — start the tailnet + private service, then wait until nodes are online.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

echo "Starting stack..."
dc up -d
dc --profile probe up -d client-probe dev-probe >/dev/null 2>&1 || true

echo "Waiting for nodes to register on the tailnet..."
for node in ts-backend ts-client ts-dev; do
  for i in $(seq 1 30); do
    if dc exec -T "$node" tailscale status >/dev/null 2>&1; then
      printf '  ✓ %s online\n' "$node"; break
    fi
    sleep 2
    [[ $i -eq 30 ]] && { echo "  ✗ $node did not come online — check: dc logs $node"; exit 1; }
  done
done

echo
echo "All nodes up. Tailnet status (from backend):"
dc exec -T ts-backend tailscale status
echo
echo "Now run the health check:  ./scripts/doctor.sh"
