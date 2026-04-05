#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# monitor.sh – Live dashboard for Claude Code container
# ─────────────────────────────────────────────────────────────────────────────
# Usage (from host):
#   ./scripts/monitor.sh              # single snapshot
#   ./scripts/monitor.sh --loop       # live refresh (default 5s)
#   ./scripts/monitor.sh --loop 3     # live refresh every 3s
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

B="\033[1m"
D="\033[2m"
G="\033[32m"
Y="\033[33m"
R="\033[31m"
C="\033[36m"
N="\033[0m"
BG_R="\033[41m"
BG_G="\033[42m"
BG_Y="\033[43m"

# ─── Resolve project name for container names ────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_NAME=$(grep '^PROJECT_NAME=' "$SCRIPT_DIR/../.env" 2>/dev/null | cut -d= -f2 | tr -d '"' | tr -d "'")
PROJECT_NAME="${PROJECT_NAME:-claude}"
PROXY_CONTAINER="${PROJECT_NAME}-proxy"
WS_CONTAINER="${PROJECT_NAME}-workspace"

status_badge() {
  case "$1" in
    running) echo -e "${BG_G}${B} RUNNING ${N}" ;;
    healthy) echo -e "${BG_G}${B} HEALTHY ${N}" ;;
    exited)  echo -e "${BG_R}${B} EXITED  ${N}" ;;
    stopped) echo -e "${BG_Y}${B} STOPPED ${N}" ;;
    *)       echo -e "${BG_R}${B} $1 ${N}" ;;
  esac
}

