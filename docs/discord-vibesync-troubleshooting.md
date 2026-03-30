# Discord VibeSync Troubleshooting

## Purpose

This note records the real live paths and the root cause of the `discord-vibesync` monitoring issue, so future Claude/Codex sessions do not debug the wrong state directory.

## Live Entrypoint

The VibeSync Discord bridge is started from:

- `~/.claude/channels/discord-vibesync/start.sh`

Important line inside that script:

```bash
export DISCORD_STATE_DIR=$HOME/.claude/channels/discord-vibesync
```

That means the live state for this project is:

- `~/.claude/channels/discord-vibesync/access.json`

It is **not** the generic:

- `~/.claude/channels/discord/access.json`

## Root Cause Found On 2026-03-30

Symptom:

- Bot could receive one allowed user in real time.
- Bot could not receive Bruce in real time.
- REST `GET /channels/{id}/messages` could still read Bruce's messages.

Actual root cause:

- The real live allowlist file was `~/.claude/channels/discord-vibesync/access.json`.
- Bruce's ID was missing there.
- `gate()` therefore dropped Bruce before the message reached the reply flow.

Bruce ID:

- `1488071059281547314`

Relevant group/channel IDs:

- `1487899618090946634`
- `1488034916481368147`

## Fix Applied Outside This Repo

These runtime fixes were applied directly in the live WSL environment and are **not** committed in this repo:

1. Added Bruce to the real live allowlist:
   - `~/.claude/channels/discord-vibesync/access.json`
2. Patched the live Discord plugin:
   - `~/.claude/plugins/marketplaces/claude-plugins-official/external_plugins/discord/server.ts`

Live plugin hardening added there:

- `GuildMembers` gateway intent
- allowlisted guild-channel polling fallback
- inbound dedup

## What To Check First Next Time

If Discord real-time monitoring breaks again, check in this order:

1. Which start script is actually used.
2. Which `DISCORD_STATE_DIR` it exports.
3. Whether the real live `access.json` contains the target user ID.
4. Whether the live plugin file in WSL is the one being edited.

## Important Distinction

There are effectively two different Discord state roots:

- generic Discord channel state
- project-specific `discord-vibesync` state

Do not assume fixes under the generic `discord` path apply to VibeSync.

## Recommended Debug Flow

1. Confirm the user can post in the expected Discord channel.
2. Inspect `~/.claude/channels/discord-vibesync/access.json`.
3. Verify the target user ID appears in both top-level `allowFrom` and the relevant group.
4. If allowlist is correct but real-time still fails, inspect the live WSL plugin:
   - `~/.claude/plugins/marketplaces/claude-plugins-official/external_plugins/discord/server.ts`
5. Restart the channel via:
   - `~/.claude/channels/discord-vibesync/start.sh`

## Notes For Future Sessions

- The fix that restored Bruce monitoring was primarily the `discord-vibesync/access.json` correction.
- The plugin patch is a resilience improvement, not the primary root cause fix.
- If a future session sees Discord symptoms but only inspects repo files, it is looking in the wrong place.
