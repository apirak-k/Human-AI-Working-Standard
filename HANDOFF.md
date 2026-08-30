# Handoff — Human-AI Working Standard (HAWS)

## Current goal and scope
Converting HAWS into a portable, cross-tool (Claude Code / Antigravity / any AI assistant reading plain markdown) plugin package.

## Completed work
- [x] Restructured repository layout into `plugins/haws/` (`plugin.json`, `rules/haws.md`, `agents/`, empty `skills/`).
- [x] Created subagent definitions for `frontend-engineer.md`, `backend-engineer.md`, and `tester.md` with appropriate tool scopes and standard system prompts.
- [x] Created orchestration rule in `plugins/haws/rules/haws.md` containing full verbatim `HAWS.md`, `WORK_INSTRUCTIONS.md`, and a new `## Role: Main Agent (Orchestrator)` section.
- [x] Created root marketplace manifest `.claude-plugin/marketplace.json`.
- [x] Removed deprecated legacy files in `skills/` and deleted the old root `skills/` directory.
- [x] Normalized all file line endings to LF (Unix format).
- [x] Created plugin extension and maintenance guide in `plugins/haws/MAINTAINERS.md`.

## Remaining work
- [ ] Update `TEMPLATES.md` content to reflect the new plugin and agent directory structure (explicitly deferred by user to a future task).
- [ ] Add new modular skills under `plugins/haws/skills/` (currently empty as designed; workflow documented in `MAINTAINERS.md`).
- [ ] Test installation and behavior natively on Antigravity side.
- [ ] (Optional future task) Reference external starred skills repository via a new `marketplace.json` entry.

## Confirmed decisions
- **Portability First**: Plain markdown files with YAML frontmatter remain the source of truth; plugin manifests serve as an auto-install convenience layer.
- **Dynamic Orchestration**: Subagents do not enforce a fixed execution pipeline; orchestration and routing decisions are dynamically made by the main agent.
- **Verbatim Rule Preservation**: Original `HAWS.md` and `WORK_INSTRUCTIONS.md` text is preserved verbatim in `plugins/haws/rules/haws.md`, while root-level files remain untouched.
- **Line Ending Standard**: All text and markdown files standardized to LF line endings.

## Assumptions
- Downstream AI clients support standard YAML frontmatter parsing on markdown rule/agent files.

## Pending questions
- None.

## Checks and results

| Check | Result | Notes |
|---|---|---|
| Directory Structure Verification | PASSED | `plugins/haws/` and `.claude-plugin/` structured per specification |
| Legacy Skills Cleanup | PASSED | Old `skills/` directory removed |
| Root Files Integrity (`HAWS.md`, etc.) | PASSED | 0 diff against original content |
| Line Ending Normalization | PASSED | LF across all root and plugin files |
| JSON Manifest Validity | PASSED | Valid JSON in `plugin.json` and `marketplace.json` |

## Risks and blockers
- None currently blocking.

## Exact resume point
Plugin structure complete and tested on Claude Code; next session should either (a) add skills, (b) test on Antigravity, or (c) update TEMPLATES.md — ask user which.

## Next action
None pending, awaiting user direction.
