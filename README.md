# safe-agentic-ai

A containerized, security-first setup for running AI coding agents (Claude Code CLI) safely on your machine.

<p align="center">
    <img src="https://github.com/user-attachments/assets/698bcf98-43cd-40eb-8e43-b84f3ec52331" width="25%">
</p>


## Why This Exists

I created this because I wanted an AI coding assistant that can work on my projects autonomously - without installing random packages on my machine, without reaching servers I didn't approve, without me watching every step. Something simple but safe.

The only technology needed is **Dev Containers** - a standard supported natively by VS Code (and other editors like JetBrains, Codespaces, etc.). No custom frameworks, no orchestration platforms, no cloud services. Just Docker and a proxy.

### The mindset

**One project = one VS Code workspace = one Dev Container = one isolated environment.**

Each project gets its own sandboxed container where Claude Code CLI runs with full permissions (`--dangerously-skip-permissions`). This is safe because the container has no direct internet access - everything goes through an allowlist-only proxy. Claude can read, write, and execute anything inside the container, but it can only reach the domains you explicitly allow.

You give Claude a task. It works on it. You close VS Code, come back later, and pick up where you left off - Claude remembers the context, your decisions, and the project state.

**Important rule: always work inside the Dev Container, never mix environments.** Don't run Claude CLI on your host for a project that has a Dev Container. Don't mix host-side and container-side Claude sessions for the same project. The Dev Container is the workspace - open it in VS Code, work there, keep it clean. This avoids session conflicts, memory confusion, and ensures the security isolation actually works.

### What it is

- A single AI agent per project, working independently inside a container
- Full autonomous mode - safe because the container is network-isolated
- Each project gets its own workspace, proxy allowlist, and persistent Claude memory
- Simple to set up: clone, run `setup.sh`, open in VS Code

### What it is not

- Not a multi-agent coordination platform
- Not an AI framework or SDK
- Not a cloud deployment tool

### Memory isolation

Each project has its own Docker volume (`claude-state`) where Claude stores memory - MEMORY.md, session history, learned preferences, project-specific knowledge. These are **never shared between projects**. When you switch between projects, each Claude instance remembers only its own context. Think of it as having a dedicated developer assistant per project who knows that project's codebase, conventions, and history - and nothing else.

## Architecture

```
                         Internet
                            |
                     [ proxy-egress ]
                            |
                   +------------------+
                   |  <name>-proxy    |
                   |  (Squid)         |
                   |  allowlist-only  |
                   |  default: DENY   |
                   +------------------+
                            |
                     [ claude-net ]          (no internet)
                            |
                   +------------------+
                   |  <name>-workspace|
                   |  Ubuntu 24.04   |
                   |  Node 20        |      workspace/
                   |  Claude CLI     |  <-- mounted from host
                   |  Playwright     |
                   |  1Password CLI  |
                   +------------------+
                            |
                     SSH agent + 1Password sockets
                     (1Password / Keeper / custom)
```

Two Docker networks. The workspace container has **zero direct internet access** - every outbound request must pass through the Squid proxy, which enforces a domain allowlist (~50 domains). Anything not on the list is dropped.

This means `--dangerously-skip-permissions` is safe to use: the agent has freedom inside a locked box.

## Prerequisites

