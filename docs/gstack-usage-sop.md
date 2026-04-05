# gstack Usage SOP

Last updated: 2026-04-05

This file explains how Claude and Codex should use the installed `gstack-*`
skills inside the VibeSync project.

## What gstack is

gstack is not product code.

It is an AI workflow layer for:

- review
- debugging
- QA
- security review
- release documentation

## Most Useful Commands For VibeSync

### `/gstack-review`

Use when:

- you changed code
- you want a code review before merge
- you want a bug / regression / missing-test pass

What it reviews:

- the current branch / worktree diff against the base branch

### `/gstack-investigate`

Use when:

- something is broken
- the bug is not obvious
- a flow keeps failing after multiple fixes

Best for:

- auth bugs
- subscription sync bugs
- OCR misclassification bugs
- deploy / CI issues

### `/gstack-qa`

Use when:

- a web flow is ready for testing
- a dashboard page needs end-to-end QA
- you want a structured bug-finding pass

### `/gstack-cso`

Use when:

- you want a security review
- you want an infra / secrets / trust-boundary pass
- you are close to launch

### `/gstack-document-release`

Use when:

- you shipped a batch of changes
- you want release notes or handoff updates
- you want README / docs / status files synced

## Recommended VibeSync Workflow

### New bug

1. `/gstack-investigate`
2. fix the root cause
3. `/gstack-review`

### Pre-merge / pre-push

1. `/gstack-review`

### Pre-launch security pass

1. `/gstack-cso`

### Post-ship documentation sync

1. `/gstack-document-release`

## Important Notes

- In this repo, use the namespaced commands:
  - `/gstack-review`
  - not `/review`
- Use Discord bot for short coordination, not long spec work.
- Use separate local threads for:
  - Phase planning
  - bug fixing
  - shipping / review

## Related Docs

- [AGENTS.md](/C:/Users/eric1/OneDrive/Desktop/VibeSync/AGENTS.md)
- [CLAUDE.md](/C:/Users/eric1/OneDrive/Desktop/VibeSync/CLAUDE.md)
