#!/usr/bin/env bash
# lib.sh — shared helpers. Detects Docker Compose v2 ("docker compose")
# or v1 ("docker-compose") and exposes a `dc` wrapper used by every script.
if docker compose version >/dev/null 2>&1; then
  DC=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  DC=(docker-compose)
else
  DC=()
fi
dc(){ "${DC[@]}" "$@"; }
have_compose(){ [[ ${#DC[@]} -gt 0 ]]; }
