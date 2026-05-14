#!/usr/bin/env bash
# cc-rotate UserPromptSubmit hook
#
# Fires on every user prompt. If the prompt body contains a line starting with
# `!cc-rotate` (the Discord bridge rotation command), inject a protocol
# reminder into context so Claude is forced to follow the SOP in AGENTS.md.
#
# Defensive: NEVER block the prompt (no exit 2). Worst case = no reminder
# injected, Claude still sees the !cc-rotate text via the normal prompt path.
#
# Design ref: docs/plans/2026-05-14-cc-rotate-design.md §D4 (UserPromptSubmit hook)

set -uo pipefail
export PATH="$HOME/.local/bin:$PATH"

LOG() { echo "[cc-rotate/user-prompt-hook] $*" >&2; }

# Read entire stdin (hook JSON payload)
if ! command -v jq >/dev/null 2>&1; then
  exit 0  # silent no-op if jq missing
fi

payload=$(cat 2>/dev/null || true)
if [ -z "$payload" ]; then
  exit 0
fi

prompt=$(echo "$payload" | jq -r '.prompt // ""' 2>/dev/null || true)
if [ -z "$prompt" ]; then
  exit 0
fi

ENV_FILE="${CC_ROTATE_ENV:-$HOME/.claude/channels/discord-vibesync/cc-rotate.local.env}"
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  BOOTSTRAP_FILE="$CC_ROTATE_DIR/cc-rotate.bootstrap.json"
  BOOTSTRAP_HOOK="$VIBESYNC_REPO/tools/cc-rotate/bootstrap-hook.sh"
  CODEX_BRIDGE="$VIBESYNC_REPO/tools/codex-bridge/codex-discord-bridge.sh"

  # SessionStart hooks seed context, but Claude Code does not always create an
  # autonomous model turn after startup. If a bootstrap manifest is still
  # present when the next Discord/user prompt arrives, inject the same bootstrap
  # context again for this prompt so the new session must finish handoff intake
  # before doing fresh work.
  if [ -f "$BOOTSTRAP_FILE" ] && [ -x "$BOOTSTRAP_HOOK" ]; then
    CC_ROTATE_HOOK_EVENT_NAME=UserPromptSubmit "$BOOTSTRAP_HOOK"
    exit 0
  fi
fi

# Match a line that STARTS with !codex (after optional whitespace). This is a
# Discord bridge command, not ordinary chat. Execute the safe Phase 1 wrapper
# directly and inject the result so Claude must reply with concrete evidence
# (job id/result) instead of claiming Codex was consulted from memory.
if echo "$prompt" | grep -qE '^[[:space:]]*!codex([[:space:]]|$)'; then
  if [ -n "${CODEX_BRIDGE:-}" ] && [ -x "$CODEX_BRIDGE" ]; then
    bridge_output="$("$CODEX_BRIDGE" "$prompt" 2>&1 || true)"
  else
    bridge_output="Codex bridge is not installed or not executable at ${CODEX_BRIDGE:-unknown}."
  fi

  reminder="[CODEX BRIDGE REQUEST DETECTED: !codex]

This is NOT a normal chat message. The repo wrapper has already executed (or attempted to execute) the safe Phase 1 Codex bridge.

Bridge output:
\`\`\`
$bridge_output
\`\`\`

Mandatory behavior:
1. Reply to Discord with the bridge output in a concise phone-friendly form.
2. Do NOT say Codex reviewed anything unless the bridge output includes a job id or concrete result.
3. Do NOT start extra implementation work from this message.
4. If the output says a job was queued, tell Eric/Bruce to use \`!codex status <job-id>\` and then \`!codex result <job-id>\`."

  jq -nc --arg ctx "$reminder" '{
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit",
      additionalContext: $ctx
    }
  }'
  exit 0
fi

# Match a line that STARTS with !cc-rotate (after optional whitespace).
# This avoids false positives on prompts that merely *mention* the command
# (e.g. "what does !cc-rotate do?").
if ! echo "$prompt" | grep -qE '^[[:space:]]*!cc-rotate([[:space:]]|$)'; then
  exit 0
fi

# Inject protocol reminder as additional context
reminder='[ROTATION REQUEST DETECTED: !cc-rotate]

This is NOT a normal chat message. It is a Discord bridge command that requires the **Rotation Protocol** defined in `docs/shared-agent-rules.md` (canonical Shared rule).

**Mandatory steps before any other action:**

1. Read `docs/shared-agent-rules.md` section "Rotation Protocol (!cc-rotate)" to load the exact 10-step SOP.
2. Execute the 10 steps in order. Do NOT improvise reply formats. Do NOT skip validation.
3. Reply formats, JSON schema for `cc-rotate.request.json`, and failure message format are defined there - use them verbatim.

**User is on mobile Discord - keep all replies phone-screen friendly (8 lines or fewer).**

If you have not read the shared-agent-rules Rotation Protocol section in this session, read it NOW as your first action.'

jq -nc --arg ctx "$reminder" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'
exit 0
