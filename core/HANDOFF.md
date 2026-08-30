# Handoff — Human-AI Working Standard (HAWS)

## Current goal and scope
Converting HAWS into a portable, cross-tool (Claude Code / Antigravity / any AI assistant reading plain markdown) plugin package.

## Completed work
- [x] Restructured repository layout into `plugins/haws/` (`plugin.json`, `rules/haws.md`, `agents/`, `skills/`).
- [x] Created subagent definitions for all 4 specialized subagents: `frontend-engineer.md`, `backend-engineer.md`, `tester.md`, and `researcher.md` with appropriate tool scopes and standard system prompts.
- [x] Created orchestration rule in `plugins/haws/rules/haws.md` containing full verbatim `HAWS.md`, `WORK_INSTRUCTIONS.md`, and an updated `## Role: Main Agent (Orchestrator)` section.
- [x] Created root marketplace manifest `.claude-plugin/marketplace.json` registering all 12 curated external GitHub skill repositories with categories and UI tags.
- [x] Normalized all file line endings to LF (Unix format).
- [x] Created plugin extension and maintenance guide in `plugins/haws/MAINTAINERS.md`.
- [x] Audited all 40 user-starred GitHub repositories from `https://github.com/apirak-k?tab=stars` and mapped them into curated categories.
- [x] Embedded all 12 curated upstream GitHub repositories as official Git Submodules in `plugins/haws/skills/` to enable clean, lightweight 1-Click Installation (`/plugin install haws@haws-marketplace`).
- [x] Additively enriched `core/HAWS.md` and `plugins/haws/rules/haws.md` with Section 3.1 (LLM Coding Discipline, Pitfall Prevention, & Respect Upstream Sources), Section 5.1 (Minimalist Engineering & YAGNI), Work Instructions 1.1 (Context Window Discipline), and Orchestration Workflow Architecture (`Command` ➔ `Agent` ➔ `Skill`) with zero regressions to existing core rules.
- [x] Updated `README.md` to reflect the 1-Click install mode and 4 specialized subagents.

## Remaining work
- [ ] Update `TEMPLATES.md` content to reflect the new plugin and agent directory structure (deferred to a future task).
- [ ] Test installation and behavior natively on Antigravity / Claude Code side.

## Confirmed decisions
- **1-Click Install via Git Submodules**: All 12 curated external open-source skills are embedded directly as official Git Submodules (`.gitmodules`) from their original upstream GitHub repositories so `/plugin install haws@haws-marketplace` installs rules, 4 subagents, and all 12 authentic skills in one click.
- **Respect Upstream Sources & User Scope**: Pure upstream repositories are cloned without synthetic local file recreation or unauthorized edits.
- **Portability First**: Plain markdown files in `core/` remain the universal source of truth; plugin manifests serve as an auto-install convenience layer.
- **Dynamic Orchestration**: Subagents do not enforce a fixed execution pipeline; orchestration and routing decisions are dynamically made by the main agent.
- **Additive-Only Core Standard Updates**: Existing HAWS principles are preserved verbatim; all enhancements are added as dedicated subsections.
- **Clean Structure & LF Endings**: All text, markdown, and JSON files standardized to LF line endings.

## Assumptions
- Downstream AI clients support standard YAML frontmatter parsing on markdown rule/agent files and Git Submodule recursive cloning.

## Pending questions
- None.

## Checks and results

| Check | Result | Notes |
|---|---|---|
| Subagents Count Check | PASSED | 4 subagents created in `plugins/haws/agents/` (`frontend`, `backend`, `tester`, `researcher`) |
| Git Submodules Check | PASSED | 12 authentic upstream repos embedded under `plugins/haws/skills/` |
| Marketplace JSON Manifest Validity | PASSED | Valid JSON in `marketplace.json` with UI tags and category metadata |
| Additive Rule Integrity Check | PASSED | 100% of existing `HAWS.md` text preserved; Sections 3.1, 5.1 & WI 1.1 added cleanly |
| Line Ending Normalization | PASSED | LF maintained across all modified files |

## Exact resume point
All 12 Git Submodules, 4 subagents, and updated rules are embedded cleanly. The repository is completely ready for commit and push.

## Next action
Commit and push the updated standards, `.gitmodules`, submodules, and subagents to GitHub repository (`apirak-k/Human-AI-Working-Standard`).
