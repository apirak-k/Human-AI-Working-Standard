# Human–AI Working Standard (HAWS)

A shared working standard, orchestration rules, and specialized subagents for collaboration between humans and AI agents — built for cross-tool portability across **Claude Code**, **Antigravity**, **Cursor**, **ChatGPT**, **Gemini**, and any AI coding assistant.

---

## What is HAWS?

HAWS defines the **principles, responsibilities, safeguards, and expected outcomes** that govern human-AI collaboration. It establishes a consistent engineering bar, dynamic orchestration model, and reliable verification practices across tasks, sessions, and platforms.

The goal and required outcome are always prioritized over blindly following a rigid procedure.

---

## Quick Install

Install HAWS skills and subagents globally across detected AI environments (**Google Antigravity** and **Claude Code**) in one command:

```bash
curl -fsSL https://raw.githubusercontent.com/apirak-k/Human-AI-Working-Standard/main/install.sh | bash
```

To update to the latest version across all tools:
```bash
curl -fsSL https://raw.githubusercontent.com/apirak-k/Human-AI-Working-Standard/main/update.sh | bash
```

---

## Repository Structure

```text
├── core/                                # Universal Plain Markdown Standards (Copy-pasteable for any AI)
│   ├── HAWS.md                          # Core principles, priority hierarchy, safety & safeguards
│   ├── WORK_INSTRUCTIONS.md             # Step-by-step procedures, context loading & verification
│   ├── TEMPLATES.md                     # Starter prompt, design.md (TH), PROJECT_SPECIFIC.md & HANDOFF.md templates
│   └── HANDOFF.md                       # Active work state & continuity checkpoint
├── .claude-plugin/
│   └── marketplace.json                 # Marketplace manifest for Claude Code / Antigravity plugins
└── plugins/
    └── haws/
        ├── plugin.json                  # Plugin manifest metadata
        ├── rules/
        │   └── haws.md                  # Unified orchestration rule & Main Agent Orchestrator role
        ├── agents/
        │   ├── frontend-engineer.md     # UI, styling, client state, accessibility & web performance
        │   ├── backend-engineer.md      # APIs, service logic, databases, security & server performance
        │   ├── tester.md                # Test execution, boundary verification & regression analysis
        │   └── researcher.md            # Deep codebase exploration, documentation lookup & dependency verification
        ├── skills/                      # Custom in-house skills directory
        └── MAINTAINERS.md               # Guide for adding skills, agents, and multi-device updates
```

---

## How to Use HAWS

HAWS is designed with a **Portability First** philosophy and supports two operational modes:

### Mode 1: Native Plugin Installation (Claude Code / Antigravity)

Install HAWS directly into your agent environment to auto-load rules, all 4 specialized subagents, and all 12 curated upstream skills simultaneously in a single command:

```text
# 1. Add the marketplace source
/plugin marketplace add apirak-k/Human-AI-Working-Standard

# 2. 1-Click Install HAWS (installs rules, 4 subagents & 12 authentic Git submodules at once)
/plugin install haws@haws-marketplace
```

To update across devices whenever new skills or agents are added:
```text
/plugin marketplace update haws-marketplace
/plugin update haws@haws-marketplace
```

---

### Mode 2: Universal Plain Markdown (Any AI Assistant)

For AI tools that read plain markdown files (ChatGPT, Claude Web, Gemini, Cursor):

