# TEMPLATES — Starter Templates and Prompt Blueprints

## Purpose

This file collects reusable templates in one place. Copy and adapt them as
needed. They follow the conventions defined in HAWS and Work Instructions.

---

## 1. Master Starter Prompt

Use this prompt (or an adapted version) at the beginning of a new AI session
to load context correctly.

```text
You are working under the Human–AI Working Standard (HAWS).

Before starting:

1. Read HAWS.md — the core working standard.
2. Read WORK_INSTRUCTIONS.md — practical procedures.
3. Check the skills/ directory — see available on-demand skills (e.g. [grill-me], [caveman], [qa-edgecase]).
4. Read PROJECT_SPECIFIC.md if it exists in this project.
5. Read HANDOFF.md if continuing previous work.

After reading, report:
- Understood goal and scope
- Current state and starting point
- Any conflicts, risks, or missing information

Then wait for instructions.
```

---

## 2. PROJECT_SPECIFIC.md — Blank Template

Create this file in your project when stable, confirmed project rules exist.
Do not create it preemptively with placeholder content.

```markdown
# Project Specific — [Project Name]

## Project overview

Brief description of the project, its purpose, and primary users.

## Stack and tools

- Language:
- Framework:
- Database:
- Hosting:
- Version control:

## Confirmed conventions

- Naming:
- File structure:
- Branching strategy:
- Commit message format:

## Domain definitions

| Term | Definition |
|------|-----------|
|      |           |

## Constraints and dependencies

- External APIs:
- Third-party services:
- Known limitations:

## Safety and access rules

- Folders or files excluded from Git:
- Destructive commands requiring confirmation:
- Credentials and secrets handling:
```

---

## 3. HANDOFF.md — Blank Template

Create this file when work must continue in another session, machine, tool,
or AI agent. Update it at each checkpoint. Remove or close obsolete entries.

```markdown
# Handoff — [Project Name]

## Current goal and scope

What we are trying to achieve in this phase of work.

## Completed work

- [ ] Task 1
- [x] Task 2 (done)

## Remaining work

- [ ] Task 3
- [ ] Task 4

## Confirmed decisions

- Decision A: chosen option and rationale
- Decision B: chosen option and rationale

## Assumptions

- Assumption 1 (pending user verification)
- Assumption 2 (pending user verification)

## Pending questions

- Question 1
- Question 2

## Checks and results

| Check | Result | Notes |
|-------|--------|-------|
|       |        |       |

## Risks and blockers

- Risk 1: description and mitigation
- Blocker 1: description and status

## Exact resume point

The next person or AI should start at: [specific file, function, step, or
state].

## Next action

What to do immediately when resuming.
```
