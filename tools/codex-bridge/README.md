# codex-bridge — Discord `!codex` Phase 1

> Purpose: let Eric trigger a deterministic, read-only Codex review from phone Discord while Claude Code handles first-line dogfood fixes.

## What Works In Phase 1

Supported Discord commands:

```text
!codex review latest
!codex adversarial-review latest
!codex setup
!codex status <job-id>
!codex result <job-id>
!codex cancel <job-id>
```

`latest` means `HEAD~1..HEAD`, so Claude should commit and push its hotfix before calling Codex.

## What Does Not Work Yet

Not supported in Phase 1:

- `!codex task`
- `!codex rescue`
- `!codex login`
- any write-enabled Codex command
- arbitrary shell commands
- automatic infinite review loops

If `!codex setup` says Codex is not authenticated, run this once in the Ubuntu terminal:

```bash
codex login --device-auth
```

## Runtime Shape

This does **not** modify the Discord plugin cache.

Current flow:

1. Discord message reaches Claude Code as normal prompt text.
2. `tools/cc-rotate/user-prompt-hook.sh` detects a prompt line starting with `!codex`.
3. The hook executes `tools/codex-bridge/codex-discord-bridge.sh`.
4. The wrapper calls the installed Codex companion runtime:
   `~/.claude/plugins/cache/openai-codex/codex/1.0.2/scripts/codex-companion.mjs`
5. The hook injects the bridge output back into Claude context.
6. Claude replies to Discord with the job id/result.

This is not a pure plugin intercept, but it is deterministic enough for Phase 1: Claude cannot claim Codex reviewed something unless the wrapper returns a concrete job id or result.

## External Review Loop

```text
CC fixes bug + commit/push
→ !codex review latest
→ !codex status <job-id>
→ !codex result <job-id>
→ CC fixes P0/P1/P2 only if needed
→ at most one second !codex review latest
→ APPROVED or WAITING_ON_ERIC
```

Stop after two review rounds. Do not let Claude and Codex ping-pong indefinitely.

## Manual Local Test

From WSL:

```bash
cd /mnt/c/Users/eric1/OneDrive/Desktop/VibeSync
bash tools/codex-bridge/codex-discord-bridge.sh '!codex status'
bash tools/codex-bridge/codex-discord-bridge.sh '!codex setup'
bash tools/codex-bridge/codex-discord-bridge.sh '!codex review latest'
```

If `review latest` is blocked because the working tree is dirty, commit/push first.
