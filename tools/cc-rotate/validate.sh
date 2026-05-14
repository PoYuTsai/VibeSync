#!/usr/bin/env bash
# cc-rotate validate — external hard-block checks (B1-B4)
#
# Output: JSON to stdout
#   pass: {"ok":true, "blocks":[]}
#   fail: {"ok":false, "blocks":[{"code":"B1","msg":"..."}, ...]}
# Exit:
#   0 = pass
#   1 = at least one block triggered (B1-B4)
#   2 = setup error (config missing / VIBESYNC_REPO not a git repo / jq missing)
#
# Design ref: docs/plans/2026-05-14-cc-rotate-design.md §D3

set -euo pipefail

ENV_FILE="${CC_ROTATE_ENV:-$HOME/.claude/channels/discord-vibesync/cc-rotate.local.env}"

emit_setup_error() {
  printf '{"ok":false,"blocks":[{"code":"SETUP","msg":%s}]}\n' "$(printf '%s' "$1" | jq -Rs . 2>/dev/null || printf '"%s"' "$1")"
  exit 2
}

if ! command -v jq >/dev/null 2>&1; then
  printf '{"ok":false,"blocks":[{"code":"SETUP","msg":"jq not installed — sudo apt install jq"}]}\n'
  exit 2
fi

if [ ! -f "$ENV_FILE" ]; then
  emit_setup_error "cc-rotate.local.env not found at $ENV_FILE — see tools/cc-rotate/README.md step 2"
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

: "${VIBESYNC_REPO:?VIBESYNC_REPO not set in $ENV_FILE}"
: "${CC_ROTATE_DIR:?CC_ROTATE_DIR not set in $ENV_FILE}"
LOCK_STALE_SECONDS="${LOCK_STALE_SECONDS:-120}"

if [ ! -d "$VIBESYNC_REPO/.git" ]; then
  emit_setup_error "$VIBESYNC_REPO is not a git repository"
fi

# Cross-platform mtime (GNU stat on Linux/WSL, BSD stat on macOS)
file_mtime() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0
}

cd "$VIBESYNC_REPO"

blocks=()

# === B1: working tree dirty ===
dirty_total=$(git status --porcelain | wc -l | tr -d ' ')
if [ "$dirty_total" -gt 0 ]; then
  sample=$(git status --porcelain | head -5 | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')
  if [ "$dirty_total" -gt 5 ]; then
    sample="${sample}, ...(+$((dirty_total - 5)) more)"
  fi
  blocks+=("$(jq -nc --arg msg "$dirty_total 個未 commit 變更：$sample" '{code:"B1", msg:$msg}')")
fi

# === B2: mid-rebase / mid-merge ===
if [ -e ".git/REBASE_HEAD" ] || [ -d ".git/rebase-merge" ] || [ -d ".git/rebase-apply" ]; then
  blocks+=("$(jq -nc '{code:"B2", msg:"mid-rebase 進行中（.git/rebase-* 存在）"}')")
fi
if [ -e ".git/MERGE_HEAD" ]; then
  blocks+=("$(jq -nc '{code:"B2", msg:"mid-merge 進行中（.git/MERGE_HEAD 存在）"}')")
fi

# === B3: ahead of origin ===
ahead_line=$(git status -sb 2>/dev/null | head -1 || true)
if echo "$ahead_line" | grep -q 'ahead'; then
  ahead_n=$(echo "$ahead_line" | sed -nE 's/.*ahead ([0-9]+).*/\1/p')
  ahead_n="${ahead_n:-?}"
  blocks+=("$(jq -nc --arg n "$ahead_n" '{code:"B3", msg:("本地 " + $n + " 個 commit 未 push 到 origin")}')")
fi

# === B4: rotate lock present (with stale auto-recover) ===
LOCK_FILE="$CC_ROTATE_DIR/cc-rotate.lock"
if [ -f "$LOCK_FILE" ]; then
  lock_mtime=$(file_mtime "$LOCK_FILE")
  now=$(date +%s)
  lock_age=$((now - lock_mtime))
  if [ "$lock_age" -lt "$LOCK_STALE_SECONDS" ]; then
    blocks+=("$(jq -nc --arg age "$lock_age" '{code:"B4", msg:("另一 rotate 進行中（lock " + $age + "s old, threshold=" + (env.LOCK_STALE_SECONDS // "120") + "s）")}')")
  fi
  # else: stale — let supervisor clear it on next spawn
fi

# === Emit ===
if [ ${#blocks[@]} -eq 0 ]; then
  printf '{"ok":true,"blocks":[]}\n'
  exit 0
else
  joined=$(IFS=,; printf '%s' "${blocks[*]}")
  printf '{"ok":false,"blocks":[%s]}\n' "$joined"
  exit 1
fi
