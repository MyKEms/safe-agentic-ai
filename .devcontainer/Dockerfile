# ============================================================
# Safe Agentic AI — Workspace Container
# ============================================================
# Ubuntu 22.04 with Node 20, Claude CLI, Playwright (Chromium)
# All network traffic routes through Squid proxy.
# ============================================================

FROM --platform=linux/amd64 mcr.microsoft.com/devcontainers/base:ubuntu-22.04

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

# --- Node.js 20 ---
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
  && apt-get install -y nodejs \
  && rm -rf /var/lib/apt/lists/*

# --- Claude Code CLI ---
RUN npm install -g @anthropic-ai/claude-code

# --- Playwright (Chromium only, headless) ---
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
RUN mkdir -p /home/vscode/.npm /home/vscode/.ssh-agent

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
