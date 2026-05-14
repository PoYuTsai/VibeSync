#!/usr/bin/env bash
# cc-rotate supervisor — outer loop that owns the claude process lifecycle.
#
# Responsibility:
#   - Spawn Claude Code with Discord plugin attached
#   - Watch ~/.claude/channels/discord-vibesync/cc-rotate.request.json for create
#   - On rotation signal: SIGTERM old claude, escalate to SIGKILL on timeout,
#     atomically rename request → bootstrap, then spawn fresh claude
#   - Exit cleanly if claude terminates without a rotation request
#
# Triggered by:  ~/.claude/channels/discord-vibesync/start.sh (after sourcing
#                cc-rotate.local.env, then `exec` into this script)
#
# Design ref:  docs/plans/2026-05-14-cc-rotate-design.md §D4 architecture

set -uo pipefail

# ── Configuration ────────────────────────────────────────────────────
ENV_FILE="${CC_ROTATE_ENV:-$HOME/.claude/channels/discord-vibesync/cc-rotate.local.env}"

if [ ! -f "$ENV_FILE" ]; then
  echo "[cc-rotate/supervisor] FATAL: cc-rotate.local.env not found at $ENV_FILE" >&2
  echo "                     See tools/cc-rotate/README.md step 2" >&2
  exit 2
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

: "${VIBESYNC_REPO:?VIBESYNC_REPO not set in $ENV_FILE}"
: "${CC_ROTATE_DIR:?CC_ROTATE_DIR not set in $ENV_FILE}"
: "${CLAUDE_CMD:?CLAUDE_CMD not set in $ENV_FILE}"

SIGTERM_TIMEOUT_SECONDS="${SIGTERM_TIMEOUT_SECONDS:-30}"
LOCK_STALE_SECONDS="${LOCK_STALE_SECONDS:-120}"
INOTIFY_TIMEOUT_SECONDS="${INOTIFY_TIMEOUT_SECONDS:-60}"  # internal: how long to block in inotifywait before re-checking claude liveness

REQUEST_FILE="$CC_ROTATE_DIR/cc-rotate.request.json"
BOOTSTRAP_FILE="$CC_ROTATE_DIR/cc-rotate.bootstrap.json"
LOCK_FILE="$CC_ROTATE_DIR/cc-rotate.lock"
PID_FILE="$CC_ROTATE_DIR/bridge.pid"

LOG() { echo "[cc-rotate/supervisor $(date +%H:%M:%S)] $*" >&2; }

# ── Dependency check ────────────────────────────────────────────────
for dep in inotifywait jq; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    LOG "FATAL: '$dep' not installed. Run: sudo apt install inotify-tools jq"
    exit 2
  fi
done

if [ ! -d "$CC_ROTATE_DIR" ]; then
  LOG "FATAL: CC_ROTATE_DIR does not exist: $CC_ROTATE_DIR"
  exit 2
fi

# ── Cross-platform mtime helper ─────────────────────────────────────
file_mtime() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0
}

# ── Pre-flight cleanup (handle crashes in prior runs) ───────────────
preflight_cleanup() {
  # Stale lock from a crashed previous rotation
  if [ -f "$LOCK_FILE" ]; then
    local age=$(($(date +%s) - $(file_mtime "$LOCK_FILE")))
    if [ "$age" -gt "$LOCK_STALE_SECONDS" ]; then
      LOG "Removing stale lock (age=${age}s > ${LOCK_STALE_SECONDS}s)"
      rm -f "$LOCK_FILE"
    else
      LOG "FATAL: lock present and fresh (${age}s old). Another supervisor running? Remove $LOCK_FILE manually if not."
      exit 2
    fi
  fi

  # Orphaned request from a crashed claude that wrote request.json but supervisor
  # never picked it up. Safe to delete — no live rotation in flight.
  if [ -f "$REQUEST_FILE" ]; then
    LOG "Removing orphaned request.json from prior run"
    rm -f "$REQUEST_FILE"
  fi

  # bootstrap.json may linger from prior rotation if new session never deleted it.
  # The SessionStart hook handles TTL; we do not touch it here.
}

# ── Spawn one claude session ────────────────────────────────────────
CLAUDE_PID=""
spawn_claude() {
  LOG "Spawning: $CLAUDE_CMD"
  # Subshell + exec: subshell PID becomes claude PID after exec; clean SIGTERM target.
  # shellcheck disable=SC2086
  ( exec $CLAUDE_CMD ) &
  CLAUDE_PID=$!
  echo "$CLAUDE_PID" > "$PID_FILE"
  LOG "claude pid=$CLAUDE_PID"
}

