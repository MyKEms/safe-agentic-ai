#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# proxy-ctl.sh – Manage proxy allowlists (domains, networks, SSH hosts)
# ─────────────────────────────────────────────────────────────────────────────
# Run from the HOST, not from inside the container.
# Edits allowlist files on the host and restarts the proxy.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DOMAINS_FILE="$SCRIPT_DIR/proxy/allowed-domains.txt"
NETWORKS_FILE="$SCRIPT_DIR/proxy/allowed-networks.txt"
SSH_HOSTS_FILE="$SCRIPT_DIR/proxy/trusted-ssh-hosts.txt"

# Detect docker compose variant (v2 plugin vs standalone docker-compose)
if docker compose version >/dev/null 2>&1; then
  DC="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  DC="docker-compose"
else
  echo "ERROR: neither 'docker compose' nor 'docker-compose' found" >&2
  exit 1
fi

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [args]

Domain rules (HTTP/HTTPS):
  add <domain>               Add a domain to the allowlist (auto-prefixes .)
  remove <domain>            Remove a domain from the allowlist

Network rules (all ports — HTTP, HTTPS, SSH, custom services):
  allow <ip-or-cidr>         Allow an IP or CIDR range (e.g. 192.168.0.0/24)
  block <ip-or-cidr>         Remove an IP or CIDR range

SSH host rules (SSH CONNECT only):
  add-ssh <domain>           Allow SSH to a domain (e.g. .bitbucket.org)
  remove-ssh <domain>        Remove SSH access for a domain

General:
  list                       Show all active rules (domains + networks + SSH)
  test <url>                 Test if a URL is reachable through the proxy
  logs                       Tail proxy access logs (Ctrl+C to stop)
  reload                     Restart the proxy to pick up config changes

Examples:
  $(basename "$0") add .pypi.org                 # HTTP/HTTPS to pypi.org + subdomains
  $(basename "$0") allow 192.168.0.0/24          # all ports to entire subnet
  $(basename "$0") allow 10.0.0.5                # all ports to single IP
  $(basename "$0") add-ssh .bitbucket.org        # SSH to bitbucket.org
  $(basename "$0") add-ssh git.your-company.com  # SSH to internal git server
  $(basename "$0") list                          # show all active rules
  $(basename "$0") test https://api.anthropic.com
EOF
}

reload_proxy() {
  echo "Reloading proxy..."
  $DC -f "$SCRIPT_DIR/docker-compose.yml" restart proxy
  echo "Proxy reloaded"
}

# Add or uncomment an entry in a file, then reload
_add_entry() {
  local file="$1" entry="$2" label="$3"
  if grep -qxF "$entry" "$file" 2>/dev/null; then
    echo "Already active: $entry ($label)"
    return 1
  elif grep -qxF "# ${entry}" "$file" 2>/dev/null; then
    # Entry exists commented out as exactly "# <entry>" — uncomment it
    sed -i.bak "s|^# ${entry}$|${entry}|" "$file" && rm -f "$file.bak"
    echo "Uncommented: $entry ($label)"
  else
    echo "$entry" >> "$file"
    echo "Added: $entry ($label)"
  fi
}

# Comment out an entry in a file, then reload
_remove_entry() {
  local file="$1" entry="$2" label="$3"
  if grep -qxF "$entry" "$file" 2>/dev/null; then
    sed -i.bak "s|^${entry}$|# ${entry}|" "$file" && rm -f "$file.bak"
    echo "Removed: $entry ($label)"
  else
    echo "Not found (active): $entry in $label"
    return 1
  fi
}

# Validate IP or CIDR format
_validate_network() {
  local target="$1"
  if [[ ! "$target" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]]; then
    echo "Error: invalid IP or CIDR: $target"
    echo "Expected format: 192.168.0.10 or 192.168.0.0/24"
    echo "For domains, use: add <domain> or add-ssh <domain>"
    exit 1
  fi
}

case "${1:-}" in
  list)
    echo "=== Allowed domains (HTTP/HTTPS) ==="
    grep -v '^\s*#' "$DOMAINS_FILE" | grep -v '^\s*$' | sort || true
    echo ""
    echo "=== Allowed networks (HTTP/HTTPS + SSH) ==="
    grep -v '^\s*#' "$NETWORKS_FILE" | grep -v '^\s*$' | sort || true
    echo ""
    echo "=== Trusted SSH hosts (SSH only) ==="
    grep -v '^\s*#' "$SSH_HOSTS_FILE" | grep -v '^\s*$' | sort || true
    ;;

  add)
    [[ -z "${2:-}" ]] && { echo "Error: specify a domain, e.g.: add nasems.cz"; exit 1; }
    domain="$2"
    # Auto-prepend . for wildcard subdomain matching (Squid dstdomain convention)
    if [[ "$domain" != .* ]]; then
      domain=".$domain"
      echo "Using .$2 (matches $2 + all subdomains)"
    fi
    _add_entry "$DOMAINS_FILE" "$domain" "domain" && reload_proxy
    ;;

  remove)
    [[ -z "${2:-}" ]] && { echo "Error: specify a domain"; exit 1; }
    domain="$2"
    if [[ "$domain" != .* ]]; then
      domain=".$domain"
    fi
    _remove_entry "$DOMAINS_FILE" "$domain" "domain" && reload_proxy
    ;;

  allow)
    [[ -z "${2:-}" ]] && { echo "Error: specify an IP or CIDR, e.g.: allow 192.168.0.0/24"; exit 1; }
    _validate_network "$2"
    _add_entry "$NETWORKS_FILE" "$2" "network — all ports" && reload_proxy
    ;;

  block)
    [[ -z "${2:-}" ]] && { echo "Error: specify an IP or CIDR, e.g.: block 192.168.0.0/24"; exit 1; }
    _validate_network "$2"
    _remove_entry "$NETWORKS_FILE" "$2" "network" && reload_proxy
    ;;

  add-ssh)
    [[ -z "${2:-}" ]] && { echo "Error: specify a domain, e.g.: add-ssh .bitbucket.org"; exit 1; }
    domain="$2"
    if [[ "$domain" != .* ]]; then
      domain=".$domain"
      echo "Using .$2 (matches $2 + all subdomains)"
    fi
    _add_entry "$SSH_HOSTS_FILE" "$domain" "SSH host" && reload_proxy
    ;;

  remove-ssh)
    [[ -z "${2:-}" ]] && { echo "Error: specify a domain, e.g.: remove-ssh .bitbucket.org"; exit 1; }
    domain="$2"
    if [[ "$domain" != .* ]]; then
      domain=".$domain"
    fi
    _remove_entry "$SSH_HOSTS_FILE" "$domain" "SSH host" && reload_proxy
    ;;

  test)
    [[ -z "${2:-}" ]] && { echo "Error: specify a URL, e.g.: test https://api.anthropic.com"; exit 1; }
    url="$2"
    echo "Testing: $url (through proxy)"
    $DC -f "$SCRIPT_DIR/docker-compose.yml" exec claude \
      curl -s -o /dev/null -w "HTTP %{http_code} (%{time_total}s)\n" \
      --proxy http://proxy:3128 "$url" || echo "Connection failed"
    ;;

  logs)
    $DC -f "$SCRIPT_DIR/docker-compose.yml" logs -f proxy
    ;;

  reload)
    reload_proxy
    ;;

  *)
    usage
    ;;
esac
