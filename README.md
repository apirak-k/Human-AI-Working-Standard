# Human–AI Working Standard (HAWS)

A shared working standard, orchestration rules, and specialized subagents for collaboration between humans and AI agents — built for cross-tool portability across **Claude Code**, **Antigravity**, **Cursor**, **ChatGPT**, **Gemini**, and any AI coding assistant.

---

## What is HAWS?

HAWS defines the **principles, responsibilities, safeguards, and expected outcomes** that govern human-AI collaboration. It establishes a consistent engineering bar, dynamic orchestration model, and reliable verification practices across tasks, sessions, and platforms.

The goal and required outcome are always prioritized over blindly following a rigid procedure.

---

## Quick Install & Universal Management

Manage HAWS, skills, and subagents globally across detected AI environments (**Google Antigravity** and **Claude Code**) via the unified `haws.sh` command engine:

```bash
# Clone the repository
git clone https://github.com/apirak-k/Human-AI-Working-Standard.git
cd Human-AI-Working-Standard

# Run all-in-one setup & sync
bash haws.sh sync
```

Or run directly via remote curl:
```bash
curl -fsSL https://raw.githubusercontent.com/apirak-k/Human-AI-Working-Standard/main/haws.sh | bash -s -- sync
```

---

## Repository Structure

```text
├── core/                                # Universal Plain Markdown Standards (Copy-pasteable for any AI)
│   ├── HAWS.md                          # Core principles, priority hierarchy, safety & safeguards
│   ├── WORK_INSTRUCTIONS.md             # Step-by-step procedures, context loading & SWE disciplines
│   ├── WORKFLOW.md                      # 6-phase engineering lifecycle & primary/secondary skill mapping
│   ├── USER_PREFERENCES.md              # Personal Second Brain: User preferences & communication style
│   ├── ANTI_PATTERNS.md                 # Personal Second Brain: Guardrails, forbidden patterns & learned lessons
│   └── SKILL_TAXONOMY.md                # Dynamic skill taxonomy & semantic router (@organizer)
├── agents/                              # Unified Subagent Source (Author Once, Deploy to All AI Tools)
│   ├── organizer.md                     # Skill inventory health, workspace hygiene & pattern learning ledger
│   ├── frontend-engineer.md             # UI components, client state, styling, responsive design & a11y
│   ├── backend-engineer.md              # REST/GraphQL APIs, domain logic, DB schemas, auth & security
│   ├── tester.md                        # Automated test suites, edge cases, regression & boundary testing
│   └── researcher.md                    # Codebase reconnaissance, doc lookup & dependency verification
├── templates/                           # Standalone Project Blueprint & Quality Gate Templates
│   ├── README.md                        # Blueprint guide and usage instructions
│   ├── DESIGN.md                        # Official Design System standard (WCAG AA tokens)
│   ├── PROJECT.md                       # Project-specific scope, stack, and convention template
│   ├── ARCHITECTURE.md                  # System architecture, topology, and component boundaries
│   ├── CONSTRAINTS.md                   # Non-negotiable quality gates, linters, and coverage contracts
│   └── HANDOFF.md                       # Session checkpoint, active task backlog & exact resume point
├── skills/                              # Curated Skill Repository (3 Clean Categories)
│   ├── custom/                          # User-defined proprietary skills (empty/extensible)
│   ├── packs/                           # Multi-skill submodule packs (agent-skills, superpowers, etc.)
│   └── standalone/                      # Single-purpose standalone skills (taste-skill, ui-ux-pro-max, etc.)
└── haws.sh                              # Standalone Universal CLI Engine (sync, status, doctor, test)
```

---

## How to Use HAWS

HAWS is designed with a **Portability First** philosophy and supports two operational modes:

### Mode 1: Global Cross-Tool Setup (Google Antigravity & Claude Code)

Run the universal command engine to configure global pointers, install all 5 specialized subagents, and link all skills simultaneously across your machine:

