#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# wipe.sh – Clean reset of the container environment
# ─────────────────────────────────────────────────────────────────────────────
# Usage:
#   ./scripts/wipe.sh              # interactive menu
#   ./scripts/wipe.sh --soft       # sessions/logs only (keep volumes)
#   ./scripts/wipe.sh --hard       # destroy containers, volumes, images
#   ./scripts/wipe.sh --nuclear    # hard + clean host ~/.claude sessions
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

B="\033[1m"
R="\033[31m"
G="\033[32m"
Y="\033[33m"
N="\033[0m"

cd "$(dirname "$0")/.."

echo -e "${B}=== Safe Agentic AI — Wipe Tool ===${N}"
echo ""

MODE="${1:-}"

# ─── Interactive mode ────────────────────────────────────────────────────────
if [ -z "$MODE" ]; then
  echo "What do you want to clean?"
  echo ""
  echo -e "  ${G}1) Soft reset${N}  – Sessions & temp files only"
  echo "                  Memory, credentials, workspace KEPT"
  echo ""
  echo -e "  ${Y}2) Hard reset${N}  – Containers, volumes, images"
  echo -e "                  ${Y}WARNING: Claude memory & sessions DESTROYED${N}"
  echo ""
  echo -e "  ${R}3) Nuclear${N}     – Everything (containers, volumes, images)"
  echo -e "                  ${R}WARNING: Claude memory & sessions DESTROYED${N}"
  echo ""
  read -rp "Choice [1/2/3]: " CHOICE
  case "$CHOICE" in
    1) MODE="--soft" ;;
    2) MODE="--hard" ;;
    3) MODE="--nuclear" ;;
    *) echo "Cancelled."; exit 0 ;;
  esac
fi

echo ""

# ─── Soft reset ──────────────────────────────────────────────────────────────
if [ "$MODE" = "--soft" ]; then
  echo -e "${G}>>> Soft reset${N}"
  echo "Cleaning container sessions and temp files..."

  docker compose exec claude bash -c "rm -rf /home/vscode/.claude/sessions/* /home/vscode/.claude/projects/*/sessions/* 2>/dev/null; rm -rf /home/vscode/.claude/history.jsonl 2>/dev/null" || true
  echo "  Claude sessions:  cleared"

  docker compose exec claude rm -f /home/vscode/.claude.json 2>/dev/null || true
  echo "  MCP config:       cleared"

  docker compose exec claude bash -c "rm -rf /tmp/* 2>/dev/null" || true
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
  echo -e "${Y}>>> Hard reset${N}"
  echo ""
  echo -e "  ${Y}${B}WARNING: This will permanently destroy the claude-state volume.${N}"
  echo -e "  ${Y}All Claude memory (MEMORY.md, memory files), sessions, and project${N}"
  echo -e "  ${Y}data stored inside the container will be lost and CANNOT be recovered.${N}"
  echo ""
  echo -e "  ${B}To check what's there before wiping:${N}"
  echo "    docker compose exec claude ls /home/vscode/.claude/projects/-workspace/memory/"
  echo ""
  read -rp "Continue? [y/N]: " CONFIRM
  [ "$CONFIRM" != "y" ] && echo "Cancelled." && exit 0

  echo "Stopping containers..."
  docker compose down -v 2>/dev/null
  echo "  Containers + volumes: removed"
  echo -e "  ${Y}claude-state volume: DESTROYED (memory, sessions, project data gone)${N}"

  echo "Removing images..."
  docker compose down --rmi local 2>/dev/null
  echo "  Images: removed (will rebuild)"

  docker builder prune -f 2>/dev/null | tail -1
  echo ""
  echo -e "  ${B}NOT touched:${N}"
  echo "  Workspace files (/workspace)"
  echo "  Host credentials (~/.claude/.credentials.json)"
  echo "  Host SSH keys"
  echo ""
  echo -e "${Y}Done.${N} Run 'docker compose build && docker compose up -d' to rebuild."

# ─── Nuclear reset ───────────────────────────────────────────────────────────
elif [ "$MODE" = "--nuclear" ]; then
  echo -e "${R}>>> Nuclear reset${N}"
  echo ""
  echo -e "  ${R}${B}WARNING: This will permanently destroy ALL container state.${N}"
  echo -e "  ${R}All Claude memory (MEMORY.md, memory files), sessions, and project${N}"
  echo -e "  ${R}data stored inside the container will be lost and CANNOT be recovered.${N}"
  echo ""
  echo -e "  ${B}To check what's there before wiping:${N}"
  echo "    docker compose exec claude ls /home/vscode/.claude/projects/-workspace/memory/"
  echo ""
  read -rp "Type 'nuke' to confirm: " CONFIRM
  [ "$CONFIRM" != "nuke" ] && echo "Cancelled." && exit 0

  docker compose down -v --rmi local 2>/dev/null
  echo "  Containers + volumes + images: destroyed"
  echo -e "  ${R}claude-state volume: DESTROYED (memory, sessions, project data gone)${N}"
  echo ""
  echo -e "${R}NOT removed (by design):${N}"
  echo "  .env                           (project config)"
  echo "  proxy/allowed-domains.txt      (domain allowlist)"
  echo "  ~/.claude/.credentials.json    (host auth credentials)"
  echo "  ~/.ssh/                        (host SSH keys)"
  echo ""
  echo -e "${R}Done.${N} Fresh start: docker compose build && docker compose up -d"
fi

echo ""
echo "─────────────────────────────────────"
echo "Cheat sheet:"
echo "  docker compose build --no-cache   # full image rebuild"
echo "  docker compose up -d              # start containers"
echo "  VS Code: 'Reopen in Container'    # attach VS Code"
echo "─────────────────────────────────────"
