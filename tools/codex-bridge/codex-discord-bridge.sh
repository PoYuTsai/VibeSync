#!/usr/bin/env bash
# Discord-facing Codex bridge wrapper.
#
# Phase 1 is intentionally read-only:
# - starts background Codex review tasks
# - reads status/result
# - cancels active jobs
# - never exposes arbitrary shell or write-enabled Codex tasks

set -uo pipefail
export PATH="$HOME/.local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMPANION="${CODEX_COMPANION:-$HOME/.claude/plugins/cache/openai-codex/codex/1.0.2/scripts/codex-companion.mjs}"
export CLAUDE_PLUGIN_DATA="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugins/data/codex-openai-codex}"

usage() {
  cat <<'EOF'
Usage:
  !codex review [latest|<base-ref>]
  !codex adversarial-review [latest|<base-ref>]
  !codex setup
  !codex status [job-id]
  !codex result [job-id]
  !codex cancel [job-id]

Phase 1 is read-only. No !codex task / write commands are enabled.
EOF
}

fail() {
  echo "❌ Codex bridge refused: $*"
  echo
  usage
}

extract_command_line() {
  local raw="$1"
  local line trimmed
  while IFS= read -r line; do
    trimmed="${line#"${line%%[![:space:]]*}"}"
    case "$trimmed" in
      "!codex"|"!codex "*) printf '%s\n' "$trimmed"; return 0 ;;
    esac
  done <<< "$raw"
}

safe_ref() {
  [[ "$1" =~ ^[A-Za-z0-9._/@~+-]+$ ]]
}

ensure_runtime() {
  if [ ! -f "$COMPANION" ]; then
    echo "❌ Codex bridge is not ready: missing codex-companion at $COMPANION"
    return 1
  fi
  if ! command -v node >/dev/null 2>&1; then
    echo "❌ Codex bridge is not ready: node is not available on PATH."
    return 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "❌ Codex bridge is not ready: jq is not available on PATH."
    return 1
  fi
}

require_clean_tree() {
  local dirty
  dirty="$(git -C "$REPO_ROOT" status --porcelain)"
  if [ -n "$dirty" ]; then
    echo "❌ Codex review blocked: working tree is dirty."
    echo "CC must commit/push the hotfix before asking Codex to review."
    echo
    git -C "$REPO_ROOT" status --short
    return 1
  fi
}

resolve_base_ref() {
  local requested="${1:-latest}"
  if [ "$requested" = "latest" ]; then
    echo "HEAD~1"
    return 0
  fi
  if ! safe_ref "$requested"; then
    echo "❌ Unsupported base ref: $requested" >&2
    return 1
  fi
  echo "$requested"
}

