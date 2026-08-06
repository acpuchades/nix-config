---
name: gtd
description: How to manage commitments as an agent — capture, clarify, next actions, review — adapted for the agent's actual constraint (continuity across sessions, not cognitive load). Consult it whenever you process mail, handle something the owner asks you to remember or do, answer "what is pending?", or run a daily or weekly review.
---

# Agentic Task Flow

A commitment management system built for agents. It takes the GTD principles that genuinely help and drops the apparatus that does not apply.

## Why this is not standard GTD

GTD solves human cognitive load and working memory stress. An agent's constraint is different: **continuity across sessions**. There is no anxiety about pending items — there is amnesia between conversations. The fix is not more structure; it is that everything that matters is written somewhere reliable.

## Two systems, two owners

### Agent's own tasks (markdown files in workspace)
- `gtd/next-actions.md` — things the agent must do
- `gtd/waiting-for.md` — things the agent is waiting on from others
- `gtd/projects.md` — projects the agent is actively managing

### Owner's tasks (their task system)
The owner may use any tool: CalDAV, Todoist, Things, Notion, etc. Consult the relevant integration skill for access details and list identifiers.

**Separation rule:** the agent's markdown files are exclusively for the agent's own actions. The owner's tasks always go to their system, never to the agent's files.

## Contexts

**For the agent's own tasks — execution triggers (when to act, not where):**

Each task can carry a context tag indicating which scheduled cycle it belongs to. Any recurring cron job or workflow can define its own context. Core contexts:

- `@heartbeat` — standard checks on every heartbeat cycle (server health, inbox, readiness scores, etc.)
- `@mailcheck` — run when processing the inbox (triage, archive, capture to owner's list)
- `@gtdreview` — run during the weekly GTD review cycle
- `@nixupdate` — run during the daily NixOS update check
- `@morning` — morning-specific actions (readiness summary, day preview, calendar scan)

When a cycle runs, process any pending tasks tagged with its context.

**For the owner's tasks — situational triggers (when to surface, not when to execute):**

Contexts help decide when to proactively mention a task to the owner. Useful contexts detectable from calendar or conversation:

- `@hospital` — calendar shows a hospital or clinical day → surface patient-related or administrative clinical tasks
- `@research` — meeting or day at a research institute → surface tasks related to studies, manuscripts, collaborators
- `@conference` — attending a symposium or congress → surface networking or presentation tasks
- `@phone` — task requires making a call; surface when the owner has a free slot or mentions availability
- `@computer` — task requires being at a computer (baseline for most tasks; use only when it distinguishes from phone-only or in-person tasks)

When relevant context is detected, proactively mention matching tasks from the owner's list — without waiting to be asked.

## Capture

When something actionable arises in conversation or mail:

1. **Is it the agent's to do?** → add to `next-actions.md` or `waiting-for.md`
2. **Is it the owner's, and concrete?** → add to their inbox (no permission needed for capture)
3. **Is it a new project for the owner?** → ask before adding. Never add silently.
4. **Is it a next action for one of the owner's projects?** → only add if there is real context (the owner said so, it came from processed mail, etc.). If context is missing, **ask** — never invent one that sounds plausible.

## Projects

Every project must have at least one next action. If one is missing, ask for it. Do not fabricate it.

## Review

**Daily (morning heartbeat):** read the owner's lists. If the inbox has had unprocessed items for more than 2 days, flag it.

**Weekly (Friday):** send the owner a single message covering:
- **Inbox:** unprocessed items?
- **Next actions:** anything stalled or already done?
- **Projects:** does the list reflect reality? Any project without a next action?
- **Waiting for:** overdue follow-ups? Items with no response for weeks?

## Operations on external lists

When creating, editing, or deleting items in the owner's task system:

1. **Read the full list first** — fetch all items before any destructive operation
2. **Identify targets by content** in the fetched result
3. **Apply changes one at a time**, confirm success for each
4. Never chain a filtered search directly to a bulk delete — filters may not work server-side and can return everything

## Relation to other skills

- Integration skills (e.g. `gtd-nextcloud-integration`): provide the concrete access layer for the owner's specific task system
