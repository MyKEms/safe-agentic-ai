#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# setup-container.sh – One-time container setup (postCreateCommand)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

echo "=== Safe Agentic AI — Container Setup ==="

# ─── Fix ownership ──────────────────────────────────────────────────────────
sudo chown -R vscode:vscode /home/vscode/.claude 2>/dev/null || true
sudo chown -R vscode:vscode /home/vscode/.cache 2>/dev/null || true

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

# ─── 1Password CLI (app integration via mounted socket) ──────────────────
OP_SOCK="/home/vscode/.op/agent.sock"
if [ -S "$OP_SOCK" ]; then
  mkdir -p /home/vscode/.config/op
  cat > /home/vscode/.config/op/config << 'OPEOF'
{"app_integrated": true}
OPEOF
  echo "  1Password CLI: configured (app integration via socket)"
elif [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then
  echo "  1Password CLI: configured (service account token)"
else
  echo "  1Password CLI: not configured (no socket or token)"
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
echo "Run 'ccd' for interactive Claude (dangerous mode — inside container this is safe)"
echo "Run 'ccw' for watchdog mode (auto-restart)"
echo "Run 'cch \"your task\"' for headless agent"
