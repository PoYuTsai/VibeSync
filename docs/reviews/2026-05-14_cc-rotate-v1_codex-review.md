# 2026-05-14 cc-rotate v1 Codex Review

## Scope

Reviewed commits:

- `18278e5` `[docs] 加入 !cc-rotate v1 設計文件`
- `80ce48a` `[feat] 加入 !cc-rotate v1 實作（Discord 外出模式 session rotation）`

Focus: process supervisor safety, setup consistency, and phone-mode context rules.

## Findings And Fixes

### 🔴 Fixed — supervisor could spawn a duplicate Discord listener after a failed rotation request

`tools/cc-rotate/supervisor.sh` originally called `perform_rotation` and then always looped back to spawn a replacement session. If `perform_rotation` failed before terminating the old Claude process, for example invalid JSON or failed atomic `mv`, the old process would keep running while supervisor spawned a second Discord listener.

Fix: the supervisor now keeps monitoring the existing Claude process when rotation aborts before termination, and only spawns a replacement after `perform_rotation` succeeds.

### 🟡 Fixed — `inotify-tools` was treated as a hard dependency despite being a convenience layer

The design/README required `inotifywait`, so missing `inotify-tools` could prevent the bridge from starting even though polling is sufficient for v1.

Fix: `jq` remains the only hard dependency. `inotifywait` is used when available; otherwise supervisor falls back to short polling.

### 🟡 Fixed — green-context thresholds were inconsistent across shared docs

The implementation docs still referenced older `25% / 40%` reminders, while the agreed rule is unified green-context bands.

Fix: shared rules and the design doc now use `30-40% yellow`, `40-45% orange`, `45%+ hard stop`, with high-risk work treated as orange at `35%+`.

### 🟢 Fixed — local setup template leaked machine-specific defaults

The checked-in `.env.example` used Eric's absolute paths as defaults, which increases copy/paste risk and makes the tool less portable.

Fix: replaced concrete paths with placeholders and updated README setup commands.

## Verification

- `bash -n tools/cc-rotate/*.sh` passed.
- `git diff --check` passed.
- `shellcheck` was not installed in this WSL environment, so shellcheck verification remains a manual follow-up.

## Remaining Manual Gate

Before relying on this outside the house, run the README integration checks:

- Clean `!cc-rotate` from Discord should produce a new ready session.
- Dirty tree should reject with B1.
- Commit-not-pushed should reject with B3.
