# CLAUDE.md — Project Context

## What This Is

A **template** for creating containerized, security-first environments for running AI coding agents (Claude Code CLI) safely on macOS, Windows, and Linux.

This repo is never used directly as a devcontainer. Run `./setup.sh <path>` to scaffold a new project folder from this template. Each project gets its own `.env`, proxy allowlist, and uniquely named containers.

Two Docker containers per project:
- **\<name\>-workspace** — Ubuntu 24.04 with Claude CLI, Node 20, Playwright. Has zero direct internet access.
- **\<name\>-proxy** — Squid forward proxy. Allowlist-only egress. Default deny.

The workspace can only reach the internet through the proxy. This makes `--dangerously-skip-permissions` safe: the agent has freedom inside a locked box.

## Architecture

```
Host machine
  └── VS Code Dev Container
        ├── <name>-workspace (internal network, no internet)
        │     ├── Claude CLI (ccd = dangerous mode)
        │     ├── Playwright MCP (headless Chromium)
        │     ├── SSH agent socket (1Password / Bitwarden / custom)
        │     └── /workspace ← shared folder from host
        └── <name>-proxy (Squid, allowlist-only)
              └── proxy/allowed-domains.txt
```

## Key Files

| File | Purpose |
|---|---|
| `docker-compose.yml` | Two-container orchestration, env var driven |
| `.devcontainer/Dockerfile` | Workspace image (Node 20, Claude CLI, Playwright) |
| `.devcontainer/devcontainer.json` | VS Code lifecycle hooks |
| `proxy/squid.conf` | Squid ACLs, timeouts for long-running agents |
| `proxy/allowed-domains.txt` | Domain allowlist (~25 entries) |
| `setup.sh` | Template scaffolding (creates project folders) and project configuration wizard |
| `update.sh` | Update existing project with latest template files (preserves .env, domains, workspace) |
| `scripts/preflight.sh` | Host-side check before build (conflicts, missing .env, Docker status) |
| `scripts/setup-container.sh` | One-time container init (git config, MCP, Claude permissions, verification) |
| `scripts/welcome.sh` | Startup banner with status checks |
| `scripts/watchdog.sh` | Auto-restart wrapper for long-running agents |
| `scripts/monitor.sh` | Live dashboard (run from host) |
| `scripts/proxy-ctl.sh` | Add/remove domains, reload proxy, test URLs |
| `scripts/wipe.sh` | Clean reset (soft/hard/nuclear) |
| `.env.example` | Configuration reference — setup.sh generates .env from wizard answers |

## Conventions

- All sensitive values (API keys, paths, git identity) live in `.env`, never hardcoded
- `.env` is gitignored — never committed
- Claude CLI auth: host `~/.claude/` is mounted read-only to `/home/vscode/.claude-host/`. Init scripts copy credentials and settings into the `claude-state` volume on every start. All other CLI state (sessions, memory, projects) lives in the named volume, isolated per project. A stable machine-id is persisted in the volume to prevent auth invalidation across rebuilds.
- Scripts in `scripts/` are mounted read-only into the container
- Proxy config is mounted read-only
- SSH keys are mounted read-only; SSH agent socket is the preferred method
- Container names are `${PROJECT_NAME}-proxy` and `${PROJECT_NAME}-workspace` (derived from `.env`, default `claude`)
- This repo is a template — never open it directly as a devcontainer; use `setup.sh <path>` to create project folders
- Each project must have its own folder — do not share `.env` or `allowed-domains.txt` between projects
- All shell scripts use `#!/usr/bin/env bash` and must keep LF line endings (enforced by `.gitattributes`)

## Claude CLI State & Memory

Two separate `.claude` directories exist inside the container — don't confuse them:

| Path | What it is | Visible in VS Code | Persistent |
|---|---|---|---|
| `/workspace/.claude/` | Project settings (`settings.local.json`) | Yes | In workspace mount |
| `/home/vscode/.claude/` | CLI home (auth, sessions, **memory**, projects) | No | In `claude-state` volume |

Claude Code stores memory, sessions, and project data in its home config dir (`/home/vscode/.claude/projects/-workspace/memory/`), **not** in the workspace. This is by design:
- Memory files are personal AI state, not project code — they don't belong in git
- Each container project gets its own isolated `claude-state` Docker volume
- Auth credentials (`.credentials.json`) are the only thing shared from the host — everything else is container-local

**Wipe impact on memory:**

| Wipe level | Memory | Sessions | Credentials | Workspace |
|---|---|---|---|---|
| **Soft** (`wipe --soft`) | KEPT | Cleared | KEPT | KEPT |
| **Hard** (`wipe --hard`) | **DESTROYED** | **DESTROYED** | KEPT (on host) | KEPT |

Hard wipe runs `docker compose down -v` which destroys the `claude-state` volume. All memory files (MEMORY.md, memory files), session history, and project data are permanently lost. The wipe script warns about this before proceeding.

To inspect memory from inside the container:
```bash
ls /home/vscode/.claude/projects/-workspace/memory/
cat /home/vscode/.claude/projects/-workspace/memory/MEMORY.md
```

## Authentication

**Recommended flow: authenticate on host, share into container.**

1. Run `claude login` on the host — this stores OAuth tokens in `~/.claude/.credentials.json`
2. The credentials file is bind-mounted into the container automatically
3. Claude CLI inside the container uses the shared token — no OAuth needed

**Why not authenticate inside the container?** OAuth callback flow (browser → localhost redirect → CLI) is unreliable through VS Code's port forwarding. The redirect chain can hang because the callback needs to traverse: host browser → VS Code port forward → Docker network → container. Authenticating on the host avoids this entirely.

**Fallback: API key.** Set `ANTHROPIC_API_KEY` in `.env` if OAuth isn't an option.

The `welcome.sh` banner shows auth status on every container start. If it shows "not configured", run `claude login` on the host and restart the container.

## SSH Agent Support

Three providers supported via `setup.sh`:
1. **1Password** — native socket per platform
2. **Bitwarden** — native socket (`~/.bitwarden-ssh-agent.sock` on macOS .dmg / Linux; sandboxed path on macOS App Store). Hidden on Windows because Bitwarden uses a named pipe there, which Docker can't mount.
3. **Custom** — any Unix socket path

The socket is mounted to `/home/vscode/.ssh-agent/agent.sock` inside the container regardless of provider. This is a separate directory from `.ssh` (which is mounted read-only from the host) to avoid mount conflicts.

## Cross-Platform

- macOS (Intel + Apple Silicon): native arm64/amd64, no Rosetta needed. OrbStack recommended over Docker Desktop
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
