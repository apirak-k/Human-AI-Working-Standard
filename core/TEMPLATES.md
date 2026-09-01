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

1. Read HAWS.md — the core working standard and orchestration rules.
2. Read WORK_INSTRUCTIONS.md — practical procedures and autonomous skill matching.
3. Inspect the current project source and codebase structure.
4. Check the skills/ directory and available skills catalog — review their descriptions.
5. Read design.md if it exists in this project (architecture & technical blueprint).
6. Read PROJECT_SPECIFIC.md if it exists in this project.
7. Read HANDOFF.md if continuing previous work.

Autonomous Skill Selection Rule:
Throughout our session, proactively evaluate the context of every task against the descriptions of available skills (e.g. superpowers for brainstorming/TDD/debugging, planning-with-files for multi-step tasks/handoffs, taste-skill/ui-ux-pro-max for UI design, humanizer for text refinement, graphify/drawio for architecture & diagrams). Simple/trivial tasks execute directly; substantial tasks activate matching skills automatically with a brief tag: `[Auto-Skill: <skill-name>] <brief reason>`.

After reading, report:
- Understood goal and scope
- Current state and starting point
- Available skills detected and active capabilities
- Any conflicts, risks, or missing information

Then wait for instructions.
```

---

## 2. design.md — System Design Specification Template

Create this file during project initialization or major feature kickoff, summarizing the brainstorming/ideation phase to align requirements, architecture, and data contracts before coding begins (not needed for simple/trivial tasks).

```markdown
# Design Specification — [System / Feature Name]

## 1. Overview & Problem Statement
- **Context & Problem**: What is the current problem and why is this system needed?
- **Goals**: What must this system accomplish? (Expected measurable outcomes)
- **Non-Goals**: What is explicitly out-of-scope for this phase to prevent scope creep?

## 2. Architecture & Component Boundaries
- **High-Level Architecture**: System topology, relationships, and component interactions
- **Component Responsibilities**:
  - **Frontend / Client**: Views, UI state, rendering, and accessibility
  - **Backend / Services**: Business logic, domain rules, validation, and security
  - **Database / Storage**: Data persistence, schema design, and query models

## 3. Data Contracts & Interfaces
- **Data Models / Schemas**: Entity definitions, database tables, or TypeScript interfaces
- **API Contracts**: Endpoints, HTTP methods, request payloads, response structures, and status codes

## 4. Error Handling & Edge Cases
- Validation fallbacks for missing or malformed inputs
- Handling external service unavailability, network timeouts, and partial failures
- Data integrity, concurrency protection, and Pokayoke error-proofing

## 5. Verification & Acceptance Criteria
- **Definition of Done**: Criteria that confirm the feature is complete and production-ready
- **Testing Strategy**: Unit tests, integration tests, boundary checks, and regression verification
```

---


## 3. PROJECT_SPECIFIC.md — Blank Template

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

## 4. HANDOFF.md — Blank Template

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

---

## 5. PRP.md — Product Requirements Prompt (Context Engineering Blueprint)

Create or generate this file when translating user intent into a high-fidelity execution blueprint before implementing substantial features.

```markdown
# Product Requirements Prompt (PRP) — [Feature Name]

<prp_blueprint version="1.0">

<goal_and_context>
## Goal
[Brief 1-2 sentence description of what must be built and why]

## Problem & Context
[Current baseline, relevant existing files, and technical dependencies]
</goal_and_context>

<architectural_decisions>
## Architecture & Topology
- **Component Boundaries**: [Which layer handles what]
- **Key Trade-offs**: [Chosen approach vs alternatives considered]
- **State Flow**: [Data flow: input ➔ state ➔ output]
</architectural_decisions>

<data_models_and_contracts>
## Data Models & API Contracts
- **Data Structures**: [Schema definitions, interfaces, or DB models]
- **Endpoints / Functions**: [Signatures, inputs, outputs, errors]
</data_models_and_contracts>

<implementation_steps>
## Step-by-Step Implementation
1. [Step 1: Test authoring (TDD)]
2. [Step 2: Core domain logic]
3. [Step 3: Integration & wiring]
4. [Step 4: Error handling & Pokayoke safeguards]
</implementation_steps>

<hard_constraints>
## Hard Constraints (Never Violate)
- Strictly preserve existing comments, docstrings, and type annotations.
- Never generate unprompted mock files or synthetic duplicates.
- Targeted edits only; no unrequested surrounding refactoring.
</hard_constraints>

<acceptance_criteria>
## Acceptance Criteria
- [ ] [Objective condition 1]
- [ ] [Objective condition 2]
- [ ] Edge cases handled: null inputs, boundary values, timeouts.
</acceptance_criteria>

<verification_commands>
## Automated Verification Commands
```bash
# Exact commands that must pass with exit code 0
pytest tests/ -v
npm run build
```
</verification_commands>

</prp_blueprint>
```

---

## 6. Subagent Task Delegation & Return Protocol (XML Schema)

Use these lightweight XML payloads when the Main Agent delegates scoped work to a Subagent, ensuring strict context isolation and preventing context window bloat.

### A. Main ➔ Subagent: `<task_assignment>`
```xml
<task_assignment>
  <role>[frontend-engineer | backend-engineer | tester | researcher]</role>
  <task_id>[e.g. TASK-01]</task_id>
  <objective>[Specific, atomic goal to achieve]</objective>
  <target_files>
    <file path="[relative/path/to/file]" action="[edit | create | inspect]" />
  </target_files>
  <constraints>
    [Hard boundaries, existing libraries to reuse, styling rules]
  </constraints>
  <verification_command>[Terminal command to verify work]</verification_command>
</task_assignment>
```

### B. Subagent ➔ Main: `<task_report>`
```xml
<task_report status="[COMPLETED | BLOCKED | FAILED]">
  <summary>[1-2 sentence executive summary of actions taken]</summary>
  <modified_files>
    <file path="[relative/path/to/file]" />
  </modified_files>
  <verification_results>[Actual command run and output summary: e.g. "4/4 tests passed"]</verification_results>
  <notes>[Key findings, edge cases handled, or follow-up recommendations]</notes>
</task_report>
```

---

## 7. Global Tool Pointer Templates

Use these 3-line pointer templates in your root project or global tool config files to point all AI agents directly to canonical HAWS.

### `CLAUDE.md` (Claude Code)
```markdown
# HAWS Standard Integration
This project operates under the Human-AI Working Standard (HAWS).
Before acting, read and follow canonical rules in `@~/.haws/core/HAWS.md` and `@~/.haws/core/WORK_INSTRUCTIONS.md`.
```

### `GEMINI.md` / `AGENTS.md` (Google Antigravity & Open Standards)
```markdown
# HAWS Standard Integration
This environment operates under the Human-AI Working Standard (HAWS).
Follow canonical rules in `core/HAWS.md` and practical procedures in `core/WORK_INSTRUCTIONS.md`.
```

