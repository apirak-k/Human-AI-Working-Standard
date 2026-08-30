# Task: Restructure "Human-AI Working Standard" (HAWS) repo into a universal, portable AI-context package

## Role
You are a senior technical architect performing a structural refactor of an existing
repository. You are not writing new working logic — you are reorganizing and packaging
existing content so it can be consumed by any AI coding assistant (Claude Code,
Antigravity, ChatGPT, Gemini, Cursor, or any tool that reads plain markdown context),
while also being natively installable in Claude Code and Antigravity specifically.

## Context
- This repo already contains working, finalized content: `HAWS.md` and
  `WORK_INSTRUCTIONS.md` at the root. Their content is final — do not edit,
  rewrite, summarize, or paraphrase any part of them.
- `TEMPLATES.md` exists at the root. Do not touch it — it will be handled in a
  separate task later.
- There is currently a `skills/` folder containing plain `.md` files with no
  frontmatter. These are being retired.
- The repo currently has no `plugins/` folder, no `.claude-plugin/` folder, and
  no `agents/` folder — you are creating all of these from scratch.
- Assume a local clone of this repo already exists on disk and you are operating
  inside it. Do not attempt to clone the repo yourself.

## Critical design principle: portability first
The primary source of truth must remain plain markdown files with YAML frontmatter —
readable and usable by copy-paste into ANY AI assistant's context window, not just
Claude Code or Antigravity. Native plugin manifests (`plugin.json`, `marketplace.json`)
are a *convenience layer* on top of this content for tools that support auto-install —
they are not a replacement for the plain-file source of truth. Never make plugin-manifest
mechanics a requirement for the content to be usable elsewhere.

## Step-by-step instructions

### Step 1 — Inventory and confirm before deleting
List every file currently inside `skills/` (paths + filenames only, no need to print
full content). Show this list before deleting anything. Then delete all files inside
`skills/` entirely — do not preserve their content anywhere, do not archive them.
This is a destructive step: stop and show the list first, wait for explicit
confirmation before deleting.

### Step 2 — Create the new directory structure
Create the following structure at repo root (do not remove or move any existing
root-level files — HAWS.md, WORK_INSTRUCTIONS.md, TEMPLATES.md stay exactly where
they are):

```
plugins/
  haws/
    plugin.json
    rules/
      haws.md
    skills/            <- leave this empty for now, no files inside
    agents/
      frontend-engineer.md
      backend-engineer.md
      tester.md
.claude-plugin/
  marketplace.json
```

### Step 3 — Write the three subagent files
Create `plugins/haws/agents/frontend-engineer.md`, `backend-engineer.md`, and
`tester.md`. Each file must have:

- YAML frontmatter with at minimum: `name`, `description`, `tools`
- `description` must be specific enough that a main orchestrating AI can decide,
  from a natural-language task description, whether this subagent is the right one
  to delegate to. Avoid vague descriptions like "handles frontend stuff" — be concrete
  about scope (e.g. "implements UI components, client-side state, styling,
  accessibility — not API or database work").
- Tool scoping:
  - `frontend-engineer`: Read, Write, Edit, Grep, Glob
  - `backend-engineer`: Read, Write, Edit, Grep, Glob, Bash
  - `tester`: Read, Grep, Glob, Bash
- Body content (system prompt) should follow standard, widely-recognized industry
  practice for each role's responsibilities and quality bar (frontend: UI
  correctness/accessibility/responsive design/state management; backend: API design/
  data integrity/security/input validation/performance; tester: edge cases/regression
  risk/test coverage, verifying rather than assuming). Do not invent unconventional
  practices — use standard, well-established engineering norms for each discipline.
- Do NOT hardcode a fixed delegation order or fixed workflow sequence between these
  three agents anywhere in their files — sequencing and delegation decisions belong
  to the main orchestrating AI's judgment, not to the subagent definitions themselves.

### Step 4 — Write the orchestration rule
Create `plugins/haws/rules/haws.md`:
- Include the full existing content of `HAWS.md` and `WORK_INSTRUCTIONS.md`,
  copied verbatim, unedited, unabridged. Organize with clear section headers so the
  combined file is easy to navigate, but do not alter a single word of the original
  content itself.
- Add a new section titled `## Role: Main Agent (Orchestrator)` describing this
  main-agent responsibility, in your own words based on this brief:
  - The main agent's primary responsibilities are (a) brainstorming and ideation
    together with the user, and (b) triaging/classifying incoming work and deciding
    how to delegate it.
  - Delegation to frontend-engineer, backend-engineer, and tester should follow
    standard SWE workflow judgment — not a rigid fixed sequence. The main agent
    decides case-by-case which subagent(s) a task needs, and in what order, based
    on the nature of the task.
  - When an ad-hoc or unexpected issue comes up mid-task, the main agent should
    re-evaluate and re-route the fix to whichever subagent is actually appropriate,
    rather than following a rigid predetermined plan.
  - The main agent may also fix a problem directly itself — without delegating —
    when a subagent is stuck or unavailable, or when direct handling is simply
    faster. The main agent holds the same engineering standards and knowledge of
    good practice as each specialist subagent — it is not less skilled. What it
    does not automatically have is the fine-grained working context a subagent may
    have accumulated mid-task (e.g. specific file state just inspected, edge cases
    just discovered). Before taking over directly, the main agent should pull that
    context first — read the relevant files/state itself, or request a short
    handoff summary from the subagent — rather than act on stale assumptions.
    Direct intervention should be the exception, not the default — prefer
    delegating when a suitable subagent is available and unblocked.
  - Do not phrase this as a mandatory checklist or hard gate (e.g. do NOT write
    "tester must always run before anything is marked done") — phrase it as
    guidance for judgment, consistent with the flexible delegation model described
    above.

### Step 5 — Write the plugin manifest
Create `plugins/haws/plugin.json`:
```json
{
  "name": "haws",
  "version": "1.0.0",
  "description": "Human-AI Working Standard"
}
```

### Step 6 — Write the marketplace manifest
Create `.claude-plugin/marketplace.json` at repo root:
```json
{
  "name": "haws-marketplace",
  "owner": { "name": "apirak-k" },
  "plugins": [
    {
      "name": "haws",
      "source": "./plugins/haws",
      "description": "Human-AI Working Standard"
    }
  ]
}
```

## Guardrails
- Do not modify, rename, or delete `HAWS.md`, `WORK_INSTRUCTIONS.md`, or
  `TEMPLATES.md` at the repo root under any circumstances in this task.
- Do not create any files inside `plugins/haws/skills/` — leave it empty. Skill
  creation is an explicitly separate, future task.
- Do not invent a fixed multi-agent workflow sequence anywhere in this task's output.
- Confirm the Step 1 deletion list with the user before executing the deletion.

## Definition of done
- `skills/` folder at root no longer exists (or is empty — confirm which the tool
  environment prefers).
- `plugins/haws/` contains: `plugin.json`, `rules/haws.md`, empty `skills/`, and
  three populated files under `agents/`.
- `.claude-plugin/marketplace.json` exists at root and correctly references
  `./plugins/haws`.
- `HAWS.md`, `WORK_INSTRUCTIONS.md`, `TEMPLATES.md` are untouched and still present
  at root.

## Report back
Before committing anything, output a summary of:
1. Every file deleted
2. Every file created (full paths)
3. Confirmation that root-level HAWS.md / WORK_INSTRUCTIONS.md / TEMPLATES.md were
   not modified
