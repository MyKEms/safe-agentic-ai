#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# update.sh – Update an existing project with latest template files
# ─────────────────────────────────────────────────────────────────────────────
# Copies infrastructure files from the template to a project folder.
# Preserves project-specific files (.env, custom domains, workspace/).
#
# Usage:
#   ./update.sh ~/my-project-agent
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

B="\033[1m"
C="\033[36m"
G="\033[32m"
Y="\033[33m"
R="\033[31m"
D="\033[2m"
N="\033[0m"

TEMPLATE_DIR="$(cd "$(dirname "$0")" && pwd)"

# ─── Resolve target ──────────────────────────────────────────────────────
TARGET_DIR="${1:-}"
if [ -z "$TARGET_DIR" ]; then
  echo ""
  echo -e "${B}${C}  Safe Agentic AI — Update Project${N}"
  echo ""
  read -rp "  Project folder path: " TARGET_DIR
fi

if [ -z "$TARGET_DIR" ]; then
  echo -e "  ${R}No path provided. Aborting.${N}"
  exit 1
fi

# Expand ~ and make absolute
if [[ "$TARGET_DIR" == ~* ]]; then
  TARGET_DIR="${TARGET_DIR/#\~/$HOME}"
fi
case "$TARGET_DIR" in
  /*) ;;
  *)  TARGET_DIR="$(pwd)/$TARGET_DIR" ;;
esac

# Verify it's a project
if [ ! -f "$TARGET_DIR/.env" ]; then
  echo -e "${R}  ERROR: $TARGET_DIR doesn't look like a project (no .env found)${N}"
  exit 1
fi

echo ""
echo -e "${B}${C}  Safe Agentic AI — Update Project${N}"
echo -e "${D}  Template: $TEMPLATE_DIR${N}"
echo -e "${D}  Project:  $TARGET_DIR${N}"
echo ""

# ─── Show what will change ────────────────────────────────────────────────
CHANGES=0
for f in \
  .devcontainer/Dockerfile \
  .devcontainer/devcontainer.json \
  docker-compose.yml \
  proxy/squid.conf \
  scripts/setup-container.sh \
  scripts/welcome.sh \
  scripts/watchdog.sh \
  scripts/monitor.sh \
  scripts/proxy-ctl.sh \
  scripts/wipe.sh \
  scripts/preflight.sh \
  setup.sh \
  update.sh \
  .gitattributes \
  .gitignore \
  CLAUDE.md \
  README.md \
; do
  if [ -f "$TEMPLATE_DIR/$f" ]; then
    if [ ! -f "$TARGET_DIR/$f" ] || ! diff -q "$TEMPLATE_DIR/$f" "$TARGET_DIR/$f" &>/dev/null; then
      if [ "$CHANGES" -eq 0 ]; then
        echo -e "${B}  Files to update:${N}"
      fi
      if [ ! -f "$TARGET_DIR/$f" ]; then
        echo -e "    ${G}+ $f${N} (new)"
      else
        echo -e "    ${Y}~ $f${N}"
      fi
      CHANGES=$((CHANGES + 1))
    fi
  fi
done

if [ "$CHANGES" -eq 0 ]; then
  echo -e "  ${G}Project is already up to date.${N}"
  exit 0
fi

echo ""
echo -e "${B}  Not touched (project-specific):${N}"
echo -e "    ${D}.env${N}"
echo -e "    ${D}proxy/allowed-domains.txt${N}"
echo -e "    ${D}workspace/${N}"
echo ""

read -rp "  Apply updates? [Y/n]: " CONFIRM
if [ "${CONFIRM:-Y}" = "n" ]; then
  echo "  Cancelled."
  exit 0
fi

echo ""

# ─── Copy files ──────────────────────────────────────────────────────────
for f in \
  .devcontainer/Dockerfile \
  .devcontainer/devcontainer.json \
  docker-compose.yml \
  proxy/squid.conf \
  scripts/setup-container.sh \
  scripts/welcome.sh \
  scripts/watchdog.sh \
  scripts/monitor.sh \
  scripts/proxy-ctl.sh \
  scripts/wipe.sh \
  scripts/preflight.sh \
  setup.sh \
  update.sh \
  .gitattributes \
  .gitignore \
  CLAUDE.md \
  README.md \
; do
  if [ -f "$TEMPLATE_DIR/$f" ]; then
    mkdir -p "$TARGET_DIR/$(dirname "$f")"
    cp "$TEMPLATE_DIR/$f" "$TARGET_DIR/$f"
  fi
done

chmod +x "$TARGET_DIR/setup.sh" "$TARGET_DIR/update.sh" "$TARGET_DIR"/scripts/*.sh 2>/dev/null || true

echo -e "  ${G}$CHANGES file(s) updated.${N}"

# ─── Check allowed-domains.txt ───────────────────────────────────────────
# Update the base domains (above the "ADD YOUR DOMAINS" marker) while
# preserving the user's custom domains (below the marker)
MARKER="# ADD YOUR DOMAINS BELOW"
TEMPLATE_DOMAINS="$TEMPLATE_DIR/proxy/allowed-domains.txt"
PROJECT_DOMAINS="$TARGET_DIR/proxy/allowed-domains.txt"

if [ -f "$TEMPLATE_DOMAINS" ] && [ -f "$PROJECT_DOMAINS" ]; then
  # Extract base section from template (up to and including marker block)
  TEMPLATE_BASE=$(sed -n "1,/$MARKER/p" "$TEMPLATE_DOMAINS")
  # Extract user's custom domains (after the marker block + examples)
  USER_CUSTOM=$(sed -n "/$MARKER/,\$p" "$PROJECT_DOMAINS" | tail -n +1)

  if ! diff -q <(sed -n "1,/$MARKER/p" "$PROJECT_DOMAINS") <(echo "$TEMPLATE_BASE") &>/dev/null; then
    echo ""
    echo -e "  ${Y}Base domains updated in allowed-domains.txt${N}"
    echo -e "  ${D}Your custom domains (below '$MARKER') are preserved.${N}"
    # Write: template base + user's custom section
    echo "$TEMPLATE_BASE" > "$PROJECT_DOMAINS"
    echo "$USER_CUSTOM" >> "$PROJECT_DOMAINS"
    # Remove the duplicate marker line
    awk "!seen[\$0]++ || \$0 !~ /$MARKER/" "$PROJECT_DOMAINS" > "$PROJECT_DOMAINS.tmp" && mv "$PROJECT_DOMAINS.tmp" "$PROJECT_DOMAINS"
  fi
fi

# ─── Check .env for missing variables ────────────────────────────────────
echo ""
MISSING_VARS=""
for VAR in PROJECT_NAME PLATFORM; do
  if ! grep -q "^${VAR}=" "$TARGET_DIR/.env" 2>/dev/null; then
    MISSING_VARS="${MISSING_VARS}  ${VAR}\n"
  fi
done

if [ -n "$MISSING_VARS" ]; then
  echo -e "  ${Y}Your .env may need new variables. Run ./setup.sh to reconfigure,${N}"
  echo -e "  ${Y}or add them manually. Missing:${N}"
  echo -e "$MISSING_VARS"
fi

# ─── Done ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${B}  Rebuild to apply:${N}"
echo "    VS Code: Cmd+Shift+P → 'Dev Containers: Rebuild Container'"
echo "    CLI:     cd $TARGET_DIR && docker compose build --no-cache && docker compose up -d"
echo ""