1. Reference or copy the [`core/`](core/) directory (or specifically [`core/HAWS.md`](core/HAWS.md) and [`core/WORK_INSTRUCTIONS.md`](core/WORK_INSTRUCTIONS.md)) into your project workspace.
2. At the start of a session, use the **Master Starter Prompt** in [`core/TEMPLATES.md`](core/TEMPLATES.md) to bootstrap context.
3. Use [`PROJECT_SPECIFIC.md`](core/TEMPLATES.md#3-project_specificmd--blank-template) when stable project-level rules exist.
4. Use [`core/HANDOFF.md`](core/HANDOFF.md) to preserve state when pausing and resuming work across sessions.

---

## Specialized Subagents

When running as a plugin, the Main Agent dynamically orchestrates four specialized subagents based on software engineering judgment (no rigid, hardcoded sequencing):

| Subagent | Scoped Tools | Focus Areas |
|---|---|---|
| [`frontend-engineer`](plugins/haws/agents/frontend-engineer.md) | `Read`, `Write`, `Edit`, `Grep`, `Glob` | UI components, client-side state, styling, responsive design, a11y (WCAG), performance |
| [`backend-engineer`](plugins/haws/agents/backend-engineer.md) | `Read`, `Write`, `Edit`, `Grep`, `Glob`, `Bash` | REST/GraphQL APIs, domain logic, DB schemas/queries, auth, security, data integrity |
| [`tester`](plugins/haws/agents/tester.md) | `Read`, `Grep`, `Glob`, `Bash` | Automated test suites, edge cases, regression detection, bug reproduction, boundary checks |
| [`researcher`](plugins/haws/agents/researcher.md) | `Read`, `Grep`, `Glob` | Codebase reconnaissance, technical documentation lookup, dependency verification, architecture mapping |

---

## Skills Catalog (12 Verified Curated Skills)

The marketplace manifest (`.claude-plugin/marketplace.json`) catalogs **12 verified curated open-source skills & packs** (pointing directly to their upstream GitHub repositories):
- **Single Skills (7)**: `drawio-skill` (`/drawio`), `planning-with-files` (`/plan`), `ui-ux-pro-max-skill` (`/ui-ux`), `taste-skill` (`/taste`), `humanizer` (`/humanize`), `graphify` (`/graphify`), `caveman` (`/caveman`).
- **Skill Packs (Top 5)**: `superpowers` (`/tdd`, `/debug`), `ecc` (`/ecc`, `/audit`), `agent-skills` (`/perf`, `/a11y`), `anthropics-skills`, `mattpocock-skills`.

See [`plugins/haws/MAINTAINERS.md`](plugins/haws/MAINTAINERS.md) for full instructions on authoring custom skills and adding marketplace plugins.

---

## Autonomous Skill Selection (Flexible & Context-Driven)

HAWS empowers AI agents to **autonomously evaluate when to pick the right skill** based on context and each skill's `description`, rather than following rigid, mechanical sequences or forcing the human to memorize slash commands.

- **Proportionality (Keep Simple Work Simple)**: Trivial tasks (typo fixes, quick 1-line edits, direct Q&A) execute directly and immediately without loading skills or announcing tags.
- **Natural Milestones**:
  1. **Project & Feature Kickoff**: Automatically evaluates brainstorming capabilities (e.g. `superpowers/brainstorming`) to explore trade-offs and draft a technical blueprint in `design.md`.
  2. **Session Checkpoints**: Automatically evaluates session persistence (e.g. `planning-with-files` / `HANDOFF.md`) to record state and resume points when pausing.
  3. **Task-Specific Execution**: Proactively matches context with domain skills when substantial.

| Situation / Intent | Auto-Activated Skill | What the AI Does |
|---|---|---|
| Brainstorming, ideation, design exploration | `superpowers` (*brainstorming*) | Refines rough ideas into structured specs with trade-off analysis (creates `design.md`) |
| Multi-step execution (>3 steps), handoffs, pausing work | `planning-with-files` / `HANDOFF.md` | Crash-proof file-backed planning and session recovery |
| Frontend UI/UX, styling, aesthetic polish | `taste-skill` + `ui-ux-pro-max` | Applies anti-slop design bar, typography, and responsive design systems |
| Backend feature logic & test coverage | `superpowers` (*test-driven-development*) | Enforces Red-Green-Refactor ("no code without failing test first") |
| Bug fixing, crashes, unexpected errors | `superpowers` (*systematic-debugging*) | Traces root causes (`input ➔ state ➔ output`) rather than guessing fixes |
| Documentation, copywriting, READMEs | `humanizer` | Removes AI clichés and buzzwords for clean, natural prose |
| Codebase architecture & dependency exploration | `graphify` / `drawio-skill` | Builds codebase knowledge graphs and generates system diagrams |
| Brevity or token-saving request | `caveman` | Ultra-concise communication mode |

---

## Priority Hierarchy

When instructions or information conflict, always resolve in this order:

1. **Safety, privacy, legal, authorization, security, and irreversible action constraints**
2. **The user's latest clear intent and instruction**
3. **HAWS**
4. **Confirmed Project Specific requirements**
5. **Applicable Work Instructions**
6. **Handoff** as a description of current work state