render() {
  local COLS
  COLS=$(tput cols 2>/dev/null || echo 80)
  local LINE
  LINE=$(printf '─%.0s' $(seq 1 "$COLS"))

  echo -e "${B}${C}  Safe Agentic AI — Monitor${N}  ${D}$(date '+%Y-%m-%d %H:%M:%S')${N}"
  echo -e "${D}${LINE}${N}"

  # ─── Containers overview ────────────────────────────────────────────────
  echo -e "${B}  Containers${N}"
  echo ""

  for SVC in $WS_CONTAINER $PROXY_CONTAINER; do
    local NAME=${SVC#${PROJECT_NAME}-}
    local STATUS
    STATUS=$(docker inspect -f '{{.State.Status}}' "$SVC" 2>/dev/null || echo "not found")
    local HEALTH
    HEALTH=$(docker inspect -f '{{.State.Health.Status}}' "$SVC" 2>/dev/null || echo "")

    local BADGE
    if [ "$HEALTH" = "healthy" ]; then
      BADGE=$(status_badge "healthy")
    elif [ "$STATUS" = "running" ]; then
      BADGE=$(status_badge "running")
    elif [ "$STATUS" = "exited" ]; then
      BADGE=$(status_badge "exited")
    elif [ "$STATUS" = "not found" ]; then
      BADGE=$(status_badge "stopped")
    else
      BADGE=$(status_badge "$STATUS")
    fi

    if [ "$STATUS" = "running" ]; then
      local STATS
      STATS=$(docker stats "$SVC" --no-stream --format '{{.CPUPerc}}\t{{.MemUsage}}' 2>/dev/null)
      local S_CPU S_MEM
      S_CPU=$(echo "$STATS" | cut -f1)
      S_MEM=$(echo "$STATS" | cut -f2)
      printf "  %-12s %b CPU: %b%-7s%b RAM: %b%s%b\n" "$NAME" "$BADGE" "$C" "$S_CPU" "$N" "$C" "$S_MEM" "$N"
    else
      printf "  %-12s %b\n" "$NAME" "$BADGE"
    fi
  done

  echo ""
  echo -e "${D}${LINE}${N}"

  # ─── Claude process ─────────────────────────────────────────────────────
  local WS_STATUS
  WS_STATUS=$(docker inspect -f '{{.State.Status}}' $WS_CONTAINER 2>/dev/null || echo "off")
  if [ "$WS_STATUS" != "running" ]; then
    echo -e "  ${R}Workspace container is not running${N}"
    return
  fi

  echo -e "${B}  Claude Process${N}"
  echo ""
  docker exec $WS_CONTAINER bash -c '
    PIDS=$(pgrep -f "^claude" 2>/dev/null || true)
    if [ -z "$PIDS" ]; then
      echo "  \033[2m(not running)\033[0m"
    else
      for P in $PIDS; do
        RSS=$(awk "/VmRSS/{print \$2}" /proc/$P/status 2>/dev/null || echo "?")
        RSS_MB=$(( RSS / 1024 ))
        TIME=$(ps -o etime= -p $P 2>/dev/null | xargs)
        THREADS=$(ls /proc/$P/task 2>/dev/null | wc -l)
        echo "  \033[36mPID $P\033[0m  |  ${RSS_MB}MB RSS  |  ${THREADS} threads  |  uptime: $TIME"
      done
    fi
  ' 2>/dev/null
  echo ""
  echo -e "${D}${LINE}${N}"

  # ─── Network connections ────────────────────────────────────────────────
  echo -e "${B}  Network${N}"
  echo ""
  local CONNS
  CONNS=$(docker exec $WS_CONTAINER ss -tnp 2>/dev/null | awk '
    /ESTAB/ && /proxy:3128/ {
      match($0, /users:\(\("([^"]+)"/, a)
      print "proxy  " a[1]
    }
    /ESTAB/ && !/127\.0\.0\.1/ && !/proxy:3128/ {
      match($0, /users:\(\("([^"]+)"/, a)
      print "other  " a[1] " -> " $5
    }
  ' 2>/dev/null)

  local PROXY_N OTHER_N
  PROXY_N=$(echo "$CONNS" | grep -c "^proxy" || true)
  OTHER_N=$(echo "$CONNS" | grep -c "^other" || true)

  echo -e "  Proxy: ${C}${PROXY_N}${N} conn  |  Other: ${C}${OTHER_N}${N}"
  echo ""
  echo -e "${D}${LINE}${N}"

  # ─── Proxy log ──────────────────────────────────────────────────────────
  echo -e "${B}  Proxy Activity (last 8)${N}"
  echo ""
  docker exec $PROXY_CONTAINER tail -8 /var/log/squid/access.log 2>/dev/null | awk '{
    split($4, t, ":")
    time = t[2]":"t[3]":"t[4]
    status = $6
    method = $7
    url = $8
    if (length(url) > 55) url = substr(url, 1, 52) "..."
    if (status ~ /2[0-9][0-9]/) color = "\033[32m"
    else if (status ~ /4[0-9][0-9]/) color = "\033[31m"
    else if (status ~ /TCP_TUNNEL/) color = "\033[36m"
    else color = "\033[33m"
    printf "  \033[2m%s\033[0m %s%-3s\033[0m %-8s %s\n", time, color, status, method, url
  }' 2>/dev/null
  echo ""
  echo -e "${D}${LINE}${N}"

  # ─── Blocked requests ──────────────────────────────────────────────────
  local DENIED
  DENIED=$(docker exec $PROXY_CONTAINER grep -c "TCP_DENIED" /var/log/squid/access.log 2>/dev/null || echo 0)
  local RECENT_DENIED
  RECENT_DENIED=$(docker exec $PROXY_CONTAINER tail -100 /var/log/squid/access.log 2>/dev/null | grep "TCP_DENIED" | tail -3)

  if [ "$DENIED" -gt 0 ] 2>/dev/null; then
    echo -e "${B}  ${R}Blocked Requests${N} ${D}(${DENIED} total)${N}"
    echo ""
    if [ -n "$RECENT_DENIED" ]; then
      echo "$RECENT_DENIED" | awk '{
        split($4, t, ":")
        time = t[2]":"t[3]":"t[4]
        method = $7
        url = $8
        if (length(url) > 55) url = substr(url, 1, 52) "..."
        printf "  \033[31m%s\033[0m  %s %s\n", time, method, url
      }'
    fi
    echo ""
    echo -e "${D}${LINE}${N}"
  fi

  # ─── SSH agent ──────────────────────────────────────────────────────────
  echo -e "${B}  SSH Agent${N}"
  echo ""
  local KEYS
  KEYS=$(docker exec $WS_CONTAINER ssh-add -l 2>&1)
  if echo "$KEYS" | grep -q "SHA256"; then
    echo "$KEYS" | while read -r _ HASH NAME _; do
      echo -e "  ${G}*${N} ${NAME} ${D}(${HASH})${N}"
    done
  else
    echo -e "  ${Y}not available${N} ${D}(check SSH agent on host)${N}"
  fi
  echo ""
  echo -e "${D}${LINE}${N}"
}

# ─── Main ────────────────────────────────────────────────────────────────────
if [ "${1:-}" = "--loop" ]; then
  INTERVAL="${2:-5}"
  trap 'tput cnorm 2>/dev/null; exit 0' SIGINT SIGTERM
  tput civis 2>/dev/null
  while true; do
    tput cup 0 0 2>/dev/null
    tput ed 2>/dev/null
    render
    sleep "$INTERVAL"
  done
else
  render
fi