1. **Docker runtime** - one of:
   - **OrbStack** (recommended for macOS) - [orbstack.dev](https://orbstack.dev/) - faster, lighter, drop-in Docker Desktop replacement
   - **Docker Desktop** - [docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop/) (macOS, Windows, Linux)
2. **VS Code** - [code.visualstudio.com/Download](https://code.visualstudio.com/Download)
3. **Dev Containers extension** - install from VS Code: `ms-vscode-remote.remote-containers`
4. **Claude CLI** (optional, for host-side debugging) - `npm install -g @anthropic-ai/claude-code` or `brew install claude-code`

## Quick Start

**Step 1 - Clone the template (once):**

```bash
git clone https://github.com/MyKEms/safe-agentic-ai.git
cd safe-agentic-ai
```

**Step 2 - Create a project:**

macOS / Linux:
```bash
./setup.sh ~/my-project-agent
```

Windows (run from **Git Bash** or **WSL**, not PowerShell/CMD):
```bash
bash setup.sh ~/my-project-agent
```

This copies the template to a new folder, runs the configuration wizard, and initializes a git repo. Each project gets its own `.env`, proxy allowlist, and uniquely named containers.

**Step 3 - Open the project in VS Code:**

```bash
code ~/my-project-agent
```

Then: `Cmd+Shift+P` (macOS) or `Ctrl+Shift+P` (Windows) → type **"Dev Containers: Reopen in Container"** → Enter.

Wait for the build to finish (first time takes ~2 minutes, subsequent starts are instant).

**Step 4 - Open a terminal inside the container:**

VS Code will show several terminal tabs at the bottom (Configuring..., Dev Containers). **Ignore those** - they are build logs.

Click the **`+`** button in the terminal panel to open a new terminal. You're now inside the container at `/workspace`.

**Step 5 - Start Claude:**

```bash
ccd
```

This launches Claude CLI in autonomous mode (`--dangerously-skip-permissions` - safe because you're inside the isolated container).

On first run, Claude will ask you to authenticate. Follow the browser link, paste the code back. Your token persists across container restarts and rebuilds.

**Step 6 - Pick a model and start prompting:**

Inside Claude CLI, type `/model` to select your preferred model and effort level. You're ready to go.

> **Tip:** For smoother auth, run `claude login` on your **host machine** first - credentials are automatically copied into the container on every start. See [Authentication](#authentication) for details.

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
- Its own `claude-state` Docker volume with isolated Claude memory (MEMORY.md, sessions, preferences) - never shared between projects
- Its own git repo for tracking config changes

**To reconfigure** an existing project, run `./setup.sh` inside the project folder (it detects `.env` and enters reconfigure mode).

**To update** an existing project with the latest template (new Dockerfile, scripts, etc.):
```bash
cd ~/safe-agentic-ai
git pull                              # get latest template
./update.sh ~/my-project-agent        # sync infrastructure files
# then rebuild container in VS Code
```
Your `.env`, custom domains, and workspace files are preserved.

**Do not:**
- Open the template folder as a devcontainer
- Copy `.env` between projects
- Share `allowed-domains.txt` between projects

## What's Inside

| Component | Purpose |
|---|---|
| `<name>-proxy` | Squid forward proxy, allowlist-only egress, default deny |
| `<name>-workspace` | Ubuntu 24.04 + Node 20 + Claude CLI + Playwright + 1Password CLI |
| `claude-net` | Internal Docker network (no internet) |
| `proxy-egress` | Proxy-only network with internet access |
| `claude-state` (volume) | Persistent Claude CLI state: memory, sessions, auth tokens |
| `workspace/` | Shared folder between host and container |
| `proxy/allowed-domains.txt` | Domain allowlist for egress |

## How It Works

The workspace container sits on an internal network with **no internet route**. The only way out is through the Squid proxy, which checks every request against `allowed-domains.txt`. Anything not on the list is dropped.

- **Network isolation** - workspace can only talk to the proxy, nothing else
- **Allowlist-only egress** - HTTP, HTTPS, and SSH CONNECT checked against the domain list
- **Resource limits** - memory and CPU caps via Docker Compose (configurable in `.env`)
- **No credential leakage** - API keys injected as env vars at runtime, never baked into the image
- **SSH agent forwarding** - private keys stay in your password manager, only the socket is mounted

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

| Level | What it does | Claude Memory |
|---|---|---|
| `--soft` | Clears sessions, MCP config, temp files | **Kept** |
| `--hard` | Containers, volumes, images destroyed | **Destroyed** |
| `--nuclear` | Everything destroyed | **Destroyed** |

```bash
./scripts/wipe.sh --soft
./scripts/wipe.sh --hard
./scripts/wipe.sh --nuclear
```

Hard and nuclear wipe destroy the `claude-state` volume - all Claude memory (MEMORY.md, memory files), session history, and project data are permanently lost. The script warns before proceeding and shows how to inspect memory first.

**Never touched** by any level: `.env`, `proxy/allowed-domains.txt`, `~/.ssh/`, host `~/.claude/`.

## Authentication

**Recommended: authenticate on host first.**

```bash
# On your host machine (not inside the container):
claude login
```

Host credentials (`~/.claude/`) are mounted read-only into the container and copied into the `claude-state` volume on every start. A stable machine identity is persisted in the volume so auth survives container rebuilds.

On first run in a new project, Claude CLI may still prompt for auth inside the container. After that, the token is stored in the volume and persists across restarts and rebuilds.

**API key fallback:**

Set `ANTHROPIC_API_KEY` in `.env`. The key is injected as an environment variable at runtime - never written to disk inside the container.

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
| Docker runtime | OrbStack (recommended) or Docker Desktop | Docker Desktop (WSL2 backend) | Docker Engine |
| Apple Silicon | Native arm64 (no emulation) | N/A | N/A |
| SSH socket | 1Password / Keeper native path | Docker Desktop forwarded socket | `SSH_AUTH_SOCK` |
| Resources | Configurable in `.env` | Configurable in `.env` | Configurable in `.env` |
| Setup | `./setup.sh <path>` | `bash setup.sh <path>` (Git Bash or WSL) | `./setup.sh <path>` |

The `setup.sh` wizard scaffolds a project folder, auto-detects your platform, and generates the correct `.env` configuration.

**Windows notes:**
- Run `setup.sh` from Git Bash or WSL2 terminal
- Docker Desktop must be running with WSL2 backend
- For 1Password SSH agent forwarding, enable WSL Integration in Docker Desktop settings

## Troubleshooting

> **Best debugging tip:** If something isn't working, open a **regular terminal on your host** and ask Claude CLI (without dangerous mode) to help you debug. Paste the error, describe what happened - it will read docker logs, inspect configs, and fix the issue for you. This is the fastest way to solve any devcontainer problem. Example:
>
> ```bash
> # On your host (not inside the container):
> claude
> # Then paste: "My devcontainer failed to start, here's the error: ..."
> ```
>
> The host-side Claude runs in safe/restrictive mode and has access to your docker-compose, logs, and scripts. It can diagnose and fix most issues in a few prompts.

**Playwright / browser errors: `ERR_TUNNEL_CONNECTION_FAILED`**

This is the proxy working as intended. The domain you're trying to reach is not in `proxy/allowed-domains.txt`. Playwright routes all traffic through Squid - if a domain isn't allowlisted, it gets blocked.

Add the domain **from the host**:

```bash
./scripts/proxy-ctl.sh add .the-domain.com
```

Then retry inside the container. No restart needed.

**VS Code extension errors: `Unexpected HTTP response: 403`**

These are harmless. VS Code tries to check for extension updates through the proxy, and the marketplace domains are not on the allowlist. Extensions still install correctly because VS Code downloads them on the host and forwards them into the container. You can safely ignore these 403 errors.

**Container won't start**

```bash
docker compose logs    # all containers
```

Check for port conflicts (Squid default: 3128) or missing `.env` file. If stuck, ask Claude on the host to help - paste the error and it will diagnose it.

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

First try `claude login` on your **host machine** and restart the container - credentials are copied from host on every start. If that doesn't work, run `claude login` inside the container. If using an API key, check that `ANTHROPIC_API_KEY` is set in `.env` and restart after changing it.

**SSH not working**

1. Verify your SSH agent is running on the host (`ssh-add -l`).
2. Check the socket path in `.env` matches your actual agent socket.
3. Test from inside the container: `ssh -T git@github.com`
4. Check proxy logs for blocked CONNECT requests: `./scripts/proxy-ctl.sh logs`

**Apple Silicon: slow or crashing**

The container runs natively on arm64. If performance is a problem, increase the memory limit in `.env`.

**Monitor script shows nothing**

Run `monitor.sh` from the **host**, not from inside the container.

**General debugging**

When in doubt, open a terminal on your host machine and run `claude` (safe mode). Describe the problem, paste the error. It can read your docker-compose.yml, check container logs, inspect proxy config, and suggest fixes. This is faster than manual debugging and safer than trying to fix things from inside the container.

## Files

```
safe-agentic-ai/
├── .devcontainer/
│   ├── Dockerfile              # Ubuntu 24.04, Node 20, Claude CLI, Playwright, 1Password CLI
│   └── devcontainer.json       # VS Code dev container config
├── proxy/
│   ├── squid.conf              # Squid proxy (allowlist-only, default deny)
│   └── allowed-domains.txt     # Domain allowlist (~50 domains)
├── scripts/
│   ├── preflight.sh            # Host-side checks before build
│   ├── setup-container.sh      # One-time container init (postCreateCommand)
│   ├── welcome.sh              # Startup banner + auth refresh (postStartCommand)
│   ├── watchdog.sh             # Auto-restart wrapper for long agents
│   ├── monitor.sh              # Live dashboard (run from host)
│   ├── proxy-ctl.sh            # Manage proxy allowlist (run from host)
│   └── wipe.sh                 # Clean reset (3 levels: soft/hard/nuclear)
├── workspace/                  # Default shared folder (host <-> container)
├── docker-compose.yml          # Two containers + volumes: proxy + workspace
├── .env.example                # Configuration template
├── setup.sh                    # Template scaffolding + project wizard
├── update.sh                   # Sync latest template into existing projects
└── README.md
```

## License

MIT
