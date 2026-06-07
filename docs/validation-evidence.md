# Validation evidence

Captured from a real run of `./scripts/doctor.sh` against a live tailnet. All six
checks pass. The diagnostics block shows the actual `tailscale serve` forwarding
rules and confirms userspace networking mode.

```text
A. DIAGNOSTICS
  ····  networking mode: userspace (this build is designed for userspace)
  ····  backend tailnet IP: 100.93.71.122
  ····  serve: |-- tcp://backend.<tailnet>.ts.net:80 (TLS over TCP, tailnet only)
               |-- tcp://100.93.71.122:80
               |--> tcp://127.0.0.1:80
               |-- tcp://backend.<tailnet>.ts.net:5432 (TLS over TCP, tailnet only)
               |-- tcp://100.93.71.122:5432
               |--> tcp://127.0.0.1:5432

B. CHECKS
  PASS  1. developer → dashboard  (HTTP 200 via tailnet serve)
  PASS  2. attacker → dashboard  (blocked by ACL)
  PASS  3. developer → postgres :5432  (reachable over tailnet)
  PASS  4. attacker → postgres :5432  (blocked by ACL)
  PASS  5. backend publishes no host port  (no public attack surface)
  PASS  6. encrypted WireGuard link  (via DERP relay — expected on one host)

RESULT
Passed: 6   Failed: 0
All checks passed — the demo is healthy.
```

## How to reproduce

```bash
./scripts/deploy.sh     # or: ./scripts/doctor.sh once the stack is up
```

## What each check proves

1. **Developer → dashboard** — the authorized node reaches nginx over the
   tailnet (HTTP 200), through `tailscale serve` and the SOCKS5 proxy.
2. **Attacker → dashboard blocked** — the unauthorized node is denied by the
   default-deny ACL. Only trusted because check 1 first proved the service is up.
3. **Developer → database** — the authorized node opens a TCP connection to the
   private Postgres on :5432 over the tailnet.
4. **Attacker → database blocked** — same node, same default-deny.
5. **No host ports** — `docker compose ps` confirms the backend publishes nothing
   to the host or the public internet.
6. **Encrypted link** — a WireGuard session exists (direct, or via an encrypted
   DERP relay; on a single Docker host the relay path is expected).

## Manual spot-checks

```bash
docker compose exec ts-backend tailscale status          # peers + tags
docker compose exec ts-backend tailscale serve status    # what's published
BIP=$(docker compose exec -T ts-backend tailscale ip -4 | tr -d '\r')
docker compose exec client-probe curl --socks5 127.0.0.1:1055 http://$BIP/   # 200
docker compose exec dev-probe    curl --socks5 127.0.0.1:1055 --max-time 8 http://$BIP/  # blocked
```
