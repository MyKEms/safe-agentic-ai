# ============================================================
# Safe Agentic AI — Workspace Container
# ============================================================
# Ubuntu 24.04 with Node 20, Claude CLI, Playwright, 1Password CLI
# Supports both amd64 and arm64 (Apple Silicon) natively.
# All network traffic routes through Squid proxy.
# ============================================================

FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# --- System packages ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    git \
    jq \
    ripgrep \
    tree \
    unzip \
    vim \
    openssh-client \
    netcat-openbsd \
    procps \
    htop \
  && rm -rf /var/lib/apt/lists/*

# --- 1Password CLI (vault access from workspace) ---
RUN ARCH=$(dpkg --print-architecture) \
    && curl -sSfo /tmp/op.zip \
       "https://cache.agilebits.com/dist/1P/op2/pkg/v2.32.0/op_linux_${ARCH}_v2.32.0.zip" \
    && unzip -o /tmp/op.zip op -d /usr/local/bin \
    && chmod +x /usr/local/bin/op \
    && rm -f /tmp/op.zip

# --- Node.js 20 ---
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
  && apt-get install -y nodejs \
  && rm -rf /var/lib/apt/lists/*

# --- Claude Code CLI ---
# Baked into image; auto-updated on every container start via welcome.sh
RUN npm install -g @anthropic-ai/claude-code

# --- Playwright (Chromium only, headless) ---
# Supported on both amd64 and arm64 since Playwright 1.34
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers
RUN npx playwright install --with-deps chromium \
    && chmod -R 777 /opt/pw-browsers

# --- Route SSH through Squid proxy ---
RUN mkdir -p /etc/ssh/ssh_config.d && \
    echo 'ProxyCommand nc -X connect -x proxy:3128 %h %p' \
    > /etc/ssh/ssh_config.d/99-proxy.conf

# --- Route APT through Squid proxy ---
RUN echo 'Acquire::http::Proxy "http://proxy:3128/";\nAcquire::https::Proxy "http://proxy:3128/";' \
    > /etc/apt/apt.conf.d/99proxy

# --- Non-root user setup ---
USER vscode
RUN mkdir -p /home/vscode/.npm /home/vscode/.ssh-agent \
    && mkdir -m 700 -p /home/vscode/.op

# --- Shell aliases & environment ---
RUN echo '\n\
# Claude Code aliases\n\
alias cc="claude"\n\
alias ccd="claude --dangerously-skip-permissions"\n\
alias ccw="/scripts/watchdog.sh"\n\
alias cch="/scripts/watchdog.sh -p"\n\
export CLAUDE_CODE_DISABLE_AUTO_UPDATE=1\n\
' >> /home/vscode/.bashrc

WORKDIR /workspace
