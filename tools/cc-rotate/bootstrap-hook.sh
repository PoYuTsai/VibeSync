#!/usr/bin/env bash
# cc-rotate SessionStart hook
#
# Fires on every Claude Code session start. If a cc-rotate.bootstrap.json exists
# (left by supervisor after a rotation), expand the prompt template and inject
# it as additional context via JSON output.
#
# The same script can also be reused by UserPromptSubmit as a fallback by
# setting CC_ROTATE_HOOK_EVENT_NAME=UserPromptSubmit. This covers the important
# edge case where SessionStart adds context but does not trigger an autonomous
# model turn.
#
# Defensive principle: NEVER block session start (no exit 2). On any failure,
# log to stderr and exit 0 with no output — worst case is a missed rotation
# bootstrap, which the user can recover from manually.
#
# Design ref: docs/plans/2026-05-14-cc-rotate-design.md §D4

set -uo pipefail
export PATH="$HOME/.local/bin:$PATH"

ENV_FILE="${CC_ROTATE_ENV:-$HOME/.claude/channels/discord-vibesync/cc-rotate.local.env}"
LOG() { echo "[cc-rotate/bootstrap-hook] $*" >&2; }

if [ ! -f "$ENV_FILE" ]; then
  exit 0  # No cc-rotate setup on this machine; silent no-op
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

BOOTSTRAP_TTL_SECONDS="${BOOTSTRAP_TTL_SECONDS:-1800}"
BOOTSTRAP_FILE="$CC_ROTATE_DIR/cc-rotate.bootstrap.json"
TEMPLATE_FILE="$VIBESYNC_REPO/tools/cc-rotate/bootstrap-prompt.tmpl"

if [ ! -f "$BOOTSTRAP_FILE" ]; then
  exit 0  # Normal cold start
fi

if [ ! -f "$TEMPLATE_FILE" ]; then
  LOG "Template missing: $TEMPLATE_FILE"
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  LOG "jq not installed — cannot parse bootstrap.json"
  exit 0
fi

# Cross-platform mtime
file_mtime() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0
}

# R3: TTL stale check
boot_mtime=$(file_mtime "$BOOTSTRAP_FILE")
now=$(date +%s)
age=$((now - boot_mtime))
if [ "$age" -gt "$BOOTSTRAP_TTL_SECONDS" ]; then
  LOG "Stale bootstrap.json discarded (age=${age}s > TTL=${BOOTSTRAP_TTL_SECONDS}s)"
  rm -f "$BOOTSTRAP_FILE"
  exit 0
fi

# Validate JSON shape
if ! jq empty "$BOOTSTRAP_FILE" 2>/dev/null; then
  LOG "Malformed bootstrap.json — discarding"
  rm -f "$BOOTSTRAP_FILE"
  exit 0
fi

# Extract fields with defaults
ts=$(jq -r '.ts // "unknown"' "$BOOTSTRAP_FILE")
old_head=$(jq -r '.head_commit // "unknown"' "$BOOTSTRAP_FILE")
dc_channel=$(jq -r '.discord_channel_id // "unknown"' "$BOOTSTRAP_FILE")
handoff_path=$(jq -r '.handoff_path // "unknown"' "$BOOTSTRAP_FILE")
warnings_count=$(jq -r '.warnings // [] | length' "$BOOTSTRAP_FILE")

if [ "$warnings_count" -eq 0 ]; then
  warnings_block="(none)"
else
  warnings_block=$(jq -r '.warnings // [] | map("- " + .) | join("\n")' "$BOOTSTRAP_FILE")
fi

# Derived repo paths
agents_path="$VIBESYNC_REPO/AGENTS.md"
shared_rules_path="$VIBESYNC_REPO/docs/shared-agent-rules.md"
snapshot_path="$VIBESYNC_REPO/docs/snapshot.md"
bug_log_path="$VIBESYNC_REPO/docs/bug-log.md"
queue_path="$VIBESYNC_REPO/docs/reviews/ai-arbitration-queue.md"

# Substitute via bash parameter expansion (literal replacement, no regex pitfalls)
template=$(cat "$TEMPLATE_FILE")
template="${template//\{\{TS\}\}/$ts}"
template="${template//\{\{OLD_HEAD\}\}/$old_head}"
template="${template//\{\{DISCORD_CHANNEL_ID\}\}/$dc_channel}"
template="${template//\{\{HANDOFF_PATH\}\}/$handoff_path}"
template="${template//\{\{AGENTS_MD_PATH\}\}/$agents_path}"
template="${template//\{\{SHARED_RULES_PATH\}\}/$shared_rules_path}"
template="${template//\{\{SNAPSHOT_PATH\}\}/$snapshot_path}"
template="${template//\{\{BUG_LOG_PATH\}\}/$bug_log_path}"
template="${template//\{\{QUEUE_PATH\}\}/$queue_path}"
template="${template//\{\{BOOTSTRAP_JSON_PATH\}\}/$BOOTSTRAP_FILE}"
template="${template//\{\{WARNINGS_BLOCK\}\}/$warnings_block}"

# Emit as Claude Code hook JSON for explicit additionalContext attachment.
hook_event_name="${CC_ROTATE_HOOK_EVENT_NAME:-SessionStart}"
output=$(jq -nc --arg ctx "$template" --arg hook_event_name "$hook_event_name" '{
  hookSpecificOutput: {
    hookEventName: $hook_event_name,
    additionalContext: $ctx
  }
}')

# SessionStart additionalContext does not always create an autonomous model turn,
# so keep bootstrap.json for the UserPromptSubmit fallback. Once the fallback has
# emitted the same context into a real user turn, remove the manifest here instead
# of asking Claude Code to delete a sensitive channel-runtime file interactively.
if [ "$hook_event_name" = "UserPromptSubmit" ]; then
  rm -f "$BOOTSTRAP_FILE" 2>/dev/null || LOG "Unable to remove bootstrap.json after UserPromptSubmit fallback"
fi

printf '%s\n' "$output"
exit 0
