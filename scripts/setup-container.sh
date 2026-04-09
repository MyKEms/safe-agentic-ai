#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# setup-container.sh – One-time container setup (postCreateCommand)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

echo "=== Claude Code Sandbox — Container Setup ==="

# ─── Fix ownership ──────────────────────────────────────────────────────────
# The claude-state volume is created by Docker as root.
# Chown the volume contents so vscode can write sessions, memory, etc.
sudo chown -R vscode:vscode /home/vscode/.claude 2>/dev/null || true
sudo chown -R vscode:vscode /home/vscode/.cache 2>/dev/null || true

# ─── Copy auth files from host into the volume ──────────────────────────────
# Host ~/.claude is mounted read-only at /home/vscode/.claude-host.
# We copy only auth-related files into the volume — sessions and project
# data stay isolated in the volume (not shared with host).
HOST_DIR="/home/vscode/.claude-host"
CLAUDE_DIR="/home/vscode/.claude"
if [ -d "$HOST_DIR" ]; then
  for f in .credentials.json settings.json; do
    if [ -f "$HOST_DIR/$f" ]; then
      cp "$HOST_DIR/$f" "$CLAUDE_DIR/$f"
      chown vscode:vscode "$CLAUDE_DIR/$f"
      chmod 600 "$CLAUDE_DIR/$f"
    fi
  done
  echo "  Auth files: copied from host"
fi

# ─── Stable machine identity ────────────────────────────────────────────────
# Claude CLI may bind auth tokens to the machine identity. Docker generates
# a new /etc/machine-id on each container creation, which would invalidate
# auth. Persist the machine-id in the volume so it survives rebuilds.
SAVED_MID="$CLAUDE_DIR/.machine-id"
if [ -f "$SAVED_MID" ]; then
  sudo cp "$SAVED_MID" /etc/machine-id
  echo "  Machine ID: restored from volume"
else
  cp /etc/machine-id "$SAVED_MID" 2>/dev/null || true
  echo "  Machine ID: saved to volume"
fi

# ─── Restore .claude.json if lost ───────────────────────────────────────────
# Claude CLI's user-level config (.claude.json) lives in HOME, outside the
# volume. It gets lost on container rebuild. If a backup exists in the volume
# (Claude auto-creates these), restore it.
CLAUDE_JSON="/home/vscode/.claude.json"
if [ ! -f "$CLAUDE_JSON" ]; then
  BACKUP=$(ls -t "$CLAUDE_DIR"/backups/.claude.json.backup.* 2>/dev/null | head -1 || true)
  if [ -n "$BACKUP" ]; then
    cp "$BACKUP" "$CLAUDE_JSON"
    chown vscode:vscode "$CLAUDE_JSON"
    echo "  Claude config: restored from backup"
  fi
fi

# ─── Git config ────────────────────────────────────────────────────────────
git config --global --add safe.directory '*'
git config --global init.defaultBranch main

# Git identity (from .env via docker-compose environment)
if [ -n "${GIT_USER_NAME:-}" ]; then
  git config --global user.name "$GIT_USER_NAME"
  echo "  Git user.name: $GIT_USER_NAME"
fi
if [ -n "${GIT_USER_EMAIL:-}" ]; then
  git config --global user.email "$GIT_USER_EMAIL"
  echo "  Git user.email: $GIT_USER_EMAIL"
fi

# ─── Git SSH signing (optional — only if key exists) ──────────────────────
if [ -n "${SSH_SIGNING_KEY:-}" ] && [ -f "${SSH_SIGNING_KEY}" ]; then
  git config --global gpg.format ssh
  git config --global user.signingkey "$SSH_SIGNING_KEY"
  git config --global commit.gpgsign true
  git config --global tag.gpgSign true
  git config --global gpg.ssh.program ssh-keygen
  echo "  Git signing: enabled (SSH key: $SSH_SIGNING_KEY)"
else
  echo "  Git signing: disabled (no SSH_SIGNING_KEY or key not found)"
fi

# ─── MCP config (Playwright) ─────────────────────────────────────────────
echo ""
echo ">>> Checking MCP config..."
if [ -f /workspace/.mcp.json ]; then
  echo "    /workspace/.mcp.json found"
else
  echo "    Creating default MCP config (Playwright)..."
  cat > /workspace/.mcp.json << 'MCPEOF'
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["-y", "@playwright/mcp@latest", "--headless", "--browser", "chromium"]
    }
  }
}
MCPEOF
  echo "    Created /workspace/.mcp.json"
fi

# ─── Claude CLI default permissions ──────────────────────────────────────
CLAUDE_SETTINGS="/workspace/.claude/settings.local.json"
if [ ! -f "$CLAUDE_SETTINGS" ]; then
  echo ">>> Creating default Claude CLI permissions..."
  mkdir -p /workspace/.claude
  cat > "$CLAUDE_SETTINGS" << 'CLEOF'
{
  "permissions": {
    "allow": [
      "Bash(docker exec:*)",
      "Bash(docker compose:*)",
      "Bash(docker logs:*)"
    ]
  }
}
CLEOF
  echo "    Created $CLAUDE_SETTINGS"
else
  echo ">>> Claude CLI permissions: $CLAUDE_SETTINGS (exists)"
fi

# ─── Claude auth check ───────────────────────────────────────────────────
# Credentials are bind-mounted from host. Verify they contain a valid token
# so Claude CLI doesn't trigger an OAuth flow inside the container.
echo ""
echo ">>> Checking Claude auth..."
if [ -f "$CLAUDE_DIR/.credentials.json" ] && grep -q '"accessToken"' "$CLAUDE_DIR/.credentials.json" 2>/dev/null; then
  echo "    OAuth credentials: found (from host)"
elif [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  echo "    Auth: API key configured"
else
  echo "    WARNING: no valid credentials found"
  echo "    Run 'claude login' on the HOST, then restart the container."
  echo "    Or set ANTHROPIC_API_KEY in .env as a fallback."
fi

# ─── Verification ────────────────────────────────────────────────────────
echo ""
echo "=== Verification ==="
echo -n "SSH Agent: "
ssh-add -l 2>/dev/null && true || echo "  No keys (enable SSH agent on host)"
echo -n "Claude CLI: "
claude --version 2>/dev/null || echo "  Not found"
echo -n "Proxy: "
curl -s -o /dev/null -w "HTTP %{http_code}" --proxy http://proxy:3128 --max-time 5 https://api.anthropic.com 2>/dev/null || echo "  Unreachable"
echo ""
echo ""
echo "=== Setup complete ==="
echo "  cc               Claude interactive (with permission prompts)"
echo "  ccd              Claude autonomous (--dangerously-skip-permissions)"
echo "  ccw              Watchdog mode (auto-restart on crash)"
echo "  cch \"your task\"  Headless agent (fire-and-forget)"
