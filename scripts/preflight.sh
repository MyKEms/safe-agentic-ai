#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# preflight.sh – Host-side check before container build (initializeCommand)
# ─────────────────────────────────────────────────────────────────────────────
# Detects conflicting containers and missing .env before VS Code tries to
# build. Runs on the HOST, not inside the container.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

R="\033[31m"
Y="\033[33m"
G="\033[32m"
B="\033[1m"
D="\033[2m"
N="\033[0m"

ERRORS=0

# ─── Resolve project name for container name checks ──────────────────────
PROJECT_NAME=$(grep '^PROJECT_NAME=' .env 2>/dev/null | cut -d= -f2 | tr -d '"' | tr -d "'")
PROJECT_NAME="${PROJECT_NAME:-claude}"
PROXY_CONTAINER="${PROJECT_NAME}-proxy"
WS_CONTAINER="${PROJECT_NAME}-workspace"

# ─── Check .env exists ──────────────────────────────────────────────────────
if [ ! -f .env ]; then
  echo ""
  echo -e "${R}${B}  ERROR: .env file not found${N}"
  echo ""
  echo "  Run the setup wizard first:"
  echo "    ./setup.sh"
  echo ""
  echo "  Or copy the example and edit manually:"
  echo "    cp .env.example .env"
  echo ""
  ERRORS=1
fi

# ─── Check Docker is running ────────────────────────────────────────────────
if ! docker info &>/dev/null; then
  echo ""
  echo -e "${R}${B}  ERROR: Docker is not running${N}"
  echo ""
  echo "  Start Docker Desktop and try again."
  echo ""
  ERRORS=1
fi

# ─── Check for conflicting container names ──────────────────────────────────
if docker info &>/dev/null; then
  CONFLICTS=""

  for NAME in "$PROXY_CONTAINER" "$WS_CONTAINER"; do
    EXISTING=$(docker ps -a --filter "name=^/${NAME}$" --format '{{.ID}} {{.Status}} (project: {{.Label "com.docker.compose.project"}})' 2>/dev/null)
    if [ -n "$EXISTING" ]; then
      # Check if it belongs to a DIFFERENT compose project
      EXISTING_PROJECT=$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' "$NAME" 2>/dev/null)
      CURRENT_PROJECT=$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]//g')

      if [ "$EXISTING_PROJECT" != "$CURRENT_PROJECT" ]; then
        CONFLICTS="${CONFLICTS}    ${NAME}  →  ${EXISTING}\n"
      fi
    fi
  done

  if [ -n "$CONFLICTS" ]; then
    echo ""
    echo -e "${Y}${B}  WARNING: Conflicting containers detected${N}"
    echo ""
    echo -e "  Another project is using the same container names:"
    echo -e "$CONFLICTS"
    echo -e "  ${B}To fix, stop the conflicting containers:${N}"
    echo ""
    echo "    docker stop $PROXY_CONTAINER $WS_CONTAINER"
    echo "    docker rm $PROXY_CONTAINER $WS_CONTAINER"
    echo ""
    echo -e "  ${D}Then retry: Cmd+Shift+P → 'Dev Containers: Reopen in Container'${N}"
    echo ""
    ERRORS=1
  fi
fi

# ─── Result ──────────────────────────────────────────────────────────────────
if [ "$ERRORS" -eq 0 ]; then
  echo -e "${G}  Preflight checks passed${N}"
else
  exit 1
fi