```bash
# All-in-one smart sync (pull updates, link skills & subagents, auto-prune obsolete items)
bash haws.sh sync

# Force purge foreign unmanaged skills not in HAWS
bash haws.sh sync --clean

# Instant sub-second health and token budget check (< 0.2s)
bash haws.sh status

# Comprehensive 6-axis system diagnostics
bash haws.sh doctor
```

*(On Windows, run within **Git Bash**)*

---

### Mode 2: Universal Plain Markdown (Any AI Assistant)

For AI tools that read plain markdown files (ChatGPT, Claude Web, Gemini, Cursor):

1. Reference or copy the [`core/`](core/) directory (or specifically [`core/HAWS.md`](core/HAWS.md) and [`core/WORK_INSTRUCTIONS.md`](core/WORK_INSTRUCTIONS.md)) into your project workspace.
2. At the start of a session, use the project blueprint templates in [`templates/`](templates/) to bootstrap context.
3. Use [`templates/PROJECT.md`](templates/PROJECT.md) when stable project-level rules exist.
4. Use [`templates/HANDOFF.md`](templates/HANDOFF.md) to preserve state when pausing and resuming work across sessions.

---

## Specialized Subagents

When running, the Main Agent dynamically orchestrates five specialized subagents based on software engineering judgment (no rigid, hardcoded sequencing):

| Subagent | Scoped Tools | Focus Areas |
|---|---|---|
| [`organizer`](agents/organizer.md) | `Read`, `Write`, `Edit`, `Grep`, `Glob`, `Bash` | Skill inventory health, taxonomy auditing, workspace hygiene, learning ledger |
| [`frontend-engineer`](agents/frontend-engineer.md) | `Read`, `Write`, `Edit`, `Grep`, `Glob` | UI components, client-side state, styling, responsive design, a11y (WCAG), performance |
| [`backend-engineer`](agents/backend-engineer.md) | `Read`, `Write`, `Edit`, `Grep`, `Glob`, `Bash` | REST/GraphQL APIs, domain logic, DB schemas/queries, auth, security, data integrity |
| [`tester`](agents/tester.md) | `Read`, `Grep`, `Glob`, `Bash` | Automated test suites, edge cases, regression detection, bug reproduction, boundary checks |
| [`researcher`](agents/researcher.md) | `Read`, `Grep`, `Glob` | Codebase reconnaissance, technical documentation lookup, dependency verification, architecture mapping |

---

## Skills Catalog & Multi-Skill Packs

HAWS bundles curated open-source skills & packs (pointing directly to their upstream GitHub repositories):
- **Standalone Skills (`skills/standalone/`)**: `drawio-skill`, `planning-with-files`, `ui-ux-pro-max`, `taste-skill`, `humanizer`, `graphify`, `caveman`.
- **Skill Packs (`skills/packs/`)**: `superpowers`, `agent-skills`, `anthropics-skills`, `mattpocock-skills`.
- **Custom Skills (`skills/custom/`)**: Reserved for user-defined proprietary skills.

---

## Extensibility: Adding New Skills & Subagents

HAWS supports the open **AgentSkills.io** / Anthropic specification across Google Antigravity and Claude Code:

### 1. Adding a Custom In-House Skill
Proprietary or AI-authored skills reside in `skills/custom/<skill-name>/` and hold highest linking priority over external submodules to prevent upstream collisions (per [`core/USER_PREFERENCES.md`](core/USER_PREFERENCES.md)).
1. Create `skills/custom/<skill-name>/SKILL.md` following the **Anthropic Skill Standard** (`skill-creator` / `writing-skills`):
   ```markdown
   ---
   name: <skill-name>
   description: Brief capability summary. Use when [triggers]. Do NOT use when [anti-triggers].
   origin: ai-generated        # Required: "ai-generated" or "user-authored"
   author: HAWS Multi-Agent System
   ---
   # <Skill Title>
   ## Overview & Purpose
   ## Step-by-Step Workflow
   ## Verification & Quality Bar
   ```
