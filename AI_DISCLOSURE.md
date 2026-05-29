# AI Disclosure

Per the exercise instructions, an honest account of AI use. 

## What I used AI for
- Drafting the scaffold: `docker-compose.yml`, the helper scripts, the
  `policy.hujson` ACL, the demo cockpit, the slide deck, and the docs.
- A sounding board for architecture trade-offs and for debugging three real
  failures (ACL allow-all override, a Docker-bridge path that bypassed the
  tailnet, and userspace-mode networking on Docker Desktop).

## What I reviewed or changed myself
- Ran the stack on my own tailnet and confirmed all six checks pass.
- The AI's config was helpful, but incomplete. Permissions were wrong in several
  places, and significant troubleshooting was required to get the app `up`.
- Confirmed the negative tests genuinely fail (attacker blocked), not pass for
  the wrong reason.

## Where AI was helpful
- Fast, correct boilerplate; quick identification that "no `tailscale0`
  interface" meant userspace mode, which pointed straight at the `serve` + SOCKS5
  fix.

