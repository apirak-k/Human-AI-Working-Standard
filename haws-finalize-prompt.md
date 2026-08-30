# Task: Finalize HAWS plugin restructure — commit, test install, document extension workflow, create Handoff

## Step 1 — Fix line endings
Normalize line endings of these 4 root files back to LF (Unix). Do NOT change
any content — whitespace/line-ending only:
- HAWS.md
- WORK_INSTRUCTIONS.md
- TEMPLATES.md
- README.md

Confirm via `git diff --stat` that these 4 files are now content-identical to
the original (line-ending-only diff, or no diff).

## Step 2 — Commit and push
Show me `git status` first. Then stage everything, commit with message:
"Restructure HAWS into portable plugin package (Claude Code / Antigravity compatible)"
Push to origin.

## Step 3 — Test local installation
Run, in order, and report the actual output of each:
```
/plugin marketplace add apirak-k/Human-AI-Working-Standard
/plugin install haws@haws-marketplace
```
Confirm the 3 subagents (frontend-engineer, backend-engineer, tester) and the
rules content are visible/loaded after install. If install fails, report the
exact error — do not attempt undocumented workarounds.

## Step 4 — Write a documentation file for future maintenance
Create `plugins/haws/MAINTAINERS.md` covering, in plain instructional language:

### How to add a new Skill
- Create `plugins/haws/skills/<skill-name>/SKILL.md`
- Required YAML frontmatter: `name`, `description` (must be specific enough
  for auto-invocation — explain what makes a good description with 1 example)
- Body = the skill's instructions/system prompt
- No changes needed to `marketplace.json` or `plugin.json` — skills inside an
  already-referenced plugin are picked up automatically on next
  `/plugin update`

### How to add a new Subagent
- Create `plugins/haws/agents/<agent-name>.md`
- Required YAML frontmatter: `name`, `description`, `tools` (list which tools
  this agent needs — reference the existing 3 agents as examples of scoping)
- Body = system prompt defining the agent's responsibilities and quality bar
- Do not hardcode delegation order relative to other agents — that stays the
  main agent's judgment call, per `plugins/haws/rules/haws.md`
- After adding, update `plugins/haws/rules/haws.md` → "Role: Main Agent
  (Orchestrator)" section if the new agent's domain should be explicitly
  mentioned there

### How to push an update to all devices
```
git add . && git commit -m "..." && git push
```
Then on each other device:
```
/plugin marketplace update haws-marketplace
/plugin update haws@haws-marketplace
```

Keep this file concise — a working reference, not a tutorial essay.

## Step 5 — Create a Handoff file
Create `HANDOFF.md` at repo root (per the existing HAWS/WORK_INSTRUCTIONS.md
convention already defined in this repo — follow their Handoff template from
`TEMPLATES.md` section 3 if present). Include:
- Current goal and scope: converting HAWS into a portable, cross-tool
  (Claude Code / Antigravity / any AI reading plain markdown) plugin package
- Completed work: restructure into plugins/haws/ (agents, rules, plugin.json),
  marketplace.json, old skills/ removed, line endings fixed, install tested
- Remaining/deferred work:
  - TEMPLATES.md content itself not yet updated to reflect new structure
    (explicitly deferred by user, do later)
  - plugins/haws/skills/ is currently empty — new skills to be added later,
    process documented in MAINTAINERS.md
  - Antigravity-side installation not yet tested (only Claude Code tested)
  - Possible future task: reference an external starred skill repo via a new
    marketplace.json entry (not started)
- Exact resume point: "plugin structure complete and tested on Claude Code;
  next session should either (a) add skills, (b) test on Antigravity, or
  (c) update TEMPLATES.md — ask user which"
- Next action: none pending, awaiting user direction

## Step 6 — Report back
Summarize: what was committed, test install result, files created in this
session (MAINTAINERS.md, HANDOFF.md), and confirm nothing in
plugins/haws/agents/, plugins/haws/rules/haws.md, plugin.json, or
marketplace.json was altered from the previous session's reviewed version.
