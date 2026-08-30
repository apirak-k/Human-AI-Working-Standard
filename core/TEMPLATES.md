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