2. Run `bash haws.sh sync` to link globally. Custom skills in `skills/custom/` automatically override upstream submodule versions if naming conflicts occur.

### 2. Adding an External Skill Pack (Git Submodule)
```bash
git submodule add https://github.com/<owner>/<repo>.git skills/<pack-name>
bash haws.sh sync
```
`haws.sh sync` automatically discovers all nested `SKILL.md` files and links them directly into all AI environments.

### 3. Adding a New Subagent
Create `agents/<agent-name>.md` with YAML frontmatter (`tools`, `model: inherit`), then run `bash haws.sh sync`. It is automatically deployed to `~/.claude/agents/` and `~/.gemini/config/agents/`.

---

## Autonomous Skill Selection (Flexible & Context-Driven)

HAWS empowers AI agents to **autonomously evaluate when to pick the right skill** based on context and each skill's `description`, rather than following rigid, mechanical sequences or forcing the human to memorize slash commands.

- **Proportionality (Keep Simple Work Simple)**: Trivial tasks (typo fixes, quick 1-line edits, direct Q&A) execute directly and immediately without loading skills or announcing tags.
- **Natural Milestones**:
  1. **Project & Feature Kickoff**: Automatically evaluates brainstorming capabilities (e.g. `brainstorming`) to explore trade-offs and draft a technical blueprint in `DESIGN.md`.
  2. **Session Checkpoints**: Automatically evaluates session persistence (e.g. `planning-with-files` / `HANDOFF.md`) to record state and resume points when pausing.
  3. **Task-Specific Execution**: Proactively matches context with domain skills across the 5 drawers in `SKILL_TAXONOMY.md`.

| Situation / Intent | Auto-Activated Skill | What the AI Does |
|---|---|---|
| Brainstorming, ideation, design exploration | `brainstorming` | Refines rough ideas into structured specs with trade-off analysis (creates `DESIGN.md`) |
| Multi-step execution (>3 steps), handoffs, pausing work | `planning-with-files` / `HANDOFF.md` | Crash-proof file-backed planning and session recovery |
| Frontend UI/UX, styling, aesthetic polish | `taste-skill` + `ui-ux-pro-max` | Applies anti-slop design bar, typography, and responsive design systems |
| Backend feature logic & test coverage | `test-driven-development` | Enforces Red-Green-Refactor ("no code without failing test first") |
| Complex bug, regression, or root cause analysis | `systematic-debugging` / `diagnosing-bugs` | Traces defects systematically from input to output without guesswork |
| Documentation, copywriting, READMEs | `humanizer` | Removes AI clichés and buzzwords for clean, natural prose |
| Codebase architecture & dependency exploration | `graphify` / `drawio-skill` | Builds codebase knowledge graphs and generates system diagrams |
| Brevity or token-saving request | `caveman` | Ultra-concise communication mode |

---

## Persistent Second Brain & Context Engineering

HAWS includes persistent memory architecture and high-fidelity context engineering:

- **Personal Second Brain**:
  - [`core/USER_PREFERENCES.md`](core/USER_PREFERENCES.md): Stores user preferences, communication style (chat-first), and architectural habits.
  - [`core/ANTI_PATTERNS.md`](core/ANTI_PATTERNS.md): Permanent registry of forbidden patterns and learned lessons (powered by autonomous continuous self-learning across all AI platforms).
- **Context Engineering & Self-Correction Loop**:
  - Features are blueprinted via Product Requirements Prompts ([`templates/`](templates/)).
  - Implementing agents operate under an automated **Self-Correcting Validation Loop**: writing tests (TDD), executing verification commands, diagnosing failures systematically, and iterating autonomously until all checks pass with zero assumptions.

---

## Priority Hierarchy

When instructions or information conflict, always resolve in this order:

1. **Safety, privacy, legal, authorization, security, and irreversible action constraints**
2. **The user's latest clear intent and instruction**
3. **HAWS**
4. **Confirmed Project Specific requirements**
5. **Applicable Work Instructions**
6. **Handoff** as a description of current work state
