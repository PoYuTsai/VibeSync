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

# Match a line that STARTS with !cc-rotate (after optional whitespace).
# This avoids false positives on prompts that merely *mention* the command
# (e.g. "what does !cc-rotate do?").
if ! echo "$prompt" | grep -qE '^[[:space:]]*!cc-rotate([[:space:]]|$)'; then
  exit 0
fi

# Inject protocol reminder as additional context
reminder='🔄 **ROTATION REQUEST DETECTED: `!cc-rotate`**

This is NOT a normal chat message. It is a Discord bridge command that requires the **Rotation Protocol** defined in `docs/shared-agent-rules.md` (canonical Shared rule).

**Mandatory steps before any other action:**

1. Read `docs/shared-agent-rules.md` section "Rotation Protocol (!cc-rotate)" to load the exact 10-step SOP.
2. Execute the 10 steps in order. Do NOT improvise reply formats. Do NOT skip validation.
3. Reply formats, JSON schema for `cc-rotate.request.json`, and failure message format are defined there — use them verbatim.

**User is on mobile Discord — keep all replies phone-screen friendly (≤ 8 lines).**

If you have not read the shared-agent-rules Rotation Protocol section in this session, read it NOW as your first action.'

jq -nc --arg ctx "$reminder" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'
exit 0