# ── Wait for rotation request OR claude exit ────────────────────────
# Returns 0 if rotation requested (REQUEST_FILE present), 1 if claude died first.
wait_for_rotation_or_exit() {
  while kill -0 "$CLAUDE_PID" 2>/dev/null; do
    # Race-safe: check before waiting (request.json could have appeared between
    # last check and inotifywait registration)
    if [ -f "$REQUEST_FILE" ]; then
      return 0
    fi

    # Block on directory events with timeout. Timeout lets us re-check claude
    # liveness periodically — protects against the race where claude exits
    # while we're blocked in inotifywait.
    inotifywait -q -t "$INOTIFY_TIMEOUT_SECONDS" \
      -e create,moved_to,close_write \
      "$CC_ROTATE_DIR" >/dev/null 2>&1 || true
    # inotifywait exit codes: 0 = event, 1 = error, 2 = timeout.
    # We don't branch on exit code — we just re-check REQUEST_FILE and liveness.
  done

  # claude died
  return 1
}

# ── Perform the rotation handoff ────────────────────────────────────
perform_rotation() {
  local old_pid="$CLAUDE_PID"
  LOG "Rotation requested by claude pid=$old_pid"

  # Acquire lock first (so concurrent !cc-rotate from any path sees B4)
  touch "$LOCK_FILE"

  # Validate request before doing anything destructive
  if ! jq empty "$REQUEST_FILE" 2>/dev/null; then
    LOG "Invalid JSON in request.json — aborting rotation, preserving session"
    mv "$REQUEST_FILE" "$REQUEST_FILE.invalid.$(date +%s)" 2>/dev/null || true
    rm -f "$LOCK_FILE"
    return 1
  fi

  # Atomic rename: request.json → bootstrap.json. From this point, the bootstrap
  # is committed to be consumed by the next session.
  if ! mv "$REQUEST_FILE" "$BOOTSTRAP_FILE"; then
    LOG "Failed to mv request → bootstrap — aborting"
    rm -f "$LOCK_FILE"
    return 1
  fi

  # Graceful SIGTERM, escalate to SIGKILL on timeout
  LOG "SIGTERM claude pid=$old_pid"
  kill -TERM "$old_pid" 2>/dev/null || true

  local elapsed=0
  while kill -0 "$old_pid" 2>/dev/null; do
    if [ "$elapsed" -ge "$SIGTERM_TIMEOUT_SECONDS" ]; then
      LOG "SIGTERM timeout after ${elapsed}s — escalating to SIGKILL"
      kill -KILL "$old_pid" 2>/dev/null || true
      # Kill any plugin children that survived (Discord plugin MCP subprocess)
      pkill -P "$old_pid" 2>/dev/null || true
      sleep 1
      break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  # Reap zombie (best effort)
  wait "$old_pid" 2>/dev/null || true
  LOG "claude pid=$old_pid terminated. bootstrap.json staged for next session."

  return 0
}

# ── Signal handlers ─────────────────────────────────────────────────
cleanup_and_exit() {
  LOG "Supervisor received TERM/INT — shutting down"
  if [ -n "$CLAUDE_PID" ] && kill -0 "$CLAUDE_PID" 2>/dev/null; then
    LOG "SIGTERM claude pid=$CLAUDE_PID"
    kill -TERM "$CLAUDE_PID" 2>/dev/null || true
    sleep 2
    if kill -0 "$CLAUDE_PID" 2>/dev/null; then
      kill -KILL "$CLAUDE_PID" 2>/dev/null || true
      pkill -P "$CLAUDE_PID" 2>/dev/null || true
    fi
  fi
  rm -f "$PID_FILE" "$LOCK_FILE"
  exit 0
}
trap cleanup_and_exit TERM INT

# ── Main loop ───────────────────────────────────────────────────────
LOG "Supervisor starting (VIBESYNC_REPO=$VIBESYNC_REPO, CC_ROTATE_DIR=$CC_ROTATE_DIR)"
preflight_cleanup

while true; do
  rm -f "$REQUEST_FILE"  # ensure clean slate per cycle
  spawn_claude

  # Clear lock now that fresh session is up (B4 should clear for next rotation)
  rm -f "$LOCK_FILE"

  if wait_for_rotation_or_exit; then
    perform_rotation
    # Loop back: spawn replacement claude
  else
    LOG "claude exited without rotation request — supervisor exiting cleanly"
    rm -f "$PID_FILE"
    exit 0
  fi
done
