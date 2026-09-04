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

## 2. Core Build & Verification Commands
*(Universal reference for agents across tools — OpenAI, Cursor, Claude Code, Antigravity)*
```bash
# Install dependencies
npm install  # or: pnpm install / pip install -r requirements.txt

# Run linting & static analysis
npm run lint

# Run typechecking
npm run typecheck

# Execute automated tests
npm test
```

---

## 3. Project Constraints & Code Quality Standards
For detailed quality thresholds, anti-patterns, and coverage constraints, see [CONSTRAINTS.md](CONSTRAINTS.md).
- **Quality Gates**: All PRs and commits must satisfy [CONSTRAINTS.md](CONSTRAINTS.md).
- **Git Remote Control**: Never run `git push` autonomously without explicit human approval in chat.
- **Cross-Tool Parity**: When resuming work from another session, inspect git status and verify current state before making edits.
