#!/usr/bin/env python3
"""
Demo cockpit server.

Serves ONE page (index.html) and a few JSON endpoints that run the exact same
docker compose / tailscale commands the CLI validation uses — so the live demo
is just clicking buttons. Runs locally on the Mac; nothing is exposed publicly.

Run:  python3 cockpit/server.py     →  open http://127.0.0.1:8700
(Helper: `make demo` does this for you.)
"""
import json
import os
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # project root
HERE = os.path.dirname(os.path.abspath(__file__))
PORT = int(os.environ.get("COCKPIT_PORT", "8700"))


def sh(args, timeout=30):
    """Run a command in the project dir; return (rc, stdout, stderr)."""
    try:
        p = subprocess.run(
            args, cwd=ROOT, capture_output=True, text=True, timeout=timeout
        )
        return p.returncode, p.stdout.strip(), p.stderr.strip()
    except subprocess.TimeoutExpired:
        return 124, "", "timed out"
    except Exception as e:  # noqa: BLE001
        return 1, "", str(e)


def _compose_cmd():
    """Detect Docker Compose v2 ('docker compose') or v1 ('docker-compose')."""
    for cmd in (["docker", "compose"], ["docker-compose"]):
        try:
            r = subprocess.run(cmd + ["version"], capture_output=True, timeout=10)
            if r.returncode == 0:
                return cmd
        except Exception:  # noqa: BLE001
            continue
    return ["docker", "compose"]  # fall back; errors surface in checks


COMPOSE = _compose_cmd()


def dc(*args, timeout=30):
    return sh([*COMPOSE, *args], timeout=timeout)


def check_status():
    rc, out, err = dc("exec", "-T", "ts-backend", "tailscale", "status", "--json")
    if rc != 0:
        return {"ok": False, "detail": err or "backend not up", "peers": []}
    data = json.loads(out)
    peers = []
    self_ = data.get("Self", {})
    everyone = [self_] + list(data.get("Peer", {}).values())
    for n in everyone:
        peers.append({
            "host": n.get("HostName", "?"),
            "ip": (n.get("TailscaleIPs") or ["—"])[0],
            "online": bool(n.get("Online", n is self_)),
            "tags": [t.replace("tag:", "") for t in (n.get("Tags") or [])],
        })
    return {"ok": True, "peers": peers, "fqdn": self_.get("DNSName", "").rstrip(".")}


def ensure_probes():
    dc("--profile", "probe", "up", "-d", "client-probe", "dev-probe", timeout=60)


SOCKS = "127.0.0.1:1055"   # each node's tailscaled outbound proxy


def backend_ip():
    rc, out, _ = dc("exec", "-T", "ts-backend", "tailscale", "ip", "-4")
    return out.strip().splitlines()[0].strip() if rc == 0 and out.strip() else None


def web(probe, ip):
    """HTTP code from <probe> to the backend dashboard, through SOCKS."""
    rc, out, _ = dc("exec", "-T", probe, "curl", "-s", "-o", "/dev/null",
                    "-w", "%{http_code}", "--socks5", SOCKS, "--max-time", "12",
                    f"http://{ip}:80/", timeout=25)
    return out.strip()


def tcp_ok(probe, ip, port="5432"):
    """True if <probe> can open a TCP connection to the port through SOCKS."""
    rc, _, _ = dc("exec", "-T", probe, "nc", "-X", "5", "-x", SOCKS,
                  "-z", "-w", "8", ip, port, timeout=25)
    return rc == 0


def check_web_positive():
    ensure_probes()
    ip = backend_ip()
    if not ip:
        return {"ok": False, "detail": "backend tailnet IP unavailable — is the stack up?"}
    dc("exec", "-T", "ts-client", "tailscale", "ping", "--c", "5", ip, timeout=25)
    code = "000"
    for _ in range(4):
        code = web("client-probe", ip)
        if code == "200":
            break
    return {"ok": code == "200", "code": code,
            "detail": f"developer → dashboard via tailnet serve returned HTTP {code or 'no response'}"}


def check_web_negative():
    ensure_probes()
    ip = backend_ip()
    if not ip:
        return {"ok": False, "detail": "backend tailnet IP unavailable"}
    blocked = web("dev-probe", ip) != "200"
    return {"ok": blocked,
            "detail": "attacker → dashboard blocked by ACL" if blocked
                      else "attacker REACHED dashboard — ACL not enforcing!"}


def check_db_positive():
    ensure_probes()
    ip = backend_ip()
    if not ip:
        return {"ok": False, "detail": "backend tailnet IP unavailable"}
    reachable = tcp_ok("client-probe", ip)
    return {"ok": reachable,
            "detail": "developer → private postgres :5432 reachable over the tailnet"
                      if reachable else "developer could not reach postgres :5432"}


def check_db_negative():
    ensure_probes()
    ip = backend_ip()
    if not ip:
        return {"ok": False, "detail": "backend tailnet IP unavailable"}
    blocked = not tcp_ok("dev-probe", ip)
    return {"ok": blocked,
            "detail": "attacker → postgres blocked by ACL" if blocked
                      else "attacker REACHED postgres — ACL not enforcing!"}


def check_isolation():
    rc, out, _ = dc("ps", "--format", "{{.Publishers}}", "ts-backend")
    exposed = out.strip().strip("[]").strip()
    return {"ok": exposed == "",
            "detail": "backend publishes no host/public port"
                      if not exposed else f"published ports found: {exposed}"}


def check_path():
    """An encrypted tailnet link exists. Direct OR DERP relay both count —
    on a single Docker host, NAT punching fails and DERP relays the (still
    encrypted) traffic, which is expected, not a failure."""
    ip = backend_ip()
    if not ip:
        return {"ok": False, "detail": "backend tailnet IP unavailable"}
    rc, out, _ = dc("exec", "-T", "ts-client", "tailscale", "ping", "--c", "3", ip, timeout=25)
    low = out.lower()
    if rc == 0 and "direct" in low:
        return {"ok": True, "detail": "direct peer-to-peer WireGuard tunnel"}
    if rc == 0 or "derp" in low:
        return {"ok": True, "detail": "encrypted link via DERP relay (expected on one host)"}
    return {"ok": False, "detail": "no encrypted link to backend yet (nodes negotiating)"}


CHECKS = {
    "status": check_status,
    "web_positive": check_web_positive,
    "web_negative": check_web_negative,
    "db_positive": check_db_positive,
    "db_negative": check_db_negative,
    "isolation": check_isolation,
    "path": check_path,
}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):  # quiet
        pass

    def _send(self, code, body, ctype="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.end_headers()
        self.wfile.write(body if isinstance(body, bytes) else body.encode())

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            with open(os.path.join(HERE, "index.html"), "rb") as f:
                return self._send(200, f.read(), "text/html; charset=utf-8")
        if self.path.startswith("/api/check/"):
            name = self.path.rsplit("/", 1)[-1]
            fn = CHECKS.get(name)
            if not fn:
                return self._send(404, json.dumps({"ok": False, "detail": "unknown check"}))
            return self._send(200, json.dumps(fn()))
        return self._send(404, json.dumps({"ok": False, "detail": "not found"}))


if __name__ == "__main__":
    print(f"Demo cockpit → http://127.0.0.1:{PORT}   (Ctrl-C to stop)")
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
