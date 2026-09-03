# System Source of Truth (SOT) — [Project Name]

> **Purpose**: Serves as the authoritative, verified ground truth of the current live system. AI agents switching across tools, sessions, or machines MUST read this file first to understand verified reality without repeating past mistakes.

---

## 1. Verified Live System State
- **Last Verified Date**: [YYYY-MM-DD]
- **Verification Authority**: [e.g. Automated CI (100% PASS), Manual User Acceptance]
- **Active Environment**: [e.g. Node v20.x, Python 3.11, Local Dev / Staging]

---

## 2. Verified Capabilities & Implemented Modules

| Module / Component | File Location | Verified Functionality | Test Suite / Command |
| :--- | :--- | :--- | :--- |
| [e.g. Auth Service] | src/auth/ | OAuth2 + JWT session validation | 
pm test src/auth (PASS) |
| [e.g. UI Header] | src/components/ | Responsive fluid header + theme toggle | Storybook / Unit test (PASS) |

---

## 3. Active Data Contracts & API Surface
- **Database Schema Version**: [e.g. Prisma Migration 20260903_init]
- **Public API Endpoints**:
  - GET /api/v1/health -> Returns 200 OK
  - POST /api/v1/resource -> Requires Auth token, returns 201 Created

---

## 4. Confirmed Architectural Invariants & Learned Lessons
*(Record hard-learned facts here so cross-tool agents never re-introduce solved bugs)*
- **Invariant 1**: [e.g. Database transactions must use serializable isolation for balance updates]
- **Invariant 2**: [e.g. All filesystem operations on Windows must use forward slashes or path.resolve]
