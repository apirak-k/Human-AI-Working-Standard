# Human–AI Working Standard (HAWS)

A shared working standard and practical framework for collaboration between
humans and AI agents — across projects, tools, sessions, and environments.

## What is HAWS?

HAWS defines the **principles, responsibilities, safeguards, and expected
outcomes** that govern how a user and AI agent work together. It is not tied to
any specific tool, language, or platform.

The goal and required outcome are always more important than blindly following a
procedure.

## Repository structure

| Path | Purpose |
|------|---------|
| [`HAWS.md`](HAWS.md) | The core standard — principles, priorities, safeguards, and verification requirements |
| [`WORK_INSTRUCTIONS.md`](WORK_INSTRUCTIONS.md) | Practical step-by-step procedures that translate HAWS into daily work |
| [`TEMPLATES.md`](TEMPLATES.md) | Starter prompt, blank `PROJECT_SPECIFIC.md` template, and blank `HANDOFF.md` template |
| [`skills/`](skills/) | Directory of on-demand working modes as standalone `.md` files |
| ├── [`skills/grill-me.md`](skills/grill-me.md) | Requirement interview mode — extracts and clarifies scope before building |
| ├── [`skills/caveman.md`](skills/caveman.md) | Ultra-compressed communication mode — minimizes token usage while keeping accuracy |
| └── [`skills/qa-edgecase.md`](skills/qa-edgecase.md) | QA and edge case detection mode — spots edge cases, boundary errors, and Excel safety issues |

### Adding new skills

You can add new skills at any time:
1. Create a new `<skill-name>.md` inside the [`skills/`](skills/) directory.
2. Define its **Purpose**, **When to use**, **Behavior**, and **Output format**.
3. Activate it on-demand during conversations using `[<skill-name>]`.

### Per-project files (created when needed)

| File | When to create |
|------|---------------|
| `PROJECT_SPECIFIC.md` | When stable, confirmed project rules exist |
| `HANDOFF.md` | When work must continue in another session or context |

These are **not** included in this repository as empty placeholders. See
[`TEMPLATES.md`](TEMPLATES.md) for blank templates.

## Quick start

1. Copy `HAWS.md` and `WORK_INSTRUCTIONS.md` into your project (or reference
   this repository).
2. Copy the [`skills/`](skills/) directory and [`TEMPLATES.md`](TEMPLATES.md).
3. At the start of a new AI session, use the **Master Starter Prompt** from
   [`TEMPLATES.md`](TEMPLATES.md) to load context.
4. Create `PROJECT_SPECIFIC.md` when your project has confirmed rules.
5. Create `HANDOFF.md` when you need to pause and resume later.

## Priority hierarchy

When instructions or information conflict, use this order:

1. **Safety, privacy, legal, authorization, security, and irreversible action
   constraints**
2. **The user's latest clear intent and instruction**
3. **HAWS**
4. **Confirmed Project Specific requirements**
5. **Applicable Work Instructions**
6. **Handoff** as a description of current work state

## Contributing

Propose changes according to their scope:

- Broadly reusable principle → `HAWS.md`
- Recurring procedure → `WORK_INSTRUCTIONS.md`
- New on-demand skill → create `<skill-name>.md` inside `skills/`
- One-project rule → `PROJECT_SPECIFIC.md`
- Current work state → `HANDOFF.md`

Do not update central files automatically. Propose the smallest necessary
change and wait for review and confirmation.
