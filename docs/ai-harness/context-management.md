# VibeSync Context Management

> Goal: keep fresh Claude Code and Codex sessions small, current, and easy to rotate.

## Policy Layers

### 1. Always-On

Files loaded by default:

- `CLAUDE.md`
- `AGENTS.md`

Rules:

- Keep each file near 3.5 KB or less.
- Keep the two files byte-for-byte synchronized.
- Store only high-density project identity, workflow rules, context budget rules, and pointers.
- Do not paste old plans, long product specs, bug timelines, or command output here.

### 2. On-Demand

Read these only when the task needs them:

- `docs/plans/`
- `docs/integrations/`
- `docs/reviews/`
- `docs/qa/`
- `docs/ai-harness/`
- prompts, benchmarks, and project-specific skills

Rules:

- Read the smallest useful file or section.
- Summarize findings into the reply instead of pasting large chunks.
- Prefer targeted grep/search over opening whole archives.

### 3. Archive

Completed history belongs here:

- `docs/archive/`
- old review records
- finished handoffs
- old implementation plans

Rules:

- Archive files do not belong in always-on context.
- Update archives after completion, not during every small step.
- If a completed item becomes a durable rule, move the rule into `docs/shared-agent-rules.md` or another active doc.

## Skills Policy

Project active skills should be VibeSync-specific. Generic engineering, review, planning, browser, deployment, or debugging skills should live outside active project context or be quarantined under:

```text
.claude/skills.disabled/YYYY-MM-DD-context-harness/
```

Do not delete quarantined skills. They can be restored if Eric decides a specific one is truly project-specific.

## Slash Command Policy

Project slash commands should be small prompts. They must not automatically inject files or shell output. If a command needs data, it should tell the agent what to summarize and let the agent choose a targeted read.

`/.claude/commands/round.md` is the default short handoff format for lightweight rotations.

## Audit

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/context-harness-audit.ps1
```

The audit reports:

- root context file size
- active project skill count and total bytes
- slash commands containing file or shell injection markers
- project and global enabled plugins
- project and global MCP server counts

If a new session still starts with high context after project cleanup, check global/user skills, global plugins, MCP metadata, hooks, and pasted conversation history before expanding project files again.
