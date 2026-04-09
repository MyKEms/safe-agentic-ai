#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# setup.sh – Create and configure Claude Code Sandbox projects
# ─────────────────────────────────────────────────────────────────────────────
# Template mode (no .env): scaffolds a new project folder, then configures it
# Project mode  (.env exists): reconfigures the current project
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

B="\033[1m"
C="\033[36m"
G="\033[32m"
Y="\033[33m"
R="\033[31m"
D="\033[2m"
N="\033[0m"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ─── Scaffold mode (template → new project) ──────────────────────────────
# Triggers when there is no .env (we're in the clean template)
if [ ! -f "$SCRIPT_DIR/.env" ] && [ "${1:-}" != "--configure" ]; then
  echo ""
  echo -e "${B}${C}  Claude Code Sandbox — New Project${N}"
  echo -e "  ====================================="
  echo ""
  echo -e "  This is the template. It will create a new project folder for you."
  echo -e "  ${D}Each project gets its own config, proxy allowlist, and containers.${N}"
  echo ""

  TARGET_DIR="${1:-}"
  if [ -z "$TARGET_DIR" ]; then
    read -rp "  Project folder path (e.g. ~/my-project-agent): " TARGET_DIR
  fi

  if [ -z "$TARGET_DIR" ]; then
    echo -e "  ${R}No path provided. Aborting.${N}"
    exit 1
  fi

  # Expand ~ and make absolute
  if [[ "$TARGET_DIR" == ~* ]]; then
    TARGET_DIR="${TARGET_DIR/#\~/$HOME}"
  fi
  case "$TARGET_DIR" in
    /*) ;; # already absolute
    *)  TARGET_DIR="$(pwd)/$TARGET_DIR" ;;
  esac

  if [ -d "$TARGET_DIR" ] && [ -n "$(ls -A "$TARGET_DIR" 2>/dev/null)" ]; then
    echo -e "  ${R}ERROR: $TARGET_DIR already exists and is not empty.${N}"
    exit 1
  fi

  echo -e "  Creating project at: ${G}$TARGET_DIR${N}"
  echo ""
  mkdir -p "$TARGET_DIR"

  # Copy template files (exclude git history, env, OS artifacts)
  (cd "$SCRIPT_DIR" && tar \
    --exclude='.git' \
    --exclude='.env' \
    --exclude='.DS_Store' \
    --exclude='node_modules' \
    --exclude='__pycache__' \
    -cf - .) | (cd "$TARGET_DIR" && tar xf -)

  chmod +x "$TARGET_DIR/setup.sh" "$TARGET_DIR"/scripts/*.sh 2>/dev/null || true

  # Initialize git repo so config changes are tracked
  (cd "$TARGET_DIR" && git init -q && git add -A && git commit -q -m "Initialize from claude-code-sandbox template")

  echo -e "  ${G}Project scaffolded.${N} Running configuration wizard..."
  echo ""

  # Re-exec setup.sh in the new project folder
  cd "$TARGET_DIR"
  exec bash "$TARGET_DIR/setup.sh" --configure
fi

# Consume --configure flag if present
[ "${1:-}" = "--configure" ] && shift

# ─────────────────────────────────────────────────────────────────────────────
# Configuration wizard — runs inside a project folder
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${B}${C}  Claude Code Sandbox — Project Setup${N}"
echo -e "  ====================================="
echo ""

# ─── Detect platform ─────────────────────────────────────────��──────────────
case "$(uname -s)" in
  Darwin*)  PLATFORM="macos" ;;
  MINGW*|MSYS*|CYGWIN*) PLATFORM="windows" ;;
  Linux*)   PLATFORM="linux" ;;
  *)        PLATFORM="linux" ;;
esac

echo -e "  Platform detected: ${G}${PLATFORM}${N}"
echo ""

# ─── Project name ────────────────────────────────────────────────────────
echo -e "${B}  Project Name${N}"
echo -e "  ${D}Used for container names and identification.${N}"
echo -e "  ${D}Use lowercase, letters/numbers/hyphens only.${N}"
echo ""
PROJECT_DEFAULT=$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')
read -rp "  Project name [$PROJECT_DEFAULT]: " PROJECT_INPUT
PROJECT_NAME="${PROJECT_INPUT:-$PROJECT_DEFAULT}"
# Sanitize
PROJECT_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/^-//' | sed 's/-$//')
echo -e "  Containers will be: ${C}${PROJECT_NAME}-workspace${N}, ${C}${PROJECT_NAME}-proxy${N}"
echo ""

# ─── Platform-specific defaults ─────────────────────────��───────────────────
WORKSPACE_DEFAULT="$(pwd)/workspace"
SSH_PATH_DEFAULT="$HOME/.ssh"

case "$PLATFORM" in
  macos)
    MEMORY_DEFAULT="4G"
    CPUS_DEFAULT="4"
    ;;
  windows)
    MEMORY_DEFAULT="8G"
    CPUS_DEFAULT="4"
    ;;
  linux)
    MEMORY_DEFAULT="4G"
    CPUS_DEFAULT="4"
    ;;
esac

# ─── Git identity ──────────────────────────────────────────────────────────
echo -e "${B}  Git Identity${N} (used for commits inside the container)"
read -rp "  Your name: " GIT_NAME
read -rp "  Your email: " GIT_EMAIL
echo ""

# ─── Paths ──────────────────────────────────────────────────────────────────
echo -e "${B}  Paths${N} (press Enter for defaults)"
read -rp "  Workspace folder [$WORKSPACE_DEFAULT]: " WORKSPACE_INPUT
WORKSPACE="${WORKSPACE_INPUT:-$WORKSPACE_DEFAULT}"

read -rp "  SSH keys folder [$SSH_PATH_DEFAULT]: " SSH_INPUT
SSH_PATH="${SSH_INPUT:-$SSH_PATH_DEFAULT}"
echo ""

# ─── SSH Agent Provider ────────────────────────────────────────────────────
echo -e "${B}  SSH Agent${N}"
echo ""
echo "  Which SSH agent do you use?"
echo -e "    ${C}1)${N} 1Password"
echo -e "    ${C}2)${N} Keeper PAM"
echo -e "    ${C}3)${N} Custom (other SSH agent)"
echo -e "    ${C}4)${N} None / skip"
echo ""
read -rp "  Choice [1]: " AGENT_CHOICE
AGENT_CHOICE="${AGENT_CHOICE:-1}"

SSH_SOCK=""
AGENT_PROVIDER="none"

case "$AGENT_CHOICE" in
  1)
    AGENT_PROVIDER="1password"
    echo ""
    echo -e "  ${D}Make sure SSH agent is enabled in 1Password:${N}"
    echo -e "  ${D}  1Password -> Settings -> Developer -> 'Use the SSH Agent' (toggle ON)${N}"
    echo -e "  ${D}  Recommended: also enable 'Ask approval for each new application'${N}"
    echo -e "  ${D}  for biometric confirmation on each key use.${N}"
    echo ""
    case "$PLATFORM" in
      macos)
        SSH_SOCK_DEFAULT="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
        ;;
      windows)
        SSH_SOCK_DEFAULT="/run/host-services/ssh-auth.sock"
        echo -e "  ${D}Windows: also enable Docker Desktop -> Settings -> Resources -> WSL Integration${N}"
        echo ""
        ;;
      linux)
        SSH_SOCK_DEFAULT="$HOME/.1password/agent.sock"
        ;;
    esac
    if [ -e "$SSH_SOCK_DEFAULT" ]; then
      echo -e "  ${G}Socket found at default path.${N}"
    else
      echo -e "  ${Y}Socket not found at default path — is the SSH agent enabled?${N}"
    fi
    read -rp "  1Password socket [$SSH_SOCK_DEFAULT]: " SSH_SOCK_INPUT
    SSH_SOCK="${SSH_SOCK_INPUT:-$SSH_SOCK_DEFAULT}"

    echo ""
    echo -e "  ${D}1Password CLI ('op') is also installed in the container.${N}"
    echo -e "  ${D}App integration (biometric) does not work cross-platform in Docker.${N}"
    echo -e "  ${D}To use 'op' inside the container, set OP_SERVICE_ACCOUNT_TOKEN in .env${N}"
    echo -e "  ${D}or resolve secrets on host with 'op read' and pass as env vars.${N}"
    ;;
  2)
    AGENT_PROVIDER="keeper"
    echo ""
    echo -e "  ${D}Keeper PAM uses email-based socket: ~/.keeper/<email>.ssh_agent${N}"
    echo -e "  ${D}Prerequisites:${N}"
    echo -e "  ${D}  1. Install Keeper Commander CLI: pip install keepercommander${N}"
    echo -e "  ${D}  2. Start the agent: keeper ssh-agent start${N}"
    echo -e "  ${D}  3. The agent loads SSH keys from your Keeper Vault automatically${N}"
    echo -e "  ${D}  Docs: https://docs.keeper.io/en/keeperpam/commander-cli/command-reference/connection-commands/ssh-agent${N}"
    echo ""
    read -rp "  Your Keeper account email: " KEEPER_EMAIL
    if [ -n "$KEEPER_EMAIL" ]; then
      SSH_SOCK_DEFAULT="$HOME/.keeper/${KEEPER_EMAIL}.ssh_agent"
    else
      SSH_SOCK_DEFAULT=""
    fi
    if [ -n "$SSH_SOCK_DEFAULT" ] && [ -e "$SSH_SOCK_DEFAULT" ]; then
      echo -e "  ${G}Socket found at default path.${N}"
    elif [ -n "$SSH_SOCK_DEFAULT" ]; then
      echo -e "  ${Y}Socket not found — have you run 'keeper ssh-agent start'?${N}"
    fi
    read -rp "  Keeper socket [$SSH_SOCK_DEFAULT]: " SSH_SOCK_INPUT
    SSH_SOCK="${SSH_SOCK_INPUT:-$SSH_SOCK_DEFAULT}"
    ;;
  3)
    AGENT_PROVIDER="custom"
    echo ""
    read -rp "  SSH agent socket path: " SSH_SOCK
    ;;
  4)
    AGENT_PROVIDER="none"
    SSH_SOCK=""
    echo -e "  ${Y}Skipping SSH agent setup.${N}"
    ;;
esac
echo ""

# ─── Resources ──────────────────────────────────────────────────────────────
echo -e "${B}  Resources${N}"
read -rp "  Workspace memory [$MEMORY_DEFAULT]: " MEM_INPUT
MEMORY="${MEM_INPUT:-$MEMORY_DEFAULT}"
read -rp "  Workspace CPUs [$CPUS_DEFAULT]: " CPU_INPUT
CPUS="${CPU_INPUT:-$CPUS_DEFAULT}"
echo ""

# ─── Git signing ────────────────────────────────────────────────────────────
echo -e "${B}  Git Commit Signing${N} (optional)"
echo ""
echo -e "  ${D}Signs your git commits with an SSH key so GitHub shows them as 'Verified'.${N}"
echo -e "  ${D}Your ~/.ssh is mounted read-only into the container at /home/vscode/.ssh/${N}"
echo -e "  ${D}Point this to the PUBLIC key (.pub) inside the container.${N}"
echo ""
echo -e "  ${D}Examples:${N}"
echo -e "  ${D}  /home/vscode/.ssh/id_ed25519.pub       (if you have ed25519 key)${N}"
echo -e "  ${D}  /home/vscode/.ssh/id_rsa.pub            (if you have RSA key)${N}"
echo ""
echo -e "  ${D}To check which keys you have: ls ~/.ssh/*.pub${N}"
echo -e "  ${D}Leave empty to skip — commits will work but won't show as 'Verified'.${N}"
echo ""

# Show available public keys as hints
PUB_KEYS=$(ls "$SSH_PATH"/*.pub 2>/dev/null | while read f; do echo "  /home/vscode/.ssh/$(basename "$f")"; done)
if [ -n "$PUB_KEYS" ]; then
  echo -e "  ${G}Public keys found on your machine:${N}"
  echo "$PUB_KEYS"
  echo ""
fi

read -rp "  SSH signing key []: " SIGNING_KEY
echo ""

# ─── Generate .env ──────────────────────────────────────────────────────────
cat > .env << ENVEOF
# Generated by setup.sh on $(date '+%Y-%m-%d %H:%M:%S')
# Platform: $PLATFORM

# Project identity — one folder per project, do not share
PROJECT_NAME=$PROJECT_NAME

PLATFORM=$PLATFORM

# Git
GIT_USER_NAME=$GIT_NAME
GIT_USER_EMAIL=$GIT_EMAIL

# SSH Agent
SSH_AGENT_PROVIDER=$AGENT_PROVIDER
SSH_AGENT_SOCK_HOST=$SSH_SOCK

# Paths
WORKSPACE_PATH=$WORKSPACE
SSH_HOST_PATH=$SSH_PATH
CLAUDE_CONFIG_PATH=$HOME/.claude

# Resources
WORKSPACE_MEMORY=$MEMORY
WORKSPACE_CPUS=$CPUS
PROXY_MEMORY=256M
PROXY_CPUS=1
TMP_SIZE=536870912

# Git signing (optional)
SSH_SIGNING_KEY=$SIGNING_KEY

# Claude overrides (uncomment if needed)
# ANTHROPIC_API_KEY=sk-ant-xxxxxxxxxxxxx
# CLAUDE_MODEL=claude-opus-4-20250514
# CLAUDE_MAX_TURNS=25
ENVEOF

echo -e "${G}  .env created successfully!${N}"
echo ""

# ─── Create workspace directory if needed ────────────────────────────────────
if [ ! -d "$WORKSPACE" ]; then
  read -rp "  Workspace $WORKSPACE doesn't exist. Create it? [Y/n]: " CREATE_WS
  if [ "${CREATE_WS:-Y}" != "n" ]; then
    mkdir -p "$WORKSPACE"
    echo -e "  ${G}Created $WORKSPACE${N}"
  fi
fi

# ─── Set devcontainer name to project name ──────────────────────────────────
sed -i.bak "s/\"name\": \".*\"/\"name\": \"${PROJECT_NAME}\"/" .devcontainer/devcontainer.json && rm -f .devcontainer/devcontainer.json.bak

# ─── Make scripts executable ────────────────────────────────────────────────
chmod +x scripts/*.sh 2>/dev/null || true

# ─── Next steps ──────────────────────────────────────────────────────────────
PROJECT_DIR="$(pwd)"
echo ""
echo -e "${B}  Next steps:${N}"
echo ""
echo "  1. Open this project folder in VS Code:"
echo "     code $PROJECT_DIR"
echo ""
echo "  2. Reopen in container:"
echo "     Cmd+Shift+P (macOS) / Ctrl+Shift+P (Windows)"
echo "     -> 'Dev Containers: Reopen in Container'"
echo ""
echo "  3. Inside the container, run:"
echo "     ccd              # interactive Claude (dangerous mode — safe in container)"
echo "     ccw              # watchdog mode (auto-restart)"
echo "     cch \"your task\"  # headless autonomous agent"
echo ""
echo -e "${C}  Happy prompting!${N}"
echo ""