write_review_prompt() {
  local kind="$1"
  local base_ref="$2"
  local head_short
  head_short="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"

  local prompt_file
  prompt_file="$(mktemp "${TMPDIR:-/tmp}/vibesync-codex-review.XXXXXX.md")"

  cat >"$prompt_file" <<EOF
You are Codex reviewing a VibeSync first-line Discord hotfix while Eric is away from the computer.

Mode: READ-ONLY REVIEW. Do not edit files. Do not commit. Do not push.
Review type: $kind
Target diff: \`$base_ref..HEAD\`
Current HEAD: \`$head_short\`

Mandatory context:
1. Read \`AGENTS.md\`.
2. Read \`docs/shared-agent-rules.md\`, especially "External Codex Review Gate".
3. Read \`docs/snapshot.md\`.
4. Inspect \`git diff --stat $base_ref..HEAD\` and \`git diff $base_ref..HEAD\`.

Review rules:
- Output exactly one verdict: APPROVED, REVISE_REQUIRED, or NEEDS_ERIC.
- P0/P1/P2 findings block dogfood.
- P3 suggestions do not block; mention them separately only if useful.
- Required findings must cite evidence: file path/line, commit hash, failing test/log, or exact diff behavior.
- If the fix touches subscription/paywall/quota/RevenueCat/auth/data deletion/Hive schema/analyze-chat/opener/OCR/Edge schema/AI prompt/token cost, be extra skeptical.
- If the bug report or product intent is ambiguous, use NEEDS_ERIC rather than guessing.
- Do not claim tests passed unless you actually ran or saw them.

Response format:

Codex Review: APPROVED | REVISE_REQUIRED | NEEDS_ERIC
Target: $base_ref..HEAD @ $head_short

Findings:
- [P0/P1/P2 only for required fixes, or "None"]

P3 / Non-blocking:
- [optional]

Evidence:
- [files/lines/commands/logs inspected]

Next:
- [CC fix P1/P2, Eric/Bruce can dogfood, or wait Eric decision]
EOF

  echo "$prompt_file"
}

start_review_job() {
  local kind="$1"
  local requested_ref="${2:-latest}"

  ensure_runtime || return 1
  require_clean_tree || return 1

  local base_ref
  if ! base_ref="$(resolve_base_ref "$requested_ref")"; then
    return 1
  fi
  if ! git -C "$REPO_ROOT" rev-parse --verify "$base_ref" >/dev/null 2>&1; then
    echo "❌ Codex review blocked: base ref '$base_ref' does not exist."
    return 1
  fi

  local prompt_file
  prompt_file="$(write_review_prompt "$kind" "$base_ref")"

  local output status job_id
  output="$(
    node "$COMPANION" task --background --fresh --cwd "$REPO_ROOT" --prompt-file "$prompt_file" --json 2>&1
  )"
  status=$?
  rm -f "$prompt_file"

  if [ "$status" -ne 0 ]; then
    if printf '%s' "$output" | grep -qi "not authenticated"; then
      echo "❌ Codex review failed to start: Codex CLI is not authenticated."
      echo "On the Ubuntu terminal, run once:"
      echo "  codex login --device-auth"
      echo "Then verify from Discord:"
      echo "  !codex setup"
      return "$status"
    fi
    echo "❌ Codex review failed to start."
    echo "$output"
    return "$status"
  fi

  job_id="$(printf '%s' "$output" | jq -r '.jobId // empty' 2>/dev/null || true)"
  if [ -z "$job_id" ]; then
    echo "❌ Codex review started but no job id was returned."
    echo "$output"
    return 1
  fi

  echo "✅ Codex $kind queued."
  echo "Job: $job_id"
  echo "Target: $base_ref..HEAD"
  echo "Mode: read-only background review"
  echo "Next: !codex status $job_id"
  echo "Then: !codex result $job_id"
}

run_companion() {
  local subcommand="$1"
  shift || true

  ensure_runtime || return 1
  node "$COMPANION" "$subcommand" "$@" --cwd "$REPO_ROOT" 2>&1
}

run_setup() {
  local output

  ensure_runtime || return 1
  output="$(node "$COMPANION" setup --cwd "$REPO_ROOT" 2>&1)"
  printf '%s\n' "$output" | sed \
    -e 's/Run `!codex login`./Run `codex login --device-auth` once in the Ubuntu terminal./' \
    -e 's/If browser login is blocked, retry with `!codex login --device-auth` or `!codex login --with-api-key`./Discord Phase 1 does not run login. After terminal login, retry `!codex setup`./' \
    -e '/Optional: run `\/codex:setup --enable-review-gate`/d'
}

main() {
  local raw="${*:-}"
  if [ -z "$raw" ]; then
    raw="$(cat 2>/dev/null || true)"
  fi

  local line
  line="$(extract_command_line "$raw")"
  if [ -z "$line" ]; then
    fail "no !codex command found"
    return 1
  fi

  local rest="${line#!codex}"
  rest="${rest#"${rest%%[![:space:]]*}"}"
  local tokens=()
  if [ -n "$rest" ]; then
    read -r -a tokens <<< "$rest"
  fi
  local command="${tokens[0]:-help}"
  local arg1="${tokens[1]:-}"
  local arg2="${tokens[2]:-}"

  case "$command" in
    help|"")
      usage
      ;;
    review)
      if [ -n "$arg2" ]; then
        fail "review accepts at most one target: latest or <base-ref>"
        return 1
      fi
      start_review_job "review" "${arg1:-latest}"
      ;;
    adversarial-review)
      if [ -n "$arg2" ]; then
        fail "adversarial-review accepts at most one target: latest or <base-ref>"
        return 1
      fi
      start_review_job "adversarial-review" "${arg1:-latest}"
      ;;
    setup)
      if [ -n "$arg1" ]; then
        fail "setup does not accept arguments in Discord Phase 1"
        return 1
      fi
      run_setup
      ;;
    status)
      run_companion status ${arg1:+"$arg1"}
      ;;
    result)
      run_companion result ${arg1:+"$arg1"}
      ;;
    cancel)
      run_companion cancel ${arg1:+"$arg1"}
      ;;
    login)
      echo "❌ Codex login is not run from Discord in Phase 1."
      echo "On the Ubuntu terminal, run once:"
      echo "  codex login --device-auth"
      echo "Then verify from Discord:"
      echo "  !codex setup"
      return 1
      ;;
    task|rescue|fix|write)
      fail "'$command' is not enabled in Discord Phase 1"
      return 1
      ;;
    *)
      fail "unknown command '$command'"
      return 1
      ;;
  esac
}

main "$@"
