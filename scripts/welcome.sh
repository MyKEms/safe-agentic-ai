#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# welcome.sh – Dev container startup banner (postStartCommand)
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

B="\033[1m"
D="\033[2m"
G="\033[32m"
Y="\033[33m"
R="\033[31m"
C="\033[36m"
N="\033[0m"

# ─── Fix ownership & permissions ────────────────────────────────────────────
sudo chown -R vscode:vscode /home/vscode/.claude 2>/dev/null
sudo chown -R vscode:vscode /home/vscode/.cache 2>/dev/null
sudo chmod 777 /home/vscode/.ssh-agent/agent.sock 2>/dev/null || true

# ─── Banner ─────────────────────────────────────────────────────────────────
echo ""
PROJ="${PROJECT_NAME:-claude}"
echo -e "${B}${C}  Safe Agentic AI — ${PROJ}${N}"
echo -e "${D}  ─────────────────────────────────────────────${N}"
echo ""

# Claude version
LOCAL_VER=$(claude --version 2>/dev/null | awk '{print $1}')
echo -e -n "  ${B}Claude CLI:${N}  ${LOCAL_VER:-not found}"
LATEST_VER=$(npm view @anthropic-ai/claude-code version 2>/dev/null)
if [ -n "$LATEST_VER" ] && [ -n "$LOCAL_VER" ] && [ "$LOCAL_VER" != "$LATEST_VER" ]; then
  echo -e "  ${Y}(update: ${LATEST_VER})${N} ${D}npm i -g @anthropic-ai/claude-code@latest${N}"
else
  echo ""
fi

# SSH agent
echo -e -n "  ${B}SSH Agent:${N}   "
KEY=$(ssh-add -l 2>/dev/null)
if [ $? -eq 0 ]; then
  echo -e "${G}$(echo "$KEY" | wc -l | xargs) key(s)${N} – $(echo "$KEY" | head -1 | awk '{print $3}')"
else
  echo -e "${Y}not available${N} (check SSH agent on host)"
fi

# 1Password CLI
echo -e -n "  ${B}1Password:${N}  "
if command -v op &>/dev/null; then
  if [ -S /home/vscode/.op/agent.sock ]; then
    OP_EMAIL=$(op whoami --format=json 2>/dev/null | jq -r '.email // empty' 2>/dev/null)
    if [ -n "$OP_EMAIL" ]; then
      echo -e "${G}connected${N} ($OP_EMAIL)"
    else
      echo -e "${Y}socket mounted, not signed in on host${N}"
    fi
  elif [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then
    echo -e "${G}service account${N}"
  else
    echo -e "${D}not configured (no socket or token)${N}"
  fi
else
  echo -e "${D}not installed${N}"
fi

# Proxy
echo -e -n "  ${B}Proxy:${N}       "
PROXY_TEST=$(curl -s -o /dev/null -w "%{http_code}" --proxy http://proxy:3128 --max-time 3 https://api.anthropic.com 2>/dev/null)
if [ "$PROXY_TEST" = "404" ] || [ "$PROXY_TEST" = "200" ]; then
  echo -e "${G}connected${N}"
else
  echo -e "${R}unreachable${N}"
fi

# Playwright
echo -e -n "  ${B}Playwright:${N}  "
if command -v npx &>/dev/null && npx playwright --version &>/dev/null 2>&1; then
  echo -e "${G}$(npx playwright --version 2>/dev/null)${N} (Chromium, headless)"
else
  echo -e "${Y}not installed${N}"
fi

# Aliases
echo ""
echo -e "  ${B}Aliases:${N}"
echo -e "    ${C}ccd${N}              Claude interactive (--dangerously-skip-permissions)"
echo -e "    ${C}ccw${N}              Watchdog mode (auto-restart on crash)"
echo -e "    ${C}cch \"task\"${N}        Headless agent mode"
echo ""
echo -e "  ${Y}Open a new terminal (+) or click the 'bash' tab to start.${N}"
echo -e "  ${D}The 'Configuring...' and 'Dev Containers' tabs are just logs.${N}"
echo ""
echo -e "  ${B}From host:${N}"
echo -e "    ${D}claude login${N}                Auth (token shared via mount)"
echo -e "    ${D}./scripts/monitor.sh --loop${N}  Live dashboard"
echo -e "    ${D}./scripts/wipe.sh${N}           Clean reset"
echo -e "${D}  ─────────────────────────────────────────────${N}"
echo ""
