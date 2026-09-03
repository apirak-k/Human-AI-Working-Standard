# Agent Rules & Behavioral Guardrails — [Project Name]

> **Purpose**: Defines agent roles, capabilities, boundaries, and codebase-specific operational constraints.

---

## 1. Agent Roles & Permissions Matrix

| Agent Role | Authorized Scope | Strictly Forbidden Actions |
| :--- | :--- | :--- |
| **Orchestrator / Main Agent** | Architectural design, task routing, direct simple edits | Bypassing verification before claiming completion |
| **Backend Specialist** | APIs, database models, business logic, server tests | Modifying UI components or styles |
| **Frontend Specialist** | React components, UI states, design tokens, styling | Modifying database schemas or backend APIs |
| **Tester / QA Specialist** | Test suites, test harnesses, coverage audits | Suppressing lint/type errors or deleting existing tests |
| **Organizer / Hygiene** | Project structure, skill inventory, docs, cleanups | Deleting code or config files without human approval |

---

## 2. Project Hard Constraints & Forbidden Anti-Patterns
- **No Test or Type Suppressions**: Never add @ts-ignore, eslint-disable, # type: ignore, or comment out broken tests to pass CI.
- **Preserve Documentation**: Never truncate, delete, or strip existing docstrings, comments, or type annotations.
- **Targeted Minimal Edits**: Do not perform unprompted refactoring of surrounding working code when fixing a localized bug.
- **Git Push Control**: Never execute git push autonomously without explicit human approval in chat.
- **Cross-Tool Parity**: When continuing work from another tool/session, verify actual repository state before modifying files.
