# Discord Codex Command Bridge Design

## Goal

Make phone-triggered Discord messages able to **deterministically** invoke Codex jobs, instead of relying on Claude to maybe delegate.

This bridge is specifically for the `discord-vibesync` channel runtime:

- start script: `~/.claude/channels/discord-vibesync/start.sh`
- live state: `~/.claude/channels/discord-vibesync/access.json`
- live Discord plugin: `~/.claude/plugins/marketplaces/claude-plugins-official/external_plugins/discord/server.ts`

## Problem Statement

Today, a phone message such as:

```text
/codex:review
```

does **not** execute a Codex command.

Why:

1. `/codex:*` is a Claude Code UI command, not a Discord-native command.
2. The Discord bridge currently forwards inbound messages as plain text:
   - `content: msg.content`
3. Therefore `/codex:review` from Discord is treated as ordinary chat text, not as a local command invocation.

Result:

- Desktop Claude Code can deterministically run Codex commands.
- Phone Discord can only ask Claude in natural language, which does **not** guarantee Codex is actually used.

## Design Principles

1. Keep normal Discord chat behavior unchanged.
2. Add a **small explicit command prefix** for deterministic Codex delegation.
3. Call the installed Codex plugin runtime directly, instead of trying to emulate Claude UI slash commands.
4. Start with **read-only / review-oriented commands** first.
5. Keep write-capable or open-ended commands behind a second phase.

## Recommended Command Syntax

Use a Discord-only prefix:

```text
!codex review
!codex review --wait
!codex adversarial-review
!codex status
!codex result <job-id>
!codex cancel <job-id>
```

Optional later:

```text
!codex rescue <problem statement>
```

Do **not** overload normal `/codex:*` in Discord. That would be confusing because it looks like a slash command but is not actually one there.

## Why `!codex` Instead of `/codex`

`/codex:*` already means "Claude Code UI command" in terminal or VS Code.

Discord does not know how to execute those.

Using `!codex ...` makes it explicit that:

- this is a Discord bridge command
- the Discord plugin is responsible for executing it
- the behavior is deterministic and local

## Runtime Integration

The bridge should execute the installed Codex plugin script directly:

- Windows plugin cache:
  - `C:\Users\eric1\.claude\plugins\cache\openai-codex\codex\1.0.2\scripts\codex-companion.mjs`
- WSL equivalent:
  - `~/.claude/plugins/cache/openai-codex/codex/1.0.2/scripts/codex-companion.mjs`

The command entrypoints supported by that script are:

- `setup`
- `review`
- `adversarial-review`
- `task`
- `status`
- `result`
- `cancel`

On the live WSL runtime, the Discord plugin should spawn:

```bash
node ~/.claude/plugins/cache/openai-codex/codex/1.0.2/scripts/codex-companion.mjs review --background --cwd /mnt/c/Users/eric1/OneDrive/Desktop/VibeSync
```

or equivalent for each subcommand.

## Phase Plan

### Phase 1: Safe Deterministic Review Commands

Support:

- `!codex review`
- `!codex review --wait`
- `!codex adversarial-review`
- `!codex adversarial-review --wait`
- `!codex status`
- `!codex result <job-id>`
- `!codex cancel <job-id>`

Behavior:

1. Discord plugin intercepts `msg.content` before normal relay.
2. If text matches `!codex ...`, do not forward it to Claude chat.
3. Execute `node .../codex-companion.mjs ...`.
4. Reply in Discord with:
   - accepted command
   - job id if background
   - concise completion output if wait-mode
5. Store the latest job IDs in local state so `!codex status` and `!codex result` are easy to use from phone.

Phase 1 should be **read-only by default**.

### Phase 2: Rescue / Task Delegation

Add:

```text
!codex rescue <problem statement>
```

Recommended mapping:

- either a dedicated rescue wrapper in the Discord plugin
- or `task --background` with a controlled template prompt

Important:

- do not allow arbitrary write-enabled tasks by default
- keep `--write` disabled unless intentionally enabled for trusted users

### Phase 3: Richer Mobile Workflow

Optional later:

- `!codex help`
- `!codex last`
- button shortcuts for `status`, `result`, `cancel`
- mapping review output into Discord-friendly summaries

## Parsing Rules

The Discord plugin should treat these as bridge commands only when the content starts with:

```text
!codex
```

Everything else remains normal Claude chat.

Suggested parser:

1. trim message
2. if not `!codex`, continue existing `handleInbound`
3. split tokens after prefix
4. validate subcommand against allowlist
5. reject unknown commands with short help text

## Security Rules

1. Only allow already-allowlisted senders to trigger bridge commands.
2. Reuse existing `gate()` result before command execution.
3. Phase 1 only permits read-only review/status/result/cancel.
4. Do not expose arbitrary shell execution from Discord.
5. If `task`/`rescue` is enabled later, keep a tight allowlist of templates and arguments.

## Failure Handling

If Codex is unavailable:

- reply: `Codex bridge is not ready on this runtime. Run /codex:setup in Claude Code first.`

If auth is missing:

- reply: `Codex is installed but not authenticated on this runtime. Complete /codex:setup first.`

If the command is invalid:

- reply with short usage examples

If the background job starts:

- reply with job id and suggested next command:
  - `!codex status`
  - `!codex result <job-id>`

## UX Recommendation

For phone use, optimize for the shortest useful set:

- `!codex review`
- `!codex adversarial-review`
- `!codex status`
- `!codex result <job-id>`

This is enough to cover most "I am away from my computer" scenarios.

## Recommended First Implementation

If this bridge is implemented, start with exactly:

1. `!codex review`
2. `!codex adversarial-review`
3. `!codex status`
4. `!codex result <job-id>`
5. `!codex cancel <job-id>`

Do **not** start with open-ended task execution.

## Success Criteria

The bridge is considered successful when:

1. A phone Discord message can deterministically trigger a Codex review job.
2. The user receives a job id back in Discord.
3. The user can fetch the result later from Discord without opening terminal UI.
4. Normal chat messages still behave exactly as before.
