# Project Specification & Scope — [Project Name]

> **Purpose**: Defines project scope, boundaries (in-scope vs non-goals), tech stack conventions, and active delivery roadmap.

---

## 1. Project Overview & Scope Boundaries
- **Project Purpose**: Core mission and problem this software solves.
- **Target Audience / Users**: Primary user personas.
- **In-Scope Deliverables**: Exactly what this project produces.
- **Explicit Non-Goals**: What this project explicitly will NOT do (prevents scope creep).

---

## 2. Active Roadmap & Milestones

| Milestone / Phase | Status | Goal & Deliverables | Exit Criteria |
| :--- | :---: | :--- | :--- |
| **Phase 1: Foundation** | 🟢 Complete | Core schema, scaffolding, and CI checks | 100% tests pass |
| **Phase 2: MVP Features** | 🟡 In Progress | User authentication and core dashboard | Manual acceptance |
| **Phase 3: Production Prep**| ⚪ Planned | Load testing, security hardening, monitoring | Staging signoff |

---

## 3. Tech Stack & Engineering Conventions
- **Runtime & Language**: [e.g., TypeScript Node 20+, Python 3.11]
- **Framework & Libraries**: [e.g., Next.js 15, FastAPI]
- **Database & Storage**: [e.g., PostgreSQL, SQLite]
- **Coding Conventions**: [e.g., Conventional Commits, kebab-case files, camelCase variables]
- **Environment & Secrets**: [Document required env keys without secrets in .env.example]

---

## 4. System Source of Truth & Verified Live State
*(Authoritative, verified ground truth for AI agents switching across tools, sessions, or machines)*

- **Last Verified Date**: [YYYY-MM-DD]
- **Verification Authority**: [e.g. Automated CI (100% PASS), Manual User Acceptance]
- **Active Environment**: [e.g. Node v20.x, Python 3.11, Local Dev / Staging]

### Verified Capabilities & Implemented Modules

| Module / Component | File Location | Verified Functionality | Test Suite / Command |
| :--- | :--- | :--- | :--- |
| [e.g. Auth Service] | src/auth/ | OAuth2 + JWT session validation | npm test src/auth (PASS) |
| [e.g. UI Header] | src/components/ | Responsive fluid header + theme toggle | Storybook / Unit test (PASS) |

### Confirmed Architectural Invariants & Learned Lessons
*(Record hard-learned facts here so cross-tool agents never re-introduce solved bugs)*
- **Invariant 1**: [e.g. Database transactions must use serializable isolation for balance updates]
- **Invariant 2**: [e.g. All filesystem operations on Windows must use forward slashes or path.resolve]
