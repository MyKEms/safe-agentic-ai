# CLAUDE.md — Project Context

## What This Is

A containerized, security-first environment for running AI coding agents (Claude Code CLI) safely on macOS, Windows, and Linux.

Two Docker containers:
- **claude-workspace** — Ubuntu 22.04 with Claude CLI, Node 20, Playwright. Has zero direct internet access.
- **claude-proxy** — Squid forward proxy. Allowlist-only egress. Default deny.

The workspace can only reach the internet through the proxy. This makes `--dangerously-skip-permissions` safe: the agent has freedom inside a locked box.

## Architecture

```
Host machine
  └── VS Code Dev Container
        ├── claude-workspace (internal network, no internet)
        │     ├── Claude CLI (ccd = dangerous mode)
        │     ├── Playwright MCP (headless Chromium)
        │     └── /workspace ← shared folder from host
        └── claude-proxy (Squid, allowlist-only)
              └── proxy/allowed-domains.txt
```

## Key Files

| File | Purpose |
|---|---|
| `docker-compose.yml` | Two-container orchestration, env var driven |
| `.devcontainer/Dockerfile` | Workspace image (Node 20, Claude CLI, Playwright) |
| `.devcontainer/devcontainer.json` | VS Code lifecycle hooks |
| `proxy/squid.conf` | Squid ACLs, timeouts for long-running agents |
| `proxy/allowed-domains.txt` | Domain allowlist (~50 entries) |
| `setup.sh` | First-time wizard: platform detection, SSH agent choice, .env generation |
| `scripts/preflight.sh` | Host-side check before build (conflicts, missing .env, Docker status) |
| `scripts/setup-container.sh` | One-time container init (git config, MCP, verification) |
| `scripts/welcome.sh` | Startup banner with status checks |
| `scripts/watchdog.sh` | Auto-restart wrapper for long-running agents |
| `scripts/monitor.sh` | Live dashboard (run from host) |
| `scripts/proxy-ctl.sh` | Add/remove domains, reload proxy, test URLs |
| `scripts/wipe.sh` | Clean reset (soft/hard/nuclear) |
| `.env.example` | Configuration template — user copies to .env |

## Conventions

- All sensitive values (API keys, paths, git identity) live in `.env`, never hardcoded
- `.env` is gitignored — never committed
- Scripts in `scripts/` are mounted read-only into the container
- Proxy config is mounted read-only
- SSH keys are mounted read-only; SSH agent socket is the preferred method
- Container names are `claude-proxy` and `claude-workspace` (hardcoded — preflight.sh detects conflicts)
- All shell scripts use `#!/usr/bin/env bash` and must keep LF line endings (enforced by `.gitattributes`)

## SSH Agent Support

Three providers supported via `setup.sh`:
1. **1Password** — native socket per platform
2. **Keeper PAM** — email-based socket (`~/.keeper/<email>.ssh_agent`)
3. **Custom** — any Unix socket path

The socket is mounted to `/home/vscode/.ssh-agent/agent.sock` inside the container regardless of provider. This is a separate directory from `.ssh` (which is mounted read-only from the host) to avoid mount conflicts.

## Cross-Platform

- macOS (Intel + Apple Silicon): `--platform=linux/amd64` in Dockerfile handles Rosetta
- Windows: Docker Desktop with WSL2 backend, SSH agent via `/run/host-services/ssh-auth.sock`
- Linux: Docker Engine, native paths

## When Editing This Repo

- Do not add hardcoded paths, emails, or credentials — use .env variables
- Do not add company-specific or personal domains to allowed-domains.txt — keep the "ADD YOUR DOMAINS" section for users
- Test changes on both macOS and Windows if touching docker-compose.yml or setup.sh
- Scripts run in two contexts — always check which side before editing:
  - **Host-side:** `setup.sh`, `preflight.sh`, `proxy-ctl.sh`, `monitor.sh`, `wipe.sh` — these call `docker compose` and edit host files
  - **Container-side:** `setup-container.sh`, `welcome.sh`, `watchdog.sh` — these run inside the workspace via devcontainer lifecycle hooks or aliases
- `proxy-ctl.sh` **cannot** run from inside the container — it edits `allowed-domains.txt` on the host and calls `docker compose restart`
