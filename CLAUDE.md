# CLAUDE.md — Project Context

## What This Is

A **template** for creating containerized, security-first environments for running AI coding agents (Claude Code CLI) safely on macOS, Windows, and Linux.

This repo is never used directly as a devcontainer. Run `./setup.sh <path>` to scaffold a new project folder from this template. Each project gets its own `.env`, proxy allowlist, and uniquely named containers.

Two Docker containers per project:
- **\<name\>-workspace** — Ubuntu 22.04 with Claude CLI, Node 20, Playwright, 1Password CLI. Has zero direct internet access.
- **\<name\>-proxy** — Squid forward proxy. Allowlist-only egress. Default deny.

The workspace can only reach the internet through the proxy. This makes `--dangerously-skip-permissions` safe: the agent has freedom inside a locked box.

## Architecture

```
Host machine
  └── VS Code Dev Container
        ├── <name>-workspace (internal network, no internet)
        │     ├── Claude CLI (ccd = dangerous mode)
        │     ├── Playwright MCP (headless Chromium)
        │     ├── 1Password CLI (op)
        │     └── /workspace ← shared folder from host
        └── <name>-proxy (Squid, allowlist-only)
              └── proxy/allowed-domains.txt
```

## Key Files

| File | Purpose |
|---|---|
| `docker-compose.yml` | Two-container orchestration, env var driven |
| `.devcontainer/Dockerfile` | Workspace image (Node 20, Claude CLI, Playwright, 1Password CLI) |
| `.devcontainer/devcontainer.json` | VS Code lifecycle hooks |
| `proxy/squid.conf` | Squid ACLs, timeouts for long-running agents |
| `proxy/allowed-domains.txt` | Domain allowlist (~50 entries) |
| `setup.sh` | Template scaffolding (creates project folders) and project configuration wizard |
| `scripts/preflight.sh` | Host-side check before build (conflicts, missing .env, Docker status) |
| `scripts/setup-container.sh` | One-time container init (git config, 1Password CLI, MCP, Claude permissions, verification) |
| `scripts/welcome.sh` | Startup banner with status checks |
| `scripts/watchdog.sh` | Auto-restart wrapper for long-running agents |
| `scripts/monitor.sh` | Live dashboard (run from host) |
| `scripts/proxy-ctl.sh` | Add/remove domains, reload proxy, test URLs |
| `scripts/wipe.sh` | Clean reset (soft/hard/nuclear) |
| `.env.example` | Configuration reference — setup.sh generates .env from wizard answers |

## Conventions

- All sensitive values (API keys, paths, git identity) live in `.env`, never hardcoded
- `.env` is gitignored — never committed
- Claude CLI credentials are shared from host `~/.claude` via bind mount (login on host, token auto-shared)
- Scripts in `scripts/` are mounted read-only into the container
- Proxy config is mounted read-only
- SSH keys are mounted read-only; SSH agent socket is the preferred method
- Container names are `${PROJECT_NAME}-proxy` and `${PROJECT_NAME}-workspace` (derived from `.env`, default `claude`)
- This repo is a template — never open it directly as a devcontainer; use `setup.sh <path>` to create project folders
- Each project must have its own folder — do not share `.env` or `allowed-domains.txt` between projects
- All shell scripts use `#!/usr/bin/env bash` and must keep LF line endings (enforced by `.gitattributes`)

## 1Password CLI Support

The `op` CLI is installed in the container image. 1Password desktop app integration (biometric) does **not** work cross-platform (macOS host → Linux container). Two working approaches:

1. **Service account token** — set `OP_SERVICE_ACCOUNT_TOKEN` in `.env`. Best for automation. Usage: `op run --env-file=.env.tpl -- command`
2. **Resolve on host** — run `op read "op://vault/item/field"` on your host (biometric triggers there), pass values as env vars into the container.

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
