# safe-agentic-ai

A containerized, security-first setup for running AI coding agents (Claude Code CLI) safely on your machine.

## Architecture

```
                         Internet
                            |
                     [ proxy-egress ]
                            |
                   +------------------+
                   |  claude-proxy    |
                   |  (Squid)         |
                   |  allowlist-only  |
                   |  default: DENY   |
                   +------------------+
                            |
                     [ claude-net ]          (no internet)
                            |
                   +------------------+
                   |  claude-workspace|
                   |  Ubuntu 22.04   |
                   |  Node 20        |      workspace/
                   |  Claude CLI     |  <-- mounted from host
                   |  Playwright     |
                   +------------------+
                            |
                     SSH agent socket
                     (1Password / Keeper / custom)
```

Two Docker networks. The workspace container has **zero direct internet access** -- every outbound request must pass through the Squid proxy, which enforces a domain allowlist (~50 domains). Anything not on the list is dropped.

This means `--dangerously-skip-permissions` is safe to use: the agent has freedom inside a locked box.

## Prerequisites

1. **Docker Desktop** — [docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop/) (macOS, Windows, Linux)
2. **VS Code** — [code.visualstudio.com/Download](https://code.visualstudio.com/Download)
3. **Dev Containers extension** — install from VS Code: `ms-vscode-remote.remote-containers`
4. **Claude CLI** (optional, for host-side debugging) — `npm install -g @anthropic-ai/claude-code` or `brew install claude-code`

## Quick Start

**Step 1 — Clone the template (once):**

```bash
git clone https://github.com/MyKEms/safe-agentic-ai.git
cd safe-agentic-ai
```

**Step 2 — Create a project:**

macOS / Linux:
```bash
./setup.sh ~/my-project-agent
```

Windows (run from **Git Bash** or **WSL**, not PowerShell/CMD):
```bash
bash setup.sh ~/my-project-agent
```

This copies the template to a new folder, runs the configuration wizard, and initializes a git repo. Each project gets its own `.env`, proxy allowlist, and uniquely named containers.

**Step 3 — Open the project in VS Code:**

```bash
code ~/my-project-agent
```

Then: `Cmd+Shift+P` (macOS) or `Ctrl+Shift+P` (Windows) → type **"Dev Containers: Reopen in Container"** → Enter.

Wait for the build to finish (first time takes ~2 minutes, subsequent starts are instant).

**Step 3 — Open a terminal inside the container:**

VS Code will show several terminal tabs at the bottom (Configuring..., Dev Containers). **Ignore those** — they are build logs.

Click the **`+`** button in the terminal panel to open a new terminal. You're now inside the container at `/workspace`.

**Step 4 — Start Claude:**

```bash
ccd
```

This launches Claude CLI in autonomous mode (`--dangerously-skip-permissions` — safe because you're inside the isolated container).

On first run, Claude will ask you to authenticate. Follow the browser link, paste the code back. Your token is stored in `~/.claude` (shared from host) and persists across restarts.

**Step 5 — Switch to the best model:**

Inside Claude CLI, type:

```
/model
```

Select **Opus** (usually the default), then press the **right arrow key** to set effort to **MAX**.

You're ready. Start prompting.

> **Tip:** If Claude auth fails from inside the container (browser redirect doesn't work), run `claude login` on your **host machine** first — the token is shared via the mount.

## Template vs Project

This repo is a **template**. You never open it directly in VS Code Dev Containers. Instead, `setup.sh` creates a new project folder from it.

```
safe-agentic-ai/              ← template (keep clean, update with git pull)
  └── setup.sh                ← creates project folders

~/my-project-agent/           ← project #1 (has its own .env, containers, allowlist)
~/another-project-agent/      ← project #2 (fully independent)
```

Each project gets:
- Its own `.env` with credentials and paths
- Its own `proxy/allowed-domains.txt` with project-specific domains
- Uniquely named containers (`<name>-workspace`, `<name>-proxy`) so multiple projects run side by side
- Its own git repo for tracking config changes

**To reconfigure** an existing project, run `./setup.sh` inside the project folder (it detects `.env` and enters reconfigure mode).

**Do not:**
- Open the template folder as a devcontainer
- Copy `.env` between projects
- Share `allowed-domains.txt` between projects

## What's Inside

| Component | Purpose |
|---|---|
| `claude-proxy` | Squid forward proxy, allowlist-only egress, default deny |
| `claude-workspace` | Ubuntu 22.04 + Node 20 + Claude CLI + Playwright |
| `claude-net` | Internal Docker network (no internet) |
| `proxy-egress` | Proxy-only network with internet access |
| `workspace/` | Shared folder between host and container |
| `.claude/settings.local.json` | Claude CLI permission grants |
| `proxy/allowed-domains.txt` | Domain allowlist for egress |

## How It Works

The security model is simple:

1. **Network isolation.** The workspace container is on `claude-net`, which has no route to the internet. The only peer on that network is the proxy container.

2. **Allowlist-only egress.** The proxy container runs Squid configured with `allowed-domains.txt`. HTTP, HTTPS, and SSH CONNECT requests are checked against this list. Everything else is denied.

3. **Resource limits.** Memory and CPU caps are enforced via Docker Compose, configurable in `.env`.

4. **SSH tunneling.** SSH connections route through Squid CONNECT to trusted hosts only. Your private keys never leave your password manager -- only the agent socket is mounted.

5. **No credential leakage.** API keys are injected via environment variables at runtime, never baked into the image.

The result: Claude CLI can run with full permissions (`--dangerously-skip-permissions`) because the blast radius is contained. It can read, write, and execute anything inside the container -- but it can only reach the domains you explicitly allow.

## Aliases & Commands

Available inside the workspace container:

| Alias | Expands to | Use case |
|---|---|---|
| `cc` | `claude` | Interactive coding session |
| `ccd` | `claude --dangerously-skip-permissions` | Autonomous mode (safe in this container) |
| `ccw` | watchdog mode via `watchdog.sh` | Auto-restart on crash, long-running agents |
| `cch "task"` | headless autonomous agent | Fire-and-forget tasks |

## Proxy Management

> **Run from the host**, not from inside the container. The script edits the allowlist file on the host and calls `docker compose` to reload the proxy.

```bash
# List currently allowed domains
./scripts/proxy-ctl.sh list

# Add a domain
./scripts/proxy-ctl.sh add .pypi.org

# Remove a domain
./scripts/proxy-ctl.sh remove .example.com

# Test if a URL is reachable through the proxy
./scripts/proxy-ctl.sh test https://api.anthropic.com

# Tail proxy logs
./scripts/proxy-ctl.sh logs
```

Changes take effect after reload. No container restart needed.

## Monitor

Run the live dashboard from your **host machine** to watch container activity:

```bash
./scripts/monitor.sh            # single snapshot
./scripts/monitor.sh --loop     # live refresh (default 5s)
./scripts/monitor.sh --loop 3   # refresh every 3s
```

Shows resource usage, proxy logs, active connections, and blocked requests in real time.

## Wipe & Reset

Three levels of cleanup via `wipe.sh`:

| Level | What it does |
|---|---|
| `--soft` | Clears container sessions, watchdog logs, MCP config. Host sessions untouched. |
| `--hard` | Soft + destroys containers, volumes, images. Full rebuild needed. Host sessions safe. |
| `--nuclear` | Hard + clears host `~/.claude` sessions too. **Affects host Claude CLI.** |

```bash
./scripts/wipe.sh --soft
./scripts/wipe.sh --hard
./scripts/wipe.sh --nuclear
```

**Never touched** by any level: `~/.claude/.credentials.json`, `~/.claude/settings.json`, `~/.ssh/`, your workspace repos.

## Authentication

**OAuth (recommended):**

```bash
# Inside the container:
claude login
```

Follow the browser flow. The token is stored in `~/.claude` (mounted from host) and survives restarts.

**API key fallback:**

Set `ANTHROPIC_API_KEY` in `.env`. The key is injected as an environment variable at runtime -- never written to disk inside the container.

## SSH Agent Setup

The container mounts your SSH agent socket so your private keys are never exposed. The `setup.sh` wizard asks which provider you use.

### 1Password

The most common setup. 1Password exposes an SSH agent socket that the container uses directly.

| Platform | Socket path |
|---|---|
| macOS | `~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock` |
| Windows | `/run/host-services/ssh-auth.sock` (Docker Desktop forwards it) |
| Linux | `~/.1password/agent.sock` |

**Prerequisites:**
- 1Password → Settings → Developer → **"Use the SSH Agent"** enabled
- (Recommended) Enable "Ask approval for each new application" for biometric prompts on key use
- Windows: Docker Desktop → Settings → Resources → WSL Integration enabled

### Keeper PAM

Keeper Commander CLI exposes an SSH agent via email-based socket naming.

| Platform | Socket path |
|---|---|
| macOS/Linux | `~/.keeper/<your-email>.ssh_agent` |
| Windows | Not currently supported for Docker socket mounting |

**Prerequisites:**
- Keeper Commander CLI installed
- Start the agent: `keeper ssh-agent start`
- Docs: https://docs.keeper.io/en/keeperpam/commander-cli/command-reference/connection-commands/ssh-agent

### Custom / Other

Any SSH agent that exposes a Unix socket works. Set `SSH_AGENT_SOCK_HOST` in `.env` to your socket path.

### Without SSH Agent

If you skip the SSH agent, key-based git operations (push, pull over SSH) won't work from inside the container. Use HTTPS remotes instead, or mount `~/.ssh` and configure keys manually.

## Cross-Platform Notes

| | macOS | Windows | Linux |
|---|---|---|---|
| Docker runtime | Docker Desktop or Colima | Docker Desktop (WSL2 backend) | Docker Engine |
| Apple Silicon | Rosetta emulation (automatic) | N/A | N/A |
| SSH socket | 1Password / Keeper native path | Docker Desktop forwarded socket | `SSH_AUTH_SOCK` |
| Resources | Configurable in `.env` | Configurable in `.env` | Configurable in `.env` |
| Setup | `./setup.sh` | `bash setup.sh` (Git Bash or WSL) | `./setup.sh` |

The `setup.sh` wizard auto-detects your platform and generates the correct `.env` configuration.

**Windows notes:**
- Run `setup.sh` from Git Bash or WSL2 terminal
- Docker Desktop must be running with WSL2 backend
- For 1Password SSH agent forwarding, enable WSL Integration in Docker Desktop settings

## Troubleshooting

> **Best debugging tip:** If something isn't working, open a **regular terminal on your host** and ask Claude CLI (without dangerous mode) to help you debug. Paste the error, describe what happened — it will read docker logs, inspect configs, and fix the issue for you. This is the fastest way to solve any devcontainer problem. Example:
>
> ```bash
> # On your host (not inside the container):
> claude
> # Then paste: "My devcontainer failed to start, here's the error: ..."
> ```
>
> The host-side Claude runs in safe/restrictive mode and has access to your docker-compose, logs, and scripts. It can diagnose and fix most issues in a few prompts.

**Playwright / browser errors: `ERR_TUNNEL_CONNECTION_FAILED`**

This is the proxy working as intended. The domain you're trying to reach is not in `proxy/allowed-domains.txt`. Playwright routes all traffic through Squid — if a domain isn't allowlisted, it gets blocked.

Add the domain **from the host**:

```bash
./scripts/proxy-ctl.sh add .the-domain.com
```

Then retry inside the container. No restart needed.

**VS Code extension errors: `Unexpected HTTP response: 403`**

These are harmless. VS Code tries to check for extension updates through the proxy, and the marketplace domains are not on the allowlist. Extensions still install correctly because VS Code downloads them on the host and forwards them into the container. You can safely ignore these 403 errors.

**Container won't start**

```bash
docker compose logs claude-workspace
docker compose logs claude-proxy
```

Check for port conflicts (Squid default: 3128) or missing `.env` file. If stuck, ask Claude on the host to help — paste the error and it will diagnose it.

**"Connection refused" from workspace**

The proxy isn't running or the internal network isn't configured. Verify both containers are on `claude-net`:

```bash
docker network inspect claude-net
```

**Domain blocked (HTTP 403 from proxy)**

The domain isn't in `proxy/allowed-domains.txt`. Add it **from the host** (not from inside the container):

```bash
./scripts/proxy-ctl.sh add .the-domain.com
```

**Claude CLI can't authenticate**

Run `claude login` again inside the container. If using an API key, check that `ANTHROPIC_API_KEY` is set in `.env` and restart the container after changing it.

**SSH not working**

1. Verify your SSH agent is running on the host (`ssh-add -l`).
2. Check the socket path in `.env` matches your actual agent socket.
3. Test from inside the container: `ssh -T git@github.com`
4. Check proxy logs for blocked CONNECT requests: `./scripts/proxy-ctl.sh logs`

**Apple Silicon: slow or crashing**

The container runs under Rosetta (`--platform=linux/amd64`). This is expected. If performance is a problem, re-run `./setup.sh` and choose arm64 native mode (no Playwright), or increase the memory limit in `.env`.

**Monitor script shows nothing**

Run `monitor.sh` from the **host**, not from inside the container.

**General debugging**

When in doubt, open a terminal on your host machine and run `claude` (safe mode). Describe the problem, paste the error. It can read your docker-compose.yml, check container logs, inspect proxy config, and suggest fixes. This is faster than manual debugging and safer than trying to fix things from inside the container.

## Files

```
safe-agentic-ai/
├── .devcontainer/
│   ├── Dockerfile              # Ubuntu 22.04, Node 20, Claude CLI, Playwright
│   └── devcontainer.json       # VS Code dev container config
├── proxy/
│   ├── squid.conf              # Squid proxy (allowlist-only, default deny)
│   └── allowed-domains.txt     # Domain allowlist (~50 domains)
├── scripts/
│   ├── setup-container.sh      # One-time postCreateCommand
│   ├── welcome.sh              # Startup banner (postStartCommand)
│   ├── watchdog.sh             # Auto-restart wrapper for long agents
│   ├── monitor.sh              # Live dashboard (run from host)
│   ├── proxy-ctl.sh            # Manage proxy allowlist
│   └── wipe.sh                 # Clean reset (3 levels: soft/hard/nuclear)
├── workspace/                  # Shared folder (host <-> container)
├── docker-compose.yml          # Two containers: proxy + workspace
├── .env.example                # Configuration template
├── setup.sh                    # First-time setup wizard
└── README.md
```

## License

MIT
