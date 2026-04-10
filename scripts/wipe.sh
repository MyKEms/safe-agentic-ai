#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# wipe.sh - Clean reset of the container environment
# ─────────────────────────────────────────────────────────────────────────────
# Usage:
#   ./scripts/wipe.sh              # interactive menu
#   ./scripts/wipe.sh --soft       # sessions/logs only (keep volumes + images)
#   ./scripts/wipe.sh --hard       # destroy containers, volumes, images
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

B="\033[1m"
R="\033[31m"
G="\033[32m"
N="\033[0m"

cd "$(dirname "$0")/.." || exit 1

# Detect docker compose variant (v2 plugin vs standalone docker-compose)
if docker compose version >/dev/null 2>&1; then
  DC="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  DC="docker-compose"
else
  echo "ERROR: neither 'docker compose' nor 'docker-compose' found" >&2
  exit 1
fi

echo -e "${B}=== Claude Code Sandbox - Wipe Tool ===${N}"
echo ""

MODE="${1:-}"

# ─── Interactive mode ────────────────────────────────────────────────────────
if [ -z "$MODE" ]; then
  echo "What do you want to clean?"
  echo ""
  echo -e "  ${G}1) Soft reset${N}  - Sessions & temp files only"
  echo "                  Memory, credentials, workspace KEPT"
  echo ""
  echo -e "  ${R}2) Hard reset${N}  - Containers, volumes, images destroyed"
  echo -e "                  ${R}WARNING: Claude memory & sessions DESTROYED${N}"
  echo ""
  read -rp "Choice [1/2]: " CHOICE
  case "$CHOICE" in
    1) MODE="--soft" ;;
    2) MODE="--hard" ;;
    *) echo "Cancelled."; exit 0 ;;
  esac
fi

echo ""

# ─── Soft reset ──────────────────────────────────────────────────────────────
if [ "$MODE" = "--soft" ]; then
  echo -e "${G}>>> Soft reset${N}"
  echo "Cleaning container sessions and temp files..."

  $DC exec claude bash -c "rm -rf /home/vscode/.claude/sessions/* /home/vscode/.claude/projects/*/sessions/* 2>/dev/null; rm -rf /home/vscode/.claude/history.jsonl 2>/dev/null" || true
  echo "  Claude sessions:  cleared"

  $DC exec claude rm -f /home/vscode/.claude.json 2>/dev/null || true
  echo "  MCP config:       cleared"

  $DC exec claude bash -c "rm -rf /tmp/* 2>/dev/null" || true
  echo "  Container /tmp:   cleared"

  echo ""
  echo -e "  ${B}NOT touched:${N}"
  echo "  Claude credentials (.credentials.json from host)"
  echo "  Claude memory & project data (claude-state volume)"
  echo "  Workspace files"
  echo ""
  echo -e "${G}Done.${N} Run 'bash /scripts/setup-container.sh' inside to re-setup MCP."

# ─── Hard reset ──────────────────────────────────────────────────────────────
elif [ "$MODE" = "--hard" ]; then
  echo -e "${R}>>> Hard reset${N}"
  echo ""
  echo -e "  ${R}${B}WARNING: This will permanently destroy the claude-state volume.${N}"
  echo -e "  ${R}All Claude memory (MEMORY.md, memory files), sessions, and project${N}"
  echo -e "  ${R}data stored inside the container will be lost and CANNOT be recovered.${N}"
  echo ""
  echo -e "  ${B}To check what's there before wiping:${N}"
  echo "    docker compose exec claude ls /home/vscode/.claude/projects/-workspace/memory/"
  echo ""
  read -rp "Type 'wipe' to confirm: " CONFIRM
  [ "$CONFIRM" != "wipe" ] && echo "Cancelled." && exit 0

  $DC down -v --rmi local 2>/dev/null
  echo "  Containers + volumes + images: destroyed"
  echo -e "  ${R}claude-state volume: DESTROYED (memory, sessions, project data gone)${N}"

  docker builder prune -f 2>/dev/null | tail -1
  echo ""
  echo -e "  ${B}NOT touched:${N}"
  echo "  .env                           (project config)"
  echo "  proxy/allowed-domains.txt      (domain allowlist)"
  echo "  Workspace files (/workspace)"
  echo "  Host credentials (~/.claude/)"
  echo "  Host SSH keys (~/.ssh/)"
  echo ""
  echo -e "${R}Done.${N} Rebuild: docker compose build && docker compose up -d"
fi

echo ""
echo "─────────────────────────────────────"
echo "Cheat sheet:"
echo "  docker compose build --no-cache   # full image rebuild"
echo "  docker compose up -d              # start containers"
echo "  VS Code: 'Reopen in Container'    # attach VS Code"
echo "─────────────────────────────────────"
